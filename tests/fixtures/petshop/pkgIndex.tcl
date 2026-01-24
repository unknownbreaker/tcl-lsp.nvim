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
