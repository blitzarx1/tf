;;; tf-ts-mode.el --- Major mode for tf task files (tree-sitter)  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Dmitrii Samsonov
;; License: MIT
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; Major mode for `.tfmd' files (the tf task list format) built on the `tfmd' tree-sitter grammar
;; from `tree-sitter-tfmd/'.  Install the grammar first:
;;
;;   (add-to-list 'treesit-language-source-alist
;;                '(tfmd "https://github.com/blitzarx1/tf" nil "tree-sitter-tfmd"))
;;   (treesit-install-language-grammar 'tfmd)
;;
;; The mode keeps lines at 100 columns (auto-fill; the 101st column and beyond, trailing spaces and
;; tabs are highlighted),
;; indents with spaces only, and indents a line break to where the paragraph's text starts.
;;
;; Keys (prefix C-c C-):
;;   n / p   next / previous task
;;   t       new task below the current one
;;   d       add a `D :' field (or a new paragraph in the existing one)
;;   m       add a `C :' field (comment)
;;   s / a   add a separator below / above the current task
;;   C-c SPC / C-c S-SPC   the same (separator below / above)

;;; Code:

(require 'treesit)
(require 'subr-x)
(require 'cl-lib)
(require 'seq)

(declare-function treesit-node-at "treesit.c")
(declare-function treesit-node-type "treesit.c")
(declare-function treesit-node-start "treesit.c")
(declare-function treesit-node-end "treesit.c")
(declare-function treesit-node-parent "treesit.c")
(declare-function treesit-node-child "treesit.c")

(defgroup tf-ts nil "Major mode for tf task files." :group 'languages)

(defcustom tf-ts-mode-column-limit 100
  "Column at which lines wrap; everything after it is highlighted."
  :type 'integer)

(defface tf-ts-title-face '((t :inherit bold))
  "Face for task titles.")
(defface tf-ts-overflow-face '((t :inherit whitespace-line))
  "Face for the text after the column limit (the 101st column and beyond).")
(defface tf-ts-tab-face '((t :inherit whitespace-tab))
  "Face for tabs, which the format forbids.")
(defface tf-ts-cancelled-face '((t :inherit shadow :strike-through t))
  "Face for titles of cancelled tasks.")

(defconst tf-ts-mode--separator (make-string 32 ?-)
  "Line that divides tasks.")

;;;; Font lock

(defvar tf-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'tfmd :feature 'heading
   '((heading) @font-lock-keyword-face)

   :language 'tfmd :feature 'separator
   '((separator) @font-lock-comment-delimiter-face)

   :language 'tfmd :feature 'state
   '((state_open) @font-lock-function-name-face
     (state_done) @success
     (state_cancelled) @shadow)

   :language 'tfmd :feature 'title
   '((task_header (state_open) (title) @tf-ts-title-face)
     (task_header (state_done) (title) @tf-ts-title-face)
     (task_header (state_cancelled) (title) @tf-ts-cancelled-face)
     (title_continuation (text) @tf-ts-title-face))

   :language 'tfmd :feature 'property
   '((id_marker) @font-lock-delimiter-face
     (priority_marker) @font-lock-delimiter-face
     (type_marker) @font-lock-delimiter-face
     (tags_marker) @font-lock-delimiter-face
     (id_value) @font-lock-number-face
     (priority_value) @font-lock-number-face
     (type_value) @font-lock-type-face
     (tag) @font-lock-constant-face)

   :language 'tfmd :feature 'field
   '((field_label) @font-lock-keyword-face)

   :language 'tfmd :feature 'list
   '((list_marker) @font-lock-builtin-face
     (entry_marker) @font-lock-builtin-face
     (entry_name) @font-lock-constant-face)

   :language 'tfmd :feature 'code
   '((fence_open) @font-lock-delimiter-face
     (fence_close) @font-lock-delimiter-face
     (code_line) @font-lock-string-face)

   :language 'tfmd :feature 'error
   '((invalid) @font-lock-warning-face))
  "Tree-sitter font-lock rules for `tf-ts-mode'.")

;;;; Format violations

(defun tf-ts-mode--violation-keywords ()
  "Font-lock keywords for what the format forbids: text past the limit, trailing space, tabs."
  `((,(format "^.\\{%d\\}\\(.+\\)$" tf-ts-mode-column-limit) 1 'tf-ts-overflow-face t)
    ("[ \t]+$" 0 'trailing-whitespace t)
    ("\t" 0 'tf-ts-tab-face t)))

;;;; Tree helpers

(defconst tf-ts-mode--containers
  '("source_file" "task_section" "text_section" "task" "field" "code_block" "separator_line")
  "Node types that span several lines; the line-level node is the child below one of them.")

(defconst tf-ts-mode--field-types
  '("field_label" "text_line" "list_item" "fence_open" "fence_close" "code_line")
  "Line kinds that belong to the body of a field.")

(defconst tf-ts-mode--header-types
  '("task_header" "title_continuation" "id" "priority" "type" "tags")
  "Line kinds of a task between its header and its first field.")

(defun tf-ts-mode--blank-line-p ()
  "Non-nil if the current line has only whitespace."
  (save-excursion (beginning-of-line) (looking-at-p "[ \t]*$")))

(defun tf-ts-mode--first-char ()
  "Position of the first non-blank character of the current line."
  (save-excursion (beginning-of-line) (skip-chars-forward " \t") (point)))

(defun tf-ts-mode--line-node ()
  "Line-level node of the current (nonblank) line, or nil."
  (when-let* ((node (treesit-node-at (tf-ts-mode--first-char) 'tfmd)))
    (let ((parent (treesit-node-parent node)))
      (while (and parent (not (member (treesit-node-type parent) tf-ts-mode--containers)))
        (setq node parent
              parent (treesit-node-parent node))))
    node))

(defun tf-ts-mode--child (node type)
  "First child of NODE whose type is TYPE."
  (car (treesit-filter-child node (lambda (c) (equal (treesit-node-type c) type)))))

(defun tf-ts-mode--column-at (pos)
  "Column of buffer position POS."
  (save-excursion (goto-char pos) (current-column)))

(defun tf-ts-mode--text-column (node)
  "Column where the text of the line NODE starts, as a following line should align to it.
Returns nil for NODE nil."
  (when node
    (let ((type (treesit-node-type node)))
      (cond
       ((equal type "task_header")
        (tf-ts-mode--column-at (treesit-node-start (tf-ts-mode--child node "title"))))
       ((member type '("title_continuation" "text_line" "list_item"))
        (tf-ts-mode--column-at (treesit-node-start (tf-ts-mode--child node "text"))))
       ((equal type "field_label") 6)
       ((member type '("id" "priority" "type" "tags")) 2)
       ((member type '("fence_open" "code_line"))
        (save-excursion (goto-char (treesit-node-start node)) (current-indentation)))
       ((equal type "fence_close") 6)
       (t 0)))))

(defun tf-ts-mode--previous-line-node ()
  "Line node of the nearest nonblank line above the current one, with a flag for a gap.
Returns (NODE . GAP) where GAP is non-nil when blank lines lie in between."
  (save-excursion
    (let ((gap nil) node)
      (forward-line -1)
      (while (and (not (bobp)) (tf-ts-mode--blank-line-p))
        (setq gap t)
        (forward-line -1))
      (unless (tf-ts-mode--blank-line-p)
        (setq node (tf-ts-mode--line-node)))
      (cons node gap))))

(defconst tf-ts-mode--fence-regexp "^[ \t]*```"
  "A line that opens or closes a fenced block.")

(defun tf-ts-mode--fences-above ()
  "Number of fence lines above the current line.
An odd number means the current line is inside (or closes) a fenced block.  This is counted on
the text because a block being typed has no closing fence yet and the tree is not reliable."
  (save-excursion
    (beginning-of-line)
    (let ((count 0))
      (while (re-search-backward tf-ts-mode--fence-regexp nil t)
        (setq count (1+ count)))
      count)))

(defun tf-ts-mode--opening-fence-indentation ()
  "Indentation of the nearest fence line above the current line."
  (save-excursion
    (beginning-of-line)
    (when (re-search-backward tf-ts-mode--fence-regexp nil t)
      (current-indentation))))

;;;; Indentation

(defun tf-ts-mode--list-items-above ()
  "List items directly above the current line, nearest first, as (MARKER-COLUMN TEXT-COLUMN).
Stops at the first line that is not part of a list in a field."
  (save-excursion
    (let (items)
      (catch 'done
        (while (and (not (bobp)) (zerop (forward-line -1)))
          (unless (tf-ts-mode--blank-line-p)
            (let* ((node (tf-ts-mode--line-node))
                   (type (and node (treesit-node-type node))))
              (cond ((equal type "list_item")
                     (push (list (current-indentation) (tf-ts-mode--text-column node)) items))
                    ((equal type "text_line"))
                    (t (throw 'done nil)))))))
      (nreverse items))))

(defun tf-ts-mode--indent-column ()
  "Column the current line should be indented to."
  (let* ((blank (tf-ts-mode--blank-line-p))
         (node (unless blank (tf-ts-mode--line-node)))
         (type (and node (treesit-node-type node)))
         (prev (tf-ts-mode--previous-line-node))
         (pnode (car prev))
         (ptype (and pnode (treesit-node-type pnode)))
         (gap (cdr prev))
         (in-field (and ptype (member ptype tf-ts-mode--field-types)
                        ;; a fence at column 0 belongs to a `# tags' / `# commands' section
                        (not (and (member ptype '("fence_open" "fence_close"))
                                  (zerop (save-excursion
                                           (goto-char (treesit-node-start pnode))
                                           (current-indentation)))))))
         (in-header (and ptype (member ptype tf-ts-mode--header-types)))
         (code (cl-oddp (tf-ts-mode--fences-above)))
         (text (unless blank
                 (buffer-substring-no-properties (tf-ts-mode--first-char) (line-end-position)))))
    (cond
     ;; inside a fenced block the content is opaque: keep it, a closing fence matches its opener
     (code
      (cond ((and text (string-match-p "\\``\\{3\\}" text)) (tf-ts-mode--opening-fence-indentation))
            (blank (save-excursion (forward-line -1) (current-indentation)))
            (t (current-indentation))))
     ;; blank line: where the paragraph above puts its text
     (blank
      (cond ((null pnode) 0)
            ((and gap (or in-field in-header)) 6)
            (t (tf-ts-mode--text-column pnode))))
     ((string-match-p "\\`# \\(todo\\|backlog\\|done\\|tags\\|commands\\) *\\'" text) 0)
     ((string-match-p (concat "\\`" tf-ts-mode--separator "\\'") text) 0)
     ((and (string-match-p "\\`- \\(\\[[ x]\\]\\|~~\\[ \\]\\) " text)
           (or (not in-field) (zerop (current-indentation))))
      0)
     ((string-match-p "\\`[DC] :\\( \\|\\'\\)" text) 2)
     ((and in-header (string-match-p "\\`[.!;:] " text)) 4)
     ((string-match-p "\\``\\{3\\}" text) (if in-field 4 0))
     ((string-match-p "\\`\\([*-]\\|[0-9]+\\.\\) " text)
      (if (not in-field)
          0
        ;; a marker goes where an item above has its marker (sibling) or its text (child)
        (let* ((items (tf-ts-mode--list-items-above))
               (valid (cons 6 (apply #'append items)))
               (here (current-indentation)))
          (if (member here valid) here (or (car (car items)) 6)))))
     ;; plain text: continues the paragraph above
     ((null pnode) 0)
     ((and gap (or in-field in-header)) 6)
     ((or in-field in-header) (tf-ts-mode--text-column pnode))
     (t 0))))

(defun tf-ts-mode--indent-offset (_node _parent _bol &rest _)
  "Indentation offset; the anchor is the line start, column 0 (BOL is the indentation start)."
  (tf-ts-mode--indent-column))

(defvar tf-ts-mode--indent-rules
  `((tfmd ((lambda (&rest _) t)
           (lambda (_n _p bol &rest _)
             (save-excursion (goto-char bol) (line-beginning-position)))
           tf-ts-mode--indent-offset)))
  "Indentation rules: one rule that asks `tf-ts-mode--indent-column'.")

;;;; Auto fill

(defun tf-ts-mode--auto-fill ()
  "Wrap the line, giving the next one the indentation of the paragraph's text."
  (let ((node (tf-ts-mode--line-node)))
    (unless (member (and node (treesit-node-type node)) '("code_line" "fence_open" "fence_close"))
      (let ((fill-prefix (make-string (or (tf-ts-mode--text-column node) 0) ?\s))
            (adaptive-fill-mode nil))
        (do-auto-fill)))))

;;;; Navigation and editing commands

(defconst tf-ts-mode--header-regexp "^- \\(\\[[ x]\\] \\|~~\\[ \\] \\)"
  "Start of a task header line.")

(defun tf-ts-mode--header-at-p (pos)
  "Non-nil if a real task header (not text in a code block) starts at POS."
  (member (treesit-node-type (treesit-node-at pos 'tfmd))
          '("state_open" "state_done" "state_cancelled")))

(defun tf-ts-mode-next-task ()
  "Move to the next task header."
  (interactive)
  (let ((start (point)) found)
    (end-of-line)
    (while (and (not found) (re-search-forward tf-ts-mode--header-regexp nil t))
      (when (tf-ts-mode--header-at-p (match-beginning 0))
        (setq found (match-beginning 0))))
    (if found (goto-char found) (goto-char start) (user-error "No next task"))))

(defun tf-ts-mode-previous-task ()
  "Move to the previous task header."
  (interactive)
  (let ((start (point)) found)
    (beginning-of-line)
    (while (and (not found) (re-search-backward tf-ts-mode--header-regexp nil t))
      (when (tf-ts-mode--header-at-p (point))
        (setq found (point))))
    (if found (goto-char found) (goto-char start) (user-error "No previous task"))))

(defun tf-ts-mode--task-node ()
  "The task node at point, or the one just above point (point on a blank line or a separator)."
  (or (treesit-parent-until
       (treesit-node-at (point) 'tfmd)
       (lambda (n) (equal (treesit-node-type n) "task")) t)
      (save-excursion
        (when (re-search-backward tf-ts-mode--header-regexp nil t)
          (treesit-parent-until
           (treesit-node-at (point) 'tfmd)
           (lambda (n) (equal (treesit-node-type n) "task")) t)))))

(defun tf-ts-mode--last-line-end (node)
  "End of the last nonblank line of NODE."
  (save-excursion
    (goto-char (treesit-node-end node))
    (skip-chars-backward " \t\n")
    (point)))

(defun tf-ts-mode--end-of-task ()
  "Position where the current task's text ends, or error."
  (let ((task (or (tf-ts-mode--task-node) (user-error "Not in a task"))))
    (tf-ts-mode--last-line-end task)))

(defun tf-ts-mode-new-task ()
  "Insert a new task below the current one, divided by a separator."
  (interactive)
  (let ((end (tf-ts-mode--end-of-task)))
    (goto-char end)
    (insert "\n\n" tf-ts-mode--separator "\n\n- [ ] ")))

(defun tf-ts-mode--fields (task label)
  "Field nodes of TASK whose label is LABEL (\"D\" or \"C\"), or all fields when nil."
  (seq-filter
   (lambda (f)
     (or (null label)
         (string-match-p (concat "\\`[ ]*" label " :")
                         (treesit-node-text (tf-ts-mode--child f "field_label")))))
   (treesit-filter-child task (lambda (c) (equal (treesit-node-type c) "field")))))

(defun tf-ts-mode-add-description ()
  "Add a `D :' field to the current task, or a new paragraph to the existing one."
  (interactive)
  (let* ((task (or (tf-ts-mode--task-node) (user-error "Not in a task")))
         (existing (car (tf-ts-mode--fields task "D"))))
    (cond
     (existing
      (goto-char (tf-ts-mode--last-line-end existing))
      (insert "\n\n      "))
     ((tf-ts-mode--fields task nil)
      (goto-char (treesit-node-start (car (tf-ts-mode--fields task nil))))
      (insert "  D : \n\n")
      (backward-char 2))
     (t
      (goto-char (tf-ts-mode--last-line-end task))
      (insert "\n\n  D : ")))))

(defun tf-ts-mode-add-comment ()
  "Add a `C :' field after the last field of the current task."
  (interactive)
  (let ((task (or (tf-ts-mode--task-node) (user-error "Not in a task"))))
    (goto-char (tf-ts-mode--last-line-end task))
    (insert "\n\n  C : ")))

(defun tf-ts-mode-separator-below ()
  "Add a separator below the current task."
  (interactive)
  (goto-char (tf-ts-mode--end-of-task))
  (insert "\n\n" tf-ts-mode--separator)
  (unless (or (looking-at-p "\n\n") (looking-at-p "\n?\\'")) (insert "\n"))
  (forward-line 1))

(defun tf-ts-mode-separator-above ()
  "Add a separator above the current task."
  (interactive)
  (let ((task (or (tf-ts-mode--task-node) (user-error "Not in a task"))))
    (goto-char (treesit-node-start task))
    (insert tf-ts-mode--separator "\n\n")
    (forward-line -2)
    (unless (save-excursion (and (not (bobp)) (progn (forward-line -1) (tf-ts-mode--blank-line-p))))
      (insert "\n")
      (forward-line 1))
    (forward-line 2)))

;;;; Mode

(defvar-keymap tf-ts-mode-map
  :doc "Keymap for `tf-ts-mode'."
  "C-c C-n" #'tf-ts-mode-next-task
  "C-c C-p" #'tf-ts-mode-previous-task
  "C-c C-t" #'tf-ts-mode-new-task
  "C-c C-d" #'tf-ts-mode-add-description
  "C-c C-m" #'tf-ts-mode-add-comment
  "C-c C-s" #'tf-ts-mode-separator-below
  "C-c C-a" #'tf-ts-mode-separator-above
  "C-c SPC" #'tf-ts-mode-separator-below
  "C-c S-SPC" #'tf-ts-mode-separator-above)

;;;###autoload
(define-derived-mode tf-ts-mode prog-mode "TF"
  "Major mode for tf task files, using the `tfmd' tree-sitter grammar."
  (unless (treesit-ready-p 'tfmd)
    (error "The tfmd tree-sitter grammar is not available"))
  (treesit-parser-create 'tfmd)
  (setq-local treesit-font-lock-settings tf-ts-mode--font-lock-settings)
  (setq-local treesit-font-lock-feature-list
              '((heading separator state) (title property field list code) (error)))
  (setq-local treesit-simple-indent-rules tf-ts-mode--indent-rules)
  (setq-local indent-tabs-mode nil)
  (setq-local fill-column tf-ts-mode-column-limit)
  (setq-local normal-auto-fill-function #'tf-ts-mode--auto-fill)
  (setq-local display-fill-column-indicator-column tf-ts-mode-column-limit)
  (treesit-major-mode-setup)
  (font-lock-add-keywords nil (tf-ts-mode--violation-keywords) 'append)
  (auto-fill-mode 1)
  (display-fill-column-indicator-mode 1))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tfmd\\'" . tf-ts-mode))

(provide 'tf-ts-mode)

;;; tf-ts-mode.el ends here
