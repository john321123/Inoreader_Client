;;; grc-req.el --- Google Reader Mode for Emacs
;;
;; Copyright (c) 2011 David Leatherman
;;
;; Author: David Leatherman <leathekd@gmail.com>
;; URL: http://www.github.com/leathekd/grc
;; Version: 0.1.0

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This file contains code for getting and posting from and to Google

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
(require 'json)

(defvar grc-req-client-name "grc-emacs-client"
  "Arbitrary client string for various reqeuests")

(defvar grc-auth-header-format
  "--header 'Authorization: Bearer %s'"
  "HTTP authorization headers to send.")

(defvar grc-req-base-url
  "https://www.inoreader.com/reader/"
  "Base URL for Google Reader  API.")

(defvar grc-req-subscribed-feed-list-url
  (concat grc-req-base-url
          "api/0/subscription/list")
  "URL for retrieving list of subscribed feeds.")

(defvar grc-req-preference-set-url
  (concat grc-req-base-url
          "api/0/preference/set")
  "URL for setting a preference")

(defvar grc-req-edit-tag-url
  (concat grc-req-base-url
          "api/0/edit-tag")
  "URL for editing a tag")

(defvar grc-req-edit-item-url
  (concat grc-req-base-url
          "api/0/item/edit")
  "URL for editing an entry")

(defvar grc-req-last-fetch-time nil)

(defcustom grc-curl-program "/usr/bin/curl"
  "Full path of the curl executable"
  :group 'grc
  :type 'string)

(defcustom grc-curl-options
  (concat "--compressed --silent --location --location-trusted "
          "--connect-timeout 2 --max-time 10 --retry 2")
  "Options to pass to all grc curl requests"
  :group 'grc
  :type 'string)

(defun grc-req-auth-header ()
  "returns the auth header for use in curl requests"
  (format grc-auth-header-format
          (aget grc-auth-access-token 'token)))

(defun grc-req-parse-response (raw-resp)
  (cond
   ((string-match "^{" raw-resp)
    (grc-parse-parse-response
     (let ((json-array-type 'list))
       (json-read-from-string
        (decode-coding-string raw-resp 'utf-8)))))
   ((string-match "^OK" raw-resp)
    "OK")
   (t nil)))

(defmacro grc-req-with-response (command response-sym &rest sentinel-forms)
  (declare (indent defun))
  (let ((buffer-name (generate-new-buffer-name "grc-req")))
    `(let* ((proc (start-process-shell-command "grc-req" ,buffer-name ,command))
            (sentinel-cb
             (apply-partially
              (lambda (cmd process signal)
                (when (string-match "^finished" signal)
                  (let ((,response-sym
                         (with-current-buffer ,buffer-name
                           (buffer-string))))
                    (kill-buffer ,buffer-name)
                    ,@sentinel-forms)))
              ,command)))
       (set-process-sentinel proc sentinel-cb))))

(defun grc-req-curl-command (verb endpoint
                                  &optional params no-auth raw-response)
  (let ((endpoint (concat endpoint
                          "?client=" grc-req-client-name
                          "&ck=" (grc-string (floor (* 1000000 (float-time))))
                          "&output=json"))
        (params (if (listp params) (grc-req-format-params params) params)))
    (format "%s %s %s -X %s %s '%s' "
            grc-curl-program
            grc-curl-options
            (if no-auth "" (grc-req-auth-header))
            verb
            (if (string= "POST" verb)
                (format "-d \"%s\"" params)
              "")
            (if (and (not (equal "" params)) (string= "GET" verb))
                (concat endpoint "&" params)
              endpoint))))

(defun grc-req-do-request (verb endpoint &optional params no-auth raw-response)
  "Makes the actual request via curl.  Handles both POST and GET."
  (unless no-auth (grc-auth-ensure-authenticated))
  (let* ((endpoint (concat endpoint
                           "?client=" grc-req-client-name
                           "&ck=" (grc-string (floor (* 1000000 (float-time))))
                           "&output=json"))
         (params (if (listp params) (grc-req-format-params params) params))
         (command (format
                   "%s %s %s -X %s %s '%s' "
                   grc-curl-program
                   grc-curl-options
                   (if no-auth "" (grc-req-auth-header))
                   verb
                   (if (string= "POST" verb)
                       (format "-d \"%s\"" params)
                     "")
                   (if (and (not (equal "" params)) (string= "GET" verb))
                       (concat endpoint "&" params)
                     endpoint)))
         (raw-resp (shell-command-to-string command)))
    (cond
     (raw-response raw-resp)
     ((string-match "^{" raw-resp)
      (let ((json-array-type 'list))
        (json-read-from-string
         (decode-coding-string raw-resp 'utf-8))))
     ((string-match "^OK" raw-resp) "OK")
     ((string= "" raw-resp) (error "Error during grc request."))
     (t (error "Error: %s?%s\nFull command: %s\nResponse: %s"
               endpoint params command raw-resp)))))

(defun grc-req-get-request (endpoint &optional params no-auth raw-response)
  "Makes a GET request to Google"
  (grc-req-do-request "GET" endpoint params no-auth raw-response))

(defun grc-req-post-request (endpoint params &optional no-auth raw-response)
  "Makes a POST request to Google"
  (grc-req-do-request "POST" endpoint params no-auth raw-response))

(defvar grc-req-stream-url-pattern
  "https://www.inoreader.com/reader/api/0/stream/contents/%s")

(defun grc-req-stream-url (&optional state)
  "Get the url for Google Reader entries, optionally limited to a specified
  state- e.g., kept-unread"
  (let ((stream-state (if (null state)
                          ""
                        (concat "user/-/state/com.google/" state))))
    (format grc-req-stream-url-pattern stream-state)))

(defun grc-req-format-params (params)
  "Convert an alist of params into an & delimeted string suitable for curl"
  (mapconcat (lambda (p) (concat (car p)
                            "="
                            (url-hexify-string (grc-string (cdr p)))))
             params "&"))

(defun grc-req-incremental-fetch (cb-fn)
  "Fetch only entries new since the last fetch for the reading-list"
  (when (string= grc-current-state "reading-list")
    (grc-req-remote-entries cb-fn grc-current-state grc-req-last-fetch-time)))

;; TODO: Need to factor out the state specific voodoo into something
;; less kludgy
(defun grc-req-remote-entries (&optional state since)
  "Get the remote entries.  This behaves slightly differently based on the given
  state. Optionally, only fetch items newer that 'since'"
  (let ((params `(("n"       . ,(grc-string grc-fetch-count))
                  ("client"  . "emacs-grc-client"))))
    (cond
     ((string= state "reading-list")
      (setq grc-req-last-fetch-time (floor (float-time)))
      (aput 'params "xt" "user/-/state/com.google/read")
      (aput 'params "r" "n")))
    (when since
      (aput 'params "ot" (prin1-to-string since)))
    (grc-req-curl-command
     "GET"
     (grc-req-stream-url state)
     (grc-req-format-params params))))

(defun grc-req-mark-kept-unread (id feed)
  "Send a request to mark an entry as kept-unread.  Will also remove the read
  category"
  (let ((params `(("a" . "user/-/state/com.google/kept-unread")
                  ("r" . "user/-/state/com.google/read")
                  ("s" . ,feed)
                  ("i" . ,id))))
    (grc-req-with-response
      (grc-req-curl-command "POST" grc-req-edit-tag-url params) _ t)))

(defun grc-req-mark-read (id feed)
  "Send a request to mark an entry as read.  Will also remove the kept-unread
  category"
  (let ((params `(("r" . "user/-/state/com.google/kept-unread")
                  ("a" . "user/-/state/com.google/read")
                  ("s" . ,feed)
                  ("i" . ,id))))
    (grc-req-with-response
      (grc-req-curl-command "POST" grc-req-edit-tag-url params) _ t)))

(defun grc-req-edit-tag (id feed tag remove-p)
  "Send a request to remove or add a tag (category/label)"
  (let ((params
         `((,(if remove-p "r" "a") . ,(concat "user/-/state/com.google/" tag))
           ("s" . ,feed)
           ("i" . ,id))))
    (grc-req-with-response
      (grc-req-curl-command "POST" grc-req-edit-tag-url params) _ t)))

(defun grc-req-mark-all-read (&optional src)
  "Mark all items for 'src' as read"
  (let ((url "https://www.inoreader.com/reader/api/0/mark-all-as-read")
        (params `(("s"  . ,(or src "user/-/state/com.google/reading-list"))
                  ("ts" . ,(floor (* 1000000 (float-time)))))))
    (grc-req-with-response (grc-req-curl-command "POST" url params) _ t)))

(defun grc-req-subscriptions ()
  "Get a list of all subscribed feeds"
  (grc-req-get-request grc-req-subscribed-feed-list-url))

(provide 'grc-req)
;;; grc-req.el ends here
