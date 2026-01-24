# Petshop Transaction Service
# Edge cases: fully-qualified cross-namespace calls, multi-file dependency chains

namespace eval ::petshop::services::transactions {
    variable transaction_log [list]
    variable next_txn_id 1

    proc purchase {pet_id customer_id} {
        variable transaction_log
        variable next_txn_id

        # Cross-namespace call to pet model
        set pet [::petshop::models::pet::get $pet_id]

        # Cross-namespace call to pricing service
        set price [::petshop::services::pricing::calculate $pet]

        # Cross-namespace call to customer model
        ::petshop::models::customer::charge $customer_id $price
        ::petshop::models::customer::record_purchase $customer_id $pet_id $price

        # Update inventory
        ::petshop::models::inventory::update_stock $pet_id -1

        # Create transaction record
        set txn_id "txn_$next_txn_id"
        incr next_txn_id

        set txn [dict create \
            id $txn_id \
            pet_id $pet_id \
            customer_id $customer_id \
            amount $price \
            type "purchase" \
            timestamp [clock seconds] \
        ]

        lappend transaction_log $txn

        # Emit event (cross-namespace call to events service)
        ::petshop::services::events::emit purchase $pet_id $customer_id $price

        # Log the transaction
        ::petshop::utils::logging::log INFO "Purchase completed: $txn_id"

        return $txn_id
    }

    proc refund {txn_id} {
        variable transaction_log
        variable next_txn_id

        # Find original transaction
        set original {}
        foreach txn $transaction_log {
            if {[dict get $txn id] eq $txn_id} {
                set original $txn
                break
            }
        }

        if {$original eq {}} {
            return -code error "Transaction not found: $txn_id"
        }

        set amount [dict get $original amount]
        set customer_id [dict get $original customer_id]
        set pet_id [dict get $original pet_id]

        # Reverse the charge
        ::petshop::models::customer::add_funds $customer_id $amount

        # Restore inventory
        ::petshop::models::inventory::update_stock $pet_id 1

        # Create refund record
        set refund_id "txn_$next_txn_id"
        incr next_txn_id

        set refund [dict create \
            id $refund_id \
            original_txn $txn_id \
            pet_id $pet_id \
            customer_id $customer_id \
            amount [expr {-1 * $amount}] \
            type "refund" \
            timestamp [clock seconds] \
        ]

        lappend transaction_log $refund

        ::petshop::services::events::emit refund $txn_id $customer_id $amount
        ::petshop::utils::logging::log INFO "Refund processed: $refund_id for $txn_id"

        return $refund_id
    }

    proc get_history {{customer_id ""}} {
        variable transaction_log

        if {$customer_id eq ""} {
            return $transaction_log
        }

        set result [list]
        foreach txn $transaction_log {
            if {[dict get $txn customer_id] eq $customer_id} {
                lappend result $txn
            }
        }
        return $result
    }

    proc get_daily_total {{date ""}} {
        variable transaction_log

        if {$date eq ""} {
            set date [clock format [clock seconds] -format {%Y-%m-%d}]
        }

        set total 0.0
        foreach txn $transaction_log {
            set txn_date [clock format [dict get $txn timestamp] -format {%Y-%m-%d}]
            if {$txn_date eq $date} {
                set total [expr {$total + [dict get $txn amount]}]
            }
        }
        return $total
    }
}
