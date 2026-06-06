# Package index. $dir is supplied by the package machinery (pkg_mkIndex /
# auto_path scan). Maps a package name+version to the script that loads it.
package ifneeded greeter 1.0 [list source [file join $dir greeter.tcl]]
