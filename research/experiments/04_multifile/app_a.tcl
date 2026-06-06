# Part A of namespace ::app. Opens the namespace and adds a var + proc.
namespace eval ::app {
    variable version "1.0"

    # OQ5: at namespace-eval TOP LEVEL (not inside a proc), is an unqualified
    # variable name the namespace's own variable?
    set probe "set-at-ns-toplevel"
    puts "OQ5 ns-top unqualified read: version=$version probe=$probe"

    proc hello {} { return "::app::hello" }
}
