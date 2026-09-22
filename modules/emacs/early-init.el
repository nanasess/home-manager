;;; early-init.el --- Early Emacs initialization. -*- lexical-binding: t; -*-

(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)
(setq read-process-output-max (* 1024 1024))

;; see https://github.com/jschaf/esup/issues/54#issue-317095645
(add-hook 'emacs-startup-hook
          (lambda ()
            (message "Emacs ready in %s with %d garbage collections."
                     (format "%.2f seconds"
                             (float-time
                              (time-subtract after-init-time before-init-time)))
                     gcs-done)))

(setopt load-prefer-newer t)
;; NOTE: newcomers-presets 由来の frame-inhibit-implied-resize t は入れない。
;; init.el:139-147 で起動後に set-face-attribute でデフォルトフォントを
;; UDEV Gothic JPDOC に差し替えているため、暗黙リサイズを止めるとフレームの
;; ピクセルサイズが固定されたまま文字セルだけ大きくなり、行数・桁数が減る
;; (ウィンドウが縮み、幅不足でスプラッシュの GNU ロゴも出なくなる)。
;; 既定の '(tab-bar-lines) のままにしておくこと。
(push '(tool-bar-lines . 0) default-frame-alist)

;; doom-solarized-light のフラッシュ防止
(push '(background-color . "#FDF6E3") default-frame-alist)
(push '(foreground-color . "#657B83") default-frame-alist)

;; elpaca takes over package management
(setq package-enable-at-startup nil)

(with-eval-after-load 'comp
  (setopt native-comp-async-jobs-number (num-processors))
  ;; 既定値の 2 のままにする (3 にしない)。speed 3 はネイティブコンパイラに
  ;; 「同じコンパイル単位 (同一ファイル) で定義された関数は再定義されない」と
  ;; 仮定させ、その呼び出しを直接呼び出しに最適化する。結果として
  ;; `advice-add' と関数の再定義が素通りされる。
  ;; 実害があった例: Mew の master password を 1Password から供給する
  ;; `mew-read-passwd' の advice が、同じ mew-passwd.el 内の
  ;; `mew-passwd-read-passwd' から直接呼ばれるため無視され、毎回手入力を
  ;; 求められていた (docs/mew.md「native-comp-speed と advice」)。
  ;; init.el の advice はいずれも他人のパッケージの内部関数に当てているので、
  ;; この最適化とは両立しない。
  (setq native-comp-speed 2))

(provide 'early-init)
