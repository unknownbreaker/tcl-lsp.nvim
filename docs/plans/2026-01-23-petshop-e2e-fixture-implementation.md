# Petshop E2E Test Fixture Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a multi-file TCL test corpus to stress-test LSP edge cases.

**Architecture:** Package-structured TCL application with deliberate edge cases in symbol resolution, cross-file navigation, parser resilience, and RVT templates.

**Tech Stack:** TCL 8.6, RVT (Rivet templates)

---

## Task 1: Create Directory Structure

**Files:**
- Create: `tests/fixtures/petshop/` and subdirectories

**Step 1: Create all directories**

```bash
mkdir -p tests/fixtures/petshop/{models,services,utils,views/pets,views/partials}
```

**Step 2: Verify structure**

Run: `find tests/fixtures/petshop -type d | sort`

Expected:
```
tests/fixtures/petshop
tests/fixtures/petshop/models
tests/fixtures/petshop/services
tests/fixtures/petshop/utils
tests/fixtures/petshop/views
tests/fixtures/petshop/views/partials
tests/fixtures/petshop/views/pets
```

**Step 3: Commit**

```bash
git add tests/fixtures/petshop
git commit -m "chore: create petshop e2e fixture directory structure"
```

---

## Task 2: Create utils/logging.tcl (Foundation - No Dependencies)

**Files:**
- Create: `tests/fixtures/petshop/utils/logging.tcl`

**Step 1: Write the file**

```tcl
# Petshop Logging Utility
# Edge cases: format strings, escapes, embedded expressions

namespace eval ::petshop::utils::logging {
    variable log_level "INFO"
    variable log_file ""

    # Format strings with % symbols
    proc log {level msg args} {
        variable log_level
        set fmt "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] \[%s\] %s"
        set formatted [format $fmt $level $msg]

        # Embedded expression in string
        if {[llength $args] > 0} {
            append formatted " | args=[llength $args]"
        }

        puts $formatted
        return $formatted
    }

    # Escape sequences
    proc format_table {headers rows} {
        set sep "col1\tcol2\tcol3"
        set path "C:\\pets\\data\\log.txt"

        # Nested expression in string
        set summary "Total: [expr {[llength $rows]}] rows"
        return $summary
    }

    # Proc with default args and special characters
    proc debug {msg {context ""}} {
        if {$context ne ""} {
            log DEBUG "$msg (ctx: $context)"
        } else {
            log DEBUG $msg
        }
    }
}
```

**Step 2: Verify syntax**

Run: `tclsh -c 'source tests/fixtures/petshop/utils/logging.tcl; puts OK'`

Expected: `OK`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/utils/logging.tcl
git commit -m "feat(petshop): add logging utility with format string edge cases"
```

---

## Task 3: Create utils/config.tcl

**Files:**
- Create: `tests/fixtures/petshop/utils/config.tcl`

**Step 1: Write the file**

```tcl
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
```

**Step 2: Verify syntax**

Run: `tclsh -c 'source tests/fixtures/petshop/utils/config.tcl; puts [::petshop::utils::config::calculate_total]'`

Expected: `103.0` (100 + 8 + 5 - 10)

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/utils/config.tcl
git commit -m "feat(petshop): add config with multi-line strings and continuations"
```

---

## Task 4: Create services/events.tcl

**Files:**
- Create: `tests/fixtures/petshop/services/events.tcl`

**Step 1: Write the file**

```tcl
# Petshop Event System
# Edge cases: callbacks, uplevel #0, {*} expansion, apply lambdas

namespace eval ::petshop::services::events {
    variable listeners [dict create]
    variable event_log [list]

    # Register callback for event
    proc on {event callback} {
        variable listeners
        if {![dict exists $listeners $event]} {
            dict set listeners $event [list]
        }
        dict lappend listeners $event $callback
    }

    # Emit event with uplevel #0 (global context)
    proc emit {event args} {
        variable listeners
        variable event_log

        # Log the event
        lappend event_log [list $event $args [clock seconds]]

        if {![dict exists $listeners $event]} {
            return 0
        }

        set count 0
        foreach cb [dict get $listeners $event] {
            # Execute callback in global context with argument expansion
            uplevel #0 [list {*}$cb {*}$args]
            incr count
        }
        return $count
    }

    # Remove listener
    proc off {event {callback ""}} {
        variable listeners
        if {$callback eq ""} {
            dict unset listeners $event
        } else {
            if {[dict exists $listeners $event]} {
                set cbs [dict get $listeners $event]
                set idx [lsearch -exact $cbs $callback]
                if {$idx >= 0} {
                    dict set listeners $event [lreplace $cbs $idx $idx]
                }
            }
        }
    }

    # Once - fire callback only once
    proc once {event callback} {
        # Lambda that removes itself after execution
        set wrapper [list apply {{event cb args} {
            {*}$cb {*}$args
            ::petshop::services::events::off $event [info level 0]
        }} $event $callback]
        on $event $wrapper
    }

    # Get event history
    proc history {{limit 10}} {
        variable event_log
        if {$limit >= [llength $event_log]} {
            return $event_log
        }
        return [lrange $event_log end-[expr {$limit - 1}] end]
    }

    # Variable change handler (for trace callbacks)
    proc on_change {varname name1 name2 op} {
        emit "variable:change" $varname $name1 $name2 $op
    }
}
```

**Step 2: Verify syntax**

Run: `tclsh -c 'source tests/fixtures/petshop/services/events.tcl; ::petshop::services::events::on test {puts "fired"}; puts [::petshop::services::events::emit test]'`

Expected:
```
fired
1
```

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/services/events.tcl
git commit -m "feat(petshop): add event system with uplevel and lambda patterns"
```

---

## Task 5: Create models/pet.tcl

**Files:**
- Create: `tests/fixtures/petshop/models/pet.tcl`

**Step 1: Write the file**

```tcl
# Petshop Pet Model
# Edge cases: nested procs, variable/proc name collisions, coroutines, interp alias

namespace eval ::petshop::models::pet {
    variable all_pets [dict create]
    variable next_id 1

    # Variable with same name as a proc (name collision edge case)
    variable create "default_species"

    # Main create proc
    proc create {name species {price 0}} {
        variable all_pets
        variable next_id

        # Nested proc definition (unusual but valid)
        proc validate_species_inner {s} {
            set valid_species {dog cat bird fish hamster rabbit snake lizard}
            return [expr {$s in $valid_species}]
        }

        if {![validate_species_inner $species]} {
            return -code error "Invalid species: $species"
        }

        set id "pet_$next_id"
        incr next_id

        # Dynamic variable name with set
        set "pet_data_${id}" [dict create \
            id $id \
            name $name \
            species $species \
            price $price \
            created [clock seconds] \
        ]

        dict set all_pets $id [set "pet_data_${id}"]
        return $id
    }

    proc get {id} {
        variable all_pets
        if {![dict exists $all_pets $id]} {
            return -code error "Pet not found: $id"
        }
        return [dict get $all_pets $id]
    }

    proc list {{species ""}} {
        variable all_pets
        if {$species eq ""} {
            return [dict values $all_pets]
        }
        set result [list]
        dict for {id pet} $all_pets {
            if {[dict get $pet species] eq $species} {
                lappend result $pet
            }
        }
        return $result
    }

    proc update {id args} {
        variable all_pets
        if {![dict exists $all_pets $id]} {
            return -code error "Pet not found: $id"
        }
        set pet [dict get $all_pets $id]
        foreach {key value} $args {
            dict set pet $key $value
        }
        dict set all_pets $id $pet
        return $pet
    }

    proc delete {id} {
        variable all_pets
        if {![dict exists $all_pets $id]} {
            return 0
        }
        dict unset all_pets $id
        return 1
    }

    # Coroutine-style iteration (advanced feature)
    proc iter {} {
        variable all_pets
        yield [info coroutine]
        dict for {id pet} $all_pets {
            yield $pet
        }
    }

    # Start coroutine
    proc start_iter {} {
        coroutine pet_iterator ::petshop::models::pet::iter
    }
}

# Interp alias - creates shortcut command
interp alias {} ::pet {} ::petshop::models::pet::create
```

**Step 2: Verify syntax**

Run: `tclsh -c 'source tests/fixtures/petshop/services/events.tcl; source tests/fixtures/petshop/models/pet.tcl; puts [::petshop::models::pet::create "Fluffy" "cat" 50]'`

Expected: `pet_1`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/models/pet.tcl
git commit -m "feat(petshop): add pet model with nested procs and coroutines"
```

---

## Task 6: Create models/customer.tcl

**Files:**
- Create: `tests/fixtures/petshop/models/customer.tcl`

**Step 1: Write the file**

```tcl
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
```

**Step 2: Verify syntax**

Run: `tclsh -c 'source tests/fixtures/petshop/models/customer.tcl; set id [::petshop::models::customer::create "John" "john@example.com"]; puts $id'`

Expected: `cust_1`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/models/customer.tcl
git commit -m "feat(petshop): add customer model with upvar/uplevel patterns"
```

---

## Task 7: Create models/inventory.tcl

**Files:**
- Create: `tests/fixtures/petshop/models/inventory.tcl`

**Step 1: Write the file**

```tcl
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
```

**Step 2: Verify syntax**

Run: `tclsh -c 'source tests/fixtures/petshop/services/events.tcl; source tests/fixtures/petshop/models/inventory.tcl; ::petshop::models::inventory::add_item "food_001" 100 9.99; puts [::petshop::models::inventory::get_stock "food_001"]'`

Expected: `100`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/models/inventory.tcl
git commit -m "feat(petshop): add inventory model with variable traces and dynamic vars"
```

---

## Task 8: Create services/pricing.tcl

**Files:**
- Create: `tests/fixtures/petshop/services/pricing.tcl`

**Step 1: Write the file**

```tcl
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

        return [format "%.2f" $total]
    }

    proc calculate_cart {items} {
        set subtotal 0.0

        foreach item $items {
            set subtotal [expr {$subtotal + [calculate $item]}]
        }

        return [format "%.2f" $subtotal]
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
```

**Step 2: Verify syntax**

Run: `tclsh -c 'source tests/fixtures/petshop/services/pricing.tcl; set pet [dict create price 100 weight 5]; puts [::petshop::services::pricing::calculate $pet]'`

Expected: `103.00` (100 * 1.08 - 5 = 103)

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/services/pricing.tcl
git commit -m "feat(petshop): add pricing service with nested expr and dynamic eval"
```

---

## Task 9: Create services/transactions.tcl

**Files:**
- Create: `tests/fixtures/petshop/services/transactions.tcl`

**Step 1: Write the file**

```tcl
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
```

**Step 2: Verify syntax**

Run: `tclsh -c 'source tests/fixtures/petshop/services/transactions.tcl; puts "OK"'`

Expected: `OK`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/services/transactions.tcl
git commit -m "feat(petshop): add transaction service with cross-namespace calls"
```

---

## Task 10: Create petshop.tcl (Main Entry)

**Files:**
- Create: `tests/fixtures/petshop/petshop.tcl`

**Step 1: Write the file**

```tcl
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
```

**Step 2: Verify package loads**

Run: `tclsh -c 'source tests/fixtures/petshop/petshop.tcl; set id [::petshop pet create "Max" "dog" 299]; puts "Created: $id"'`

Expected: `Created: pet_1`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/petshop.tcl
git commit -m "feat(petshop): add main entry with namespace ensemble"
```

---

## Task 11: Create pkgIndex.tcl

**Files:**
- Create: `tests/fixtures/petshop/pkgIndex.tcl`

**Step 1: Write the file**

```tcl
# Petshop Package Index
# Edge cases: package ifneeded with apply lambda, conditional loading

# Standard package registration
package ifneeded petshop 1.0 [list source [file join $dir petshop.tcl]]

# Subpackage with apply lambda (edge case)
package ifneeded petshop::models 1.0 [list apply {{dir} {
    source [file join $dir models pet.tcl]
    source [file join $dir models customer.tcl]
    source [file join $dir models inventory.tcl]
}} $dir]

package ifneeded petshop::services 1.0 [list apply {{dir} {
    source [file join $dir services events.tcl]
    source [file join $dir services pricing.tcl]
    source [file join $dir services transactions.tcl]
}} $dir]

package ifneeded petshop::utils 1.0 [list apply {{dir} {
    source [file join $dir utils config.tcl]
    source [file join $dir utils logging.tcl]
}} $dir]
```

**Step 2: Verify syntax**

Run: `tclsh -c 'set dir tests/fixtures/petshop; source [file join $dir pkgIndex.tcl]; puts "OK"'`

Expected: `OK`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/pkgIndex.tcl
git commit -m "feat(petshop): add pkgIndex with apply lambda pattern"
```

---

## Task 12: Create views/layout.rvt

**Files:**
- Create: `tests/fixtures/petshop/views/layout.rvt`

**Step 1: Write the file**

```html
<?
# Layout Template
# Edge cases: RVT template with includes and variable scoping

proc render_layout {title body_content} {
    set config_name [::petshop::utils::config::get name "Pet Shop"]
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title><?= $title ?> - <?= $config_name ?></title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
        .header { background: #4CAF50; color: white; padding: 10px 20px; }
        .nav { background: #333; padding: 10px; }
        .nav a { color: white; margin-right: 15px; text-decoration: none; }
        .content { padding: 20px; }
        .footer { background: #f5f5f5; padding: 10px; text-align: center; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="header">
        <h1><?= $config_name ?></h1>
    </div>
    <div class="nav">
        <a href="/pets">Pets</a>
        <a href="/cart">Cart</a>
        <a href="/account">Account</a>
    </div>
    <div class="content">
        <?= $body_content ?>
    </div>
    <div class="footer">
        <p>&copy; <?= [clock format [clock seconds] -format %Y] ?> <?= $config_name ?></p>
    </div>
</body>
</html>
<? } ?>
```

**Step 2: Verify file created**

Run: `test -f tests/fixtures/petshop/views/layout.rvt && echo "OK"`

Expected: `OK`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/views/layout.rvt
git commit -m "feat(petshop): add layout RVT template"
```

---

## Task 13: Create views/pets/list.rvt

**Files:**
- Create: `tests/fixtures/petshop/views/pets/list.rvt`

**Step 1: Write the file**

```html
<?
# Pet List View
# Edge cases: loops in RVT, conditionals, cross-file proc calls

set pets [::petshop::models::pet::list]
set pet_count [llength $pets]
?>
<html>
<head>
    <title>Available Pets</title>
</head>
<body>
    <h1>Available Pets (<?= $pet_count ?>)</h1>

    <? if {$pet_count == 0} { ?>
        <p class="empty">No pets available at this time.</p>
    <? } else { ?>
        <div class="pet-grid">
            <? foreach pet $pets { ?>
                <div class="pet-card" data-id="<?= [dict get $pet id] ?>">
                    <h2><?= [dict get $pet name] ?></h2>
                    <p class="species"><?= [dict get $pet species] ?></p>
                    <span class="price">
                        $<?= [::petshop::services::pricing::format [dict get $pet price]] ?>
                    </span>
                    <? if {[dict exists $pet weight] && [dict get $pet weight] > 10} { ?>
                        <span class="badge">Large Pet</span>
                    <? } ?>
                    <a href="/pets/<?= [dict get $pet id] ?>" class="btn">View Details</a>
                </div>
            <? } ?>
        </div>
    <? } ?>

    <?
    # Inline proc in RVT (edge case)
    proc format_summary {count} {
        if {$count == 1} {
            return "1 pet"
        }
        return "$count pets"
    }
    ?>

    <p class="summary">Showing <?= [format_summary $pet_count] ?></p>
</body>
</html>
```

**Step 2: Verify file created**

Run: `test -f tests/fixtures/petshop/views/pets/list.rvt && echo "OK"`

Expected: `OK`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/views/pets/list.rvt
git commit -m "feat(petshop): add pet list RVT with loops and conditionals"
```

---

## Task 14: Create views/pets/detail.rvt

**Files:**
- Create: `tests/fixtures/petshop/views/pets/detail.rvt`

**Step 1: Write the file**

```html
<?
# Pet Detail View
# Edge cases: variable interpolation, proc calls, dict access

# pet_id should be passed in from router
if {![info exists pet_id]} {
    set pet_id "pet_1"
}

set pet [::petshop::models::pet::get $pet_id]
set price [::petshop::services::pricing::calculate $pet]
set in_stock [::petshop::models::inventory::get_stock $pet_id]
?>
<html>
<head>
    <title><?= [dict get $pet name] ?> - Pet Details</title>
</head>
<body>
    <nav>
        <a href="/pets">&larr; Back to Pets</a>
    </nav>

    <article class="pet-detail">
        <header>
            <h1><?= [dict get $pet name] ?></h1>
            <span class="id">ID: <?= [dict get $pet id] ?></span>
        </header>

        <section class="info">
            <dl>
                <dt>Species</dt>
                <dd><?= [dict get $pet species] ?></dd>

                <dt>Price</dt>
                <dd class="price">$<?= $price ?></dd>

                <dt>In Stock</dt>
                <dd class="<?= $in_stock > 0 ? "available" : "unavailable" ?>">
                    <?= $in_stock > 0 ? "$in_stock available" : "Out of stock" ?>
                </dd>

                <? if {[dict exists $pet weight]} { ?>
                <dt>Weight</dt>
                <dd><?= [dict get $pet weight] ?> lbs</dd>
                <? } ?>
            </dl>
        </section>

        <section class="actions">
            <? if {$in_stock > 0} { ?>
                <form action="/cart/add" method="POST">
                    <input type="hidden" name="pet_id" value="<?= $pet_id ?>">
                    <button type="submit" class="btn-primary">Add to Cart</button>
                </form>
            <? } else { ?>
                <button disabled class="btn-disabled">Out of Stock</button>
            <? } ?>
        </section>

        <footer>
            <small>Added: <?= [clock format [dict get $pet created] -format {%Y-%m-%d}] ?></small>
        </footer>
    </article>
</body>
</html>
```

**Step 2: Verify file created**

Run: `test -f tests/fixtures/petshop/views/pets/detail.rvt && echo "OK"`

Expected: `OK`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/views/pets/detail.rvt
git commit -m "feat(petshop): add pet detail RVT with variable interpolation"
```

---

## Task 15: Create views/cart.rvt

**Files:**
- Create: `tests/fixtures/petshop/views/cart.rvt`

**Step 1: Write the file**

```html
<?
# Shopping Cart View
# Edge cases: proc definitions in RVT, nested braces in HTML, form handling

# Local helper proc defined in template (edge case)
proc local_helper {item} {
    set name [dict get $item name]
    set price [dict get $item price]
    return "<li class=\"cart-item\">$name - \$$price</li>"
}

proc format_currency {amount} {
    return [format "$%.2f" $amount]
}

# Mock cart data
if {![info exists cart_items]} {
    set cart_items [list]
}

set total [::petshop::services::pricing::calculate_cart $cart_items]
set item_count [llength $cart_items]
?>
<!DOCTYPE html>
<html>
<head>
    <title>Shopping Cart</title>
    <style>
        .cart-item { padding: 10px; border-bottom: 1px solid #eee; }
        .cart-item:hover { background: #f9f9f9; }
        .total { font-size: 1.5em; font-weight: bold; }
        .empty-cart { color: #666; font-style: italic; }
        /* Edge case: braces in CSS inside HTML context */
        .badge { display: inline-block; padding: 2px 8px; }
        .badge::before { content: "{"; }
        .badge::after { content: "}"; }
    </style>
</head>
<body>
    <h1>Shopping Cart</h1>

    <? if {$item_count == 0} { ?>
        <p class="empty-cart">Your cart is empty</p>
        <a href="/pets">Browse Pets</a>
    <? } else { ?>
        <ul class="cart-list">
            <? foreach item $cart_items { ?>
                <?= [local_helper $item] ?>
            <? } ?>
        </ul>

        <div class="cart-summary">
            <p>Items: <?= $item_count ?></p>
            <p class="total">Total: <?= [format_currency $total] ?></p>
        </div>

        <form action="/checkout" method="POST" class="checkout-form">
            <? foreach item $cart_items { ?>
                <input type="hidden"
                       name="items[]"
                       value="<?= [dict get $item id] ?>"
                       data-price="<?= [dict get $item price] ?>">
            <? } ?>

            <label for="discount">Discount Code:</label>
            <input type="text"
                   id="discount"
                   name="discount_code"
                   placeholder="Enter code"
                   pattern="[A-Z0-9]+"
                   title="Discount codes are uppercase alphanumeric">

            <button type="submit">Proceed to Checkout</button>
        </form>
    <? } ?>

    <script>
        // Edge case: JavaScript with braces in HTML
        document.querySelector('form').addEventListener('submit', function(e) {
            var items = document.querySelectorAll('input[name="items[]"]');
            if (items.length === 0) {
                e.preventDefault();
                alert('Cart is empty!');
            }
        });
    </script>
</body>
</html>
```

**Step 2: Verify file created**

Run: `test -f tests/fixtures/petshop/views/cart.rvt && echo "OK"`

Expected: `OK`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/views/cart.rvt
git commit -m "feat(petshop): add cart RVT with procs and nested braces"
```

---

## Task 16: Create views/partials/pet_card.rvt

**Files:**
- Create: `tests/fixtures/petshop/views/partials/pet_card.rvt`

**Step 1: Write the file**

```html
<?
# Pet Card Partial
# Edge cases: partial includes with variable scoping, upvar in RVT

# Expect 'pet' variable to be passed in from parent
if {![info exists pet]} {
    error "pet_card.rvt requires 'pet' variable"
}

# Access parent scope variable (edge case)
if {[uplevel 1 {info exists show_price}]} {
    upvar 1 show_price show_price
} else {
    set show_price 1
}

set pet_name [dict get $pet name]
set pet_species [dict get $pet species]
set pet_id [dict get $pet id]
?>
<div class="pet-card" id="pet-<?= $pet_id ?>">
    <div class="pet-card-header">
        <h3><?= $pet_name ?></h3>
        <span class="species-badge <?= $pet_species ?>"><?= $pet_species ?></span>
    </div>

    <div class="pet-card-body">
        <? if {[dict exists $pet description]} { ?>
            <p><?= [dict get $pet description] ?></p>
        <? } ?>

        <? if {$show_price && [dict exists $pet price]} { ?>
            <p class="price">
                <?= [::petshop::services::pricing::format [dict get $pet price]] ?>
            </p>
        <? } ?>
    </div>

    <div class="pet-card-footer">
        <a href="/pets/<?= $pet_id ?>" class="btn btn-view">View</a>
        <button class="btn btn-cart"
                data-pet-id="<?= $pet_id ?>"
                onclick="addToCart('<?= $pet_id ?>')">
            Add to Cart
        </button>
    </div>
</div>
```

**Step 2: Verify file created**

Run: `test -f tests/fixtures/petshop/views/partials/pet_card.rvt && echo "OK"`

Expected: `OK`

**Step 3: Commit**

```bash
git add tests/fixtures/petshop/views/partials/pet_card.rvt
git commit -m "feat(petshop): add pet card partial with scoped variables"
```

---

## Task 17: Final Verification and Integration Commit

**Step 1: Run full package load test**

Run: `tclsh -c 'source tests/fixtures/petshop/petshop.tcl; puts "Package loaded"; set p [::petshop pet create "Buddy" "dog" 199]; puts "Pet: $p"; set c [::petshop customer create "Alice" "alice@test.com"]; puts "Customer: $c"; puts "All OK"'`

Expected:
```
Package loaded
Pet: pet_1
Customer: cust_1
All OK
```

**Step 2: Verify file count**

Run: `find tests/fixtures/petshop -type f | wc -l`

Expected: `15`

**Step 3: Verify directory structure**

Run: `find tests/fixtures/petshop -type f | sort`

Expected:
```
tests/fixtures/petshop/models/customer.tcl
tests/fixtures/petshop/models/inventory.tcl
tests/fixtures/petshop/models/pet.tcl
tests/fixtures/petshop/petshop.tcl
tests/fixtures/petshop/pkgIndex.tcl
tests/fixtures/petshop/services/events.tcl
tests/fixtures/petshop/services/pricing.tcl
tests/fixtures/petshop/services/transactions.tcl
tests/fixtures/petshop/utils/config.tcl
tests/fixtures/petshop/utils/logging.tcl
tests/fixtures/petshop/views/cart.rvt
tests/fixtures/petshop/views/layout.rvt
tests/fixtures/petshop/views/partials/pet_card.rvt
tests/fixtures/petshop/views/pets/detail.rvt
tests/fixtures/petshop/views/pets/list.rvt
```

**Step 4: Final commit**

```bash
git add -A tests/fixtures/petshop
git commit -m "feat(petshop): complete e2e test fixture with all edge cases

Adds multi-file TCL package for LSP testing:
- Symbol resolution: nested procs, upvar/uplevel, dynamic variables
- Cross-file: namespace ensemble, imports/exports, package loading
- Parser: multi-line strings, unusual quoting, nested expressions
- RVT: templates with embedded TCL, loops, conditionals, partials

15 files, ~530 lines total"
```

---

## Summary

| Task | Files | Purpose |
|------|-------|---------|
| 1 | directories | Create structure |
| 2 | utils/logging.tcl | Format strings, escapes |
| 3 | utils/config.tcl | Multi-line strings, continuations |
| 4 | services/events.tcl | Callbacks, uplevel, lambdas |
| 5 | models/pet.tcl | Nested procs, coroutines, aliases |
| 6 | models/customer.tcl | upvar levels, uplevel scripts |
| 7 | models/inventory.tcl | Traces, dynamic variables |
| 8 | services/pricing.tcl | Nested expr, subst, eval |
| 9 | services/transactions.tcl | Cross-namespace calls |
| 10 | petshop.tcl | Namespace ensemble |
| 11 | pkgIndex.tcl | Package with apply lambda |
| 12-16 | views/*.rvt | RVT templates |
| 17 | - | Final verification |
