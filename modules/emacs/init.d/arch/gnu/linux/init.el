;;----------------------- window settings ---------------------------
;; sudo apt-get install xfonts-mplus
(defun my/set-font-linux (frame)
  "Set font for FRAME when it is a graphic display."
  (when (display-graphic-p frame)
    (set-face-attribute 'default frame :family "UDEV Gothic NF" :height 120)))

(if (daemonp)
    (add-hook 'after-make-frame-functions #'my/set-font-linux)
  (when (display-graphic-p)
    (set-face-attribute 'default nil :family "UDEV Gothic NF" :height 120)))
;; (setq initial-frame-alist
;;       (append (list
;;                '(height . 32)
;;                '(width  . 82)
;;                initial-frame-alist)))
;; (setq default-frame-alist initial-frame-alist))
;; )
;;;
;;; see https://github.com/4U6U57/wsl-open
;; (when (executable-find "wsl-open")
;;   (setq browse-url-generic-program "wsl-open")
;;   (setq browse-url-browser-function 'browse-url-generic))

(require 'server)
(unless (server-running-p)
  (server-start))
(provide 'linux-init)
