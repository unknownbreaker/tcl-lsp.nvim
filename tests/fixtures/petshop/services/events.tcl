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
