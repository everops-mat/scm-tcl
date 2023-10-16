## scm.tcl
# vim: set syntax=tcl shiftwidth=4 smarttab expandtab:
#
package require logger 

package provide scm 0.0.1

namespace eval ::scm {

    # Set a version, it can be useful in debugging and error messages.
    variable version [package present scm]

    namespace export proc_doc showprocs Log
    
    # variable to hold procedure information for module.
    variable procs
    array set procs {} 
    
    # These are options that can be set using the configure procedure and 
    # and can be obtained using the optionget procedure.
    variable options
    if {![info exists options]} {
        array set options {
            scm                 {}
            blockcmds           {}
            blockbranchs        {}
            default_branch	{}
            current_branch	{}
            toplevel		{}
            hash                {}
        }
    }
 
    # A list of aliases for commands. These commands can be actual git commands
    # (like co for checkup, pl for pull, etc.) or point to custom commands.
    # Format is
    #  "ALIASES" "COMMANDS" 
    variable aliases
    if {![info exists aliases]} {
        set aliases {
            {co checkout}
        }
    }

    # This is a list of custom commands that we'll be creating. Each 
    # command definition has a short option, a long option, and procedure
    # to call and a description.
    # Format is
    #  "SHORT" "LONG" "CALL PROCEDURE" "DESCRIPTION"          
    variable commands
    if {![info exists commands]} {
        set commands {
            {"h"    "help"          "::scm::usage"         "Display usage"}
            {"SP"   "showprocs"     "::scm::showprocs"     "Show procs in module"}
        }
    }

    # Log is a variable that holds all the logging module information 
    # for this namespace. Later, there is a procedure Log that can be
    # called to write a log messages.
    variable log
    if {![info exists log]} {
        set log [logger::init scm]
        ${log}::setlevel warn
        proc ${log}::stdoutcmd {level text} {
            variable service
            puts "\[[clock format [clock seconds] -format {%H:%M:%S}]\
                $service $level\] $text"
        }
    }
    
}

# This allows use to create a procedure with a description
proc ::scm::proc_doc { name args doc_string body } {

    variable procs
    
    proc $name $args $body
    array set procs [list $name $doc_string]
    
}

::scm::proc_doc ::scm::showprocs { args } {
    arguments: args (not needed, but we need to accept arguments to be 
               called.
               
    Show all the procdures with descriptions that are defined
    for this module
} { 

    variable procs 
    
    set result ""
    foreach {name desc} [array get procs] { 
        append result "$name"
        append result "$desc"
    }
    return $result
    
}
    
::scm::proc_doc ::scm::optionget { option } {
    arguments: option - the option to get
    
    Function that allows us to get specific options.
    Since the loglevel is not in the options, there is
    a special check to return that.
} { 
    
    variable options
    variable log

    # Trim off the leading dash and check to see if the 
    # selection is vaild.
    # Since we allow the log level to be configure and it is NOT
    # part of the option array, we need to do a seperate check
    # for that outside the options array.
    set opt [string trimleft $option -]
    if { [string equal option -loglevel] } {
        return -code -ok [${log}::currentloglevel]
    } elseif { [info exists options($opt)] } {
        return -code ok $options($opt)
    } else {
        return -code error "unknown option \"-$opt\": \
            must be one of -[join [array names options] {, -}]"
    }
    
}

::scm::proc_doc ::scm::configure { args } { 
    This allows use to configure settings by updating the 
    options array.
} { 

    variable options
    variable log

    # If we are called without any arguments, prite out all the options
    # and their current vaules.
    if {[llength $args] == 0} {
        set r [list -loglevel [${log}::currentloglevel]]
        foreach {opt value} [array get options] {
            lappend r -$opt $value
        }
        lappend r -
        return $r
    }

    # If we are here, we have a specific value to change.
    # -loglevel       - change the log level of the Log function.
    # -scm            - Which SCM are using using (git, fossil, hg, svn, cvs)
    # -current_branch - the current branch of the SCM we are in.
    # -toplevel       - the toplevel directory of the repo.
    # -blockcmds      - a list of commands we don't allow to be run in the 
    #                   branches defined in blockbranches
    # -blockbranchs   - a list of branches were we don't allow blockcmds 
    #                   to run.
    while {[string match -* [set option [lindex $args 0]]]} {
        switch -glob -- $option {
            -loglevel           { ${log}::setlevel [Pop args 1]           }
            -scm                { set options(scm) [Pop args 1]           }
            -default_branch     { set options(default_branch) [Pop args 1]}
            -current_branch     { set options(current_branch) [Pop args 1]}
            -toplevel           { set options(toplevel) [Pop args 1]      }
            -hash               { set options(hash) [Pop args 1]          }
            -blockcmds          {
                set a [Pop args 1]
                # We don't want to add duplicates.
                if {[lsearch -exact $options(blockcmds) $a] == -1 } {
                    lappend options(blockcmds) $a
                } else {
                   ::scm::Log info "command $a already defined"
                }
            }
            -blockbranchs       {
                set a [Pop args 1]
                 # We don't want to add duplicates.
                if {[lsearch -exact $options(blockbranchs) $a] == -1 } {
                    lappend options(blockbranchs) $a
                } else {
                   ::scm::Log "branch $a already defined"
                }
            }
            --                  { Pop args; break }
            default {
                set failed 1
                set msg "unknown option: \"$option\":\
                   must be one of -loglevel, -scm,\
                    -blockbranch, -blockedcmds"
                if {$failed} {
                    return -code error $msg
                }
            }
        }
        Pop args
    }
    return -code ok

}

::scm::proc_doc ::scm::Log {level str } { 
    A simple (very) logging command. You can set the log level
    using ::scm::configure -loglevel.
} { 

    variable log
    
    ${log}::${level} $str
    
}

::scm::proc_doc ::scm::check_alias { command } { 
    Check if an aliases is already defined. 
} { 

    variable aliases

    if {[set line [lsearch -index 0 $aliases $command]]!=-1} { 
        return -code ok [lindex [lindex $aliases $line] 1] 
    }
    return -code error "$command not found"

}

::scm::proc_doc ::scm::check_command { command } { 
    Check if a command is defined.
    
    Since we have to command "names" we have to check but the 
    short and long indexes to make sure we don't have duplicates.
} { 

    variable commands

    for {set i 0} {$i<2} {incr i} { 
        if {[set line [lsearch -index $i $commands $command]]!=-1} {
            return -code ok [lindex $commands $line]
        }
    }
    return -code error "$command not found"

} 

::scm::proc_doc ::scm::add_commands { short long call_proc desc } { 
    Add a command to the command set.
    
    We check to make sure that the command is not already defined
    in aliases and commands. We don't want to create some loop or 
    race conition. 
} { 

    variable commands

    if {![catch {::scm::check_alias $short}]} {
        return -code error "command $short defined as aliases"
    }
    if {![catch {::scm::check_command $short}]} { 
        return -code error "command $short already defined"
    }
    if {![catch {::scm::check_command $long}]} {
        return -code error "command $long already defined"
    }

    lappend commands [list $short $long $call_proc $desc]

}

::scm::proc_doc ::scm::add_alias { short long } { 
    Add an alias.
    
    Like the commands, make sure that we don't already have 
    an alias or command defined first.
} {

    variable aliases

    if {![catch {::scm::check_alias $short}]} {
        return -code error "command $short defined as aliases"
    }
    if {![catch {::scm::check_command $short}]} { 
        return -code error "command $short already defined"
    }
    if {![catch {::scm::check_command $long}]} {
        return -code error "command $long already defined"
    }

    lappend aliases [list $short $long]

}

::scm::proc_doc ::scm::usage { {args {}} } { 
    Create a usage page using the aliases and commands. See, there is a 
    reason for the description being given.
    
    This procedure is called by the help commands in the default 
    configuration.
} { 

    global argv0

    variable commands
    variable aliases
    variable version 

    puts "scm version $version\n"
    puts "[file tail $argv0] operation \[arguments\]\n"
    puts "Custom scm Options provided:"
    foreach command $commands {
        foreach {short long call_proc desc} $command { 
            set opt "$short,$long"
            puts [format "\t%-20s\t - %s" $opt $desc]
        }
    }
    puts "scm creates the following aliases commands"
    foreach alias $aliases {
        foreach {short long} $alias {
            puts [format "\t%-20s\t - %s" $short $long]
        }
    }
}

::scm::proc_doc ::scm::run { command } { 
    This is a procedure to run a shell command and attempt to collect
    any error messages and return codes, as well as the output.
    
    One problem is presents is that all the output is stored in 
    memory and then has to be printed.
    
    But for the purpose of this module (to wrap around a SCM command)
    this should not be an issue. It is, at best, a bit annoying.
    
    We should cleanup the return information a bit to make it 
    easy to parse the error code, etc. but for the purpose of this
    module, that should be an issue.
} {

    set status [ catch {eval [linsert $command 0 exec]} result ]
    if {$status==0} {
        # command was successful
        # nothing written to stderr
        return -code ok $result
    } elseif {[string equal $::errorCode NONE]} {
        # command was successful
        # something was running to stderr
        return -code ok $result
    } else {
        switch -exact -- [lindex $::errorCode 0] {
            CHILDKILLED {
                foreach {- pid sigName msg} $::errorCode break
                # A child process, whose process ID was $pid,
                # died on a signal named $sigName.  A human-
                # readable message appears in $msg.
                return -code error "pid $pid died on $sigName\n$msg\n$result"
            }
            CHILDSTATUS {
                foreach {- pid code} $::errorCode break
                # A child process, whose process ID was $pid,
                # exited with a non-zero exit status, $code.
                return -code error "pid $pid died with error code $code\n$result"
            }
            CHILDSUSP {
                foreach {- pid sigName msg} $::errorCode break
                # A child process, whose process ID was $pid,
                # has been suspended because of a signal named
                # $sigName.  A human-readable description of the
                # signal appears in $msg.
                return -code error "pid $pid suspended by $sigName\n$msg\$result"
            }
            POSIX {
                foreach {- errName msg} $::errorCode break
                # One of the kernel calls to launch the command
                # failed.  The error code is in $errName, and a
                # human-readable message is in $msg.
                return -code error "POSIX: $errName\n$msg\n$result"
            }
        }
    }
}

::scm::proc_doc ::scm::scm { cmd args} { 
    This procedure runs the scm command and returns the output.
    
    First we make sure we can get the scm command from the options set.
    
    Then we make sure the scm command is set.
    
    Next, we get the branch and make sure that we are allowed to run
    the command in this branch.
    
    Once we have based those checks, we run the command.
} {

    # puts "running git command $cmd with args $args"
    ::scm::Log debug "running git command $cmd with args $args"
    if {[ catch {optionget -scm} scmcmd]} {
        return -code error "error getting the scm command"
    }

    if {[string compare $scmcmd ""]==0} { 
        return -code error "scm command is not set, exiting"
    }

    set branch [::scm::optionget -current_branch]
    
    if {[lsearch -exact [optionget blockbranchs] $branch]!=-1 && \
        [lsearch -exact [optionget blockcmds] $cmd]!=-1 } {
        return -code error "can not run $cmd in branch $branch"
    }
    set command "$scmcmd $cmd $args"
    if {[catch {::scm::run "$command"} result]} {
        return -code error $result
    }
    return $result

}

::scm::proc_doc ::scm::go { commands } { 
    Feed a list of commands to ::scm::scm save the results
    and return them.
    
    Note: as of now, we don't stop on error, but that will
    change in a bit.
    
    If stopping a command on error is required, you'll have to 
    call ::scm::scm seperatly for each command you wish to run
    and check for errors.
} { 
    set result ""

    foreach command $commands {
        foreach {cmd args} $command { 
            if {[string length $result]>0} { append result "\n" }
            append result [::scm::scm $cmd {*}$args]
        } 
    }
    return $result

}

::scm::proc_doc ::scm::get_operation { command } { 
    Check if a command is defined in aliases first. If some
    change the command as found in the alias.
    
    Then check if the command is defined. 
    
    If the command is not defined, return an error 
    with the command name. 
} { 
    if {![catch {::scm::check_alias $command} result]} {
        set command $result
    }
 
    if {![catch {::scm::check_command $command} result]} {
        return -code ok $result
    }

    return -code error $command

}

::scm::proc_doc ::scm::Pop {varname {n 0}} {
    Pop off element n of a list, returning that value.
    
    NOTE: This will also remove the element from the list
          so the list changes.
} { 

    upvar $varname vars

    set result [lindex $vars $n]
    set vars [lreplace $vars $n $n]

    return $result

}

