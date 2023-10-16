#!/usr/bin/env tclsh8.6
# vim: set syntax=tcl shiftwidth=4 smarttab expandtab:
package require scm

namespace import ::scm::proc_doc ::scm::Log

set default_branch master
if {[info exists env(SCM_DEFAULT_BRANCH)]} {
    set default_branch $env(SCM_DEFAULT_BRANCH)
}
::scm::configure -default_branch $default_branch

set scm "/usr/bin/git"

if {[info exists env(SCM_LOGLEVEL)]} {
    ::scm::configure -loglevel $env(SCM_LOGLEVEL)
}

## configure for git
::scm::configure -scm $scm

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


proc_doc ::scm::git_custom { commands } { 
    arguments: commands, which is a list of commands in the following format:
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
    set default_branch [::scm::optionget -default_branch]
    set current_branch [::scm::optionget -current_branch]
    set top_level      [::scm::optionget -toplevel      ]

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

    set result ""
    foreach command $commands {
        foreach {cmd args} $command {
            if {[string length $result]>0} {append result "\n"}
            switch -glob -- $cmd {
                update    { 
                    if {[string compare $current_branch $default_branch]} { 
                        ::scm::scm checkout $default_branch
                    }
                    append result [::scm::go $update]
                    if {[string compare $current_branch $default_branch]} { 
                        ::scm::scm checkout $current_branch
                    }
                }
                hash      { append result [::scm::go $hash]     }
                getbranch { append result [::scm::go $branch]   }
                toplevel  { append result [::scm::go $toplevel] }
                shortlog  { append result [::scm::go $shortlog] }
                check     { 
                    set    command $toplevel
                    append command $branch
                    append command $hash
                    append result [::scm::go $command]
                }
                default    {
                    puts stderr "command $cmd not found"
                }
            }
        }
    }
    return $result
}

## main

::scm::configure -current_branch [::scm::git_custom getbranch]
::scm::configure -toplevel       [::scm::git_custom toplevel ]
::scm::configure -hash           [::scm::git_custom hash     ]

# Pop off the first argument. I'm not using - or -- here, but the straight argument.
if {[llength $argv]==0} {
    puts stderr "No operation given for [file tail $scm], exiting"
    exit 1
}

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

## When calling our procedures, we need to accept a list of commands, which 
## is a list of {cmd args}. While this can get a bit confusing, it also means
## that any procedure we use can run MULTIPLE commands and return 
## the output.
set command [list \
    [list $cmd $argv] \
]

## This is where the magic happens
if {[catch {eval $opt_proc [list $command]} result]} {
    puts stderr "$result"
    exit 1
} else {
    puts $result
} 

exit 0
