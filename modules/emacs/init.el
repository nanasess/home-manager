;;; init.el --- Emacs initialization file.

;; Author: Kentaro Ohkouchi  <nanasess@fsm.ne.jp>
;; URL: git://github.com/nanasess/dot.emacs.git

;;; Code:
;; see https://github.com/syl20bnr/spacemacs/commit/72c89df995ee1e4eb32ab982deb0911093048f20
(defconst my/saved-file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)

(when load-file-name
  (setq user-emacs-directory (file-name-directory load-file-name)))

(defvar external-directory (expand-file-name "~/OneDrive - Skirnir Inc/emacs/"))
(setopt debug-on-error t)
(setopt warning-minimum-level :error)

;;;; ============================================================
;;;; elpaca bootstrap
;;;; ============================================================
(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-sources-directory (expand-file-name "sources/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca-activate)))
(let* ((repo  (expand-file-name "elpaca/" elpaca-sources-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (condition-case-unless-debug err
        (if-let* ((buffer (pop-to-buffer-same-window "*elpaca-bootstrap*"))
                  ((zerop (apply #'call-process `("git" nil ,buffer t "clone"
                                                  ,@(when-let* ((depth (plist-get order :depth)))
                                                      (list (format "--depth=%d" depth) "--no-single-branch"))
                                                  ,(plist-get order :repo) ,repo))))
                  ((zerop (call-process "git" nil buffer t "checkout"
                                        (or (plist-get order :ref) "--"))))
                  (emacs (concat invocation-directory invocation-name))
                  ((zerop (call-process emacs nil buffer nil "-Q" "-L" "." "--batch"
                                        "--eval" "(byte-recompile-directory \".\" 0 'force)")))
                  ((require 'elpaca))
                  ((elpaca-generate-autoloads "elpaca" repo)))
            (progn (message "%s" (buffer-string)) (kill-buffer buffer))
          (error "%s" (with-current-buffer buffer (buffer-string))))
      ((error) (warn "%s" err) (delete-directory repo 'recursive))))
  (unless (require 'elpaca-autoloads nil t)
    (require 'elpaca)
    (elpaca-generate-autoloads "elpaca" repo)
    (let ((load-source-file-function nil)) (load "./elpaca-autoloads"))))
(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;; use-package integration
(elpaca elpaca-use-package
  (elpaca-use-package-mode))

;; Lock file for version pinning (replaces el-get-lock)
;; Generate: M-x elpaca-write-lock-file
;; home-manager のソースに直接書き出すことで手動コピー不要にする
(require 'xdg)
(setopt elpaca-lock-file
        (let ((hm-lock (expand-file-name "home-manager/modules/emacs/elpaca.lock"
                                         (xdg-config-home))))
          (if (file-writable-p hm-lock) hm-lock
            (expand-file-name "elpaca.lock" user-emacs-directory))))

;; elpaca-pull 前に detached HEAD を解消するコマンド
;; ロックファイル復元後は全パッケージが detached HEAD になるため、
;; pull 前にブランチに戻す必要がある
(defun elpaca-checkout-branches ()
  "Checkout the default branch for all elpaca source repos."
  (interactive)
  (let ((sources-dir (expand-file-name "sources" (expand-file-name "elpaca" user-emacs-directory)))
        (count 0))
    (dolist (dir (directory-files sources-dir t "^[^.]"))
      (when (file-directory-p (expand-file-name ".git" dir))
        (let* ((default-directory dir)
               (branch (string-trim
                        (shell-command-to-string
                         "git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'")))
               (branch (if (string-empty-p branch) "main" branch)))
          (when (not (string-empty-p
                      (shell-command-to-string "git symbolic-ref HEAD 2>&1 | grep -q fatal && echo detached")))
            (shell-command-to-string (format "git checkout %s 2>/dev/null" branch))
            (setq count (1+ count))))))
    (message "Checked out branches for %d packages" count)))

;;;; ============================================================
;;;; Base libraries (wait for completion before dependents)
;;;; ============================================================
(use-package compat :ensure t)
(use-package dash :ensure t)
(use-package f :ensure t)
(use-package s :ensure t)
(use-package ht :ensure t)
(use-package spinner :ensure t)
(use-package request :ensure t)
(use-package aio :ensure (:host github :repo "skeeto/emacs-aio"))
(elpaca-wait)

;;;; ============================================================
;;;; Load path & initial settings
;;;; ============================================================

;;; Platform-specific settings

;; macOS NS GUI
(when (featurep 'ns)
  (setopt ns-alternate-modifier 'super)
  (setopt ns-command-modifier 'meta)
  (setopt ns-pop-up-frames nil)
  (setopt mac-allow-anti-aliasing t)
  (setopt mac-frame-tabbing t)
  (keymap-set global-map "<ns-drag-file>" #'ns-find-file)
  ;; font: Menlo + Hiragino Kaku Gothic ProN
  (set-face-attribute 'default nil :family "Menlo" :height 120)
  (set-fontset-font t 'japanese-jisx0208
                    (font-spec :family "Hiragino Kaku Gothic ProN"))
  (set-fontset-font t 'japanese-jisx0212
                    (font-spec :family "Hiragino Kaku Gothic ProN"))
  (setq face-font-rescale-alist '((".*Hiragino.*" . 1.2))))

;; GNU/Linux (WSL2, Ubuntu)
;; JPDOC をプライマリフォントに使用 (East Asian Ambiguous 文字が全角グリフ)
(when (eq system-type 'gnu/linux)
  (defun my/set-font-linux (frame)
    "Set font for FRAME when it is a graphic display."
    (when (display-graphic-p frame)
      (set-face-attribute 'default frame :family "UDEV Gothic JPDOC" :height 120)))
  (if (daemonp)
      (add-hook 'after-make-frame-functions #'my/set-font-linux)
    (when (display-graphic-p)
      (set-face-attribute 'default nil :family "UDEV Gothic JPDOC" :height 120))))

;; server
(when (display-graphic-p)
  (require 'server)
  (unless (server-running-p)
    (server-start)))

(add-to-list 'load-path (expand-file-name (locate-user-emacs-file "secret.d/")))

;;; exec-path settings
(dolist (dir (list "/sbin" "/usr/sbin" "/bin" "/usr/bin" "/usr/local/bin"
                   "/opt/local/sbin" "/opt/local/bin" "/usr/gnu/bin"
                   (expand-file-name "~/.ghcup/bin")
                   (expand-file-name "~/.cabal/bin")
                   (expand-file-name "~/bin")
                   (expand-file-name "~/.emacs.d/bin")
                   (expand-file-name "~/.local/bin")
                   (expand-file-name "~/.config/claude/local/")))
  (when (and (file-exists-p dir) (not (member dir exec-path)))
    (setenv "PATH" (concat dir ":" (getenv "PATH")))
    (setq exec-path (append (list dir) exec-path))))

;;;; ============================================================
;;;; Japanese input
;;;; ============================================================
(use-package cp5022x
  :ensure (:host github :repo "awasira/cp5022x.el")
  :demand t
  :config
  (define-coding-system-alias 'iso-2022-jp 'cp50220)
  (define-coding-system-alias 'euc-jp 'cp51932))

(set-language-environment "Japanese")
(set-default-coding-systems 'utf-8-unix)
(set-keyboard-coding-system 'utf-8)
(set-terminal-coding-system 'utf-8)
(setq default-process-coding-system '(utf-8 . utf-8))
(setenv "LANG" "ja_JP.UTF-8")

;; locale-eaw EAW-CONSOLE: East Asian Ambiguous 文字の幅を適切に設定
;; set-language-environment が char-width-table をリセットするため、その後に読み込む
;; https://github.com/hamano/locale-eaw
(load (expand-file-name (locate-user-emacs-file "site-lisp/eaw-console")) t t)

;; nskk は upstream で *.el を src/ サブディレクトリに移動したため、
;; elpaca のデフォルト :files では nskk.el が見つからずビルドが失敗する。
;; src/*.el を明示的にビルド対象に加える。
(use-package nskk
  :ensure (:host github :repo "takeokunn/nskk.el" :branch "main"
           :files ("src/*.el")
           :build (:not elpaca-build-autoloads))
  :demand t
  :bind (("C-j" . nskk-toggle-mode)
         ("C-x C-j" . nskk-toggle-mode))
  :custom
  (nskk-dict-user-dictionary-file (concat external-directory "nskk/jisyo"))
  (nskk-dict-system-dictionary-files
   (list (concat external-directory "ddskk/SKK-JISYO.all.utf8")))
  (nskk-show-tooltip t)
  (nskk-use-color-cursor t)
  (nskk-converter-auto-start-henkan t)
  (nskk-henkan-show-candidates-nth 5))

(elpaca-wait)

;;;; ============================================================
;;;; Global key-bindings
;;;; ============================================================
(global-unset-key (kbd "C-M-t"))
(global-unset-key (kbd "C-z"))
(global-unset-key (kbd "C-\\"))
(bind-keys ("M-g" . goto-line)
           ("C-t" . other-window)
           ("C-z C-u" . other-frame)
           ("C-M-g" . end-of-buffer)
           ("C-M-j" . next-line)
           ("C-M-k" . previous-line)
           ("C-M-h" . backward-char)
           ("C-M-l" . forward-char)
           ;; XXX PowerToys hack
           ("C-x <right>" . find-file)
           ("C-x <end>" . eval-last-sexp))

;;;; ============================================================
;;;; Scroll settings
;;;; ============================================================
(use-package ultra-scroll
  :ensure (:host github :repo "jdtsmith/ultra-scroll" :branch "main")
  :init
  (setq scroll-conservatively 3
        scroll-margin 0)
  :hook (emacs-startup
         . (lambda ()
             (setopt pixel-scroll-precision-interpolation-total-time 0.15)
             (ultra-scroll-mode 1)

             ;; emacs-inertial-scroll 風: ウィンドウの1/3をスムーススクロール
             (defun my/scroll-down-smoothly ()
               "Scroll down smoothly by 1/3 of window height."
               (interactive)
               (pixel-scroll-precision-interpolate
                (- (/ (window-text-height nil t) 3)) nil 1))
             (defun my/scroll-up-smoothly ()
               "Scroll up smoothly by 1/3 of window height."
               (interactive)
               (pixel-scroll-precision-interpolate
                (/ (window-text-height nil t) 3) nil 1))
             (global-set-key (kbd "C-v") 'my/scroll-down-smoothly)
             (global-set-key (kbd "M-v") 'my/scroll-up-smoothly))))

;;;; ============================================================
;;;; Clipboard (pgtk / wl-clipboard)
;;;; ============================================================
;; see http://cha.la.coocan.jp/wp/2024/05/05/post-1300/
(if (featurep 'pgtk)
    (if (and (zerop (call-process "which" nil nil nil "wl-copy"))
             (zerop (call-process "which" nil nil nil "wl-paste")))
        ;; credit: yorickvP on Github
        ;; see https://gist.github.com/yorickvP/6132f237fbc289a45c808d8d75e0e1fb
        (progn
          (setq wl-copy-process nil)
          (defun wl-copy (text)
            (setq wl-copy-process (make-process :name "wl-copy"
                                                :buffer nil
                                                :command '("wl-copy" "-f" "-n")
                                                :connection-type 'pipe
                                                :noquery t))
            (process-send-string wl-copy-process text)
            (process-send-eof wl-copy-process))
          (defun wl-paste ()
            (if (and wl-copy-process (process-live-p wl-copy-process))
                nil
              (when (executable-find "wl-paste")
                (shell-command-to-string "type -a wl-paste > /dev/null 2>&1 && wl-paste -n | tr -d \r"))))
          (setq interprogram-cut-function 'wl-copy)
          (setq interprogram-paste-function 'wl-paste))))

;;;; ============================================================
;;;; Built-in settings
;;;; ============================================================
(use-package emacs
  :ensure nil
  :config
  (setopt enable-recursive-minibuffers t)
  (setopt cua-enable-cua-keys nil)

  ;; backup files
  (add-to-list 'backup-directory-alist (cons "\\.*$" (expand-file-name "~/.bak/")))
  (setopt delete-old-versions t
         make-backup-files t
         version-control t)

  ;; show-paren
  (show-paren-mode 1)

  ;; visible-bell
  (setopt visible-bell t)

  ;; whitespace
  (setopt whitespace-style '(face trailing tabs spaces space-mark tab-mark))
  (setopt whitespace-display-mappings nil)
  (setopt whitespace-trailing-regexp  "\\([ \u00A0]+\\)$")
  (setopt whitespace-space-regexp "\\(\u3000+\\)")
  (setopt whitespace-global-modes
          '(not dired-mode tar-mode magit-log-mode magit-diff-mode))
  (global-whitespace-mode t)

  ;; hl-line
  ;; see also http://rubikitch.com/2015/05/14/global-hl-line-mode-timer/
  (global-hl-line-mode 0)
  (defun global-hl-line-timer-function ()
    (global-hl-line-unhighlight-all)
    (let ((global-hl-line-mode t))
      (global-hl-line-highlight)))
  (setq global-hl-line-timer
        (run-with-idle-timer 0.1 t 'global-hl-line-timer-function))

  ;; line/column numbers
  (line-number-mode -1)
  (column-number-mode 1)
  (size-indication-mode 1)
  (global-display-line-numbers-mode t)

  ;; uniquify
  (setopt uniquify-buffer-name-style 'post-forward-angle-brackets)
  (setopt uniquify-ignore-buffers-re "*[^*]+*")


  ;; indent
  (setq-default indent-tabs-mode nil)

  ;; misc
  (setopt indicate-empty-lines t)
  (setopt isearch-lax-whitespace nil)
  (setopt mouse-yank-at-point t)
  (setopt select-enable-clipboard t)
  (setopt select-enable-primary t)
  (setopt save-interprogram-paste-before-kill t)
  (delete-selection-mode 1)

  ;; XXX allow remembering risky and safe variables
  ;; see https://emacs.stackexchange.com/a/44604
  (defun risky-local-variable-p (sym &optional _ignored) nil)
  (defun safe-local-variable-p (sym val) t)

  ;; treesit
  (setopt treesit-font-lock-level 4)

  ;; editor
  (setenv "EDITOR" "emacsclient"))

(use-package view
  :ensure nil
  :custom
  (view-read-only t)
  :hook (view-mode . (lambda ()
                       (auto-revert-mode 1)
                       (setq-local line-move-visual nil)))
  :mode ("\\.log\\'" . view-mode)
  :bind (:map view-mode-map
         ("h" . backward-word)
         ("l" . forward-word)
         ("j" . next-line)
         ("k" . previous-line)
         (" " . scroll-up)
         ("b" . scroll-down)))

(use-package dired
  :ensure nil
  :defer t
  :custom
  (dired-bind-jump nil)
  (dired-dwim-target t)
  :config
  (require 'dired-x)
  :bind (:map dired-mode-map
         ("C-t" . other-window)
         ("r" . wdired-change-to-wdired-mode)))

(use-package ediff
  :ensure nil
  :defer t
  :custom
  (ediff-window-setup-function 'ediff-setup-windows-plain))

;;;; ============================================================
;;;; Theme & UI
;;;; ============================================================
(use-package doom-themes
  :ensure t
  :config
  (load-theme 'doom-solarized-light t))

(use-package nerd-icons
  :ensure (:host github :repo "rainstormstudio/nerd-icons.el" :branch "main")
  :config
  (setf (alist-get "php" nerd-icons-extension-icon-alist)
        '(nerd-icons-sucicon "nf-seti-php" :face nerd-icons-lpurple))
  (push '("tpl" nerd-icons-sucicon "nf-seti-smarty" :face nerd-icons-yellow)
        nerd-icons-extension-icon-alist)
  (push '("twig" nerd-icons-sucicon "nf-seti-twig" :face nerd-icons-lgreen)
        nerd-icons-extension-icon-alist))

(use-package shrink-path
  :ensure (:host github :repo "zbelial/shrink-path.el"))

(use-package doom-modeline
  :ensure t
  :hook (after-init . doom-modeline-mode)
  :custom
  (doom-modeline-vcs-max-length 999)
  (doom-modeline-buffer-file-name-style 'buffer-name))

(use-package symbol-overlay
  :ensure (:host github :repo "wolray/symbol-overlay")
  :bind ("M-i" . symbol-overlay-put))

;;;; ============================================================
;;;; Frame size utilities
;;;; ============================================================
(defvar normal-frame-width 82)
(defvar wide-frame-width 175)
(defvar toggle-frame-flag t)

(defun frame-size-greater-p ()
  (< (+ (/ (- wide-frame-width normal-frame-width) 2) normal-frame-width)
     (frame-width (selected-frame))))

(defun normal-size-frame ()
  "Resize to normal size frame."
  (interactive)
  (setq toggle-frame-flag t)
  (set-frame-width (selected-frame) normal-frame-width))

(defun wide-size-frame ()
  "Resize to wide size frame."
  (interactive)
  (setq toggle-frame-flag nil)
  (set-frame-width (selected-frame) wide-frame-width))

(defun toggle-size-frame ()
  "toggle frame size."
  (interactive)
  (cond ((frame-size-greater-p) (normal-size-frame))
        ((wide-size-frame))))

(defun toggle-fullscreen ()
  (interactive)
  (if (frame-parameter nil 'fullscreen)
      (set-frame-parameter nil 'fullscreen nil)
    (set-frame-parameter nil 'fullscreen 'fullscreen)))

(defun change-frame-height-up ()
  (interactive)
  (set-frame-height (selected-frame) (+ (frame-height (selected-frame)) 1)))
(defun change-frame-height-down ()
  (interactive)
  (set-frame-height (selected-frame) (- (frame-height (selected-frame)) 1)))
(defun change-frame-width-up ()
  (interactive)
  (set-frame-width (selected-frame) (+ (frame-width (selected-frame)) 1)))
(defun change-frame-width-down ()
  (interactive)
  (set-frame-width (selected-frame) (- (frame-width (selected-frame)) 1)))

(bind-keys ("C-z C-a" . toggle-fullscreen)
           ("C-z C-z" . toggle-size-frame))

;;;; ============================================================
;;;; Completion framework (vertico, consult, marginalia, orderless, embark)
;;;; ============================================================
(use-package orderless
  :ensure (:host github :repo "oantolin/orderless")
  :custom
  (completion-styles '(orderless))
  (completion-category-defaults nil)
  (completion-category-overrides nil))

(use-package marginalia
  :ensure (:host github :repo "minad/marginalia" :branch "main")
  :hook (after-init . marginalia-mode))

(use-package consult
  :ensure (:host github :repo "minad/consult" :branch "main")
  :bind (("C-;" . consult-buffer)
         ([remap goto-line] . consult-goto-line)
         ("C-M-s" . consult-line)
         ("C-x C-d" . consult-dir)
         ("C-z l" . consult-ls-git))
  :custom
  (consult-narrow-key ">")
  (consult-widen-key "<")
  (consult-preview-key "M-.")
  :config
  (consult-customize
   consult-ripgrep
   consult-grep
   consult-git-grep
   consult-bookmark consult-recent-file consult-xref
   :preview-key "C-."))

(use-package embark
  :ensure (:host github :repo "oantolin/embark")
  :bind ("C-," . embark-act))

(use-package embark-consult
  :ensure (:host github :repo "oantolin/embark" :files ("embark-consult.el"))
  :after (embark consult)
  :bind (:map embark-file-map
         ("s" . sudo-edit)))

(use-package savehist
  :ensure nil
  :hook (after-init . savehist-mode)
  :custom
  (savehist-additional-variables
   '(kill-ring log-edit-comment-ring search-ring regexp-search-ring)))

(use-package vertico
  :ensure (:host github :repo "minad/vertico" :branch "main"
           :files ("*.el" "extensions/*.el"))
  :hook ((after-init . vertico-mode)
         (minibuffer-setup . vertico-repeat-save))
  :bind (("C-z C-r" . vertico-repeat)
         :map vertico-map
         ("C-l" . vertico-directory-up)
         ("C-j" . vertico-directory-enter)
         ("M-v" . vertico-next-group)
         ("C-v" . vertico-previous-group))
  :custom
  (vertico-count 20)
  (read-file-name-completion-ignore-case t)
  (read-buffer-completion-ignore-case t)
  (completion-ignore-case t))

(use-package consult-ls-git
  :ensure (:host github :repo "rcj/consult-ls-git" :branch "main"))

(use-package consult-flycheck
  :ensure (:host github :repo "minad/consult-flycheck" :branch "main"))

(use-package consult-dir
  :ensure (:host github :repo "karthink/consult-dir"))

(use-package consult-tramp
  :ensure (:host github :repo "Ladicle/consult-tramp" :branch "main")
  :defer t
  :custom
  (consult-tramp-method "sshx"))

(use-package sudo-edit
  :ensure (:host github :repo "nflath/sudo-edit"))

(use-package wgrep
  :ensure t
  :custom
  (wgrep-enable-key "r"))

;;;; ============================================================
;;;; Editing support
;;;; ============================================================
(use-package migemo
  :ensure t
  :if (file-exists-p (concat external-directory "migemo/dict/utf-8/migemo-dict"))
  :hook (isearch-mode . migemo-init)
  :custom
  (migemo-dictionary (concat external-directory "migemo/dict/utf-8/migemo-dict"))
  (migemo-command "cmigemo")
  (migemo-options '("-q" "--emacs" "-i" "\a"))
  (migemo-user-dictionary nil)
  (migemo-regex-dictionary nil)
  (migemo-use-pattern-alist t)
  (migemo-use-frequent-pattern-alist t)
  (migemo-pattern-alist-length 10000)
  (migemo-coding-system 'utf-8-unix))

(use-package visual-regexp
  :ensure t
  :bind ("M-%" . vr/query-replace))

(use-package undo-tree
  :ensure (:host github :repo "emacsmirror/undo-tree")
  :hook (after-init . global-undo-tree-mode)
  :custom
  (undo-tree-visualizer-timestamps t)
  (undo-tree-visualizer-diff t)
  (undo-tree-auto-save-history t)
  (undo-tree-enable-undo-in-region t)
  (undo-tree-history-directory-alist `(("." . ,(expand-file-name "undo-tree" user-emacs-directory)))))

(use-package easy-kill
  :ensure (:host github :repo "leoliu/easy-kill"))

;; Copy menu with transient (M-w)
(defun my/copy-buffer-file-name ()
  "Copy full path to kill ring."
  (interactive)
  (if-let ((f (buffer-file-name)))
      (progn (kill-new f) (message "Copied: %s" f))
    (message "Buffer has no file")))

(defun my/copy-buffer-file-name-nondirectory ()
  "Copy file name only to kill ring."
  (interactive)
  (if-let ((f (buffer-file-name)))
      (let ((name (file-name-nondirectory f)))
        (kill-new name) (message "Copied: %s" name))
    (message "Buffer has no file")))

(defun my/copy-buffer-directory ()
  "Copy directory to kill ring."
  (interactive)
  (if-let ((f (buffer-file-name)))
      (let ((dir (file-name-directory f)))
        (kill-new dir) (message "Copied: %s" dir))
    (message "Buffer has no file")))

(defun my/copy-buffer-file-name-with-line ()
  "Copy file:line format to kill ring."
  (interactive)
  (if-let ((f (buffer-file-name)))
      (let ((loc (format "%s:%d" f (line-number-at-pos))))
        (kill-new loc) (message "Copied: %s" loc))
    (message "Buffer has no file")))

(defun my/copy-or-menu ()
  "Copy region if active, otherwise show copy menu."
  (interactive)
  (if (use-region-p)
      (kill-ring-save (region-beginning) (region-end))
    (if (fboundp 'my/copy-dwim)
        (my/copy-dwim)
      (message "Copy menu not available. Run M-x magit-status to load transient first."))))

(bind-key "M-w" #'my/copy-or-menu)

(use-package expand-region
  :ensure t
  :bind ("C-=" . er/expand-region)
  :custom
  (shift-select-mode nil))

(use-package multiple-cursors
  :ensure t
  :bind ("<C-M-return>" . mc/edit-lines))

(use-package prettier-js
  :ensure t)

;;;; ============================================================
;;;; SQL
;;;; ============================================================
(use-package sql-indent
  :ensure (:host github :repo "alex-hhh/emacs-sql-indent")
  :hook (sql-mode . (lambda ()
                      (setq-local sql-product 'sqlite)
                      (sql-indent-enable)
                      (setq-local sqlind-basic-offset 4))))

;;;; ============================================================
;;;; org-mode
;;;; ============================================================
(use-package org
  :ensure nil
  :defer t
  :custom
  (org-directory (concat external-directory "howm/"))
  (org-return-follows-link t)
  (org-startup-folded nil)
  (org-startup-truncated nil))

;;;; ============================================================
;;;; Git / Magit
;;;; ============================================================
(use-package transient
  :ensure t
  :config
  (transient-define-prefix my/copy-dwim ()
    "Select what to copy."
    [["File Info"
      ("f" "Full path" my/copy-buffer-file-name :transient nil)
      ("n" "File name only" my/copy-buffer-file-name-nondirectory :transient nil)
      ("d" "Directory" my/copy-buffer-directory :transient nil)
      ("l" "File:line" my/copy-buffer-file-name-with-line :transient nil)]
     ["Text (easy-kill)"
      ("w" "Word" (lambda () (interactive) (easy-kill ?w)) :transient nil)
      ("s" "Symbol" (lambda () (interactive) (easy-kill ?s)) :transient nil)
      ("L" "Line" (lambda () (interactive) (easy-kill ?l)) :transient nil)
      ("-" "Defun" (lambda () (interactive) (easy-kill ?-)) :transient nil)]]))

(use-package magit
  :ensure t
  :bind ("C-z m" . magit-status)
  :config
  (defun visit-gh-pull-request (repo)
    "Visit the current branch's PR on Github."
    (interactive)
    (message repo)
    (browse-url
     (format "https://github.com/%s/pull/new/%s"
             (replace-regexp-in-string
              "\\.git$" ""
              (replace-regexp-in-string
               "\\`.+github\\.com.\\(.+\\)\\(\\.git\\)?\\'" "\\1"
               repo))
             (magit-get-current-branch))))

  (defun visit-bb-pull-request (repo)
    (message repo)
    (browse-url
     (format "https://bitbucket.org/%s/pull-request/new?source=%s&t=1"
             (replace-regexp-in-string
              "\\`.+bitbucket\\.org.\\(.+\\)\\.git\\'" "\\1"
              repo)
             (magit-get-current-branch))))

  (defun endless/visit-pull-request-url ()
    "Visit the current branch's PR on Github."
    (interactive)
    (let ((repo (magit-get "remote" (magit-get-remote) "url")))
      (if (not repo)
          (setq repo (magit-get "remote" (magit-get-push-remote) "url")))
      (if (string-match "github\\.com" repo)
          (visit-gh-pull-request repo)
        (visit-bb-pull-request repo))))

  (setopt magit-diff-refine-hunk t)
  (add-to-list 'magit-process-password-prompt-regexps "^パスフレーズを入力: ?$")
  (remove-hook 'server-switch-hook 'magit-commit-diff)
  :bind (:map magit-mode-map
         ("v" . endless/visit-pull-request-url)
         :map magit-log-mode-map
         ("j" . magit-section-forward)
         ("k" . magit-section-backward)))

(use-package smerge-mode
  :ensure nil
  :defer t
  :bind (:map smerge-mode-map
         ("M-n" . smerge-next)
         ("M-p" . smerge-prev)))

;;;; ============================================================
;;;; howm
;;;; ============================================================
(use-package howm
  :ensure t
  :init
  (defvar howm-menu-lang 'ja)
  (defvar howm-view-title-header "Title:")
  :custom
  (howm-directory (concat external-directory "howm/"))
  (howm-file-name-format "%Y/%m/%Y-%m-%d-%H%M%S.md")
  (howm-keyword-file (locate-user-emacs-file ".howm-keys"))
  (howm-history-file (locate-user-emacs-file ".howm-history"))
  (howm-menu-schedule-days-before 30)
  (howm-menu-schedule-days 30)
  (howm-menu-expiry-hours 2)
  (howm-menu-refresh-after-save nil)
  (howm-refresh-after-save nil)
  (howm-list-all-title t)
  (howm-schedule-menu-types "[!@\+]")
  (howm-view-use-grep t)
  (howm-process-coding-system 'utf-8-unix)
  (howm-todo-menu-types "[-+~!]")
  (howm-view-grep-command "rg")
  (howm-view-grep-option "-nH --no-heading --color never")
  (howm-view-grep-extended-option nil)
  (howm-view-grep-fixed-option "-F")
  (howm-view-grep-expr-option nil)
  (howm-view-grep-file-stdin-option nil)
  :bind (("C-z c" . howm-create)
         ("C-z s" . consult-howm-do-ag)
         :map howm-mode-map
         ("C-c C-q" . howm-save-and-kill-buffer))
  :config
  (setq howm-template
        (concat howm-view-title-header
                " %title%cursor\n"
                "Date: %date\n\n"
                "%file\n\n"
                "<!--\n"
                "  Local Variables:\n"
                "  mode: gfm\n"
                "  coding: utf-8-unix\n"
                "  End:\n"
                "-->\n"))
  (defun howm-save-and-kill-buffer ()
    "Kill buffer when exiting from howm-mode, deleting empty files."
    (interactive)
    (let ((file-name (buffer-file-name)))
      (when (and file-name (string-suffix-p ".md" file-name))
        (if (save-excursion
              (goto-char (point-min))
              (re-search-forward "[^ \t\r\n]" nil t))
            (howm-save-buffer)
          (set-buffer-modified-p nil)
          (when (file-exists-p file-name)
            (delete-file file-name)
            (message "(Deleted %s)" (file-name-nondirectory file-name))))
        (kill-buffer nil))))
  (defun consult-howm-do-ag ()
    (interactive)
    (consult-ripgrep howm-directory)))

;; see https://stackoverflow.com/a/384346
(defun rename-file-and-buffer (new-name)
  "Renames both current buffer and file it's visiting to NEW-NAME."
  (interactive "sNew name: ")
  (let ((name (buffer-name))
        (filename (buffer-file-name)))
    (if (not filename)
        (message "Buffer '%s' is not visiting a file!" name)
      (if (get-buffer new-name)
          (message "A buffer named '%s' already exists!" new-name)
        (progn
          (rename-file filename new-name 1)
          (rename-buffer new-name)
          (set-visited-file-name new-name)
          (set-buffer-modified-p nil))))))


;;;; ============================================================
;;;; Markdown
;;;; ============================================================
(use-package markdown-mode
  :ensure t
  :mode (("\\.\\(markdown\\|md\\)\\'" . gfm-mode))
  :custom
  (markdown-fontify-code-blocks-natively t)
  (markdown-indent-on-enter 'indent-and-new-item)
  :bind (:map markdown-mode-map
         ("<S-tab>" . markdown-shifttab)))

(use-package polymode
  :ensure (:host github :repo "polymode/polymode")
  :defer t)

(use-package poly-markdown
  :ensure (:host github :repo "polymode/poly-markdown")
  :defer t)

;;;; ============================================================
;;;; Flycheck
;;;; ============================================================
(use-package flycheck
  :ensure t)

;;;; ============================================================
;;;; LSP (lsp-bridge)
;;;; ============================================================
;; lsp-bridge は外部 Python サーバー (epc 経由) で動作する補完/LSP クライアント。
;; Python 依存は uv で ~/.local/share/lsp-bridge/.venv に隔離管理する
;; (modules/emacs/lsp-bridge/pyproject.toml と default.nix の
;; home.activation.lspBridgeUvSync を参照)。
;; PHP は phpactor、その他は lsp-bridge 同梱の langserver/*.json で解決する。

(use-package yasnippet
  :ensure t
  :config
  (yas-global-mode 1))

(use-package posframe
  :ensure t)

(use-package lsp-bridge
  :ensure (:host github :repo "manateelazycat/lsp-bridge"
                 :files (:defaults "*.py" "core" "acm" "icons" "langserver" "resources"))
  :after (yasnippet posframe)
  :demand t
  :bind (("M-." . lsp-bridge-find-def)
         ("M-," . lsp-bridge-find-def-return)
         ([remap xref-find-definitions] . lsp-bridge-find-def)
         ([remap xref-go-back]          . lsp-bridge-find-def-return)
         ([remap xref-pop-marker-stack] . lsp-bridge-find-def-return))
  :init
  (setq lsp-bridge-python-command
        (expand-file-name "~/.local/share/lsp-bridge/.venv/bin/python"))
  ;; PHP は phpactor を使用 (langserver/phpactor.json が同梱されている)
  (setq lsp-bridge-php-lsp-server "phpactor")
  ;; 対象モードを明示。csharp-ts-mode 等は LSP を入れていないので除外する。
  (setq lsp-bridge-default-mode-hooks
        '(php-ts-mode-hook
          typescript-ts-mode-hook tsx-ts-mode-hook
          js-ts-mode-hook
          bash-ts-mode-hook
          yaml-mode-hook yaml-ts-mode-hook
          json-ts-mode-hook
          html-mode-hook mhtml-mode-hook
          css-ts-mode-hook
          dockerfile-ts-mode-hook
          nix-mode-hook
          ;; emacs-lisp は外部 LSP サーバーを使わず lsp-bridge 内蔵の
          ;; elisp symbol 同期 (lsp-bridge-elisp-symbols-update) で補完する。
          emacs-lisp-mode-hook))
  :config
  (global-lsp-bridge-mode))

;;;; ============================================================
;;;; Programming languages
;;;; ============================================================

;;; TypeScript
(use-package typescript-ts-mode
  :ensure nil
  :mode "\\.ts\\'")

(use-package tsx-ts-mode
  :ensure nil
  :mode "\\.tsx\\'")

;;; jq
(use-package jq-mode
  :ensure (:host github :repo "ljos/jq-mode"))

;;; web-mode (user fork)
(use-package web-mode
  :ensure (:host github :repo "nanasess/web-mode" :branch "eccube-engine")
  :mode (("\\.tpl\\'" . web-mode)
         ("\\.vue\\'" . web-mode)
         ("\\.twig\\'" . web-mode)
         ("\\.html\\'" . web-mode))
  :custom
  (web-mode-enable-block-face t)
  (web-mode-enable-current-column-highlight nil)
  (web-mode-enable-auto-indentation nil)
  :hook (web-mode . (lambda ()
                      (when (string-equal "tpl" (file-name-extension buffer-file-name))
                        (web-mode-set-engine "eccube")))))

;;; JSON
(use-package json-ts-mode
  :ensure nil
  :mode "\\.json\\'")

;;; Shell scripts
;; sh-mode に決まったあと bash-ts-mode へリマップする。bash-ts-mode 自体が
;; shebang などから bash/sh でないと判断した場合は sh--redirect-bash-ts-mode
;; advice で sh-mode に戻るため、zsh/csh 等は安全にフォールバックする。
(use-package sh-script
  :ensure nil
  :init
  (add-to-list 'major-mode-remap-alist '(sh-mode . bash-ts-mode)))

;;; CSS
(use-package css-mode
  :ensure nil
  :init
  (add-to-list 'major-mode-remap-alist '(css-mode . css-ts-mode)))

;;; JavaScript
;; auto-mode-alist のデフォルトは `\.js[mx]?\' . javascript-mode' で、
;; javascript-mode は js-mode の defalias。major-mode-remap はエイリアスを
;; 解決しないため両方の名前でリマップする。
(use-package js
  :ensure nil
  :init
  (add-to-list 'major-mode-remap-alist '(javascript-mode . js-ts-mode))
  (add-to-list 'major-mode-remap-alist '(js-mode . js-ts-mode)))

;;; C#
;; csharp-ts-mode は内部で言語シンボル 'c-sharp を使うため、grammar は
;; libtree-sitter-c-sharp.so の名前で配置する必要がある (default.nix 参照)。
(use-package csharp-mode
  :ensure nil
  :init
  (add-to-list 'major-mode-remap-alist '(csharp-mode . csharp-ts-mode)))

;;; YAML
;; ビルトインの yaml-ts-mode は treesit-simple-indent-rules が未実装で
;; インデントが効かないため、手書きの indent ルールを持つ yaml-mode を優先する。
(use-package yaml-mode
  :ensure t
  :mode "\\.ya?ml\\'"
  :init
  (setq auto-mode-alist
        (rassq-delete-all 'yaml-ts-mode auto-mode-alist)))

;;; PHP
;; Emacs 30 内蔵 php-ts-mode を使用。grammar (php / phpdoc / html / css /
;; javascript / jsdoc) は default.nix の treesitGrammarMap で配置済み。
;; HTML/CSS/JavaScript の混在ブロックも treesit-language-at で正しくハイライトされる。
(use-package php-ts-mode
  :ensure nil
  :mode ("\\.\\(inc\\|php[s34]?\\|phtml\\)\\'" . php-ts-mode)
  :hook (php-ts-mode . (lambda ()
                         (electric-indent-local-mode t)
                         (electric-pair-local-mode t))))

;;; Groovy
(use-package groovy-mode
  :ensure (:host github :repo "Groovy-Emacs-Modes/groovy-emacs-modes"))

;;; CSV
(use-package csv-mode
  :ensure t)

;;; F#
(use-package fsharp-mode
  :ensure (:host github :repo "fsharp/emacs-fsharp-mode"))

;;; Haskell
(use-package haskell-mode
  :ensure (:host github :repo "haskell/haskell-mode")
  :custom
  (haskell-stylish-on-save t)
  :hook ((haskell-mode . turn-on-haskell-doc-mode)
         (haskell-mode . turn-on-haskell-indentation)))

;;; Dockerfile
;; Emacs 29+ ビルトインの dockerfile-ts-mode を使う。grammar は Nix 側
;; (default.nix) で libtree-sitter-dockerfile.so として配置済み。
(use-package dockerfile-ts-mode
  :ensure nil
  :mode (("/Dockerfile\\(?:\\..*\\)?\\'" . dockerfile-ts-mode)
         ("\\.[Dd]ockerfile\\'" . dockerfile-ts-mode)
         ("/Containerfile\\(?:\\..*\\)?\\'" . dockerfile-ts-mode)))

;;; Terraform
(use-package terraform-mode
  :ensure t
  :custom
  (terraform-format-on-save t))

;;; Nix
(use-package nix-mode
  :ensure t
  :mode "\\.nix\\'")

;;; Nginx
(use-package nginx-mode
  :ensure t)

;;; Mermaid
(use-package mermaid-mode
  :ensure (:host github :repo "abrochard/mermaid-mode")
  :custom
  (mermaid-output-format ".pdf")
  :bind (:map mermaid-mode-map
         ("TAB" . mermaid-indent-line)
         ("<tab>" . mermaid-indent-line)))

;;; ebuild-mode (Gentoo)
(use-package ebuild-mode
  :ensure (:url "https://anongit.gentoo.org/git/proj/ebuild-mode.git"
           :pre-build (("make"))))

;;;; ============================================================
;;;; Email (oauth2)
;;;; ============================================================
(use-package oauth2
  :ensure (:host github :repo "emacsmirror/oauth2")
  :defer t)

;;;; ============================================================
;;;; Misc tools
;;;; ============================================================
(use-package bui
  :ensure (:host github :repo "alezost/bui.el"))

(use-package popwin
  :ensure t)

(use-package sqlite-dump
  :ensure (:host github :repo "nanasess/sqlite-dump")
  :mode "\\.\\(db\\|sqlite\\)\\'"
  :init
  (modify-coding-system-alist 'file "\\.\\(db\\|sqlite\\)\\'" 'raw-text-unix))

(use-package fosi
  :ensure (:host github :repo "hotoku/fosi" :branch "main"
           :files ("elisp/*.el"))
  :commands fosi)

(use-package shell-maker
  :ensure (:host github :repo "xenodium/shell-maker" :branch "main"))

(use-package mcp
  :ensure (:host github :repo "lizqwerscott/mcp.el"))

(use-package wakatime-mode
  :ensure t
  :hook (after-init . global-wakatime-mode)
  :custom
  (wakatime-cli-path (executable-find "wakatime-cli")))

(use-package recentf-ext
  :ensure t
  :custom
  (recentf-max-saved-items 50000)
  :hook (after-init . recentf-mode))

(use-package auto-save-buffers-enhanced
  :ensure (:host github :repo "kentaro/auto-save-buffers-enhanced")
  :custom
  (auto-save-buffers-enhanced-interval 30)
  (auto-save-buffers-enhanced-save-scratch-buffer-to-file-p t)
  (auto-save-buffers-enhanced-file-related-with-scratch-buffer
   (concat external-directory "howm/scratch.txt"))
  :config
  (auto-save-buffers-enhanced t)
  :bind ("C-x a s" . auto-save-buffers-enhanced-toggle-activity))

(use-package gcmh
  :ensure t
  :demand t
  :custom
  (gcmh-verbose t)
  :config
  (gcmh-mode 1))

;;;; ============================================================
;;;; Minibuffer extras
;;;; ============================================================
(bind-key "C-x C-j" #'nskk-kakutei minibuffer-local-map)

;; npm i -g vscode-json-languageserver
;; for json format
;; see https://qiita.com/saku/items/d97e930ffc9ca39ac976
(defun jq-format (beg end)
  (interactive "r")
  (shell-command-on-region beg end "jq ." nil t))

;;;; ============================================================
;;;; Finalize
;;;; ============================================================
(elpaca-wait)

;; Generate lock file: ELPACA_WRITE_LOCK=1 emacs --init-directory .emacs.d --batch
;; Generate lock file: ELPACA_WRITE_LOCK=1 emacs --init-directory .emacs.d -l .emacs.d/early-init.el -l .emacs.d/init.el --batch
(when (getenv "ELPACA_WRITE_LOCK")
  (elpaca-write-lock-file elpaca-lock-file))

(ffap-bindings)
(setq gc-cons-percentage 0.1)
(setq file-name-handler-alist my/saved-file-name-handler-alist)

;; Local Variables:
;; no-byte-compile: t
;; no-native-compile: t
;; no-update-autoloads: t
;; End:
