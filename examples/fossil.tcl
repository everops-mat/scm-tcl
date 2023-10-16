#!/usr/bin/env tclsh8.6
# vim: set syntax=tcl shiftwidth=4 smarttab expandtab:
package require scm

namespace import ::scm::proc_doc ::scm::Log

set default_branch trunk
if {[info exists env(SCM_DEFAULT_BRANCH)]} {
    set default_branch $env(SCM_DEFAULT_BRANCH)
}
::scm::configure -default_branch $default_branch

if {[info exists env(SCM_LOGLEVEL)]} {
    ::scm::configure -loglevel $env(SCM_LOGLEVEL)
}

## configure scm
set scm            "/usr/bin/fossil"
::scm::configure -scm $scm

## configure custom commands
::scm::add_commands "br" "getbranch"   "::scm::fossil_custom" "Get hash of fossil repo"
::scm::add_commands "tl" "toplevel"    "::scm::fossil_custom" "Get top level directory"

## configure aliases
::scm::add_alias "l" "timeline"
::scm::add_alias "log" "timeline"

## configure commands to block 
foreach i {add push commit} { 
    ::scm::configure -blockcmds $i
}

## configure branchs to block commands in
::scm::configure -blockbranchs $default_branch


proc_doc ::scm::fossil_custom { commands } { 
    arguments: commands
    Where commands are a list of commands in the following format:
      - cmd  - The custom fossil command we want to run
      - args - The additional arguments to use. 
 
    This will run the custom fossil commands that we create. Typically we don't
    give additional arguments to custom commands. Although you might. If you so 
    so you have to add that arguments we want to add.
    
    You could also use the argments for custom options, perhaps creating a 
    custom create_branch command has options of:
      -type [bugfix|feature|working]
      -jira JIRA_ISSUE (or NO_JIRA)
      
   While this is defined in our application, we are using the proc_doc from 
   the ::scm module, we need add the procdure to that namespace.
} { 
    variable default_branch 
    variable current_branch 
    variable top_level
 
    set branch {
        {branch         current}
    }

    set result ""
    foreach command $commands {
        foreach {cmd args} $command break
        if {[string length $result]>0} { append result "\n"}
        switch -glob -- $cmd {
            getbranch { append result [::scm::go $branch]          }
            toplevel  { append result [::scm::optionget -toplevel] }
            default    {
                puts stderr "command $cmd not found"
            }
        }
    }
    return $result
}

## main

## Fossil is a bit different, so we have to do some extra work
## to get the toplevel directory and the current hash.
foreach line [split [::scm::scm {status}] "\n"] {
    foreach {key val} [split $line ":"] break
    switch -- $key {
        local-root {
            set toplevel [string trim $val]
        }
        checkout {
            set hash [string trim $val]
        }
    }
}
::scm::configure -current_branch [::scm::fossil_custom getbranch]
::scm::configure -toplevel       $toplevel
::scm::configure -hash           $hash

if {[llength $argv]==0} {
    puts "No operation for [file tail $scm] given, exiting"
    exit 1
}

# Pop off the first argument. I'm not using - or -- here, but the straight argument.
set opt       [::scm::Pop argv]

# Check if this is a custom command, alias. If it is
# NOT a custom command, just trying running the command.
# If if it IS a custom command, run that custom procudure.
# Another note:
#     This means you can have command that have nothing to do with 
#     fossil if you wish. You could, say, create a custom funtion that 
#     might trigger a build, run make, etc.
if {[catch {::scm::get_operation $opt} result]} {
    set cmd $result; set opt_proc "::scm::go"
} else {
    foreach {short cmd opt_proc desc} $result break
}

# Setup the command and arguments for ::scm::go
set command [list \
    [list $cmd $argv] \
]

if {[catch {eval $opt_proc [list $command]} result]} {
    puts stderr "$result"
    exit 1
} else {
    puts $result
} 

exit 0
