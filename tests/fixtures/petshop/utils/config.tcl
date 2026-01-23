# Petshop Configuration
# Edge cases: multi-line strings, mixed quoting, line continuations

namespace eval ::petshop::utils::config {
    # Multi-line braced string with special characters
    variable welcome_message {
        Welcome to the Pet Shop!

        We have many animals:
          - Dogs
          - Cats
          - "Exotic" birds

        Open hours: 9am - 6pm
    }

    # Mixed quoting styles
    variable pattern "item_\{.*\}"
    variable message {He said "hello" and she said 'goodbye'}
    variable mixed "value with {braces} inside quotes"

    # Line continuation with backslash
    variable base_price 100
    variable tax 0.08
    variable shipping 5
    variable discount 10

    proc calculate_total {} {
        variable base_price
        variable tax
        variable shipping
        variable discount

        set total [expr {$base_price + \
            ($base_price * $tax) + \
            $shipping - \
            $discount}]
        return $total
    }

    # Dict with mixed content
    variable settings [dict create \
        name "Pet Shop" \
        version "1.0" \
        features {sales inventory reports} \
        paths [dict create \
            data "/var/petshop/data" \
            logs "/var/petshop/logs" \
        ] \
    ]

    proc get {key {default ""}} {
        variable settings
        if {[dict exists $settings $key]} {
            return [dict get $settings $key]
        }
        return $default
    }
}
