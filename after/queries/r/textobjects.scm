; Queries for R tree-sitter textobjects
(left_assignment (identifier) (function_definition (formal_parameters) (_) @function.inner )) @function.outer
(equals_assignment (identifier) (function_definition (formal_parameters) (_) @function.inner )) @function.outer
(super_assignment (identifier) (function_definition (formal_parameters) (_) @function.inner )) @function.outer

(binary (_) (_) @op (#eq? @op "%>%")) @pipe
