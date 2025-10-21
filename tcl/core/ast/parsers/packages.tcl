#!/usr/bin/env tclsh
# tcl/core/ast/parsers/packages.tcl
# Package Parsing Module
#
# UPDATED: Uses delimiter helper to keep version as STRING (fixes 8.6 → 8.5999... issue)

namespace eval ::ast::parsers::packages {
    namespace export parse_package parse_source
}

# Parse a package command
#
# Syntax: package require pkgName [version]
#         package provide pkgName version
#
# ⭐ FIX: Version stays as STRING not converted to float
#
# Args:
#   cmd_text   - The package command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict for the package operation
#
proc ::ast::parsers::packages::parse_package {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid package command" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    set subcommand_token [::tokenizer::get_token $cmd_text 1]
    set subcommand [::ast::delimiters::strip_outer $subcommand_token]

    set package_name ""
    set version ""

    if {$word_count >= 3} {
        set package_name_token [::tokenizer::get_token $cmd_text 2]
        set package_name [::ast::delimiters::strip_outer $package_name_token]
    }

    if {$word_count >= 4} {
        set version_token [::tokenizer::get_token $cmd_text 3]
        # ⭐ FIX: Keep version as STRING
        # normalize will strip delimiters but keep it as string
        set version [::ast::delimiters::normalize $version_token]

        # ⭐ FIX: Force to stay as string, prevent float conversion
        set version "$version"
    }

    # Determine type based on subcommand
    set node_type "package"
    if {$subcommand eq "require"} {
        set node_type "package_require"
    } elseif {$subcommand eq "provide"} {
        set node_type "package_provide"
    }

    return [dict create \
        type $node_type \
        package_name $package_name \
        version $version \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse a source command
#
# Syntax: source filepath
#
# Args:
#   cmd_text   - The source command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict for the source command
#
proc ::ast::parsers::packages::parse_source {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid source command" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    set filepath_token [::tokenizer::get_token $cmd_text 1]
    set filepath [::ast::delimiters::normalize $filepath_token]

    return [dict create \
        type "source" \
        filepath $filepath \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
