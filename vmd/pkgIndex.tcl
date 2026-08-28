# vmd/pkgIndex.tcl -- optional packaged-install form.
# The sourced form (`source biochemeleon.tcl`) works WITHOUT this file (the
# `package provide biochemeleon $ver` inside the entry makes
# vmd_install_extension's internal `package require` a no-op). This pkgIndex.tcl
# unlocks the alternative packaged-install path: `lappend auto_path /dir; package
# require biochemeleon` -- matching the form in every vmd-ref/plugins/*/pkgIndex.tcl
# (clonerep1.3/pkgIndex.tcl:11, viewmaster2.6/pkgIndex.tcl:11, etc.).
# $dir is set by the tcl package machinery to this file's directory.
package ifneeded biochemeleon 2.0 [list source [file join $dir biochemeleon.tcl]]
