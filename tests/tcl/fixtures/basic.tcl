# Basic fixture for schema validation
# Tests fundamental AST node types

# Variable assignment
set x "hello"
set y 42

# Procedure definition
proc greet {name} {
    puts "Hello, $name!"
}

# Control flow
if {$y > 0} {
    puts "positive"
} else {
    puts "not positive"
}

# Loop
foreach item {a b c} {
    puts $item
}
