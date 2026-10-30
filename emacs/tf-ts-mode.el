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
;; A new task gets an id (the unix time); priority 50, type `t' and no tags are implied.  A
;; property marker (`. ', `! ', `; ' or `: ') typed on a header line moves the line to its place:
;; id, priority, type, tags.
;;
;; The mode keeps lines at 100 columns (auto-fill; the 101st column and beyond, trailing spaces and
;; tabs are highlighted),
;; indents with spaces only, and indents a line break to where the paragraph's text starts.
;;
;; Keys (prefix C-c C-):
;;   n / p                 next / previous task
;;   t                     new task in `# todo' from anywhere: below the current task if it is in
;;                         `# todo', else at the top of the section
;;   d                     add a `D :' field (or a new paragraph in the existing one)
;;   m                     add a `C :' field (comment)
;;   s / a                 add a separator below / above the current task
;;   v                     move the task one stage on: backlog, todo, done, cancelled, backlog
;;   u                     run `.tf/update.sh' (after a confirmation)
;;   i                     show the id of the task as an RFC3339 UTC date (eldoc does the same
;;                         with point on the id line)
;;   h / l                 raise / lower the priority of the task by 10 (0 to 100)
;;   C-c SPC / C-c S-SPC   the same (separator below / above)
;;
;; Typing: a backtick pairs with its mate; a third backtick on an empty line makes a fenced block
;; (the fences on their own lines, the code line between them 4 columns deeper).  `inline code'
;; and fenced blocks are highlighted monospace.  In a fenced block the text past column 100 is
;; hidden (shown as an ellipsis) until point enters the block; see `tf-ts-mode-hide-overflow'.
;; Triple backticks in a task title are highlighted as a warning.

;;; Code:

(require 'treesit)
(require 'subr-x)
(require 'cl-lib)
(require 'seq)
(require 'compile)

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
(defface tf-ts-code-face
  '((((background light)) :inherit fixed-pitch :background "grey92" :extend t)
    (((background dark)) :inherit fixed-pitch :background "grey22" :extend t))
  "Face for inline code and fenced blocks: monospace on a subtle background.")
(defcustom tf-ts-mode-hide-overflow t
  "Non-nil: hide the text past the column limit in fenced blocks, except in the block at point."
  :type 'boolean)

(defface tf-ts-bug-face '((t :inherit error :weight bold))
  "Face for the bug task type, the letter `b'.")
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
     (state_split) @font-lock-function-name-face
     (state_done) @success
     (state_cancelled) @shadow)

   :language 'tfmd :feature 'title
   '((task_header (state_open) (title) @tf-ts-title-face)
     (task_header (state_split) (title) @tf-ts-title-face)
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

   :language 'tfmd :feature 'property :override t
   '(((type_value) @tf-ts-bug-face (:match "\\`b\\'" @tf-ts-bug-face)))

   :language 'tfmd :feature 'field
   '((field_label) @font-lock-keyword-face)

   :language 'tfmd :feature 'list
   '((list_marker) @font-lock-builtin-face)

   :language 'tfmd :feature 'code
   '((fence_open) @tf-ts-code-face
     (fence_close) @tf-ts-code-face
     (code_line) @tf-ts-code-face)

   :language 'tfmd :feature 'error
   '((invalid) @font-lock-warning-face
     (stray_property) @font-lock-warning-face))
  "Tree-sitter font-lock rules for `tf-ts-mode'.")

(defvar tf-ts-mode--inline-code-settings
  (treesit-font-lock-rules
   :language 'tfmd :feature 'code :override 'append
   '((inline_code) @tf-ts-code-face))
  "Font-lock rule for `inline code', kept apart: a grammar built before it knew the node would
make the whole query fail.")

(defun tf-ts-mode--font-lock-settings ()
  "Font-lock settings fitting the installed grammar."
  (append tf-ts-mode--font-lock-settings
          (when (treesit-query-valid-p 'tfmd '((inline_code) @x))
            tf-ts-mode--inline-code-settings)))

;;;; Format violations

(defun tf-ts-mode--fontify-code-blocks (limit)
  "Paint every fenced block up to LIMIT with `tf-ts-code-face', whole lines edge to edge.
The band runs from the start of the opening fence's line through the newline after the closing
fence, so indent, blank lines and the line ends carry the background too."
  (let ((beg (point)))
    (dolist (node (treesit-query-capture (treesit-buffer-root-node 'tfmd)
                                         '((code_block) @block) beg limit t))
      (save-excursion
        (goto-char (treesit-node-start node))
        (let ((from (line-beginning-position)))
          ;; the node may end after its last newline, on the next line's start
          (goto-char (max from (1- (treesit-node-end node))))
          (add-face-text-property from (min (point-max) (1+ (line-end-position)))
                                  'tf-ts-code-face t))))
    (goto-char limit)
    nil))

(defun tf-ts-mode--fontify-title-fences (limit)
  "Warn about triple backticks in titles up to LIMIT: a title has no fenced block."
  (let ((beg (point)))
    (dolist (node (treesit-query-capture (treesit-buffer-root-node 'tfmd)
                                         '((title) @t (title_continuation) @t) beg limit t))
      (save-excursion
        (goto-char (treesit-node-start node))
        (while (search-forward "```" (treesit-node-end node) t)
          (add-face-text-property (- (point) 3) (point) 'font-lock-warning-face))))
    (goto-char limit)
    nil))

(defun tf-ts-mode--fontify-overflow (limit)
  "Match text past the column limit before LIMIT, except inside a fenced block."
  (let (found)
    (while (and (not found)
                (re-search-forward (format "^.\\{%d\\}\\(.+\\)$" tf-ts-mode-column-limit)
                                   limit t))
      (let ((face (get-text-property (match-beginning 1) 'face)))
        (unless (memq 'tf-ts-code-face (if (listp face) face (list face)))
          (setq found t))))
    found))

(defun tf-ts-mode--violation-keywords ()
  "Font-lock keywords for the code band and what the format forbids.
The band comes first so the overflow rule can see it: text past the limit, trailing space, tabs."
  `((tf-ts-mode--fontify-code-blocks)
    (tf-ts-mode--fontify-title-fences)
    (tf-ts-mode--fontify-overflow 1 'tf-ts-overflow-face t)
    ("[ \t]+$" 0 'trailing-whitespace t)
    ("\t" 0 'tf-ts-tab-face t)))

;;;; Hidden overflow

(defun tf-ts-mode--clear-folds ()
  "Remove the overlays that hide overflowing text."
  (remove-overlays (point-min) (point-max) 'category 'tf-ts-fold))

(defun tf-ts-mode--update-folds (&optional buffer)
  "Hide the text past the column limit in fenced blocks of BUFFER, except in the block at point."
  (with-current-buffer (or buffer (current-buffer))
    (tf-ts-mode--clear-folds)
    (when (and tf-ts-mode-hide-overflow (treesit-ready-p 'tfmd t))
      (save-excursion
        (dolist (node (treesit-query-capture (treesit-buffer-root-node 'tfmd)
                                             '((code_block) @block) nil nil t))
          (let ((from (treesit-node-start node))
                (to (treesit-node-end node)))
            (unless (and (>= (point) from) (<= (point) to))
              (goto-char from)
              (while (< (point) to)
                (let ((eol (line-end-position)))
                  (move-to-column tf-ts-mode-column-limit)
                  (when (and (= (current-column) tf-ts-mode-column-limit) (< (point) eol))
                    (let ((ov (make-overlay (point) eol nil t)))
                      (overlay-put ov 'category 'tf-ts-fold)
                      (overlay-put ov 'evaporate t)
                      (overlay-put ov 'display (propertize "…" 'face 'tf-ts-code-face)))))
                (forward-line 1)))))))))

(defvar-local tf-ts-mode--fold-timer nil)

(defun tf-ts-mode--schedule-folds ()
  "Refresh the hidden overflow once Emacs is idle, so a command or edit ends before it runs."
  (unless tf-ts-mode--fold-timer
    (setq tf-ts-mode--fold-timer
          (run-with-idle-timer
           0 nil
           (let ((buf (current-buffer)))
             (lambda ()
               (when (buffer-live-p buf)
                 (with-current-buffer buf
                   (setq tf-ts-mode--fold-timer nil)
                   (tf-ts-mode--update-folds)))))))))

;;;; Tree helpers

(defconst tf-ts-mode--containers
  '("source_file" "task_section" "task" "field" "code_block" "separator_line")
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
       ((equal type "fence_open")
        (+ 4 (save-excursion (goto-char (treesit-node-start node)) (current-indentation))))
       ((equal type "code_line")
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
         (in-field (and ptype (member ptype tf-ts-mode--field-types)))
         (in-header (and ptype (member ptype tf-ts-mode--header-types)))
         (code (cl-oddp (tf-ts-mode--fences-above)))
         (text (unless blank
                 (buffer-substring-no-properties (tf-ts-mode--first-char) (line-end-position)))))
    (cond
     ;; inside a fenced block the content is opaque: keep it, a closing fence matches its opener
     (code
      (cond ((and text (string-match-p "\\``\\{3\\}" text)) (tf-ts-mode--opening-fence-indentation))
            (blank (save-excursion
                     (forward-line -1)
                     ;; the line under an opening fence is the code, 4 columns deeper
                     (+ (current-indentation)
                        (if (looking-at tf-ts-mode--fence-regexp) 4 0))))
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
     ((string-match-p "\\``\\{3\\}" text) (if in-field 6 0))
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

(defconst tf-ts-mode--header-regexp "^- \\(\\[[ x-]\\] \\|~~\\[ \\] \\)"
  "Start of a task header line.")

(defun tf-ts-mode--header-at-p (pos)
  "Non-nil if a real task header (not text in a code block) starts at POS."
  (member (treesit-node-type (treesit-node-at pos 'tfmd))
          '("state_open" "state_split" "state_done" "state_cancelled")))

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

(defun tf-ts-mode-new ()
  "Insert a new task into the todo section, wherever point is in the buffer.
On a task of `# todo' the new task goes below it, divided by a separator; anywhere else, at the
top of the section."
  (interactive)
  (let* ((task (tf-ts-mode--task-node))
         (section (and task (treesit-node-parent task))))
    (if (and section
             (equal (treesit-node-type section) "task_section")
             (equal (tf-ts-mode--section-heading section) "# todo"))
        (progn
          (goto-char (tf-ts-mode--last-line-end task))
          (insert "\n\n" tf-ts-mode--separator "\n\n- [ ] ")
          (save-excursion (insert (tf-ts-mode--new-header-lines))))
      (goto-char (+ 6 (atomic-change-group
                        (tf-ts-mode--insert-task-at-top
                         "# todo" (concat "- [ ] " (tf-ts-mode--new-header-lines)))))))))

(defun tf-ts-mode--new-header-lines ()
  "Property lines of a new task: its id (the unix time now); the rest is implied by defaults."
  (format "\n    . %d" (tf-ts-mode--new-id)))

(defun tf-ts-mode--change-priority (delta)
  "Add DELTA to the priority of the current task, within 0 to 100.
A task without a priority line gets one, from the default 50."
  (let* ((task (or (tf-ts-mode--task-node) (user-error "Not in a task")))
         (line (tf-ts-mode--property-line task 1))
         (value (if line
                    (string-to-number (tf-ts-mode--property-value task 1))
                  50))
         (new (max 0 (min 100 (+ value delta)))))
    (atomic-change-group
      (if line
          (progn (goto-char (+ 6 (car line)))
                 (delete-region (point) (cadr line)))
        (goto-char (tf-ts-mode--property-anchor
                    (tf-ts-mode--header-layout (treesit-node-start task) nil) 1))
        (insert "\n    ! "))
      (insert (number-to-string new)))
    (message "Priority %d" new)))

(defun tf-ts-mode-priority-up ()
  "Raise the priority of the current task by 10."
  (interactive)
  (tf-ts-mode--change-priority 10))

(defun tf-ts-mode-priority-down ()
  "Lower the priority of the current task by 10."
  (interactive)
  (tf-ts-mode--change-priority -10))

(defun tf-ts-mode-show-id-date ()
  "Show the id of the current task as an RFC3339 UTC date."
  (interactive)
  (let* ((task (or (tf-ts-mode--task-node) (user-error "Not in a task")))
         (id (tf-ts-mode--property-value task 0)))
    (unless (and id (string-match-p "\\`[0-9]+\\'" id)) (user-error "The task has no id"))
    (message "%s = %s" id (tf-ts-mode--id-date (string-to-number id)))))

(defun tf-ts-mode--eldoc (&rest _)
  "Documentation function: the date of the id at point."
  (when (save-excursion
          (beginning-of-line)
          (looking-at "    \\. \\([0-9]+\\)$"))
    (tf-ts-mode--id-date (string-to-number (match-string 1)))))

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

;;;; Moving tasks between stages

(defun tf-ts-mode--section-heading (section)
  "Text of the heading node of SECTION, a task_section node."
  (treesit-node-text (tf-ts-mode--child section "heading") t))

(defun tf-ts-mode--next-stage (heading state)
  "The stage after the one of a task in section HEADING with STATE, as (HEADING . STATE).
The loop is backlog, todo, done, cancelled (kept in done), back to backlog."
  (cond
   ((equal state "state_split") (user-error "A split epic is closed by tf with its last task"))
   ((equal state "state_cancelled") '("# backlog" . "state_open"))
   ((equal state "state_done") '("# done" . "state_cancelled"))
   ((equal heading "# backlog") '("# todo" . "state_open"))
   ((equal heading "# todo") '("# done" . "state_done"))
   (t (user-error "Cannot advance an open task in %s" heading))))

(defun tf-ts-mode--cut-task (task)
  "Delete TASK with the separator next to it and return its text and last title line end.
The second value is the offset in the text where the title ends."
  (let* ((start (treesit-node-start task))
         (end (tf-ts-mode--last-line-end task))
         (title-end (save-excursion
                      (goto-char (treesit-node-end
                                  (or (car (last (treesit-filter-child
                                                  task (lambda (c) (equal (treesit-node-type c)
                                                                          "title_continuation")))))
                                      (tf-ts-mode--child (tf-ts-mode--child task "task_header")
                                                         "title"))))
                      (skip-chars-backward "\n")
                      (point)))
         (text (buffer-substring-no-properties start end))
         (sep-after (concat "\n+" tf-ts-mode--separator "\n+"))
         (sep-before (concat "^" tf-ts-mode--separator "\n+\\="))
         from to)
    (goto-char end)
    (cond
     ((looking-at sep-after) (setq from start to (match-end 0)))
     ((save-excursion (goto-char start) (re-search-backward sep-before nil t))
      (setq from (save-excursion (goto-char (match-beginning 0))
                                 (skip-chars-backward " \t\n")
                                 (point))
            to end))
     (t (setq from start to (progn (skip-chars-forward "\n") (point)))))
    (delete-region from to)
    ;; a section emptied at the end of the file keeps its heading and one newline
    (when (and (eobp) (not (bobp)))
      (let ((p (point)))
        (skip-chars-backward "\n")
        (delete-region (point) p)
        (insert "\n")))
    (cons text (- title-end start))))

(defun tf-ts-mode--restate (text title-end from to)
  "TEXT of a task with its state changed from the node type FROM to TO.
TITLE-END is the offset where its last title line ends."
  (let ((prefix (if (equal from "state_cancelled") 8 6))
        (rest (substring text title-end)))
    (concat (pcase to
              ("state_open" "- [ ] ")
              ("state_done" "- [x] ")
              (_ "- ~~[ ] "))
            (let ((title (substring text prefix title-end)))
              (if (equal from "state_cancelled") (string-remove-suffix "~~" title) title))
            (if (equal to "state_cancelled") "~~" "")
            rest)))

(defun tf-ts-mode--insert-task-at-top (heading text)
  "Insert TEXT as the first task of the section HEADING, with a separator after it.
Returns the position of TEXT."
  (let* ((section (or (seq-find (lambda (n) (and (equal (treesit-node-type n) "task_section")
                                                 (equal (tf-ts-mode--section-heading n) heading)))
                                (treesit-node-children (treesit-buffer-root-node 'tfmd)))
                      (user-error "No %s section" heading)))
         (has-tasks (treesit-filter-child
                     section (lambda (c)
                               (member (treesit-node-type c) '("task" "separator_line")))))
         (from (treesit-node-end (tf-ts-mode--child section "heading")))
         (to (save-excursion
               (goto-char from)
               (skip-chars-forward " \t\n")
               (point))))
    (delete-region from to)
    (goto-char from)
    (insert "\n\n")
    (prog1 (point)
      (insert text
              (cond (has-tasks (concat "\n\n" tf-ts-mode--separator "\n\n"))
                    ((eobp) "\n")
                    (t "\n\n"))))))

(defun tf-ts-mode-advance-task ()
  "Move the current task one stage on: backlog, todo, done, cancelled, and back to backlog.
The task goes to the top of the next section, and its header changes to match."
  (interactive)
  (let* ((task (or (tf-ts-mode--task-node) (user-error "Not in a task")))
         (section (treesit-node-parent task))
         (state (treesit-node-type
                 (treesit-node-child (tf-ts-mode--child task "task_header") 0))))
    (unless (equal (treesit-node-type section) "task_section") (user-error "Not in a task"))
    (let* ((next (tf-ts-mode--next-stage (tf-ts-mode--section-heading section) state))
           pos)
      (atomic-change-group
        (let ((cut (tf-ts-mode--cut-task task)))
          (setq pos (tf-ts-mode--insert-task-at-top
                     (car next)
                     (tf-ts-mode--restate (car cut) (cdr cut) state (cdr next))))))
      (goto-char pos))))

;;;; Updating tf

(defun tf-ts-mode--after-update (buffer _status)
  "Revert the open tf buffers once the update in BUFFER has finished."
  (when (equal (buffer-name buffer) "*tf update*")
    (remove-hook 'compilation-finish-functions #'tf-ts-mode--after-update)
    (dolist (b (buffer-list))
      (with-current-buffer b
        (when (and (derived-mode-p 'tf-ts-mode) buffer-file-name)
          (if (buffer-modified-p)
              (message "tf: %s has unsaved changes, not reverted" (buffer-name))
            (revert-buffer t t t)))))))

(defun tf-ts-mode-update ()
  "After a confirmation, run `.tf/update.sh' of the project and show its output."
  (interactive)
  (let* ((root (or (locate-dominating-file default-directory ".tf/tasks.tfmd")
                   (user-error "No .tf/tasks.tfmd in this or a parent directory")))
         (script (expand-file-name ".tf/update.sh" root)))
    (unless (file-executable-p script) (user-error "No executable %s" script))
    (when (yes-or-no-p (format "Run %s? " script))
      (let ((default-directory root))
        (add-hook 'compilation-finish-functions #'tf-ts-mode--after-update)
        (compilation-start ".tf/update.sh" nil (lambda (_) "*tf update*"))))))

;;;; Typing helpers

(defconst tf-ts-mode--property-regexp "^    \\([.!;:]\\) "
  "A property line of a task header: id, priority, type or tags.")

(defconst tf-ts-mode--header-end-regexp
  (concat "^\\(?:[ \t]*$\\|  [DC] :\\|#\\|- \\|" (make-string 32 ?-) "\\)")
  "A line that ends the header region of a task: blank, a field, a heading, a task or a separator.")

(defun tf-ts-mode--property-rank (char)
  "Place of the property line with the marker CHAR in the header: id, priority, type, tags."
  (pcase char (?. 0) (?! 1) (?\; 2) (?: 3)))

(defun tf-ts-mode--header-start ()
  "Start of the task header line above the current line, or nil.
Only lines of the header region may lie in between: no blank lines, fields or headings."
  (save-excursion
    (beginning-of-line)
    (catch 'found
      (while (zerop (forward-line -1))
        (cond ((looking-at "^- \\(\\[[ x]\\] \\|~~\\[ \\] \\)") (throw 'found (point)))
              ((looking-at tf-ts-mode--header-end-regexp) (throw 'found nil)))))))

(defun tf-ts-mode--header-layout (start skip)
  "Layout of the header region of the task whose header line starts at START.
Returns (TITLE-END . PROPERTIES): the end of the last title line, and the property lines as
\(RANK BOL EOL) in buffer order.  The line starting at SKIP, if any, is left out."
  (save-excursion
    (goto-char start)
    (let ((title-end (line-end-position)) props)
      (while (and (zerop (forward-line 1))
                  (not (looking-at tf-ts-mode--header-end-regexp)))
        (cond ((eql (point) skip))
              ((looking-at tf-ts-mode--property-regexp)
               (push (list (tf-ts-mode--property-rank (char-after (+ (point) 4)))
                           (point) (line-end-position))
                     props))
              ((null props) (setq title-end (line-end-position)))))
      (cons title-end (nreverse props)))))

(defun tf-ts-mode--property-anchor (layout rank)
  "End of the line after which a property line of RANK goes, given the header LAYOUT."
  (or (car (last (mapcar #'caddr (seq-filter (lambda (p) (< (car p) rank)) (cdr layout)))))
      (car layout)))

(defun tf-ts-mode--snap-property ()
  "Put the line to where its property belongs once its marker is typed.
The header lines go in the order id, priority, type, tags, after the title.  After RET under a
title the cursor sits at the title text, so a marker typed there would read as a wrapped title
line; the line moves after the properties of lower rank (or the title) and is indented to 4.  A
kind the task already has stays where it is, only indented."
  (when (and (eq last-command-event ?\s)
             (string-match "\\`[ \t]*\\([.!;:]\\) \\'"
                           (buffer-substring-no-properties (line-beginning-position) (point))))
    (let* ((char (aref (match-string 1 (buffer-substring-no-properties
                                        (line-beginning-position) (point)))
                       0))
           (rank (tf-ts-mode--property-rank char))
           (bol (line-beginning-position))
           (start (tf-ts-mode--header-start))
           (layout (and start (tf-ts-mode--header-layout start bol))))
      (if (or (null layout)
              (assq rank (cdr layout))
              (= (1+ (tf-ts-mode--property-anchor layout rank)) bol))
          (indent-according-to-mode)
        (let ((anchor (copy-marker (tf-ts-mode--property-anchor layout rank))))
          (delete-region (if (eobp) (1- bol) bol) (if (eobp) (point) (1+ (line-end-position))))
          (goto-char anchor)
          (set-marker anchor nil)
          (insert "\n    " char " "))))))

(defun tf-ts-mode--property-line (task rank)
  "The header line of TASK (a node) with the property of RANK, as (BOL EOL), or nil."
  (cdr (assq rank (cdr (tf-ts-mode--header-layout (treesit-node-start task) nil)))))

(defun tf-ts-mode--property-value (task rank)
  "Text after the marker of the property of RANK in TASK, or nil."
  (when-let* ((line (tf-ts-mode--property-line task rank)))
    (string-trim (buffer-substring-no-properties (+ 6 (car line)) (cadr line)))))

(defun tf-ts-mode--new-id ()
  "A task id for now: the unix time, raised until no task of the buffer has it."
  (let ((id (floor (float-time))))
    (while (save-excursion
             (goto-char (point-min))
             (re-search-forward (format "^    \\. %d$" id) nil t))
      (setq id (1+ id)))
    id))

(defun tf-ts-mode--id-date (id)
  "RFC3339 UTC date of the unix time ID."
  (format-time-string "%Y-%m-%dT%H:%M:%SZ" id t))

;;;; Backticks

(defun tf-ts-mode--electric-backtick ()
  "Help typing code: pair single backticks, make the third one a fenced block.
Nothing happens inside a fenced block.  A backtick typed before whitespace, the end of the line
or closing punctuation, not after a word, inserts its closing mate; typing the closing one
steps over the mate.  A third backtick on a line holding only two backticks turns the line into
a fenced block: the fences on their own lines, the code line between them 4 columns deeper."
  (when (and (eq last-command-event ?`)
             (not (cl-oddp (tf-ts-mode--fences-above))))
    (let* ((before (buffer-substring-no-properties (line-beginning-position) (1- (point))))
           (ticks (cl-count ?` before))
           (next (char-after)))
      (cond
       ((string-match-p "\\`[ \t]*``\\'" before)
        (delete-region (line-beginning-position) (point))
        (insert "```")
        (indent-according-to-mode)
        (let ((column (current-indentation)))
          (end-of-line)
          (insert "\n" (make-string (+ column 4) ?\s) "\n" (make-string column ?\s) "```")
          (forward-line -1)
          (end-of-line)))
       ((and (cl-oddp ticks) (eq next ?`))
        (delete-char -1)
        (forward-char 1))
       ((and (cl-evenp ticks)
             (or (null next) (memq next '(?\s ?\t ?\n ?\) ?\] ?\} ?, ?. ?\; ?: ?! ??)))
             (not (and (> (length before) 0)
                       (eq (char-syntax (aref before (1- (length before)))) ?w))))
        (insert "`")
        (backward-char))))))

;;;; Mode

(defvar-keymap tf-ts-mode-map
  :doc "Keymap for `tf-ts-mode'."
  "C-c C-n" #'tf-ts-mode-next-task
  "C-c C-p" #'tf-ts-mode-previous-task
  "C-c C-t" #'tf-ts-mode-new
  "C-c C-h" #'tf-ts-mode-priority-up
  "C-c C-l" #'tf-ts-mode-priority-down
  "C-c C-d" #'tf-ts-mode-add-description
  "C-c C-m" #'tf-ts-mode-add-comment
  "C-c C-s" #'tf-ts-mode-separator-below
  "C-c C-a" #'tf-ts-mode-separator-above
  "C-c C-v" #'tf-ts-mode-advance-task
  "C-c C-u" #'tf-ts-mode-update
  "C-c C-i" #'tf-ts-mode-show-id-date
  "C-c SPC" #'tf-ts-mode-separator-below
  "C-c S-SPC" #'tf-ts-mode-separator-above)

;;;###autoload
(define-derived-mode tf-ts-mode prog-mode "TF"
  "Major mode for tf task files, using the `tfmd' tree-sitter grammar."
  (unless (treesit-ready-p 'tfmd)
    (error "The tfmd tree-sitter grammar is not available"))
  (treesit-parser-create 'tfmd)
  (setq-local treesit-font-lock-settings (tf-ts-mode--font-lock-settings))
  (setq-local treesit-font-lock-feature-list
              '((heading separator state) (title property field list code) (error)))
  (setq-local treesit-simple-indent-rules tf-ts-mode--indent-rules)
  (setq-local indent-tabs-mode nil)
  (setq-local fill-column tf-ts-mode-column-limit)
  (setq-local normal-auto-fill-function #'tf-ts-mode--auto-fill)
  (setq-local display-fill-column-indicator-column tf-ts-mode-column-limit)
  (treesit-major-mode-setup)
  (font-lock-add-keywords nil (tf-ts-mode--violation-keywords) 'append)
  (add-hook 'eldoc-documentation-functions #'tf-ts-mode--eldoc nil t)
  (add-hook 'post-command-hook #'tf-ts-mode--schedule-folds nil t)
  (add-hook 'change-major-mode-hook #'tf-ts-mode--clear-folds nil t)
  (add-hook 'post-self-insert-hook #'tf-ts-mode--snap-property nil t)
  (add-hook 'post-self-insert-hook #'tf-ts-mode--electric-backtick nil t)
  (auto-fill-mode 1)
  (display-fill-column-indicator-mode 1))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tfmd\\'" . tf-ts-mode))

(provide 'tf-ts-mode)

;;; tf-ts-mode.el ends here
