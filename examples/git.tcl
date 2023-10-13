#!/usr/bin/env tclsh8.6
# vim: set syntax=tcl shiftwidth=4 smarttab expandtab:
package require scm
package require util

namespace import ::scm::proc_doc ::scm::Log

set default_branch master

if {[info exists env(SCM_LOGLEVEL)]} {
    ::scm::configure -loglevel $env(SCM_LOGLEVEL)
}

## configure for git
::scm::configure -scm git

## configure custom commands
::scm::add_commands "up" "update"    "::scm::git_custom" "Update $default_branch branch"
::scm::add_commands "ha" "hash"      "::scm::git_custom" "Get hash of git repo"
::scm::add_commands "gb" "getbranch" "::scm::git_custom" "Get branch of git repo"
::scm::add_commands "ch" "check"     "::scm::git_custom" "Get hash and branch"
::scm::add_commands "tl" "toplevel"  "::scm::git_custom" "Show top level directory"
::scm::add_commands "sl" "shortlog"  "::scm::git_custom" "Display short log"

## configure aliases
::scm::add_alias "l" "log"

## configure commands to block 
foreach i {add push commit} { 
    ::scm::configure -blockcmds $i
}

## configure branchs to block commands in
::scm::configure -blockbranchs $default_branch


proc_doc ::scm::git_custom { cmd args } { 
    arguments:
      - cmd  - The custom git command we want to run
      - args - The additional arguments to use. 
 
    This will run the custom git commands that we create. Typically we don't
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
   
    set update {
        {"fetch"        "--all -p -t"}
        {"pull"         ""}
    }

    set hash { 
        {rev-parse      HEAD}
    }

    set branch {
        {symbolic-ref   "--short HEAD"}
    }

    set toplevel {
        {rev-parse       --show-toplevel}
    }

    set shortlog {
        {log            "--oneline --graph"}
    }

    switch -glob -- $cmd {
        update    { 
            if {[string compare $current_branch $default_branch]} { 
                ::scm::scm checkout $default_branch
            }
            ::scm::go $update   
            if {[string compare $current_branch $default_branch]} { 
                ::scm::scm checkout $current_branch
            }
        }
        hash      { ::scm::go $hash     }
        getbranch { ::scm::go $branch   }
        toplevel  { ::scm::go $toplevel }
        shortlog  { ::scm::go $shortlog }
        check     { 
            set    command $toplevel
            append command $branch
            append command $hash
            ::scm::go $command
        }
        default    {
            puts stderr "command $cmd not found"
        }
    }
}

## main

::scm::configure -current_branch [set current_branch [::scm::git_custom getbranch]]
::scm::configure -toplevel [set top_level [::scm::git_custom toplevel]]

# Pop off the first argument. I'm not using - or -- here, but the straight argument.
set opt       [::scm::Pop argv]

# Check if this is a custom command, alias. If it is
# NOT a custom command, just trying running the command.
# If if it IS a custom command, run that custom procudure.
# Another note:
#     This means you can have command that have nothing to do with 
#     git if you wish. You could, say, create a custom funtion that 
#     might trigger a build, run make, etc.
if {[catch {::scm::get_operation $opt} result]} {
    set cmd $result
    set opt_proc "::scm::go"
} else {
    foreach {short cmd opt_proc desc} $result break
}

if {[catch {eval $opt_proc [list $cmd {*}$argv]} result]} {
    puts stderr "$result"
    exit 1
} else {
    puts $result
} 

exit 0
