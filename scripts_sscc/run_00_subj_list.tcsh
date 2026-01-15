#!/bin/tcsh

# MAKE_LISTS: For this heterogeneous data collection, make triaged
# lists of what data is available per session.

# Run on a slurm/swarm system (like Biowulf) or on a desktop.

# To execute:  
#     tcsh RUN_SCRIPT_NAME

# --------------------------------------------------------------------------

# specify script to execute
set cmd           = 00_make_lists

# upper directories
set dir_scr       = $PWD
set dir_inroot    = ..
set dir_log       = ${dir_inroot}/logs
set dir_swarm     = ${dir_inroot}/swarms
set dir_basic     = ${dir_inroot}/data_00_basic

# names for logging and swarming/running
set cdir_log      = ${dir_log}/logs_${cmd}
set scr_swarm     = ${dir_swarm}/swarm_${cmd}.txt
set scr_cmd       = ${dir_scr}/do_${cmd}.tcsh

# --------------------------------------------------------------------------

# create log and swarm dirs
\mkdir -p ${cdir_log}
\mkdir -p ${dir_swarm}

# clear away older swarm script 
if ( -e ${scr_swarm} ) then
    \rm ${scr_swarm}
endif

# --------------------------------------------------------------------------

# order of script execution is important here
tcsh adjunct_00_subj_list.tcsh |& tee ${cdir_log}/log_subj_list.txt

exit 0
