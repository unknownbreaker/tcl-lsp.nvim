# Petshop Inventory Model
# Edge cases: variable traces, dynamic variable declarations, set $varname indirection

namespace eval ::petshop::models::inventory {
    variable stock [dict create]
    variable low_stock_threshold 5

    # Dynamic variable for each item's stock
    # These get created on demand: stock_item1, stock_item2, etc.

    proc add_item {item_id quantity {price 0}} {
        variable stock

        # Dynamic variable declaration (edge case)
        variable stock_$item_id
        set stock_$item_id $quantity

        dict set stock $item_id [dict create \
            quantity $quantity \
            price $price \
            last_updated [clock seconds] \
        ]

        return $item_id
    }

    proc get_stock {item_id} {
        variable stock

        # Dynamic variable access via set $varname (edge case)
        set varname "stock_$item_id"
        if {[info exists [namespace current]::$varname]} {
            return [set [namespace current]::$varname]
        }

        if {[dict exists $stock $item_id]} {
            return [dict get $stock $item_id quantity]
        }
        return 0
    }

    proc update_stock {item_id delta} {
        variable stock

        if {![dict exists $stock $item_id]} {
            return -code error "Item not found: $item_id"
        }

        set item [dict get $stock $item_id]
        set new_qty [expr {[dict get $item quantity] + $delta}]

        if {$new_qty < 0} {
            return -code error "Insufficient stock for $item_id"
        }

        dict set item quantity $new_qty
        dict set item last_updated [clock seconds]
        dict set stock $item_id $item

        # Update dynamic variable too
        set varname "stock_$item_id"
        set [namespace current]::$varname $new_qty

        return $new_qty
    }

    # Track variable with trace (edge case)
    proc track {varname} {
        upvar 1 $varname v
        trace add variable v write [list ::petshop::services::events::on_change $varname]
    }

    # Untrack variable
    proc untrack {varname} {
        upvar 1 $varname v
        trace remove variable v write [list ::petshop::services::events::on_change $varname]
    }

    proc check_low_stock {} {
        variable stock
        variable low_stock_threshold

        set low_items [list]
        dict for {item_id item} $stock {
            if {[dict get $item quantity] <= $low_stock_threshold} {
                lappend low_items $item_id
            }
        }
        return $low_items
    }

    proc get_value {} {
        variable stock
        set total 0.0

        dict for {item_id item} $stock {
            set qty [dict get $item quantity]
            set price [dict get $item price]
            set total [expr {$total + ($qty * $price)}]
        }
        return $total
    }

    # Bulk update using dynamic variable names
    proc bulk_set {updates} {
        foreach {item_id quantity} $updates {
            variable stock_$item_id
            set stock_$item_id $quantity
        }
    }
}
