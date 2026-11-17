(preamble_line) @comment

(heading) @markup.heading

(separator) @punctuation.delimiter

(state_open) @markup.list.unchecked
(state_split) @markup.list.unchecked
(state_done) @markup.list.checked
(state_cancelled) @comment

(task_header (state_open) (title) @markup.strong)
(task_header (state_split) (title) @markup.strong)
(task_header (state_done) (title) @comment)
(task_header (state_cancelled) (title) @markup.strikethrough)
(title_continuation (text) @markup.strong)

[
  (id_marker)
  (path_marker)
  (priority_marker)
  (type_marker)
  (tags_marker)
] @punctuation.special

(id_value) @number
(path_value) @string.special.path
(priority_value) @number
(type_value) @type
(tag) @tag

(field_label) @keyword
(ref_label) @keyword
(ref) @string.special.path

(list_marker) @markup.list

[
  (fence_open)
  (fence_close)
] @punctuation.delimiter
(code_line) @markup.raw
(inline_code) @markup.raw

(invalid) @error
(stray_property) @error
(stray_field) @error
(bad_ref) @error
