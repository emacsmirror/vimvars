;;; vimvars.el --- Emacs support for VI modelines

;; Copyright (C) 2010 James Youngman.

;; Author: James Youngman <james@youngman.org>
;; Maintainer: James Youngman

;; vimvars is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; vimvars is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with vimvars.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Defines a function `vimvars-obey-vim-modeline' which is suitable for
;; a hook which checks for a VI-style in the current buffer and sets
;; various Emacs buffer-local variables accordingly.

(defgroup vimvars nil
  "Support for VIM mode lines."
  :group 'find-file)


(defcustom vimvars-enabled t
  "If nil, VIM mode lines will be ignored."
  :type 'boolean
  :group 'vimvars)
(make-variable-buffer-local 'vimvars-enabled)


(defcustom vimvars-check-lines 5
  "The number of lines in the head of a file that we will search
for VIM settings (VIM itself checks 5)."
  :type 'integer
  :group 'vimvars)


(defcustom vimvars-ignore-mode-line-if-local-variables-exist t
  "If non-nil, VIM mode lines are ignored in files that have Emacs 
local variables."
  :type 'boolean
  :group 'vimvars)


;; It appears that real VIM accepts backslash-escaped characters (for
;; example \\| inside makeprg).
;;
;; Also, VIM accepts vi: and vim: at start-of line (but not ex:)
(defconst vimvars-modeline-re 
  ;; FIXME: accept vi: at start-of-line (but not ex:)
  "\\(^\\|[ 	]\\)\\(ex\\|vim?\\):[	 ]?\\(set\\|setlocal\\|se\\)? \\([^:]+\\):"
  "Regex matching a VIM modeline.")


(defun vimvars-should-obey-modeline ()
  "Returns non-nil if a VIM modeline should be obeyed in this file."
  ;; Always return nil if vimvars-enabled is nil.
  ;; Otherwise, if there are Emacs local variables for this file, 
  ;; return nil unless vimvars-ignore-mode-line-if-local-variables-exist
  ;; is also nil.
  (when vimvars-enabled
    (if file-local-variables-alist
        (not vimvars-ignore-mode-line-if-local-variables-exist)
      t)))

  

(defvar vimvars-buffer-coding-system-bom-transitions
  ;; (Current On Off)
  '(("utf-8" "utf-8-with-signature" nil)
    ("utf-8-auto" "utf-8-with-signature" "utf-8")
    ("utf-8-with-signature" nil "utf-8-with-signature")
    ("utf-16le" "utf-16le-with-signature" nil)
    ("utf-16be" "utf-16be-with-signature" nil)
    ("utf-16le-with-signature" nil "utf-16le")
    ("utf-16be-with-signature" nil "utf-16be")
    ;; coding system utf-16 chooses byte order based on the BOM,
    ;; but to select a specific coding system, we'd need to know
    ;; if the actual BOM is little-endian or big-endian.
    ("utf-16" nil nil))
  "Transition table for turning BOM marking on or off.
   Each element of the list is a list of 3 coding system names:
   (CURRENT ON OFF)
   If the current coding system is CURRENT, go to ON to turn use of a 
   byte-order-mark on, go to OFF to turn if OFF.  nil means, don't change
   the coding system.
   
   Visiting a file literally results in the use of the no-conversion coding
   system, so it would probably be a bad idea to put that in this list.")


(defun vimvars-accept-tag (leader tag)
  "Returns non-nil if LEADER followed by TAG should be accepted as a modeline."
  (cond 
   ((equal "vim" tag) t)
   ((equal "vi" tag) t)
   ;; Accept "ex:" only when it is not at the beginning of a line.
   ((equal "ex" tag) (not (equal 0 (length leader))))
   (t nil)))


(defun vimvars-obey-vim-modeline ()
  "Check the top of a file for VIM-style settings, and obey them.
Only the first `vimvars-chars-in-file-head' characters of the file 
are checked for VIM variables.   You can use this in `find-file-hook'."
  (when (vimvars-should-obey-modeline)
    (save-excursion
      ;; Look for something like this: vi: set sw=4 ts=4:
      ;; We should look for it in a comment, but for now
      ;; we won't worry about the syntax of the major mode.
      (goto-char (point-min))
      (if (and
           (re-search-forward vimvars-modeline-re
		  (line-end-position vimvars-check-lines) t)
           (vimvars-accept-tag (match-string 1) (match-string 2)))
          (progn
            (message "found a modeline: %s" (match-string 0))
            (let ((settings-end (match-end 4)))
	;; We ignore the local suffix, since for Emacs
	;; most settings will be buffer-local anyway.
	;;(message "found VIM settings %s" (match-string 4))
	(goto-char (match-beginning 4))
	(while (re-search-forward 
	        " *\\([^= ]+\\)\\(=\\([^ :]+\\)\\)?" settings-end t)
	  (let ((variable (vimvars-expand-option-name (match-string 1))))
	    (if (match-string 3)
	        (vimvars-assign variable (match-string 3))
	      (vimvars-enable-feature variable))))))))))


(defun vimvars-set-indent (indent)
  (when (equal major-mode 'c-mode) (setq c-basic-offset indent)))


(defun vimvars-expand-option-name (option)
  "Expand a VIM option abbreviation."
  (let ((expansion 
	 (assoc option
		'(("ro" "readonly")
		  ("sts" "softtabstop")
		  ("sw" "shiftwidth")
		  ("ts" "tabstop")
		  ("tw" "textwidth")))))
    (if expansion (cadr expansion) option)))
   

;;; Not supported:
;;; comments/com (comment leader), because it's not language-specific in VIM.
(defun vimvars-assign (var val)
  "Emumate VIM's :set VAR=VAL."
  (message "Setting VIM option %s to %s in %s" var val (buffer-name))
  (cond 
   ((equal var "makeprg") (setq compile-command val))
   ((equal var "shiftwidth") (vimvars-set-indent (string-to-number val)))
   ((equal var "softtabstop") t) ; Ignore.
   ((equal var "tabstop") (setq tab-width (string-to-number val)))
   ((equal var "textwidth") (set-fill-column (string-to-number val)))
   (t (message "Don't know how to emulate VIM variable %s" var))))


(defun vimvars-select-bom-coding-system (bom)
  "Choose a new coding system on the basis of whether we want a BOM.
The result is nil if no transition is needed.  If we don't need a
BOM, as with latin1, nil is also returned.  Lastly, we return nil
for utf-16 since we don't know what to do."
  (let ((transition (assoc buffer-file-coding-system 
			   vimvars-buffer-coding-system-bom-transitions)))
    (if state (cadr transition) (car (cdr (cdr transition))))))
  
(defun vimvars-set-byte-order-mark (state)
  "Enable or disable the use of a byte-order mark."
  (let ((newsystem (vimvars-select-bom-coding-system state)))
    (when newsystem
      (set-buffer-coding-system newsystem))))

;; FIXME: Also consider supporting ...
;; fileencoding, encoding could be useful but likely too hairy
;; fileformat
;; tags
;; textmode (but this is obsolete in VIM, replaced by fileformat)
(defun vimvars-enable-feature (var)
  "Emulate VIM's :set FEATURE."
  (message "Enabling VIM option %s in %s" var (buffer-name))
  (cond 
   ((equal var "bomb") (vimvars-select-bom-coding-system t))
   ((equal var "ignorecase") (setq case-fold-search t))
   ((equal var "readonly") (toggle-read-only 1))
   ((equal var "wrap") (setq truncate-lines nil))
   ((equal var "write") (toggle-read-only -1)) ; Similar, not the same.
   
   ((equal var "nobomb") (vimvars-select-bom-coding-system nil))
   ((equal var "noignorecase") (setq case-fold-search nil))
   ((equal var "noreadonly") (toggle-read-only -1))
   ((equal var "nowrap") (setq truncate-lines t))
   ((equal var "nowrite") (toggle-read-only 1)) ; Similar, not the same

   (t (message "Don't know how to emulate VIM feature %s" var))))

(provide 'vimvars)
