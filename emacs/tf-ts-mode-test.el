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

    ```markdown
    - [ ] example
        ! 100
    ```

--------------------------------

- ~~[ ] cancelled title
        wraps~~

# tags

- md text
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
  (should (= 7 (tf-ts-mode-test--column-after-ret "# todo\n\n- [ ] t\n\n  D : x\n\n    1. step")))
  (should (= 6 (tf-ts-mode-test--column-after-ret "# todo\n\n- [ ] t\n\n  D : x\n\n    * item")))
  (should (= 9 (tf-ts-mode-test--column-after-ret
                "# todo\n\n- [ ] t\n\n  D : x\n\n    1. a\n       * nested")))
  (should (= 2 (tf-ts-mode-test--column-after-ret "# todo\n\n- [ ] t\n    ! 5")))
  (should (= 4 (tf-ts-mode-test--column-after-ret
                "# todo\n\n- [ ] t\n\n  D : x\n\n    ```\n    code"))))

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

(ert-deftest tf-ts-mode-test-text-after-column-zero-fence ()
  (let ((text "# commands\n\n```\n- `tf x`\n```\n\nText after the template.\n"))
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
    (should (equal (buffer-substring (line-beginning-position) (point)) "    * item"))))

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

(ert-deftest tf-ts-mode-test-new-task ()
  (tf-ts-mode-test--with-buffer
      (concat "# todo\n\n- [ ] one\n\n" tf-ts-mode--separator "\n\n- [ ] two\n")
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (tf-ts-mode-new-task)
    (insert "new")
    (should (equal (buffer-string)
                   (concat "# todo\n\n- [ ] one\n\n" tf-ts-mode--separator
                           "\n\n- [ ] new\n\n" tf-ts-mode--separator "\n\n- [ ] two\n")))))

(ert-deftest tf-ts-mode-test-new-task-last ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] one\n\n  D : text\n"
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (tf-ts-mode-new-task)
    (should (equal (buffer-string)
                   (concat "# todo\n\n- [ ] one\n\n  D : text\n\n" tf-ts-mode--separator
                           "\n\n- [ ] \n")))
    (should (looking-at "\n\\'"))))

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

(provide 'tf-ts-mode-test)

;;; tf-ts-mode-test.el ends here
