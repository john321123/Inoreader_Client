;;; grc-lib.el --- Google Reader Mode for Emacs
;;
;; Copyright (c) 2011 David Leatherman
;;
;; Author: David Leatherman <leathekd@gmail.com>
;; URL: http://www.github.com/leathekd/grc
;; Version: 0.1.0

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This file contains general purpose elisp functions that I find
;; useful

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
(defun grc-list (thing)
  "Return THING if THING is a list or a list with THING as its element."
  (if (listp thing)
      thing
    (list thing)))

(defun grc-string (thing)
  "Return THING if THING is a string or convert THING to a string and return it"
  (if (stringp thing)
      thing
    (prin1-to-string thing t)))

(defun grc-flatten (x)
  "Takes a nested list of lists and returns the contents as a single flat list.
  (grc-flatten nil) returns nil"
  (cond ((null x) nil)
        ((listp x) (append (grc-flatten (car x)) (grc-flatten (cdr x))))
        (t (list x))))

(defun grc-get-in (alist seq &optional not-found)
  "Return the value in a nested alist structure.

  seq is a list of keys
  Returns nil or the not-found value if the key is not present"
  (let ((val (reduce (lambda (a k)
                       (aget a k)) seq :initial-value alist)))
    (or val not-found)))

(defun grc-sort-by (key entries &optional reverse-result secondary-key)
  "Sort a list of alists by a particular key.  Note that this converts alist
  values to strings before sorting.

  reverse-result will reverse the list prior to returning
  secondary-key can be used to specify another field in the alist to sort by in
  the case that two values are identical for the primary sort.  The order is
  random in that case, otherwise."
  (let* ((sorted (sort (copy-alist entries)
                       (lambda (a b)
                         (let ((result (compare-strings
                                        (grc-string (aget a key)) 0 nil
                                        (grc-string (aget b key)) 0 nil t)))
                           (cond
                            ((and secondary-key
                                  (eq result t))
                             (string<
                              (downcase (grc-string (aget a secondary-key)))
                              (downcase (grc-string (aget b secondary-key)))))
                            ((> result 0) nil)
                            ((< result 0) t)
                            (t nil))))))
         (sorted (if reverse-result (reverse sorted) sorted)))
    sorted))

(defun grc-group-by (key entries)
  "Partition a list of alists based on the specified key.  Returns an alist
  whose keys are the values of the specified key in the call to grc-group-by.

  That is, given the list:
  (((name . \"fred\") (age . 25))
   ((name . \"barney\") (age . 25))
   ((name . \"wilma\") (age . 22)))

  (grc-group-by 'age the-list) will return:

  ((22 ((name . \"wilma\")  (age . 22)))
   (25 ((name . \"barney\") (age . 25))
       ((name . \"fred\")   (age . 25)))) "
  (let* ((groups (remq nil (remove-duplicates
                            (mapcar (lambda (entry)
                                      (grc-string (aget entry key t))) entries)
                            :test 'string=)))
         (ret-list '()))
    (mapcar (lambda (entry)
              (let* ((group-name (aget entry key t))
                     (group (aget ret-list group-name t)))
                (aput 'ret-list group-name (cons entry group))))
            entries)
    ret-list))

(provide 'grc-lib)
;;; grc-lib.el ends here
