# Petshop Pricing Service
# Edge cases: deeply nested expressions, ternary operator, subst, dynamic eval

namespace eval ::petshop::services::pricing {
    variable tax_rate 0.08
    variable large_pet_fee 25.00
    variable loyalty_discount_rate 0.05
    variable currency_symbol "$"

    proc tax_rate {} {
        variable tax_rate
        return $tax_rate
    }

    proc large_pet_fee {} {
        variable large_pet_fee
        return $large_pet_fee
    }

    # Deeply nested expression with ternary (edge case)
    proc calculate {pet} {
        variable tax_rate
        variable large_pet_fee
        variable loyalty_discount_rate

        set base_price [dict get $pet price]
        set weight [expr {[dict exists $pet weight] ? [dict get $pet weight] : 5}]

        # Complex nested expression with ternary operators
        set total [expr {
            ($base_price * (1.0 + $tax_rate))
            + ($weight > 10 ? $large_pet_fee : 0)
            - ($base_price * $loyalty_discount_rate)
        }]

        return [::format "%.2f" $total]
    }

    proc calculate_cart {items} {
        set subtotal 0.0

        foreach item $items {
            set subtotal [expr {$subtotal + [calculate $item]}]
        }

        return [::format "%.2f" $subtotal]
    }

    # Dynamic calculation with subst (edge case)
    proc dynamic_calc {formula vars} {
        # Set each variable in current scope
        dict for {k v} $vars {
            set $k $v
        }

        # subst then expr - dangerous but valid edge case
        expr [subst $formula]
    }

    # Format price for display
    proc format {amount} {
        variable currency_symbol
        return "${currency_symbol}[::tcl::mathfunc::double $amount]"
    }

    # Apply discount code
    proc apply_discount {amount code} {
        set discounts [dict create \
            SAVE10 0.10 \
            SAVE20 0.20 \
            VIP 0.25 \
        ]

        if {[dict exists $discounts $code]} {
            set rate [dict get $discounts $code]
            return [expr {$amount * (1 - $rate)}]
        }
        return $amount
    }

    # Loyalty discount based on purchase history
    proc loyalty_discount {customer_id} {
        variable loyalty_discount_rate

        # Would normally look up customer purchases
        # For now, return flat discount
        return $loyalty_discount_rate
    }

    # Bulk pricing calculation using eval (edge case)
    proc bulk_price {items_expr} {
        set result [list]
        foreach item [eval $items_expr] {
            lappend result [calculate $item]
        }
        return $result
    }
}
