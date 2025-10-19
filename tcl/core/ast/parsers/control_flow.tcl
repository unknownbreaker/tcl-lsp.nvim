#!/usr/bin/env tclsh
# tcl/core/ast/parsers/control_flow.tcl
# Control Flow Structures Parser

namespace eval ::ast::parsers {
    # Exports: parse_if, parse_while, parse_for, parse_foreach, parse_switch
}

proc ::ast::parsers::parse_if {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 3} {
        return [dict create type "error" message "Invalid if syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set condition [::tokenizer::get_token $cmd_text 1]
    set then_body [::tokenizer::get_token $cmd_text 2]
    set if_node [dict create type "if" condition $condition then_body $then_body \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
    
    # Parse elseif and else clauses
    set elseif_branches [list]
    set else_body ""
    set has_else 0
    set idx 3
    while {$idx < $word_count} {
        set keyword [::tokenizer::get_token $cmd_text $idx]
        if {$keyword eq "elseif"} {
            if {$idx + 2 >= $word_count} { break }
            set elseif_cond [::tokenizer::get_token $cmd_text [expr {$idx + 1}]]
            set elseif_body [::tokenizer::get_token $cmd_text [expr {$idx + 2}]]
            lappend elseif_branches [dict create condition $elseif_cond body $elseif_body]
            set idx [expr {$idx + 3}]
        } elseif {$keyword eq "else"} {
            if {$idx + 1 >= $word_count} { break }
            set else_body [::tokenizer::get_token $cmd_text [expr {$idx + 1}]]
            set has_else 1
            break
        } else {
            break
        }
    }
    if {[llength $elseif_branches] > 0} {
        dict set if_node elseif_branches $elseif_branches
    }
    if {$has_else} {
        dict set if_node else_body $else_body
    }
    return $if_node
}

proc ::ast::parsers::parse_while {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 3} {
        return [dict create type "error" message "Invalid while syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set condition [::tokenizer::get_token $cmd_text 1]
    set body [::tokenizer::get_token $cmd_text 2]
    return [dict create type "while" condition $condition body $body \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
}

proc ::ast::parsers::parse_for {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 5} {
        return [dict create type "error" message "Invalid for syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set init [::tokenizer::get_token $cmd_text 1]
    set condition [::tokenizer::get_token $cmd_text 2]
    set increment [::tokenizer::get_token $cmd_text 3]
    set body [::tokenizer::get_token $cmd_text 4]
    return [dict create type "for" init $init condition $condition \
        increment $increment body $body range [::ast::utils::make_range $start_line 1 $end_line 50]]
}

proc ::ast::parsers::parse_foreach {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 4} {
        return [dict create type "error" message "Invalid foreach syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set var_name [::tokenizer::get_token $cmd_text 1]
    set list_var [::tokenizer::get_token $cmd_text 2]
    set body [::tokenizer::get_token $cmd_text 3]
    return [dict create type "foreach" var_name $var_name list $list_var body $body \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
}

proc ::ast::parsers::parse_switch {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 3} {
        return [dict create type "error" message "Invalid switch syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set value [::tokenizer::get_token $cmd_text 1]
    set switch_body_raw [::tokenizer::get_token $cmd_text end]
    if {[string index $switch_body_raw 0] eq "\{" && [string index $switch_body_raw end] eq "\}"} {
        set switch_body [string range $switch_body_raw 1 end-1]
    } else {
        set switch_body $switch_body_raw
    }
    set cases [list]
    set case_count [llength $switch_body]
    for {set i 0} {$i < $case_count} {incr i 2} {
        set pattern [lindex $switch_body $i]
        set body ""
        if {$i + 1 < $case_count} {
            set body [lindex $switch_body [expr {$i + 1}]]
        }
        lappend cases [dict create pattern $pattern body $body]
    }
    return [dict create type "switch" value $value cases $cases \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
}
