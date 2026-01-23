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
