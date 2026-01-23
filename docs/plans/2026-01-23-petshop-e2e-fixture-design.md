# Petshop E2E Test Fixture Design

**Purpose:** Multi-file TCL application for end-to-end LSP testing, focusing on edge cases and parser stress-testing.

**Domain:** Toy pet store inventory system

## Package Structure

```
tests/fixtures/petshop/
├── pkgIndex.tcl           # Package index
├── petshop.tcl            # Main entry, namespace ensemble
├── models/
│   ├── pet.tcl            # Pet entity
│   ├── customer.tcl       # Customer with upvar patterns
│   └── inventory.tcl      # Stock tracking, variable traces
├── services/
│   ├── pricing.tcl        # Nested expressions, dynamic eval
│   ├── transactions.tcl   # Cross-file calls, callbacks
│   └── events.tcl         # Observer pattern, uplevel
├── utils/
│   ├── config.tcl         # Multi-line strings, unusual quoting
│   └── logging.tcl        # Format strings, escapes
└── views/
    ├── layout.rvt         # Base template with includes
    ├── pets/
    │   ├── list.rvt       # Loop constructs, conditionals
    │   └── detail.rvt     # Variable interpolation
    ├── cart.rvt           # Form handling, procs in RVT
    └── partials/
        └── pet_card.rvt   # Included partial
```

## Edge Cases by Category

### Symbol Resolution

| File | Edge Cases |
|------|------------|
| `models/pet.tcl` | Nested proc definitions, variable/proc name collisions, coroutines, `interp alias` |
| `models/customer.tcl` | `upvar` at levels 1 and 2, `uplevel` with script execution |
| `models/inventory.tcl` | Variable traces with callbacks, dynamic `variable` declarations, `set $varname` indirection |

### Cross-File Navigation

| File | Edge Cases |
|------|------------|
| `pkgIndex.tcl` | `package ifneeded` with `apply` lambda, conditional loading |
| `petshop.tcl` | `namespace ensemble` with subcommand mapping, `namespace import`/`export` chains |
| `services/transactions.tcl` | Fully-qualified cross-namespace calls, multi-file dependency chains |

### Parser Resilience

| File | Edge Cases |
|------|------------|
| `utils/config.tcl` | Multi-line braced strings, mixed quoting styles, line continuations with backslash |
| `utils/logging.tcl` | Format strings with `%` symbols, escape sequences, nested `[expr]` inside strings |
| `services/pricing.tcl` | Deeply nested expressions, ternary operator, `subst`, dynamic `eval` |

### Dynamic Code & Callbacks

| File | Edge Cases |
|------|------------|
| `services/events.tcl` | Stored callbacks, `uplevel #0` execution, `{*}` argument expansion, `apply` lambdas |

### RVT Templates

| File | Edge Cases |
|------|------------|
| `views/pets/list.rvt` | `<? ?>` code blocks, `<?= ?>` expression output, loops in template |
| `views/cart.rvt` | Proc definitions within RVT, nested braces in HTML context |
| `views/partials/pet_card.rvt` | Partial includes with variable scoping |

## File Details

### pkgIndex.tcl (~15 lines)

```tcl
package ifneeded petshop 1.0 [list source [file join $dir petshop.tcl]]
package ifneeded petshop::models 1.0 [list apply {{dir} {
    source [file join $dir models pet.tcl]
    source [file join $dir models customer.tcl]
}} $dir]
```

### petshop.tcl (~30 lines)

```tcl
namespace eval ::petshop {
    namespace export pet customer inventory
    namespace ensemble create -subcommands {pet customer inventory}
}

namespace eval ::petshop {
    namespace import ::petshop::models::pet::create
    namespace export create
}
```

### models/pet.tcl (~60 lines)

```tcl
proc ::petshop::models::pet::create {name species} {
    proc validate_species {s} { ... }
    set "pet_${name}" [dict create ...]
}

variable create "default"

proc ::petshop::models::pet::iter {} {
    yield [info coroutine]
    foreach pet $::petshop::models::pet::all_pets {
        yield $pet
    }
}

interp alias {} ::pet {} ::petshop::models::pet::create
```

### models/customer.tcl (~50 lines)

```tcl
proc ::petshop::models::customer::with_customer {id body} {
    upvar 1 customer c
    upvar 2 transaction_log log
    ...
}

proc ::petshop::models::customer::in_context {id script} {
    uplevel 1 $script
}
```

### models/inventory.tcl (~50 lines)

```tcl
proc ::petshop::models::inventory::track {varname} {
    upvar 1 $varname v
    trace add variable v write [list ::petshop::services::events::on_change $varname]
}

proc get_stock {item_id} {
    variable stock_$item_id
    set varname "stock_$item_id"
    return [set $varname]
}
```

### services/pricing.tcl (~40 lines)

```tcl
proc calculate {pet} {
    expr {
        ([dict get $pet base_price] * (1 + [tax_rate]))
        + ([dict get $pet weight] > 10 ? [large_pet_fee] : 0)
        - ([loyalty_discount [dict get $pet customer_id]])
    }
}

proc dynamic_calc {formula vars} {
    dict for {k v} $vars { set $k $v }
    expr [subst $formula]
}
```

### services/transactions.tcl (~40 lines)

```tcl
proc ::petshop::services::transactions::purchase {pet_id customer_id} {
    set pet [::petshop::models::pet::get $pet_id]
    set price [::petshop::services::pricing::calculate $pet]
    ::petshop::models::customer::charge $customer_id $price
    ::petshop::services::events::emit purchase [list $pet_id $customer_id $price]
}
```

### services/events.tcl (~50 lines)

```tcl
namespace eval ::petshop::services::events {
    variable listeners [dict create]

    proc on {event callback} {
        variable listeners
        dict lappend listeners $event $callback
    }

    proc emit {event args} {
        variable listeners
        foreach cb [dict get $listeners $event] {
            uplevel #0 [list {*}$cb {*}$args]
        }
    }

    on purchase [list apply {{pet_id cust_id price} {
        ::petshop::utils::logging::log INFO "Sale: $pet_id to $cust_id for $price"
    }}]
}
```

### utils/config.tcl (~40 lines)

```tcl
variable welcome_message {
    Welcome to the Pet Shop!

    We have many animals:
      - Dogs
      - Cats
      - "Exotic" birds
}

set pattern "item_\{.*\}"
set message {He said "hello"}
set mixed "value with {braces} inside"

set long_command [expr {$base_price + \
    $tax + \
    $shipping - \
    $discount}]
```

### utils/logging.tcl (~30 lines)

```tcl
proc ::petshop::utils::logging::log {level msg args} {
    set fmt "[clock format [clock seconds]] \[%s\] %s"
    puts [format $fmt $level $msg]
}

set report "Total: [expr {$count * $price}] for $count items"
set path "C:\\pets\\data\\$filename"
set tab "col1\tcol2\tcol3"
```

### views/pets/list.rvt (~30 lines)

```html
<?
    set pets [::petshop::models::pet::list]
?>
<html>
<body>
    <? foreach pet $pets { ?>
        <div class="pet-card">
            <h2><?= [dict get $pet name] ?></h2>
            <span>$<?= [::petshop::services::pricing::format [dict get $pet price]] ?></span>
        </div>
    <? } ?>
</body>
</html>
```

### views/cart.rvt (~35 lines)

```html
<?
    proc local_helper {item} {
        return "<li>[dict get $item name]</li>"
    }
    set total [::petshop::services::pricing::calculate_cart $cart_id]
?>
```

## Estimated Size

~530 lines across 15 files
