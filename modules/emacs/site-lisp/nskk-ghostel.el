;;; nskk-ghostel.el --- nskk を ghostel の端末バッファで使う -*- lexical-binding: t; -*-

;;; Commentary:

;; ghostel のバッファは端末グリッドをネイティブモジュールが管理するため
;; read-only で、テキストを挿入しても PTY には届かない。ghostel には Lisp
;; 入力メソッド用の橋渡しとして ghostel-ime-mode があるが、これは
;; `input-method-function' をラップする実装である。nskk は Emacs の
;; input-method フレームワークを使わず (register-input-method も
;; input-method-function も参照しない)、独自 minor-mode のキーマップから
;; `self-insert-command' / `insert' でバッファへ直接書くため、この経路に
;; 乗らない。結果として ghostel バッファでは "Buffer is read-only" となり
;; 入力できない。
;;
;; ここでは pre/post-command-hook で nskk のコマンドを挟み、
;;
;;   1. nskk が書いている間だけ `buffer-read-only' を外す
;;   2. 未確定 (▽/▼) の間は ghostel の再描画を止めて表示を保護する
;;   3. 確定したらバッファから取り除き、UTF-8 で PTY へ送る
;;
;; という橋渡しをする。ghostel-ime.el が quail 系 IME に対して行っている
;; ことの nskk 版にあたる。
;;
;; nskk 側は `nskk-converting-p'、ghostel 側は `ghostel--send-string' /
;; `ghostel--send-event' / `ghostel--terminal-input-mode-p' という内部関数に
;; 依存する。どちらかの upstream が変わったら追従が必要。

;;; Code:

(require 'ghostel)

(declare-function nskk-state-p "nskk-state" (state))
(declare-function nskk-state-henkan-phase "nskk-state" (state))
(declare-function ghostel--send-string "ghostel" (string))
(declare-function ghostel--send-event "ghostel")
(declare-function ghostel--terminal-input-mode-p "ghostel")
(declare-function ghostel--redraw-now "ghostel" (buffer &optional force))

(defvar nskk-current-state)
(defvar nskk--romaji-buffer)
(defvar ghostel--cursor-char-pos)

(defgroup nskk-ghostel nil
  "nskk と ghostel の橋渡し."
  :group 'ghostel
  :prefix "nskk-ghostel-")

(defcustom nskk-ghostel-passthrough-commands
  '(nskk-handle-backspace
    nskk-handle-return
    nskk-handle-tab
    nskk-handle-cancel
    nskk-undo-kakutei
    nskk-handle-ctrl-a
    nskk-handle-ctrl-b
    nskk-handle-ctrl-e
    nskk-handle-ctrl-f
    nskk-handle-ctrl-n
    nskk-handle-ctrl-p)
  "未確定入力がないときに nskk ではなく端末へ素通しするコマンド.
DEL・RET・カーソル移動を nskk に渡すと、nskk はバッファ (= 端末グリッドの
表示そのもの) を直接書き換えてしまう。未確定テキストがない間はこれらを
`ghostel--send-event' に差し替えて端末へ送り、シェルや TUI 側に解釈させる。
未確定テキストがある間は未確定文字列の編集操作として nskk に渡す。"
  :type '(repeat symbol)
  :group 'nskk-ghostel)

(defvar-local nskk-ghostel--origin nil
  "nskk が今回の入力でバッファに書き始めた位置のマーカー.
非 nil の間はバッファ上に nskk の未確定テキストがあることを意味する。")

(defvar-local nskk-ghostel--unlocked nil
  "pre-command で `buffer-read-only' を外したかどうか.")

(defun nskk-ghostel--nskk-command-p ()
  "`this-command' が nskk のコマンドなら non-nil."
  (and (symbolp this-command)
       (string-prefix-p "nskk-" (symbol-name this-command))))

(defun nskk-ghostel--pending-p ()
  "nskk の入力が未確定で、バッファ上のテキストがまだ変わりうるなら non-nil.

`nskk-converting-p' は使えない。あれは docstring のとおり ▼ と候補一覧
(henkan-phase が active / list) だけを変換中とみなし、▽ の入力途中
\(henkan-phase = on) では nil を返すため、確定前の見出し語を 1 文字ずつ
端末へ送ってしまう。ここでは henkan-phase が nil でないこと自体を未確定と
扱う (取りうる値は nil, on, active, list, registration)。

加えてローマ字入力の途中も未確定とみなす。撥音「ん」のように、確定前の
かなが placeholder としてバッファへ書かれることがあるため。"
  (or (and (boundp 'nskk-current-state)
           nskk-current-state
           (fboundp 'nskk-state-p)
           (nskk-state-p nskk-current-state)
           (nskk-state-henkan-phase nskk-current-state)
           t)
      (and (boundp 'nskk--romaji-buffer)
           (stringp nskk--romaji-buffer)
           (not (string-empty-p nskk--romaji-buffer)))))

(defun nskk-ghostel-composing-p (&optional buffer)
  "BUFFER に nskk の未確定テキストがあれば non-nil.
`ghostel-inhibit-redraw-functions' から BUFFER を引数に呼ばれ、
未確定表示がネイティブ側の再描画で消されるのを防ぐ。"
  (with-current-buffer (or buffer (current-buffer))
    (and (markerp nskk-ghostel--origin)
         (marker-position nskk-ghostel--origin)
         t)))

(defun nskk-ghostel--goto-terminal-cursor ()
  "point を端末カーソルの位置へ寄せる.

nskk は `point' にテキストを書く。ghostel バッファの point は端末カーソルと
一致しているとは限らない — Claude Code のような全画面 TUI は画面全体を描き
替えるため、point がスクロールバック途中の行に取り残される。そのまま nskk に
書かせると、未確定表示 (▽/▼) が入力欄とは無関係な行に現れる。

`ghostel--cursor-char-pos' は端末カーソルのバッファ位置で、ghostel 自身が
\"cursor's buffer position is the source of truth ... user input goes after\"
として扱う基準点。未確定テキストもそこから書き始める。"
  (let ((pos (and (boundp 'ghostel--cursor-char-pos)
                  ghostel--cursor-char-pos)))
    (when (and (integer-or-marker-p pos)
               (<= (point-min) pos)
               (<= pos (point-max))
               (/= (point) pos))
      (goto-char pos))))

(defun nskk-ghostel--clear-origin ()
  "未確定マーカーを破棄する."
  (when (markerp nskk-ghostel--origin)
    (set-marker nskk-ghostel--origin nil))
  (setq nskk-ghostel--origin nil))

(defun nskk-ghostel--pre-command ()
  "nskk のコマンドを実行できるようバッファの read-only を一時的に外す."
  (when (and (bound-and-true-p nskk-ghostel-mode)
             (bound-and-true-p nskk-mode)
             (nskk-ghostel--nskk-command-p))
    (if (and (null nskk-ghostel--origin)
             (memq this-command nskk-ghostel-passthrough-commands))
        (setq this-command #'ghostel--send-event)
      (unless nskk-ghostel--origin
        (nskk-ghostel--goto-terminal-cursor)
        ;; insertion-type nil: 後続の挿入で前へ動かず、書き始めの位置を保つ。
        (setq nskk-ghostel--origin (copy-marker (point) nil)))
      (setq nskk-ghostel--unlocked t)
      (setq buffer-read-only nil))))

(defun nskk-ghostel--post-command ()
  "nskk が確定した文字列を端末へ送り、バッファを read-only に戻す."
  (when nskk-ghostel--unlocked
    (setq nskk-ghostel--unlocked nil)
    (unwind-protect
        (when (and nskk-ghostel--origin
                   (not (nskk-ghostel--pending-p)))
          (let ((start (marker-position nskk-ghostel--origin))
                (end (point)))
            (when (and start (> end start))
              (let ((text (buffer-substring-no-properties start end)))
                (delete-region start end)
                (when (and (not (string-empty-p text))
                           (ghostel--terminal-input-mode-p))
                  (ghostel--send-string (encode-coding-string text 'utf-8)))))
            (nskk-ghostel--clear-origin)
            ;; 未確定の間は再描画を止めているので、確定でテキストを取り除いた
            ;; 直後にグリッドから描き直す。これを省くと、抑止が解けて次の描画が
            ;; 走るまで ▽/▼ の残骸が画面に残り、送った文字と二重に見える。
            (with-demoted-errors "nskk-ghostel redraw error: %S"
              (ghostel--redraw-now (current-buffer) t))))
      (setq buffer-read-only t))))

;;;###autoload
(define-minor-mode nskk-ghostel-mode
  "ghostel の端末バッファで nskk による日本語入力を可能にする.

有効にすると、nskk がバッファへ書いた確定文字列を PTY へ転送し、
未確定 (▽/▼) の間は ghostel の再描画を止めて表示を保つ。
通常は ghostel-mode で自動的に有効化する:

  (add-hook \\='ghostel-mode-hook #\\='nskk-ghostel-mode)"
  :lighter nil
  (if nskk-ghostel-mode
      (progn
        (add-hook 'pre-command-hook #'nskk-ghostel--pre-command nil t)
        (add-hook 'post-command-hook #'nskk-ghostel--post-command nil t)
        (add-hook 'ghostel-inhibit-redraw-functions
                  #'nskk-ghostel-composing-p nil t))
    (remove-hook 'pre-command-hook #'nskk-ghostel--pre-command t)
    (remove-hook 'post-command-hook #'nskk-ghostel--post-command t)
    (remove-hook 'ghostel-inhibit-redraw-functions
                 #'nskk-ghostel-composing-p t)
    (nskk-ghostel--clear-origin)
    (setq nskk-ghostel--unlocked nil)))

(provide 'nskk-ghostel)
;;; nskk-ghostel.el ends here
