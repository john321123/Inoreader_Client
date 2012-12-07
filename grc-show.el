;;; grc-show.el --- Google Reader Mode for Emacs
;;
;; Copyright (c) 2011 David Leatherman
;;
;; Author: David Leatherman <leathekd@gmail.com>
;; URL: http://www.github.com/leathekd/grc
;; Version: 0.1.0

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This file contains the code for showing an individual Reader entry

;;; License:

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Code:
;; TODO- add light colors
(defface grc-show-header-face
  '((t :foreground "green" :bold t))
  "Face used for displaying header names."
  :group 'grc-faces)

(defface grc-show-context-face
  '((t (:foreground "DeepSkyBlue1" :bold t)))
  "Face used for displaying next/previous story headers."
  :group 'grc-faces)

(defcustom grc-use-w3m t
  "Use w3m to render the entries."
  :group 'grc
  :type 'boolean)

(defcustom grc-use-anchor-annotations t
  "When w3m is not available, render links inline or add an annotation and
list links at the bottom"
  :group 'grc
  :type 'boolean)

(defvar grc-show-buffer "*grc show*" "Name of the buffer for the grc show view")

(defun grc-show-entry (entry)
  "Print the given entry in the grc-show-buffer"
  (let ((buffer (get-buffer-create grc-show-buffer)))
    (with-current-buffer buffer
      (grc-show-mode)
      (let ((inhibit-read-only t)
            (next-entry (cadr (member entry grc-entry-cache)))
            (prev-entry (cadr (member entry (reverse grc-entry-cache))))
            (summary (or (aget entry 'content t)
                         (aget entry 'summary t)
                         "No summary provided.")))
        (erase-buffer)
        (mapcar (lambda (lst) (insert (format "%s:  %s\n"
                                         (car lst) (cadr lst))))
                `(("Title"  ,(grc-prepare-text
                              (grc-title-for-printing entry)))
                  ("Link"   ,(aget entry 'link))
                  ("Date"   ,(format-time-string
                              "%a %m/%d %l:%M %p"
                              (seconds-to-time (aget entry 'date))))
                  ("Source" ,(aget entry 'src-title))
                  ("Next Story"
                   ,(if next-entry
                        (grc-prepare-text
                         (concat (grc-title-for-printing next-entry)
                                 " [" (aget next-entry 'src-title) "]"))
                      "None"))
                  ("Previous Story"
                   ,(if prev-entry
                        (grc-prepare-text
                         (concat (grc-title-for-printing prev-entry)
                                 " [" (aget prev-entry 'src-title) "]"))
                      "None"))))

        (let ((before (point)))
          (insert "\n" summary)

          (if (and (featurep 'w3m)
                   grc-use-w3m)
              (progn
                (goto-char (point-min))
                (grc-replace-string "\n" "<br />")
                (let ((w3m-display-inline-images t)
                      (w3m-fill-column 80))
                  (w3m-region (point-min) (point-max))))
            (progn
              (grc-clean-buffer)
              (if grc-use-anchor-annotations
                  (progn
                    (goto-char (point-max))
                    (let ((after (search-backward-regexp "\n\nLinks:\n" nil t)))
                      (when after
                        (fill-region before after))))
                (fill-region before (point-max))))))

        (grc-highlight-keywords (append '("Title:" "Date:" "Source:" "Link:"
                                          "Next Story:" "Previous Story:")
                                        (grc-keywords grc-entry-cache))))
      (setq grc-current-entry (grc-mark-read entry))
      (goto-char (point-min))
      (switch-to-buffer buffer))
    (grc-list-refresh)))

(defun grc-show-help ()
  "Show the help message for the grc show view"
  (interactive)
  (grc-help))

(defun grc-show-mark-kept-unread ()
  "Mark the current entry as Keep Unread."
  (interactive)
  (setq grc-current-entry (grc-mark-kept-unread grc-current-entry))
  (grc-list-refresh))

(defun grc-show-mark-read ()
  "Mark the current entry as Read"
  (interactive)
  (setq grc-current-entry (grc-mark-read grc-current-entry))
  (grc-list-refresh))

(defun grc-show-mark-starred (remove)
  "Star the current entry."
  (interactive "P")
  (funcall (grc-mark-fn "starred") grc-current-entry remove)
  (grc-list-refresh))

(defun grc-show-kill-this-buffer ()
  "Close the show buffer and return to the list buffer."
  (interactive)
  (when (get-buffer grc-list-buffer)
    (switch-to-buffer (get-buffer grc-list-buffer))
    (kill-buffer grc-show-buffer)))

(defun grc-show-next-entry ()
  "View the next entry."
  (interactive)
  (let ((entry (cadr (member grc-current-entry grc-entry-cache))))
    (if entry
        (progn
          (grc-show-entry entry)
          (with-current-buffer grc-list-buffer
            (grc-list-refresh)
            (forward-line)))
      (error "No more entries"))))

(defun grc-show-previous-entry ()
  "View the previous entry."
  (interactive)
  (let ((entry (cadr (member grc-current-entry (reverse grc-entry-cache)))))
    (if entry
        (progn
          (grc-show-entry entry)
          (with-current-buffer grc-list-buffer
            (grc-list-refresh)
            (forward-line -1)))
      (error "No previous entries"))))

(defun grc-show-view-external ()
  "Load the current entry in an external browser."
  (interactive)
  (grc-view-external grc-current-entry))

(defun grc-show-advance-or-show-next-entry ()
  "Will move down 25 lines or load the next entry once at the bottom."
  (interactive)
  (if (eobp)
      (grc-show-next-entry)
    (let ((scroll-error-top-bottom t))
      (scroll-up-command 25)
      (when (eobp)
        (grc-show-next-entry)))))

(defun grc-show-external-view-url ()
  "Load the URL/anchor under point in an external browser."
  (interactive)
  (if (and (featurep 'w3m)
           grc-use-w3m)
      (w3m-external-view-this-url)
    (ffap)))

(defun grc-show-send-to-instapaper ()
  (interactive)
  (grc-send-to-instapaper grc-current-entry))

(defun grc-show-next-anchor ()
  "Move the point to the next anchor."
  (interactive)
  (if (and (featurep 'w3m)
           grc-use-w3m)
      (w3m-next-anchor)
    (forward-button 1 t)))

(defun grc-show-previous-anchor ()
  "Move the point to the previous anchor."
  (interactive)
  (if (and (featurep 'w3m)
           grc-use-w3m)
      (w3m-previous-anchor)
    (ffap-next-guess t)))

(defvar grc-show-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map " "               'grc-show-advance-or-show-next-entry)
    (define-key map "?"               'grc-show-help)
    (define-key map "q"               'grc-show-kill-this-buffer)
    (define-key map "k"               'grc-show-mark-kept-unread)
    (define-key map "r"               'grc-show-mark-read)
    (define-key map "*"               'grc-show-mark-starred)
    (define-key map "n"               'grc-show-next-entry)
    (define-key map "p"               'grc-show-previous-entry)
    (define-key map "v"               'grc-show-view-external)
    (define-key map "l"               'grc-show-send-to-instapaper)
    (define-key map (kbd "RET")       'grc-show-external-view-url)
    (define-key map (kbd "TAB")       'grc-show-next-anchor)
    (define-key map (kbd "<backtab>") 'grc-show-previous-anchor)
    map)
  "Keymap for \"grc show\" buffers.")
(fset 'grc-show-mode-map grc-show-mode-map)

(defun grc-show-mode ()
  "Major mode for viewing a feed entry in grc

  All currently available key bindings:

  S-TAB  Move the point to the previous anchor.
  TAB    Move the point to the next anchor.
  RET    Load the URL/anchor under point in an external browser.
  v      Load the current entry in an external browser.
  p      View the previous entry.
  n      View the next entry.
  *      Star the current entry.  Use the prefix operator to un-star.
  r      Mark the current entry as Read.
  k      Mark the current entry as Keep Unread.
  q      Close the show buffer and return to the list buffer.
  ?      Show the help message for the grc show view
  SPC    Will move down 25 lines or load the next entry once at the bottom."
  (interactive)
  (kill-all-local-variables)
  (use-local-map grc-show-mode-map)
  (mapcar (lambda (kw)
            (puthash kw 'grc-show-header-face grc-highlight-face-table))
          '("Title:" "Date:" "Source:" "Link:"))
  (mapcar (lambda (kw)
            (puthash kw 'grc-show-context-face grc-highlight-face-table))
          '("Next Story:" "Previous Story:"))
  (setq major-mode 'grc-show-mode
        mode-name "grc-show")
  (setq buffer-read-only t))

(provide 'grc-show)
;;; grc-show.el ends here
