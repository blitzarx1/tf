;;; tf-ts-mode-test.el --- Tests for tf-ts-mode  -*- lexical-binding: t; -*-

;; Run from the repo root, after `tree-sitter build -o DIR/libtree-sitter-tfmd.dylib' in
;; `tree-sitter-tfmd/' (use .so on Linux):
;;
;;   emacs --batch -L emacs -l emacs/tf-ts-mode-test.el \
;;         --eval '(setq treesit-extra-load-path (list "DIR"))' -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'tf-ts-mode)

(defconst tf-ts-mode-test--sample
  "# todo

- [ ] open task with a title that wraps
      under the title text
    . 1792321201
    ! 100
    : tag1, tag2

  D : Description text,
      wrapped under the text.

      1. Step one,
         wrapped.
         * nested item
           wrapped nested
      * bullet

  C : comment

      ```
          - [ ] example
              ! 100
      ```

--------------------------------

- ~~[ ] cancelled title
        wraps~~
"
  "A well-formed file: indenting it must not change anything.")

(defmacro tf-ts-mode-test--with-buffer (text &rest body)
  "Run BODY in a `tf-ts-mode' buffer holding TEXT, point at its end."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (tf-ts-mode)
     (goto-char (point-max))
     ,@body))

(ert-deftest tf-ts-mode-test-mode ()
  (tf-ts-mode-test--with-buffer tf-ts-mode-test--sample
    (should (eq major-mode 'tf-ts-mode))
    (should-not indent-tabs-mode)
    (should (= fill-column 100))
    (should-not (string-match-p "ERROR\\|invalid"
                                (treesit-node-string (treesit-buffer-root-node 'tfmd))))))

(ert-deftest tf-ts-mode-test-indent-region-keeps-wellformed ()
  (tf-ts-mode-test--with-buffer tf-ts-mode-test--sample
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string) tf-ts-mode-test--sample))))

(ert-deftest tf-ts-mode-test-indent-region-fixes-flat ()
  "Stripping the indentation of every line (but code and nested lists) and indenting restores it."
  (let ((flat (replace-regexp-in-string
               "^ +\\([^ *`]\\)" "\\1"
               (replace-regexp-in-string "^ +\\(    . \\|    ! \\|    : \\)" "\\1"
                                         tf-ts-mode-test--sample))))
    (should-not (equal flat tf-ts-mode-test--sample))
    (tf-ts-mode-test-indent--check flat)))

(defun tf-ts-mode-test-indent--check (flat)
  "Indent FLAT line by line and compare each line's column with the sample's."
  (let ((expected (split-string tf-ts-mode-test--sample "\n")))
    (with-temp-buffer
      (insert flat)
      (tf-ts-mode)
      (indent-region (point-min) (point-max))
      (let ((got (split-string (buffer-string) "\n")) (n 0))
        (while (and got expected)
          (setq n (1+ n))
          ;; lines of the flat text that carried their own markers keep what the sample had
          (when (and (string-match-p "\\`\\(\\s-*[*-]\\|\\s-*`\\|\\s-*[0-9]+\\.\\)" (car expected))
                     (not (string-match-p "\\`- " (car expected))))
            (setq got (cdr got) expected (cdr expected)))
          (when (and got expected)
            (should (equal (cons n (string-trim-left (car got)))
                           (cons n (string-trim-left (car expected)))))
            (setq got (cdr got) expected (cdr expected))))))))

(defun tf-ts-mode-test--column-after-ret (text)
  "Column of the new line after a line break typed at the end of TEXT."
  (tf-ts-mode-test--with-buffer text
    (newline-and-indent)
    (current-column)))

(ert-deftest tf-ts-mode-test-ret-aligns-with-paragraph-text ()
  (should (= 6 (tf-ts-mode-test--column-after-ret "# todo\n\n- [ ] title")))
  (should (= 8 (tf-ts-mode-test--column-after-ret "# todo\n\n- ~~[ ] title")))
  (should (= 6 (tf-ts-mode-test--column-after-ret "# todo\n\n- [ ] t\n\n  D : text")))
  (should (= 6 (tf-ts-mode-test--column-after-ret "# todo\n\n- [ ] t\n\n  D : text\n      more")))
  (should (= 9 (tf-ts-mode-test--column-after-ret "# todo\n\n- [ ] t\n\n  D : x\n\n      1. step")))
  (should (= 8 (tf-ts-mode-test--column-after-ret "# todo\n\n- [ ] t\n\n  D : x\n\n      * item")))
  (should (= 11 (tf-ts-mode-test--column-after-ret
                 "# todo\n\n- [ ] t\n\n  D : x\n\n      1. a\n         * nested")))
  (should (= 2 (tf-ts-mode-test--column-after-ret "# todo\n\n- [ ] t\n    ! 5")))
  (should (= 10 (tf-ts-mode-test--column-after-ret
                 "# todo\n\n- [ ] t\n\n  D : x\n\n      ```\n          code")))
  (should (= 10 (tf-ts-mode-test--column-after-ret
                 "# todo\n\n- [ ] t\n\n  D : x\n\n      ```"))))

(ert-deftest tf-ts-mode-test-ret-after-blank-line ()
  (should (= 6 (tf-ts-mode-test--column-after-ret "# todo\n\n- [ ] t\n\n  D : text\n")))
  (should (= 0 (tf-ts-mode-test--column-after-ret "# todo\n"))))

(ert-deftest tf-ts-mode-test-lookalikes-in-text-stay ()
  "Heading-looking text inside a title or a field is text, not structure."
  (let ((text (concat "# todo\n\n- [ ] title\n      # todo section\n\n"
                      "  D : text\n\n      # backlog of ideas\n")))
    (tf-ts-mode-test--with-buffer text
      (indent-region (point-min) (point-max))
      (should (equal (buffer-string) text)))))

(ert-deftest tf-ts-mode-test-tab-on-typed-line ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] t\n\n  D : x\n"
    (insert "C : y")
    (indent-for-tab-command)
    (should (equal (buffer-substring (line-beginning-position) (point)) "  C : y")))
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] t\n"
    (insert "! 5")
    (indent-for-tab-command)
    (should (equal (buffer-substring (line-beginning-position) (point)) "    ! 5")))
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] t\n\n  D : x\n"
    (insert "* item")
    (indent-for-tab-command)
    (should (equal (buffer-substring (line-beginning-position) (point)) "      * item"))))

(ert-deftest tf-ts-mode-test-font-lock ()
  (tf-ts-mode-test--with-buffer tf-ts-mode-test--sample
    (font-lock-mode 1)
    (font-lock-ensure)
    (goto-char (point-min))
    (should (eq (get-text-property 1 'face) 'font-lock-keyword-face))
    (search-forward "- [ ] ")
    (should (eq (get-text-property (- (point) 3) 'face) 'font-lock-function-name-face))
    (should (eq (get-text-property (1+ (point)) 'face) 'tf-ts-title-face))
    (search-forward "  D :")
    (should (eq (get-text-property (- (point) 2) 'face) 'font-lock-keyword-face))))

(ert-deftest tf-ts-mode-test-long-line-highlight ()
  (tf-ts-mode-test--with-buffer (concat "# todo\n\n- [ ] " (make-string 100 ?x) "\n")
    (font-lock-mode 1)
    (font-lock-ensure)
    (goto-char (point-min))
    (forward-line 2)
    (move-to-column 100)
    (should (eq (get-text-property (point) 'face) 'tf-ts-overflow-face))
    (move-to-column 99)
    (should-not (eq (get-text-property (point) 'face) 'tf-ts-overflow-face))))

(ert-deftest tf-ts-mode-test-auto-fill ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] t\n\n  D : "
    (auto-fill-mode 1)
    (dotimes (i 60)
      (dolist (c (string-to-list "word "))
        (let ((last-command-event c)) (self-insert-command 1))))
    (let ((lines (split-string (buffer-string) "\n")))
      (dolist (l lines) (should (<= (length l) 100)))
      (should (> (length lines) 6))
      (dolist (l (nthcdr 5 lines))
        (when (> (length l) 0) (should (string-prefix-p "      " l)))))))

(ert-deftest tf-ts-mode-test-next-previous-task ()
  (tf-ts-mode-test--with-buffer tf-ts-mode-test--sample
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (should (looking-at "- \\[ \\] open task"))
    (tf-ts-mode-next-task)
    (should (looking-at "- ~~\\[ \\] cancelled"))
    (should-error (tf-ts-mode-next-task) :type 'user-error)
    (tf-ts-mode-previous-task)
    (should (looking-at "- \\[ \\] open task"))
    (should-error (tf-ts-mode-previous-task) :type 'user-error)))

(defun tf-ts-mode-test--no-ids (text)
  "TEXT with the unix time ids replaced by ID."
  (replace-regexp-in-string "^\\(    \\. \\)[0-9]+$" "\\1ID" text))

(ert-deftest tf-ts-mode-test-new ()
  (tf-ts-mode-test--with-buffer
      (concat "# todo\n\n- [ ] one\n\n" tf-ts-mode--separator "\n\n- [ ] two\n")
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (tf-ts-mode-new)
    (insert "new")
    (should (equal (tf-ts-mode-test--no-ids (buffer-string))
                   (concat "# todo\n\n- [ ] one\n\n" tf-ts-mode--separator
                           "\n\n- [ ] new\n    . ID\n\n" tf-ts-mode--separator
                           "\n\n- [ ] two\n")))))

(ert-deftest tf-ts-mode-test-new-last ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] one\n\n  D : text\n"
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (tf-ts-mode-new)
    (should (equal (tf-ts-mode-test--no-ids (buffer-string))
                   (concat "# todo\n\n- [ ] one\n\n  D : text\n\n" tf-ts-mode--separator
                           "\n\n- [ ] \n    . ID\n")))
    (should (looking-at "\n    \\. "))))

(ert-deftest tf-ts-mode-test-new-outside-todo ()
  (tf-ts-mode-test--with-buffer
      (concat "# todo\n\n- [ ] one\n\n# backlog\n\n- [ ] later\n")
    (goto-char (point-min))
    (search-forward "later")
    (tf-ts-mode-new)
    (insert "new")
    (should (equal (tf-ts-mode-test--no-ids (buffer-string))
                   (concat "# todo\n\n- [ ] new\n    . ID\n\n" tf-ts-mode--separator
                           "\n\n- [ ] one\n\n# backlog\n\n- [ ] later\n")))))

(ert-deftest tf-ts-mode-test-add-description ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] one\n"
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (tf-ts-mode-add-description)
    (insert "text")
    (should (equal (buffer-string) "# todo\n\n- [ ] one\n\n  D : text\n")))
  ;; existing D: new paragraph in it, before the C field
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] one\n\n  D : text\n\n  C : note\n"
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (tf-ts-mode-add-description)
    (insert "more")
    (should (equal (buffer-string)
                   "# todo\n\n- [ ] one\n\n  D : text\n\n      more\n\n  C : note\n")))
  ;; only C exists: D goes before it
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] one\n\n  C : note\n"
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (tf-ts-mode-add-description)
    (insert "text")
    (should (equal (buffer-string) "# todo\n\n- [ ] one\n\n  D : text\n\n  C : note\n"))))

(ert-deftest tf-ts-mode-test-add-comment ()
  (tf-ts-mode-test--with-buffer
      (concat "# todo\n\n- [ ] one\n\n  D : text\n\n" tf-ts-mode--separator "\n")
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (tf-ts-mode-add-comment)
    (insert "note")
    (should (equal (buffer-string)
                   (concat "# todo\n\n- [ ] one\n\n  D : text\n\n  C : note\n\n"
                           tf-ts-mode--separator "\n")))))

(ert-deftest tf-ts-mode-test-separators ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] one\n"
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (tf-ts-mode-separator-below)
    (should (equal (buffer-string)
                   (concat "# todo\n\n- [ ] one\n\n" tf-ts-mode--separator "\n"))))
  (tf-ts-mode-test--with-buffer
      (concat "# todo\n\n- [ ] one\n\n" tf-ts-mode--separator "\n\n- [ ] two\n")
    (goto-char (point-max))
    (tf-ts-mode-previous-task)
    (tf-ts-mode-separator-above)
    (should (equal (buffer-string)
                   (concat "# todo\n\n- [ ] one\n\n" tf-ts-mode--separator "\n\n"
                           tf-ts-mode--separator "\n\n- [ ] two\n")))))

;;;; advance task stage

(defconst tf-ts-mode-test--sep tf-ts-mode--separator)

(defun tf-ts-mode-test--advance (text &optional marker)
  "Advance the task whose title contains MARKER (default \"] one\") in TEXT; return the buffer."
  (with-temp-buffer
    (insert text)
    (tf-ts-mode)
    (goto-char (point-min))
    (search-forward (or marker "] one"))
    (tf-ts-mode-advance-task)
    (buffer-string)))

(ert-deftest tf-ts-mode-test-advance-backlog-to-todo ()
  (should (equal (tf-ts-mode-test--advance
                  (concat "# todo\n\n- [ ] zero\n\n# backlog\n\n- [ ] one\n\n  D : text\n\n"
                          tf-ts-mode-test--sep "\n\n- [ ] two\n"))
                 (concat "# todo\n\n- [ ] one\n\n  D : text\n\n" tf-ts-mode-test--sep
                         "\n\n- [ ] zero\n\n# backlog\n\n- [ ] two\n"))))

(ert-deftest tf-ts-mode-test-advance-into-empty-section ()
  (should (equal (tf-ts-mode-test--advance "# todo\n\n# backlog\n\n- [ ] one\n")
                 "# todo\n\n- [ ] one\n\n# backlog\n"))
  (should (equal (tf-ts-mode-test--advance "# todo\n\n- [ ] one\n\n# done\n")
                 "# todo\n\n# done\n\n- [x] one\n")))

(ert-deftest tf-ts-mode-test-advance-split-epic ()
  (let ((text (concat "# todo\n\n- [-] epic\n    . 1\n    ; e\n")))
    (should-error (tf-ts-mode-test--advance text "] epic") :type 'user-error)))

(ert-deftest tf-ts-mode-test-advance-todo-to-done ()
  (should (equal (tf-ts-mode-test--advance
                  (concat "# todo\n\n- [ ] zero\n\n" tf-ts-mode-test--sep
                          "\n\n- [ ] one\n\n# done\n\n- [x] old\n"))
                 (concat "# todo\n\n- [ ] zero\n\n# done\n\n- [x] one\n\n" tf-ts-mode-test--sep
                         "\n\n- [x] old\n"))))

(ert-deftest tf-ts-mode-test-advance-done-to-cancelled ()
  (should (equal (tf-ts-mode-test--advance
                  (concat "# done\n\n- [x] zero\n\n" tf-ts-mode-test--sep
                          "\n\n- [x] one\n      wraps\n    ! 5\n\n  C : note\n"))
                 (concat "# done\n\n- ~~[ ] one\n      wraps~~\n    ! 5\n\n  C : note\n\n"
                         tf-ts-mode-test--sep "\n\n- [x] zero\n"))))

(ert-deftest tf-ts-mode-test-advance-cancelled-to-backlog ()
  (should (equal (tf-ts-mode-test--advance
                  "# done\n\n- ~~[ ] one\n      wraps~~\n    ! 5\n\n# backlog\n\n- [ ] two\n")
                 (concat "# done\n\n# backlog\n\n- [ ] one\n      wraps\n    ! 5\n\n"
                         tf-ts-mode-test--sep "\n\n- [ ] two\n"))))

(ert-deftest tf-ts-mode-test-advance-loop ()
  (let ((text (concat "# todo\n\n# backlog\n\n- [ ] one\n\n  D : text\n\n  C : note\n\n"
                      "# done\n")))
    (with-temp-buffer
      (insert text)
      (tf-ts-mode)
      (goto-char (point-min))
      (search-forward "] one")
      (dotimes (_ 4) (tf-ts-mode-advance-task))
      (should (equal (buffer-string) text))
      (should (looking-at "- \\[ \\] one")))))

(ert-deftest tf-ts-mode-test-advance-keeps-wellformed ()
  (with-temp-buffer
    (insert (concat "# todo\n\n- [ ] one\n\n  D : x\n\n      * item\n\n# backlog\n\n# done\n"))
    (tf-ts-mode)
    (goto-char (point-min))
    (search-forward "] one")
    (dotimes (_ 3)
      (tf-ts-mode-advance-task)
      (let ((before (buffer-string)))
        (indent-region (point-min) (point-max))
        (should (equal (buffer-string) before))))))

(ert-deftest tf-ts-mode-test-advance-undo ()
  (with-temp-buffer
    (buffer-enable-undo)
    (insert "# todo\n\n- [ ] one\n\n# done\n\n- [x] old\n")
    (tf-ts-mode)
    (undo-boundary)
    (let ((text (buffer-string)))
      (goto-char (point-min))
      (search-forward "] one")
      (tf-ts-mode-advance-task)
      (should-not (equal (buffer-string) text))
      (undo-boundary)
      (primitive-undo 1 (if (null (car buffer-undo-list)) (cdr buffer-undo-list) buffer-undo-list))
      (should (equal (buffer-string) text)))))

(ert-deftest tf-ts-mode-test-advance-errors ()
  (with-temp-buffer
    (insert "# todo\n\n# done\n")
    (tf-ts-mode)
    (goto-char (point-max))
    (should-error (tf-ts-mode-advance-task) :type 'user-error)))

;;;; update

(defun tf-ts-mode-test--project (script)
  "A temp project with `.tf/tasks.tfmd' and, when SCRIPT, an executable `.tf/update.sh'."
  (let ((root (make-temp-file "tf-test" t)))
    (make-directory (expand-file-name ".tf" root))
    (write-region "# todo\n" nil (expand-file-name ".tf/tasks.tfmd" root))
    (when script
      (let ((f (expand-file-name ".tf/update.sh" root)))
        (write-region "#!/bin/sh\n" nil f)
        (set-file-modes f #o755)))
    root))

(ert-deftest tf-ts-mode-test-update-missing-script ()
  (let* ((root (tf-ts-mode-test--project nil))
         (default-directory (file-name-as-directory root)))
    (unwind-protect
        (should-error (tf-ts-mode-update) :type 'user-error)
      (delete-directory root t))))

(ert-deftest tf-ts-mode-test-update-declined ()
  (let* ((root (tf-ts-mode-test--project t))
         (default-directory (file-name-as-directory root))
         (started nil))
    (unwind-protect
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
                  ((symbol-function 'compilation-start) (lambda (&rest _) (setq started t))))
          (tf-ts-mode-update)
          (should-not started))
      (delete-directory root t))))

(ert-deftest tf-ts-mode-test-update-confirmed ()
  (let* ((root (tf-ts-mode-test--project t))
         (default-directory (file-name-as-directory root))
         (command nil) (dir nil))
    (unwind-protect
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                  ((symbol-function 'compilation-start)
                   (lambda (c &rest _) (setq command c dir default-directory))))
          (tf-ts-mode-update)
          (should (equal command ".tf/update.sh"))
          (should (equal (file-truename dir) (file-name-as-directory (file-truename root)))))
      (remove-hook 'compilation-finish-functions #'tf-ts-mode--after-update)
      (delete-directory root t))))

(defun tf-ts-mode-test--type (string)
  "Type STRING at point as self-inserting keys."
  (dolist (c (string-to-list string))
    (let ((last-command-event c))
      (self-insert-command 1))))

(ert-deftest tf-ts-mode-test-snap-property-marker ()
  (dolist (header '("- [ ] title" "- [x] title" "- ~~[ ] title~~"))
    (dolist (typed '(": emacs" "! 5" ". 17" "; b"))
      (tf-ts-mode-test--with-buffer (concat "# todo\n\n" header)
        (newline-and-indent)
        (should (= (if (string-prefix-p "- ~~" header) 8 6) (current-column)))
        (tf-ts-mode-test--type typed)
        (should (equal (buffer-substring (line-beginning-position) (point-max))
                       (concat "    " typed)))))))

(ert-deftest tf-ts-mode-test-snap-leaves-other-lines ()
  "Only a property marker snaps: titles, fields and text keep what was typed."
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] title"
    (newline-and-indent)
    (tf-ts-mode-test--type "wrapped title")
    (should (equal (buffer-substring (line-beginning-position) (point-max)) "      wrapped title")))
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] t\n\n  D : x"
    (newline-and-indent)
    (tf-ts-mode-test--type "a : b")
    (should (equal (buffer-substring (line-beginning-position) (point-max)) "      a : b"))))

(defun tf-ts-mode-test--snap (text typed)
  "Type TYPED on a new line after TEXT (a header) and return the buffer."
  (tf-ts-mode-test--with-buffer text
    (newline-and-indent)
    (tf-ts-mode-test--type typed)
    (buffer-string)))

(ert-deftest tf-ts-mode-test-snap-order ()
  (let ((head "# todo\n\n- [ ] title\n"))
    ;; each marker goes to its place among the others
    (should (equal (tf-ts-mode-test--snap (concat head "    . 1\n    ; b\n    : t") "! 5")
                   (concat head "    . 1\n    ! 5\n    ; b\n    : t")))
    (should (equal (tf-ts-mode-test--snap (concat head "    ! 5\n    : t") "; b")
                   (concat head "    ! 5\n    ; b\n    : t")))
    (should (equal (tf-ts-mode-test--snap (concat head "    ! 5\n    ; b") ": t")
                   (concat head "    ! 5\n    ; b\n    : t")))
    (should (equal (tf-ts-mode-test--snap (concat head "    ! 5\n    : t") ". 1")
                   (concat head "    . 1\n    ! 5\n    : t")))
    ;; under a wrapped title the id goes after the last title line
    (should (equal (tf-ts-mode-test--snap "# todo\n\n- [ ] title\n      wraps\n    : t" ". 1")
                   "# todo\n\n- [ ] title\n      wraps\n    . 1\n    : t"))
    ;; before a field
    (should (equal (tf-ts-mode-test--snap "# todo\n\n- [ ] title\n    : t" "! 5")
                   "# todo\n\n- [ ] title\n    ! 5\n    : t"))))

(ert-deftest tf-ts-mode-test-snap-order-point-and-duplicates ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] title\n    : t\n"
    (goto-char (point-min))
    (search-forward "title")
    (end-of-line)
    (insert "\n")
    (tf-ts-mode-test--type "! ")
    (should (equal (buffer-string) "# todo\n\n- [ ] title\n    ! \n    : t\n"))
    (should (looking-at "\n    : t")))
  ;; a kind the task has stays where it is, indented
  (should (equal (tf-ts-mode-test--snap "# todo\n\n- [ ] title\n    ! 5" "! ")
                 "# todo\n\n- [ ] title\n    ! 5\n    ! ")))

(ert-deftest tf-ts-mode-test-priority ()
  (let ((head "# todo\n\n- [ ] title\n    . 1\n"))
    (tf-ts-mode-test--with-buffer (concat head "    ! 50\n    : t\n")
      (goto-char (point-min)) (search-forward "title")
      (tf-ts-mode-priority-up)
      (should (equal (buffer-string) (concat head "    ! 60\n    : t\n")))
      (tf-ts-mode-priority-down) (tf-ts-mode-priority-down)
      (should (equal (buffer-string) (concat head "    ! 40\n    : t\n"))))
    ;; clamped to 0..100
    (tf-ts-mode-test--with-buffer (concat head "    ! 95\n")
      (goto-char (point-min)) (search-forward "title")
      (tf-ts-mode-priority-up)
      (should (equal (buffer-string) (concat head "    ! 100\n"))))
    (tf-ts-mode-test--with-buffer (concat head "    ! 5\n")
      (goto-char (point-min)) (search-forward "title")
      (tf-ts-mode-priority-down)
      (should (equal (buffer-string) (concat head "    ! 0\n"))))
    ;; no priority line: from the default 50, after the id
    (tf-ts-mode-test--with-buffer (concat head "    : t\n")
      (goto-char (point-min)) (search-forward "title")
      (tf-ts-mode-priority-up)
      (should (equal (buffer-string) (concat head "    ! 60\n    : t\n"))))
    ;; one undo step
    (tf-ts-mode-test--with-buffer (concat head "    ! 50\n")
      (buffer-enable-undo)
      (goto-char (point-min)) (search-forward "title")
      (undo-boundary)
      (tf-ts-mode-priority-up)
      (undo-boundary)
      (primitive-undo 1 (cdr buffer-undo-list))
      (should (equal (buffer-string) (concat head "    ! 50\n"))))))

(ert-deftest tf-ts-mode-test-id-date ()
  (should (equal (tf-ts-mode--id-date 1792321201) "2026-10-18T11:00:01Z"))
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] title\n    . 1792321201\n"
    (goto-char (point-min)) (search-forward "title")
    (let (shown)
      (cl-letf (((symbol-function 'message) (lambda (f &rest a) (setq shown (apply #'format f a)))))
        (tf-ts-mode-show-id-date))
      (should (equal shown "1792321201 = 2026-10-18T11:00:01Z")))
    (forward-line 1)
    (should (equal (tf-ts-mode--eldoc) "2026-10-18T11:00:01Z")))
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] title\n"
    (goto-char (point-min)) (search-forward "title")
    (should-error (tf-ts-mode-show-id-date) :type 'user-error)))

(ert-deftest tf-ts-mode-test-new-id-unique ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] a\n"
    (let ((first (tf-ts-mode--new-id)))
      (insert (format "    . %d\n" first))
      (should (> (tf-ts-mode--new-id) first)))))

;;;; code: inline and fenced

(defun tf-ts-mode-test--face-at (text word)
  "Face of the last character of WORD in TEXT, in a fontified `tf-ts-mode' buffer."
  (with-temp-buffer
    (insert text)
    (tf-ts-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward word)
    (get-text-property (1- (point)) 'face)))

(defun tf-ts-mode-test--has-face (face prop)
  (memq face (if (listp prop) prop (list prop))))

(ert-deftest tf-ts-mode-test-code-faces ()
  (let ((text (concat "# todo\n\n- [ ] title `code` end\n\n  D : x `inline` y\n\n"
                      "      ```\n          (foo)\n      ```\n")))
    (should (tf-ts-mode-test--has-face 'tf-ts-code-face (tf-ts-mode-test--face-at text "code`")))
    ;; layered over the title face
    (should (tf-ts-mode-test--has-face 'tf-ts-title-face (tf-ts-mode-test--face-at text "code`")))
    (should (tf-ts-mode-test--has-face 'tf-ts-code-face (tf-ts-mode-test--face-at text "inline`")))
    (should-not (tf-ts-mode-test--has-face 'tf-ts-code-face (tf-ts-mode-test--face-at text " end")))
    (should (tf-ts-mode-test--has-face 'tf-ts-code-face (tf-ts-mode-test--face-at text "(foo)")))
    (should (tf-ts-mode-test--has-face 'tf-ts-code-face
                                       (tf-ts-mode-test--face-at text "      ```")))))

(ert-deftest tf-ts-mode-test-unclosed-backtick-is-plain ()
  (should-not (tf-ts-mode-test--has-face
               'tf-ts-code-face
               (tf-ts-mode-test--face-at "# todo\n\n- [ ] a ` b c\n" "b c"))))

(defun tf-ts-mode-test--typed (text typed)
  "Buffer text and the text before point after typing TYPED at the end of TEXT."
  (tf-ts-mode-test--with-buffer text
    (tf-ts-mode-test--type typed)
    (list (buffer-string) (buffer-substring (line-beginning-position) (point)))))

(ert-deftest tf-ts-mode-test-backtick-pairs ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] a "
    (tf-ts-mode-test--type "`")
    (should (equal (buffer-string) "# todo\n\n- [ ] a ``"))
    (should (looking-at "`\\'"))))

(ert-deftest tf-ts-mode-test-backtick-typing-flow ()
  (should (equal (tf-ts-mode-test--typed "# todo\n\n- [ ] a " "`x`")
                 '("# todo\n\n- [ ] a `x`" "- [ ] a `x`")))
  ;; after a word character a backtick stays alone
  (should (equal (car (tf-ts-mode-test--typed "# todo\n\n- [ ] a" "`"))
                 "# todo\n\n- [ ] a`")))

(ert-deftest tf-ts-mode-test-three-backticks-make-a-block ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] t\n\n  D : x\n\n"
    (tf-ts-mode-test--type "```")
    (should (equal (buffer-string)
                   "# todo\n\n- [ ] t\n\n  D : x\n\n      ```\n          \n      ```"))
    (should (= (current-column) 10))
    (should (equal (buffer-substring (line-beginning-position) (point)) "          "))))

(ert-deftest tf-ts-mode-test-no-pairing-inside-a-block ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] t\n\n  D : x\n\n      ```\n          "
    (tf-ts-mode-test--type "`")
    (should (equal (buffer-string) "# todo\n\n- [ ] t\n\n  D : x\n\n      ```\n          `"))))

(ert-deftest tf-ts-mode-test-ret-in-block-keeps-code-column ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] t\n\n  D : x\n\n      ```\n          code"
    (newline-and-indent)
    (should (= (current-column) 10))))

(ert-deftest tf-ts-mode-test-keys ()
  "The commands live under `C-c C-'; the bare `C-c <letter>' keys are left to the user."
  (with-temp-buffer
    (tf-ts-mode)
    (dolist (b '(("C-c C-t" . tf-ts-mode-new)
                 ("C-c C-h" . tf-ts-mode-priority-up)
                 ("C-c C-l" . tf-ts-mode-priority-down)
                 ("C-c C-v" . tf-ts-mode-advance-task)))
      (should (eq (key-binding (kbd (car b))) (cdr b))))
    (dolist (k '("C-c t" "C-c h" "C-c l"))
      (should-not (key-binding (kbd k))))))

(provide 'tf-ts-mode-test)

;;; tf-ts-mode-test.el ends here
