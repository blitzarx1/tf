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
    : tag1 tag2

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

(ert-deftest tf-ts-mode-test-agent-field ()
  "An `A :' field is parsed, highlighted and indented like `C :'."
  (let ((text "# done\n\n- [x] one\n\n  A : note\n\n      more\n"))
    (tf-ts-mode-test--with-buffer text
      (font-lock-mode 1)
      (font-lock-ensure)
      (goto-char (point-min))
      (search-forward "  A :")
      (should (tf-ts-mode-test--has-face 'font-lock-keyword-face
                                         (get-text-property (- (point) 2) 'face)))
      (should (= (length (tf-ts-mode--fields (tf-ts-mode--task-node) "A")) 1))
      (indent-region (point-min) (point-max))
      (should (equal (buffer-string) text)))))

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

(ert-deftest tf-ts-mode-test-refs-relative-to-home-folder ()
  (let* ((home (make-temp-file "tfhome" t))
         (file (expand-file-name ".tf/tasks.tfmd" home)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory file))
          (make-directory (expand-file-name "x" home))
          (with-temp-file file (insert "# todo\n"))
          (with-temp-file (expand-file-name "x/y.txt" home) (insert "a\nb\nc\n"))
          (with-temp-buffer
            (insert "# todo\n\n- [ ] t\n    . 1\n\n  R :\n\n      * x/y.txt:3\n")
            (setq buffer-file-name file)
            (tf-ts-mode)
            (let ((xref (car (xref-backend-definitions 'tf-ts-refs "x/y.txt:3"))))
              (should (equal (expand-file-name "x/y.txt" home)
                             (xref-file-location-file (xref-item-location xref))))
              (should (= 3 (xref-file-location-line (xref-item-location xref)))))
            (set-buffer-modified-p nil)))
      (delete-directory home t))))

(ert-deftest tf-ts-mode-test-refs-last-and-jump ()
  (let* ((dir (make-temp-file "tfref" t))
         (file (expand-file-name "tasks.tfmd" dir)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "x.txt" dir) (insert "a\nb\nc\n"))
          (with-temp-buffer
            (insert "# todo\n\n- [ ] t\n    . 1\n\n  D : d\n\n  R :\n\n      * x.txt:2\n")
            (setq buffer-file-name file)
            (tf-ts-mode)
            (should-not (string-match-p "stray\\|bad_ref\\|ERROR"
                                        (treesit-node-string (treesit-buffer-root-node 'tfmd))))
            (goto-char (point-max))
            (forward-line -1)
            (should (equal (tf-ts-mode--ref-at-point) "x.txt:2"))
            (let ((xref (car (xref-backend-definitions 'tf-ts-refs "x.txt:2"))))
              (should (= 2 (xref-file-location-line (xref-item-location xref)))))
            (set-buffer-modified-p nil))
          (with-temp-buffer
            (insert "# todo\n\n- [ ] t\n    . 1\n\n  R :\n\n      * x.txt:2\n\n  D : late\n")
            (tf-ts-mode)
            (should (string-match-p "stray_field"
                                    (treesit-node-string (treesit-buffer-root-node 'tfmd))))))
      (delete-directory dir t))))

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

(ert-deftest tf-ts-mode-test-add-job-instructions ()
  (tf-ts-mode-test--with-buffer
      (concat "# todo\n\n- [ ] one\n    ; j\n\n  D : text\n\n" tf-ts-mode--separator "\n")
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (tf-ts-mode-add-job-instructions)
    (insert "summary")
    (should (equal (buffer-string)
                   (concat "# todo\n\n- [ ] one\n    ; j\n\n  D : text\n\n  J : summary\n\n"
                           "      Parameters:\n\n      * \n\n      Steps:\n\n      1. \n\n"
                           tf-ts-mode--separator "\n")))
    ;; a second call goes to the existing field instead of adding another
    (goto-char (point-min))
    (tf-ts-mode-next-task)
    (tf-ts-mode-add-job-instructions)
    (should (looking-back "J : summary" (line-beginning-position)))))

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

(defun tf-ts-mode-test--epic (heading state subs)
  "Text of an epic with id 1 in HEADING as STATE and subtasks SUBS, a list of (HEADING . STATE)."
  (let ((sections (make-hash-table :test 'equal)) (n 1))
    (puthash heading (list (format "- %s epic\n    . 1\n    ; e\n" state)) sections)
    (dolist (sub subs)
      (setq n (1+ n))
      (puthash (car sub)
               (append (gethash (car sub) sections)
                       (list (format "- %s sub%d\n    . %d\n    : e1\n" (cdr sub) n n)))
               sections))
    (mapconcat (lambda (h)
                 (concat h "\n\n" (mapconcat #'identity (gethash h sections)
                                              (concat "\n" tf-ts-mode-test--sep "\n\n"))))
               '("# todo" "# backlog" "# done") "\n")))

(defun tf-ts-mode-test--headers (text)
  "Lines of TEXT that start a task."
  (seq-filter (lambda (l) (string-prefix-p "- " l)) (split-string text "\n")))

(ert-deftest tf-ts-mode-test-epic-todo-all-todo-to-done ()
  (let ((out (tf-ts-mode-test--advance
              (tf-ts-mode-test--epic "# todo" "[2]" '(("# todo" . "[ ]") ("# todo" . "[ ]")))
              "] epic")))
    (should (equal (tf-ts-mode-test--headers out)
                   '("- [x] epic" "- [x] sub2" "- [x] sub3")))
    (should (string-match-p "\\`# todo\n+# backlog\n+# done\n+- \\[x\\] epic" out))))

(ert-deftest tf-ts-mode-test-epic-backlog-to-todo ()
  (let ((out (tf-ts-mode-test--advance
              (tf-ts-mode-test--epic "# backlog" "[2]" '(("# backlog" . "[ ]") ("# backlog" . "[ ]")))
              "] epic")))
    (should (equal (tf-ts-mode-test--headers out)
                   '("- [2] epic" "- [ ] sub2" "- [ ] sub3")))
    (should (string-prefix-p "# todo\n\n- [2] epic" out))))

(ert-deftest tf-ts-mode-test-epic-todo-mixed-refuses ()
  (let ((text (tf-ts-mode-test--epic "# todo" "[1]" '(("# todo" . "[ ]") ("# done" . "[x]")))))
    (should-error (tf-ts-mode-test--advance text "] epic") :type 'user-error)))

(ert-deftest tf-ts-mode-test-epic-no-open-subtasks-closes-alone ()
  (let ((out (tf-ts-mode-test--advance
              (tf-ts-mode-test--epic "# todo" "[0]" '(("# done" . "[x]")))
              "] epic")))
    (should (equal (tf-ts-mode-test--headers out) '("- [x] epic" "- [x] sub2")))
    (should (string-prefix-p "# todo\n\n# backlog" out))))

(ert-deftest tf-ts-mode-test-epic-done-to-cancelled-and-back ()
  (let ((out (tf-ts-mode-test--advance
              (tf-ts-mode-test--epic "# done" "[x]" '(("# done" . "[x]")))
              "] epic")))
    (should (equal (tf-ts-mode-test--headers out) '("- ~~[ ] epic~~" "- ~~[ ] sub2~~")))
    (let ((back (tf-ts-mode-test--advance out "] epic")))
      (should (equal (tf-ts-mode-test--headers back) '("- [1] epic" "- [ ] sub2")))
      (should (string-match-p "# backlog\n\n- \\[1\\] epic" back)))))

(ert-deftest tf-ts-mode-test-epic-counter-follows-subtask ()
  (let* ((text (tf-ts-mode-test--epic "# todo" "[2]" '(("# todo" . "[ ]") ("# backlog" . "[ ]"))))
         (done (tf-ts-mode-test--advance text "] sub2")))
    (should (member "- [1] epic" (tf-ts-mode-test--headers done)))
    (let ((back (tf-ts-mode-test--advance
                 (concat "# todo\n\n- [0] epic\n    . 1\n    ; e\n\n# backlog\n\n# done\n\n"
                         "- ~~[ ] sub~~\n    . 2\n    : e1\n")
                 "] sub")))
      (should (member "- [1] epic" (tf-ts-mode-test--headers back))))
    (should (member "- [2] epic" (tf-ts-mode-test--headers (tf-ts-mode-test--advance text "] sub3"))))))

(ert-deftest tf-ts-mode-test-epic-last-subtask-keeps-epic-open ()
  (let ((out (tf-ts-mode-test--advance
              (tf-ts-mode-test--epic "# todo" "[1]" '(("# todo" . "[ ]"))) "] sub2")))
    (should (member "- [0] epic" (tf-ts-mode-test--headers out)))
    (should (string-prefix-p "# todo\n\n- [0] epic" out))))

(defun tf-ts-mode-test--split (text marker titles)
  "Split the task of TEXT containing MARKER into TITLES; return the buffer."
  (with-temp-buffer
    (insert text)
    (tf-ts-mode)
    (goto-char (point-min))
    (search-forward marker)
    (tf-ts-mode-split-epic titles)
    (buffer-string)))

(ert-deftest tf-ts-mode-test-split-typed-with-tags ()
  (let ((out (tf-ts-mode-test--split "# todo\n\n- [ ] fix it\n    . 1\n    ; q\n    : ui\n\n  D : why\n"
                                     "] fix" '("first part" "second part"))))
    (should (string-match-p "\\`# todo\n\n- \\[2\\] fix it\n    \\. 1\n    ; e\n    : ui\n\n  D : why\n" out))
    (should (string-match-p
             (concat "  D : why\n\n" tf-ts-mode-test--sep "\n\n- \\[ \\] first part\n    \\. [0-9]+\n"
                     "    : e1 ui\n\n" tf-ts-mode-test--sep "\n\n- \\[ \\] second part\n")
             out))))

(ert-deftest tf-ts-mode-test-split-creates-id-and-type ()
  (let ((out (tf-ts-mode-test--split "# todo\n\n- [ ] plain\n" "] plain" '("a"))))
    (should (string-match-p "\\`# todo\n\n- \\[1\\] plain\n    \\. [0-9]+\n    ; e\n" out))
    (should (string-match-p "    : e[0-9]+\n\\'" out))))

(ert-deftest tf-ts-mode-test-split-existing-epic-adds-to-counter ()
  (let ((out (tf-ts-mode-test--split
              (tf-ts-mode-test--epic "# todo" "[1]" '(("# todo" . "[ ]"))) "] epic" '("x" "y"))))
    (should (member "- [3] epic" (tf-ts-mode-test--headers out)))))

(ert-deftest tf-ts-mode-test-split-refusals ()
  (should-error (tf-ts-mode-test--split "# todo\n\n- [ ] a\n" "] a" nil) :type 'user-error)
  (should-error (tf-ts-mode-test--split "# done\n\n- [x] a\n" "] a" '("b")) :type 'user-error))

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

(ert-deftest tf-ts-mode-test-advance-job-to-jobs ()
  (should (equal (tf-ts-mode-test--advance
                  (concat "# todo\n\n- [ ] one\n    ; j\n\n  J : run it\n\n# done\n\n# jobs\n\n"
                          "- [2] old\n    ; j\n"))
                 (concat "# todo\n\n# done\n\n# jobs\n\n- [1] one\n    ; j\n\n  J : run it\n\n"
                         tf-ts-mode-test--sep "\n\n- [2] old\n    ; j\n"))))

(ert-deftest tf-ts-mode-test-advance-job-in-jobs-refused ()
  (with-temp-buffer
    (insert "# todo\n\n# jobs\n\n- [2] one\n    ; j\n")
    (tf-ts-mode)
    (goto-char (point-max))
    (search-backward "] one")
    (should-error (tf-ts-mode-advance-task) :type 'user-error)))

(ert-deftest tf-ts-mode-test-job-field-indents ()
  (with-temp-buffer
    (insert "# jobs\n\n- [1] one\n    ; j\n\nJ : run it")
    (tf-ts-mode)
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string) "# jobs\n\n- [1] one\n    ; j\n\n  J : run it"))))

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

(defun tf-ts-mode-test--run-update (grammar)
  "Run `tf-ts-mode-update' in a temp project with `tf-ts-mode--grammar-script' returning GRAMMAR.
Return the command it started."
  (let* ((root (tf-ts-mode-test--project t))
         (default-directory (file-name-as-directory root))
         (command nil))
    (unwind-protect
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                  ((symbol-function 'tf-ts-mode--grammar-script) (lambda () grammar))
                  ((symbol-function 'compilation-start)
                   (lambda (c &rest _)
                     (setq command c)
                     (should (equal (file-truename default-directory)
                                    (file-name-as-directory (file-truename root)))))))
          (tf-ts-mode-update)
          command)
      (remove-hook 'compilation-finish-functions #'tf-ts-mode--after-update)
      (delete-directory root t))))

(ert-deftest tf-ts-mode-test-update-confirmed ()
  (should (equal (tf-ts-mode-test--run-update "/x/update-grammar.sh")
                 ".tf/update.sh && /x/update-grammar.sh")))

(ert-deftest tf-ts-mode-test-update-without-grammar-script ()
  (should (equal (tf-ts-mode-test--run-update nil) ".tf/update.sh")))

(defun tf-ts-mode-test--type (string)
  "Type STRING at point as self-inserting keys."
  (dolist (c (string-to-list string))
    (let ((last-command-event c))
      (self-insert-command 1))))

(ert-deftest tf-ts-mode-test-snap-property-marker ()
  (dolist (header '("- [ ] title" "- [x] title" "- ~~[ ] title~~"))
    (dolist (typed '(": emacs" "! 5" ". 17" "; q"))
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
    (should (equal (tf-ts-mode-test--snap (concat head "    . 1\n    ; q\n    : t") "! 5")
                   (concat head "    . 1\n    ! 5\n    ; q\n    : t")))
    (should (equal (tf-ts-mode-test--snap (concat head "    ! 5\n    : t") "; q")
                   (concat head "    ! 5\n    ; q\n    : t")))
    (should (equal (tf-ts-mode-test--snap (concat head "    ! 5\n    ; q") ": t")
                   (concat head "    ! 5\n    ; q\n    : t")))
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

(ert-deftest tf-ts-mode-test-preamble-is-a-comment ()
  (let ((text "a note on top\n\n# done\n\n- [x] one\n    . 1792321201\n"))
    (should (tf-ts-mode-test--has-face 'font-lock-comment-face
                                       (tf-ts-mode-test--face-at text "note")))
    (should-not (tf-ts-mode-test--has-face 'font-lock-warning-face
                                           (tf-ts-mode-test--face-at text "note")))))

(ert-deftest tf-ts-mode-test-unknown-type-is-a-warning ()
  (let ((text "# todo\n\n- [ ] a\n    ; b\n\n- [ ] b\n    ; q\n\n- [ ] c\n    ; e\n"))
    (should (tf-ts-mode-test--has-face 'font-lock-warning-face (tf-ts-mode-test--face-at text "; b")))
    (dolist (ok '("; q" "; e"))
      (should-not (tf-ts-mode-test--has-face 'font-lock-warning-face
                                             (tf-ts-mode-test--face-at text ok))))))

(ert-deftest tf-ts-mode-test-code-block-band ()
  (let ((text (concat "# todo\n\n- [ ] t\n\n  C : x\n\n      ```\n          " (make-string 110 ?y)
                      "\n\n          z\n      ```\nafter\n")))
    (with-temp-buffer
      (insert text)
      (tf-ts-mode)
      (font-lock-ensure)
      (cl-flet ((code-p (pos) (tf-ts-mode-test--has-face
                               'tf-ts-code-face (get-text-property pos 'face))))
        (goto-char (point-min))
        (search-forward "      ```")
        (should (code-p (- (point) 7)))     ; fence indent
        (forward-line 1)
        (should (code-p (line-beginning-position)))
        ;; text past the limit keeps the band, not the overflow face
        (move-to-column 105)
        (should (code-p (point)))
        (should-not (tf-ts-mode-test--has-face 'tf-ts-overflow-face
                                               (get-text-property (point) 'face)))
        (search-forward "      ```")
        (should (code-p (1- (point))))      ; the closing fence
        (forward-line 1)
        (should-not (code-p (point)))))))   ; the line after the block

(defun tf-ts-mode-test--overlays (prop)
  "Overlays of the mode carrying PROP, in buffer order."
  (sort (seq-filter (lambda (o) (and (eq (overlay-get o 'category) 'tf-ts-fold)
                                     (overlay-get o prop)))
                    (overlays-in (point-min) (point-max)))
        (lambda (a b) (< (overlay-start a) (overlay-start b)))))

(defun tf-ts-mode-test--folds ()
  (mapcar (lambda (o) (list (overlay-start o) (overlay-get o 'display)))
          (tf-ts-mode-test--overlays 'display)))

(ert-deftest tf-ts-mode-test-overflow-fold ()
  (let ((text (concat "# todo\n\n- [ ] t\n\n  C : x\n\n      ```\n          short\n          "
                      (make-string 110 ?y) "\n      ```\n\n  D : " (make-string 105 ?z) "\n")))
    (with-temp-buffer
      (insert text)
      (tf-ts-mode)
      (goto-char (point-min))
      (tf-ts-mode--update-folds)
      (let ((folds (tf-ts-mode-test--folds)))
        ;; only the long code line, from column 97 so the `...' ends one cell before the ruler; the long
        ;; field line is not folded
        (should (= (length folds) 1))
        (goto-char (caar folds))
        (should (= (current-column) 97))
        (should (string-match-p "y" (buffer-substring (line-beginning-position) (point))))
        (should (equal (cadr (car folds)) "...")))
      ;; point inside the block reveals it
      (goto-char (point-min))
      (search-forward "short")
      (tf-ts-mode--update-folds)
      (should-not (tf-ts-mode-test--folds)))))

(ert-deftest tf-ts-mode-test-band-flush-with-ruler ()
  (let ((text (concat "# todo\n\n- [ ] t\n\n  C : x\n\n      ```\n          short\n          "
                      (make-string 90 ?e) "\n          " (make-string 110 ?y) "\n      ```\n")))
    (with-temp-buffer
      (insert text)
      (tf-ts-mode)
      (should (= display-fill-column-indicator-column 101))
      (goto-char (point-min))
      (tf-ts-mode--update-folds)
      (let (ends)
        ;; every line of the block ends at column 101: padded to it, or cut so `...' ends there
        (dolist (word '("short" "eeee" "yyyy"))
          (goto-char (point-min))
          (search-forward word)
          (let* ((eol (line-end-position))
                 (fold (seq-find (lambda (o) (stringp (overlay-get o 'display)))
                                 (overlays-in (line-beginning-position) eol)))
                 (pad (seq-find (lambda (o) (overlay-get o 'after-string))
                                (overlays-in eol eol))))
            (when fold                      ; the marker ends one cell before the pad
              (goto-char (overlay-start fold))
              (should (= (+ (current-column) (length (overlay-get fold 'display))) 100)))
            (push (cond (pad (nth 2 (get-text-property
                                     0 'display (overlay-get pad 'after-string)))))
                  ends)))
        (should (equal ends '(101 101 101)))))))

(defconst tf-ts-mode-test--two-blocks
  (concat "# todo\n\n- [ ] t\n\n  C : x\n\n      ```\n          " (make-string 110 ?a)
          "\n          short\n\n      ```\n\n      ```\n          " (make-string 110 ?b)
          "\n      ```\n"))

(ert-deftest tf-ts-mode-test-fold-follows-point ()
  (with-temp-buffer
    (insert tf-ts-mode-test--two-blocks)
    (tf-ts-mode)
    (cl-flet ((folded-p (needle)
                (goto-char (point-min))
                (search-forward needle)
                (end-of-line)
                (seq-some (lambda (o) (and (overlay-get o 'display) (= (overlay-end o) (point))))
                          (overlays-in (point-min) (point-max)))))
      ;; point in the second block: only the first one folds
      (goto-char (point-max))
      (search-backward "bbb")
      (tf-ts-mode--update-folds)
      (should (folded-p "aaa"))
      (should-not (folded-p "bbb"))
      ;; point in the first block: only the second one folds
      (goto-char (point-min))
      (search-forward "short")
      (tf-ts-mode--update-folds)
      (should-not (folded-p "aaa"))
      (should (folded-p "bbb")))))

(ert-deftest tf-ts-mode-test-band-ends-at-column-limit ()
  (with-temp-buffer
    (insert tf-ts-mode-test--two-blocks)
    (tf-ts-mode)
    (goto-char (point-max))
    (search-backward "bbb")                 ; point in the second block
    (tf-ts-mode--update-folds)
    ;; the first block: every line (fences, short, blank, the folded one) is padded up to
    ;; it, the long one is folded instead; the band is not extended to the window edge
    (let ((pads (tf-ts-mode-test--overlays 'after-string)))
      (should (= (length pads) 5))             ; fences, short, blank and the folded line
      (dolist (o pads)
        (should (equal (get-text-property 0 'display (overlay-get o 'after-string))
                       `(space :align-to ,(tf-ts-mode--band-width))))
        (should (< (overlay-start o)
                   (save-excursion (goto-char (point-max)) (search-backward "      ```\n          bbb")
                                   (point))))))
    (should (= (length (tf-ts-mode-test--overlays 'display)) 1))
    ;; the second block, holding point, is shown whole with an extending band
    (let ((bands (tf-ts-mode-test--overlays 'face)))
      (should (= (length bands) 1))
      (should (eq (overlay-get (car bands) 'face) 'tf-ts-code-band-face))
      (should (face-attribute 'tf-ts-code-band-face :extend nil t)))
    (should (eq (face-attribute 'tf-ts-code-face :extend nil t) 'unspecified))
    (should (eq (face-attribute 'tf-ts-code-face :family nil t) 'unspecified))))

(ert-deftest tf-ts-mode-test-title-fence-warning ()
  (let ((text "# todo\n\n- [ ] title ```x``` end\n      wraps ``` too\n\n  D : a ``` b\n"))
    (should (tf-ts-mode-test--has-face 'font-lock-warning-face
                                       (tf-ts-mode-test--face-at text "title ```")))
    (should (tf-ts-mode-test--has-face 'font-lock-warning-face
                                       (tf-ts-mode-test--face-at text "wraps ```")))
    (should-not (tf-ts-mode-test--has-face 'font-lock-warning-face
                                           (tf-ts-mode-test--face-at text "a ```")))))

(ert-deftest tf-ts-mode-test-code-indent ()
  (let ((text (concat "# todo\n\n- [ ] t\n\n  C : x\n\n      ```\n    low\n"
                      "                deep\n          ok\n  ```\n")))
    (with-temp-buffer
      (insert text)
      (tf-ts-mode)
      (font-lock-ensure)
      (cl-flet ((warn-p (word) (goto-char (point-min)) (search-forward word)
                  (tf-ts-mode-test--has-face 'font-lock-warning-face
                                             (get-text-property (1- (point)) 'face))))
        (should (warn-p "low"))
        (should-not (warn-p "deep"))
        (should-not (warn-p "ok"))
        (goto-char (point-min))
        (search-forward "  ```\n" nil t 1)
        (goto-char (point-max))
        (forward-line -1)
        (should (tf-ts-mode-test--has-face 'font-lock-warning-face
                                           (get-text-property (+ (point) 3) 'face))))
      ;; TAB: a short line goes to fence + 4, a deeper one stays, the closing fence aligns
      (goto-char (point-min))
      (search-forward "low")
      (indent-for-tab-command)
      (should (= (current-indentation) 10))
      (search-forward "deep")
      (indent-for-tab-command)
      (should (= (current-indentation) 16))
      (goto-char (point-max))
      (forward-line -1)
      (indent-for-tab-command)
      (should (= (current-indentation) 6)))))

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
                 ("C-c >" . tf-ts-mode-priority-up)
                 ("C-c C-l" . tf-ts-mode-add-link)
                 ("C-c <" . tf-ts-mode-priority-down)
                 ("C-c C-v" . tf-ts-mode-advance-task)))
      (should (eq (key-binding (kbd (car b))) (cdr b))))
    (dolist (k '("C-c t" "C-c h" "C-c l"))
      (should-not (key-binding (kbd k))))))

(ert-deftest tf-ts-mode-test-field-backgrounds ()
  (let ((text (concat "# todo\n\n- [ ] t\n\n  D : dd\n\n  C : cc\n      cont\n\n  A : aa\n\n"
                      "  J : jj\n\n      ```\n          code\n      ```\n")))
    (cl-flet ((has (face word) (tf-ts-mode-test--has-face
                                face (tf-ts-mode-test--face-at text word))))
      ;; the stripe covers the label only: line start up to the `:'
      (should (has 'tf-ts-comment-face "C :"))
      (should (has 'tf-ts-agent-face "A :"))
      (should (has 'tf-ts-job-face "J :"))
      (should-not (has 'tf-ts-comment-face "cc"))
      (should-not (has 'tf-ts-comment-face "cont"))
      (should-not (has 'tf-ts-agent-face "aa"))
      (should-not (has 'tf-ts-job-face "jj"))
      (should-not (has 'tf-ts-comment-face "D :"))
      (should (has 'tf-ts-code-face "code")))
    (with-temp-buffer
      (insert text)
      (tf-ts-mode)
      (font-lock-ensure)
      ;; the indent before the label carries the stripe too
      (goto-char (point-min))
      (search-forward "  C :")
      (should (tf-ts-mode-test--has-face 'tf-ts-comment-face
                                         (get-text-property (- (point) 5) 'face)))
      (tf-ts-mode--update-folds)
      (should-not (seq-filter (lambda (o) (memq (get-text-property 0 'face (overlay-get o 'after-string))
                                                '(tf-ts-comment-face tf-ts-agent-face tf-ts-job-face)))
                              (tf-ts-mode-test--overlays 'after-string))))))

;;;; The `/ :' project path

(ert-deftest tf-ts-mode-test-path-is-highlighted ()
  (let ((text "# todo\n\n- [ ] a\n    . 1\n    / services/api\n"))
    (should (tf-ts-mode-test--has-face 'font-lock-string-face
                                       (tf-ts-mode-test--face-at text "api")))
    (should (tf-ts-mode-test--has-face 'font-lock-delimiter-face
                                       (tf-ts-mode-test--face-at text "    / ")))))

(ert-deftest tf-ts-mode-test-snap-path ()
  (let ((head "# todo\n\n- [ ] title\n"))
    (should (equal (tf-ts-mode-test--snap (concat head "    . 1\n    ! 5\n    : t") "/ a/b")
                   (concat head "    . 1\n    / a/b\n    ! 5\n    : t")))
    (should (equal (tf-ts-mode-test--snap (concat head "    ! 5\n    : t") ". 1")
                   (concat head "    . 1\n    ! 5\n    : t")))
    (should (equal (tf-ts-mode-test--snap (concat head "    / a\n    : t") "! 5")
                   (concat head "    / a\n    ! 5\n    : t")))))

(ert-deftest tf-ts-mode-test-priority-with-path ()
  (let ((head "# todo\n\n- [ ] title\n    . 1\n    / a\n"))
    (tf-ts-mode-test--with-buffer (concat head "    ! 50\n")
      (goto-char (point-min)) (search-forward "title")
      (tf-ts-mode-priority-up)
      (should (equal (buffer-string) (concat head "    ! 60\n"))))
    (tf-ts-mode-test--with-buffer head
      (goto-char (point-min)) (search-forward "title")
      (tf-ts-mode-priority-up)
      (should (equal (buffer-string) (concat head "    ! 60\n"))))))

(ert-deftest tf-ts-mode-test-split-inherits-path ()
  (let ((out (tf-ts-mode-test--split
              "# todo\n\n- [ ] big\n    . 1\n    / svc/api\n    : ui\n" "] big" '("a"))))
    (should (string-match-p "- \\[ \\] a\n    \\. [0-9]+\n    / svc/api\n    : e1 ui\n\\'" out))))

(ert-deftest tf-ts-mode-test-eldoc-path ()
  (tf-ts-mode-test--with-buffer "# todo\n\n- [ ] a\n    . 1\n    / svc/api\n"
    (goto-char (point-min)) (search-forward "svc")
    (should (string-suffix-p "svc/api" (tf-ts-mode--eldoc)))))

;;;; `C-c C-t' in three steps

(defun tf-ts-mode-test--new-interactive (text titles path tags)
  "Run `tf-ts-mode-new' interactively in TEXT answering TITLES, PATH and TAGS; return the buffer.
TITLES is the list of answers to the title question, in order."
  (tf-ts-mode-test--with-buffer text
    (goto-char (point-min))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (pop titles)))
              ((symbol-function 'completing-read) (lambda (&rest _) path))
              ((symbol-function 'completing-read-multiple) (lambda (&rest _) tags)))
      (call-interactively #'tf-ts-mode-new))
    (list (tf-ts-mode-test--no-ids (buffer-string)) (point))))

(ert-deftest tf-ts-mode-test-new-three-steps ()
  (let ((out (tf-ts-mode-test--new-interactive "# todo\n\n- [ ] one\n" '("fix it") "svc/api"
                                               '("ui" "bug"))))
    (should (equal (car out)
                   (concat "# todo\n\n- [ ] fix it\n    . ID\n    / svc/api\n    : ui bug\n\n"
                           tf-ts-mode--separator "\n\n- [ ] one\n")))))

(ert-deftest tf-ts-mode-test-new-blank-path-and-tags ()
  (let ((out (tf-ts-mode-test--new-interactive "# todo\n\n- [ ] one\n" '("fix it") "" nil)))
    (should (equal (car out)
                   (concat "# todo\n\n- [ ] fix it\n    . ID\n\n" tf-ts-mode--separator
                           "\n\n- [ ] one\n")))))

(ert-deftest tf-ts-mode-test-new-blank-title-asks-again ()
  (let ((out (tf-ts-mode-test--new-interactive "# todo\n" '("" "  " "later") "" nil)))
    (should (string-prefix-p "# todo\n\n- [ ] later\n    . ID\n" (car out)))))

(ert-deftest tf-ts-mode-test-new-candidates ()
  (tf-ts-mode-test--with-buffer
      "# todo\n\n- [ ] a\n    . 1\n    / svc/api\n    : ui e1\n\n- [ ] b\n    . 2\n    : ops ui\n"
    (should (equal (tf-ts-mode--known-values 1) '("svc/api")))
    (should (equal (sort (tf-ts-mode--known-values 4) #'string<) '("ops" "ui")))))

(provide 'tf-ts-mode-test)


;;;; Links (`L :')

(defun tf-ts-mode-test--link (text id)
  "TEXT with the link to ID added to its task at point (the end of the text)."
  (tf-ts-mode-test--with-buffer text
    (tf-ts-mode-add-link id)
    (buffer-string)))

(ert-deftest tf-ts-mode-test-add-link-creates-field ()
  (should (equal (tf-ts-mode-test--link "# todo\n\n- [ ] a\n    . 1\n\n  D : d\n" "2")
                 "# todo\n\n- [ ] a\n    . 1\n\n  D : d\n\n  L :\n\n      * 2\n"))
  (should (equal (tf-ts-mode-test--link "# todo\n\n- [ ] a\n    . 1\n" "2")
                 "# todo\n\n- [ ] a\n    . 1\n\n  L :\n\n      * 2\n")))

(ert-deftest tf-ts-mode-test-add-link-goes-before-refs ()
  (let ((out (tf-ts-mode-test--link
              "# done\n\n- [x] a\n    . 1\n\n  R :\n\n      * x.txt:1\n" "2")))
    (should (equal out "# done\n\n- [x] a\n    . 1\n\n  L :\n\n      * 2\n\n  R :\n\n      * x.txt:1\n"))
    (tf-ts-mode-test--with-buffer out
      (should-not (string-match-p "stray\\|bad_ref\\|ERROR"
                                  (treesit-node-string (treesit-buffer-root-node 'tfmd)))))))

(ert-deftest tf-ts-mode-test-add-link-appends-and-refuses-duplicates ()
  (let ((text "# todo\n\n- [ ] a\n    . 1\n\n  L :\n\n      * 2\n"))
    (should (equal (tf-ts-mode-test--link text "3") (concat text "      * 3\n")))
    (should-error (tf-ts-mode-test--link text "2") :type 'user-error)))

(defmacro tf-ts-mode-test--with-tree (&rest body)
  "Run BODY with HOME, a folder with a `.tf' and a child `.tf' below it, and CHILD, the child
`.tf/tasks.tfmd'; the child holds the task 20 `deep task' and HOME the task 10 `top task'."
  (declare (indent 0))
  `(let* ((home (make-temp-file "tftree" t))
          (top (expand-file-name ".tf/tasks.tfmd" home))
          (child (expand-file-name "svc/.tf/tasks.tfmd" home)))
     (unwind-protect
         (progn
           (make-directory (file-name-directory top))
           (make-directory (file-name-directory child) t)
           (with-temp-file top (insert "# todo\n\n- [ ] top task\n    . 10\n"))
           (with-temp-file child (insert "# todo\n\n- [ ] deep task\n    . 20\n"))
           ,@body)
       (delete-directory home t))))

(defun tf-ts-mode-test--xref-lines (file text id)
  "The summaries of the xref items of the link ID, in a buffer visiting FILE with TEXT."
  (with-temp-buffer
    (insert text)
    (setq buffer-file-name file)
    (tf-ts-mode)
    (prog1 (mapcar #'xref-item-summary (xref-backend-definitions 'tf-ts-refs (concat "link:" id)))
      (set-buffer-modified-p nil))))

(ert-deftest tf-ts-mode-test-links-go-down-only ()
  (tf-ts-mode-test--with-tree
    (let ((up "# todo\n\n- [ ] up\n    . 1\n\n  L :\n\n      * 20\n")
          (down "# todo\n\n- [ ] low\n    . 2\n\n  L :\n\n      * 10\n"))
      ;; the upper .tf reaches the lower one
      (should (equal (tf-ts-mode-test--xref-lines top up "20") '("20  deep task")))
      ;; the lower .tf does not reach the upper one
      (let ((err (should-error (tf-ts-mode-test--xref-lines child down "10") :type 'user-error)))
        (should (string-match-p "above" (cadr err))))
      ;; nothing at all
      (should-error (tf-ts-mode-test--xref-lines top up "99") :type 'user-error))))

(ert-deftest tf-ts-mode-test-link-candidates ()
  (tf-ts-mode-test--with-tree
    (with-temp-buffer
      (insert "# todo\n\n- [ ] up\n    . 1\n")
      (setq buffer-file-name top)
      (tf-ts-mode)
      (should (equal (mapcar #'car (tf-ts-mode--linkable-tasks)) '("1" "20"))))
    (with-temp-buffer
      (insert-file-contents child)
      (setq buffer-file-name child)
      (tf-ts-mode)
      (should (equal (mapcar #'car (tf-ts-mode--linkable-tasks)) '("20"))))))

(ert-deftest tf-ts-mode-test-link-eldoc-and-label ()
  (tf-ts-mode-test--with-tree
    (with-temp-buffer
      (insert "# todo\n\n- [ ] up\n    . 1\n\n  L :\n\n      * 20\n")
      (setq buffer-file-name top)
      (tf-ts-mode)
      (goto-char (point-max))
      (forward-line -1)
      (should (equal (tf-ts-mode--link-at-point) "20"))
      (should (string-match-p "\\`deep task  \\[svc" (tf-ts-mode--eldoc)))
      (font-lock-ensure)
      (should (tf-ts-mode-test--has-face 'tf-ts-link-face
                                         (get-text-property (+ (point-min) (length "# todo\n\n- [ ] up\n    . 1\n\n  L")) 'face)))
      (set-buffer-modified-p nil))))

;;; tf-ts-mode-test.el ends here

(defun tf-ts-mode-test--long-block (n)
  "A task with a fenced block of N numbered code lines."
  (concat "# todo\n\n- [ ] t\n\n  C : x\n\n      ```\n"
          (mapconcat (lambda (i) (format "          line%d" i)) (number-sequence 1 n) "\n")
          "\n      ```\n\n  D : after\n"))

(defun tf-ts-mode-test--line-fold (n point-on)
  "Update the folds of a block of N lines with point after POINT-ON; the display strings."
  (with-temp-buffer
    (insert (tf-ts-mode-test--long-block n))
    (tf-ts-mode)
    (goto-char (point-min))
    (search-forward point-on)
    (tf-ts-mode--update-folds)
    (delq nil
          (mapcar (lambda (o)
                    (let ((s (substring-no-properties (overlay-get o 'after-string))))
                      (and (string-match "\\`\\.\\.\\. [0-9]+ more lines?" s) (match-string 0 s))))
                  (tf-ts-mode-test--overlays 'after-string)))))

(ert-deftest tf-ts-mode-test-line-fold ()
  (let ((tf-ts-mode-max-block-lines 10))
    (should (equal (tf-ts-mode-test--line-fold 25 "after") '("... 15 more lines")))
    (should (equal (tf-ts-mode-test--line-fold 11 "after") '("... 1 more line")))
    (should-not (tf-ts-mode-test--line-fold 10 "after"))
    ;; point inside the block: shown whole
    (should-not (tf-ts-mode-test--line-fold 25 "line3"))
    (let ((tf-ts-mode-max-block-lines nil))
      (should-not (tf-ts-mode-test--line-fold 25 "after")))))

(ert-deftest tf-ts-mode-test-line-fold-hides-lines ()
  (with-temp-buffer
    (insert (tf-ts-mode-test--long-block 25))
    (tf-ts-mode)
    (goto-char (point-max))
    (tf-ts-mode--update-folds)
    (let ((hidden (seq-find (lambda (o) (overlay-get o 'invisible))
                            (tf-ts-mode-test--overlays 'invisible))))
      (should hidden)
      (goto-char (overlay-start hidden))
      (should (looking-at "          line11\n"))
      (goto-char (overlay-end hidden))
      (should (looking-at "\n      ```")))))

(ert-deftest tf-ts-mode-test-line-fold-blank-first-hidden-line ()
  "The marker shows although the first hidden line is blank."
  (let ((tf-ts-mode-max-block-lines 2))
    (with-temp-buffer
      (insert "# todo\n\n- [ ] t\n\n  C : x\n\n      ```\n          a\n\n          b\n"
              "\n          c\n      ```\n\n  D : after\n")
      (tf-ts-mode)
      (goto-char (point-max))
      (tf-ts-mode--update-folds)
      (should (equal (seq-filter (lambda (s) (string-prefix-p "..." s))
                                 (mapcar (lambda (o) (substring-no-properties
                                                      (overlay-get o 'after-string)))
                                         (tf-ts-mode-test--overlays 'after-string)))
                     '("... 3 more lines "))))))

(ert-deftest tf-ts-mode-test-folded-block-has-no-indent-warning ()
  "Lines hidden by a fold are not flagged as misindented."
  (with-temp-buffer
    (insert (tf-ts-mode-test--long-block 25))
    (tf-ts-mode)
    (goto-char (point-max))
    (tf-ts-mode--update-folds)
    (font-lock-flush)
    (font-lock-ensure)
    (goto-char (point-min))
    (while (not (eobp))
      (let ((face (get-text-property (line-beginning-position) 'face)))
        (should-not (memq 'font-lock-warning-face (if (listp face) face (list face)))))
      (forward-line 1))))
