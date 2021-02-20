; highlights.scm (modification of 'highlights.scm' from
; https://github.com/r-lib/tree-sitter-r)

(call (identifier) @function)

; Literals

(integer) @number

(float) @number

(string) @string

(comment) @comment

(formal_parameters (identifier) @variable.parameter)

(identifier) @variable

; Operators
[
 "="
 "<-"
 "<<-"
 "->"
] @operator

(unary operator: [
  "-"
  "+"
  "!"
  "~"
] @operator)

(binary operator: [
  "-"
  "+"
  "*"
  "/"
  "^"
  "<"
  ">"
  "<="
  ">="
  "=="
  "!="
  "||"
  "|"
  "&&"
  "&"
  ":"
  "~"
] @operator)

(special) @operator

[
 "("
 ")"
 "["
 "]"
 "{"
 "}"
] @punctuation.bracket

[
 "while"
 "if"
 "else"
 "function"
 "repeat"
 "for"
 "in"
 (dots)
 (true)
 (false)
 (break)
 (next)
 (inf)
 (nan)
 (na)
 (null)
] @keyword
