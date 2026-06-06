# A FAITHFUL SIMULATION of the Rivet template transform, used to verify the
# SCOPE consequences of how .rvt files are processed. This is NOT Rivet itself
# (Rivet is an Apache C module); it reproduces the documented transform:
#   - literal text          -> output statement
#   - <? code ?>            -> TCL code, inline & verbatim
#   - <?= expr ?>           -> output the value of expr
# and the whole template becomes ONE concatenated TCL script evaluated at the
# top level of the (request) interpreter.

proc emit {s} { append ::__out $s }

# Compile template text into a single TCL script. Literals are stashed in ::L to
# avoid any quoting hazards, then referenced by index.
proc compile_rivet {text} {
    set litidx 0
    set out ""
    while {1} {
        set start [string first "<?" $text]
        if {$start < 0} {
            if {[string length $text] > 0} {
                set ::L($litidx) $text
                append out "emit \$::L($litidx)\n"; incr litidx
            }
            break
        }
        if {$start > 0} {
            set ::L($litidx) [string range $text 0 $start-1]
            append out "emit \$::L($litidx)\n"; incr litidx
        }
        set rest [string range $text $start+2 end]
        set end [string first "?>" $rest]
        if {$end < 0} { error "unterminated <? block" }
        set code [string trim [string range $rest 0 $end-1]]
        set text [string range $rest $end+2 end]
        if {[string index $code 0] eq "="} {
            set expr [string trim [string range $code 1 end]]
            append out "emit \[subst {$expr}\]\n"     ;# <?= ?> outputs the value
        } else {
            append out "$code\n"                       ;# <? ?> verbatim code
        }
    }
    return $out
}

proc render {file} {
    set fh [open $file r]; set text [read $fh]; close $fh
    set script [compile_rivet $text]
    puts "----- generated TCL script -----"
    puts $script
    puts "----- rendered output -----"
    set ::__out ""
    namespace eval :: $script      ;# run at top level, like a request
    return $::__out
}

set here [file dirname [file normalize [info script]]]
puts [render [file join $here sample.rvt]]

puts "\n----- scope checks -----"
puts "render_footer is callable after render -> [render_footer]"
puts "info procs ::render_footer -> [info procs ::render_footer]"
puts "title leaked to global frame? [info exists ::title] (value: [expr {[info exists ::title] ? $::title : {n/a}}])"
