# Petshop Customer Model
# Edge cases: upvar at levels 1 and 2, uplevel with script execution

namespace eval ::petshop::models::customer {
    variable all_customers [dict create]
    variable next_id 1

    proc create {name email} {
        variable all_customers
        variable next_id

        set id "cust_$next_id"
        incr next_id

        set customer [dict create \
            id $id \
            name $name \
            email $email \
            balance 0.0 \
            purchases [list] \
            created [clock seconds] \
        ]

        dict set all_customers $id $customer
        return $id
    }

    proc get {id} {
        variable all_customers
        if {![dict exists $all_customers $id]} {
            return -code error "Customer not found: $id"
        }
        return [dict get $all_customers $id]
    }

    # upvar at level 1 - standard pattern
    proc with_customer {id varname body} {
        variable all_customers
        upvar 1 $varname customer

        if {![dict exists $all_customers $id]} {
            return -code error "Customer not found: $id"
        }

        set customer [dict get $all_customers $id]
        set result [uplevel 1 $body]

        # Save back any changes
        dict set all_customers $id $customer
        return $result
    }

    # upvar at level 2 - skip a frame (edge case)
    proc with_transaction {customer_id varname body} {
        upvar 2 $varname txn
        upvar 2 transaction_log log

        set txn [dict create \
            customer_id $customer_id \
            started [clock seconds] \
            items [list] \
            total 0.0 \
        ]

        # Execute body in caller's context
        set result [uplevel 1 $body]

        # Log transaction if log exists in caller's caller
        if {[info exists log]} {
            lappend log $txn
        }

        return $result
    }

    # uplevel execution - run script in caller's context
    proc in_context {id script} {
        variable all_customers
        if {![dict exists $all_customers $id]} {
            return -code error "Customer not found: $id"
        }

        # Set customer data in caller's scope then run script
        uplevel 1 [list set _customer_data [dict get $all_customers $id]]
        uplevel 1 $script
    }

    proc charge {id amount} {
        variable all_customers
        if {![dict exists $all_customers $id]} {
            return -code error "Customer not found: $id"
        }

        set customer [dict get $all_customers $id]
        set new_balance [expr {[dict get $customer balance] - $amount}]
        dict set customer balance $new_balance
        dict set all_customers $id $customer

        return $new_balance
    }

    proc add_funds {id amount} {
        variable all_customers
        if {![dict exists $all_customers $id]} {
            return -code error "Customer not found: $id"
        }

        set customer [dict get $all_customers $id]
        set new_balance [expr {[dict get $customer balance] + $amount}]
        dict set customer balance $new_balance
        dict set all_customers $id $customer

        return $new_balance
    }

    proc record_purchase {id pet_id amount} {
        variable all_customers
        set customer [dict get $all_customers $id]

        set purchase [dict create \
            pet_id $pet_id \
            amount $amount \
            timestamp [clock seconds] \
        ]

        dict lappend customer purchases $purchase
        dict set all_customers $id $customer
    }
}
