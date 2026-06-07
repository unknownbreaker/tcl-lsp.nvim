# Does TCL discount backslash-quoted braces when finding the matching close brace?
# Reviewer claim (I1): inside {...}, \} still closes the brace (backslash ignored
# for depth). Spec claim: a backslash before a brace means it is NOT counted.
# Settle it empirically.

# Case 1: {\}}  -> if backslash discounts the brace, word content is "\}" (len 2)
set a {\}}
puts "case1 len=[string length $a] val=>$a<"

# Case 2: {a\}b} -> content "a\}b" (len 4) if backslash discounts
set b {a\}b}
puts "case2 len=[string length $b] val=>$b<"

# Case 3: {x{y}z} -> normal nesting, content "x{y}z" (len 5)
set c {x{y}z}
puts "case3 len=[string length $c] val=>$c<"
