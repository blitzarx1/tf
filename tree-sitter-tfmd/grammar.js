/**
 * @file tfmd grammar for tree-sitter
 * @author Dmitrii Samsonov <blitzar90@gmail.com>
 * @license MIT
 */

/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

// The format is line based: every line starts with a prefix that tells what it is (heading,
// separator, task header, property, field label, list marker, ...). Whitespace is never skipped
// (`extras` is empty), so indentation is part of the tokens and a tab becomes a local ERROR.

export default grammar({
  name: "tfmd",

  extras: $ => [],

  rules: {
    source_file: $ => seq(
      repeat($._blank),
      repeat($.task_section),
    ),

    _blank: $ => "\n",

    // # todo, # backlog, # done
    task_section: $ => seq(
      alias($._task_heading, $.heading), "\n",
      repeat(choice($._blank, $._invalid_line)),
      repeat(choice($.separator_line, $.task)),
    ),

    _task_heading: $ => token(prec(2, /# (todo|backlog|done)/)),

    // Tasks are divided by 32 dashes; the blank lines after it belong to it.
    separator_line: $ => seq($.separator, "\n", repeat(choice($._blank, $._invalid_line))),
    separator: $ => /-{32}/,

    task: $ => seq(
      $.task_header,
      repeat(alias($.text_line, $.title_continuation)),
      optional($.id),
      optional($.priority),
      optional($.type),
      optional($.tags),
      repeat(choice($._blank, $._invalid_line, $.stray_property)),
      repeat($.field),
    ),

    task_header: $ => seq(
      choice($.state_open, $.state_split, $.state_done, $.state_cancelled),
      $.title,
      "\n",
    ),
    state_open: $ => "- [ ] ",
    state_split: $ => /- \[[0-9]+\] /,
    state_done: $ => "- [x] ",
    state_cancelled: $ => "- ~~[ ] ",
    title: $ => $._inline,

    // Optional lines under the header, in this order: id, priority, type, tags. A property line
    // out of order, repeated or after a blank line is a `stray_property`.
    stray_property: $ => seq($.stray_marker, optional($.text), "\n"),
    stray_marker: $ => token(prec(-1, /    [.!;:] /)),
    id: $ => seq($.id_marker, $.id_value, "\n"),
    id_marker: $ => token(prec(1, /    \. /)),
    id_value: $ => /[0-9]+/,
    priority: $ => seq($.priority_marker, $.priority_value, "\n"),
    priority_marker: $ => token(prec(1, /    ! /)),
    priority_value: $ => /[0-9]+/,
    type: $ => seq($.type_marker, $.type_value, "\n"),
    type_marker: $ => token(prec(1, /    ; /)),
    type_value: $ => /[a-z]+/,
    tags: $ => seq($.tags_marker, $.tag, repeat(seq($._tag_separator, $.tag)), "\n"),
    tags_marker: $ => token(prec(1, /    : /)),
    tag: $ => /\S+/,
    _tag_separator: $ => / +/,

    // `  D : text` and `  C : text`, followed by paragraphs, lists and code blocks.
    field: $ => seq(
      $._field_head,
      repeat(choice($._blank, $.list_item, $.text_line, $.code_block, $._invalid_line)),
    ),
    _field_head: $ => seq($.field_label, optional($.field_text), "\n"),
    field_label: $ => /  [DC] : ?/,
    field_text: $ => $._inline,

    // Running text: plain chunks and single-line `inline code`. A lone or unclosed backtick is plain.
    _inline: $ => repeat1(choice($.inline_code, $._plain)),
    inline_code: $ => /`[^`\n]+`/,
    _plain: $ => /[^`\n]+|`/,

    // Lines indented by 4+ spaces inside a field (or under a header, for a wrapped title).
    text_line: $ => seq($._indent, $.text, "\n"),
    list_item: $ => seq($.list_marker, $.text, "\n"),
    _indent: $ => /    [ ]*/,
    list_marker: $ => /    [ ]*([*-]|[0-9]+\.) /,
    text: $ => $._inline,

    // Lines the format forbids: any tab, an indent of exactly 1 or 3 spaces, a line of only
    // spaces. They become a single node so that the rest of the file keeps parsing.
    _invalid_line: $ => seq(choice($.invalid, alias($._blank_spaces, $.invalid)), "\n"),
    _blank_spaces: $ => token(prec(-1, / +/)),
    invalid: $ => token(prec(3, /[^\n]*\t[^\n]*| [^ \n\t][^\n]*|   [^ \n\t][^\n]*/)),

    // Fenced block, content is opaque.
    code_block: $ => seq(
      $.fence_open, "\n",
      repeat(choice($._blank, seq($.code_line, "\n"))),
      $.fence_close, "\n",
    ),
    fence_open: $ => token(prec(4, /[ \t]*```[^\n]*/)),
    fence_close: $ => token(prec(5, /[ \t]*```[ \t]*/)),
    code_line: $ => /[^\n]+/,
  },
});
