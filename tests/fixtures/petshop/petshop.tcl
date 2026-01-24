# Petshop Main Entry Point
# Edge cases: namespace ensemble, namespace import/export chains

package provide petshop 1.0

# Source all modules in dependency order
set dir [file dirname [info script]]

source [file join $dir utils logging.tcl]
source [file join $dir utils config.tcl]
source [file join $dir services events.tcl]
source [file join $dir models pet.tcl]
source [file join $dir models customer.tcl]
source [file join $dir models inventory.tcl]
source [file join $dir services pricing.tcl]
source [file join $dir services transactions.tcl]

namespace eval ::petshop {
    # Export main subcommands
    namespace export pet customer inventory transaction

    # Create ensemble - maps subcommands to procs
    namespace ensemble create -subcommands {
        pet customer inventory transaction config
    }

    # Re-export from subnamespaces (edge case)
    namespace import ::petshop::models::pet::create
    namespace export create

    # Ensemble subcommand implementations
    proc pet {cmd args} {
        switch $cmd {
            create { return [::petshop::models::pet::create {*}$args] }
            get { return [::petshop::models::pet::get {*}$args] }
            list { return [::petshop::models::pet::list {*}$args] }
            delete { return [::petshop::models::pet::delete {*}$args] }
            default { error "Unknown pet command: $cmd" }
        }
    }

    proc customer {cmd args} {
        switch $cmd {
            create { return [::petshop::models::customer::create {*}$args] }
            get { return [::petshop::models::customer::get {*}$args] }
            charge { return [::petshop::models::customer::charge {*}$args] }
            add_funds { return [::petshop::models::customer::add_funds {*}$args] }
            default { error "Unknown customer command: $cmd" }
        }
    }

    proc inventory {cmd args} {
        switch $cmd {
            add { return [::petshop::models::inventory::add_item {*}$args] }
            get { return [::petshop::models::inventory::get_stock {*}$args] }
            update { return [::petshop::models::inventory::update_stock {*}$args] }
            check { return [::petshop::models::inventory::check_low_stock] }
            value { return [::petshop::models::inventory::get_value] }
            default { error "Unknown inventory command: $cmd" }
        }
    }

    proc transaction {cmd args} {
        switch $cmd {
            purchase { return [::petshop::services::transactions::purchase {*}$args] }
            refund { return [::petshop::services::transactions::refund {*}$args] }
            history { return [::petshop::services::transactions::get_history {*}$args] }
            daily { return [::petshop::services::transactions::get_daily_total {*}$args] }
            default { error "Unknown transaction command: $cmd" }
        }
    }

    proc config {cmd args} {
        switch $cmd {
            get { return [::petshop::utils::config::get {*}$args] }
            default { error "Unknown config command: $cmd" }
        }
    }
}
