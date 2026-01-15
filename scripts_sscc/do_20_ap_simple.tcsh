#!/bin/tcsh

# AP: run simple ME-FMRI AP processing (using just a couple runs, for speed)

# Process a single subj. Run it from its partner run*.tcsh script.
# Run on a slurm/swarm system (like Biowulf) or on a desktop.

# ---------------------------------------------------------------------------
# slurm on/off, and set env variables

# use slurm? 1 = yes, 0 = no (def: use if available)
set use_slurm = $?SLURM_CLUSTER_NAME

# *** set relevant environment variables
setenv AFNI_COMPRESSOR GZIP           # zip BRIK dsets

# ----------------------------- biowulf-cmd ---------------------------------
if ( $use_slurm ) then
    # load modules: *** add any other necessary ones
    source /etc/profile.d/modules.csh
    module load afni

    # set N_threads for OpenMP
    setenv OMP_NUM_THREADS $SLURM_CPUS_ON_NODE
endif
# ---------------------------------------------------------------------------

# ----------------------------- session info --------------------------------
# set initial exit code; we don't exit at fail, to copy partial results back
set ecode = 0

# set initial flag for using temp dir (def: not using); can be reset below
set usetemp  = 0

# check available N_threads and report what is being used
set nthr_avail = `afni_system_check.py -disp_num_cpu`
set nthr_using = `afni_check_omp`

echo "++ INFO: Using ${nthr_using} of available ${nthr_avail} threads"
# ---------------------------------------------------------------------------

# --------------------------- read subject ID -------------------------------
# general level version

# set subject component list (can include: site, subj, ses)
set subjli = ( ${argv[1-]} )
echo "++ Have ${#subjli} vals to make labels and paths: ${subjli}"

# set subject ID
if ( ! ${#subjli} ) then
    set ecode = -1
    goto COPY_AND_EXIT
else if ( ${#subjli} < 3 ) then
    # subj or subj_ses
    set subjid = `python -c "print('_'.join(('${subjli}').split()))"`
else if ( ${#subjli} == 3 ) then
    # site_subj_ses
    set subjid = `python -c "print('_'.join(('${subjli}').split()[1:]))"`
else
    set ecode = -1
    goto COPY_AND_EXIT
endif

# set subject data path
set subjpa = `python -c "print('/'.join(('${subjli}').split()))"`
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# top level definitions (paths)
# ---------------------------------------------------------------------------

# upper directories
set dir_inroot     = ${PWD:h}                     # one dir above scripts/
set dir_log        = ${dir_inroot}/logs
set dir_basic      = ${dir_inroot}/data_00_basic
set dir_gtkyd      = ${dir_inroot}/data_01_gtkyd
set dir_deob       = ${dir_inroot}/data_05_deob_slice
set dir_fs         = ${dir_inroot}/data_12_fs
set dir_ssw        = ${dir_inroot}/data_13_ssw
set dir_ap         = ${dir_inroot}/data_20_ap_simple

# subject directories
set sdir_basic     = ${dir_basic}/${subjpa}
set sdir_func      = ${sdir_basic}/func
set sdir_fmap      = ${sdir_basic}/fmap
set sdir_anat      = ${sdir_basic}/anat
set sdir_deob      = ${dir_deob}/${subjpa}
set sdir_fs        = ${dir_fs}/${subjpa}
set sdir_suma      = ${sdir_fs}/SUMA
set sdir_ssw       = ${dir_ssw}/${subjpa}
set sdir_ap        = ${dir_ap}/${subjpa}

set sdir_out       = ${sdir_ap}                 # *** set output directory
set lab_out        = ${sdir_out:t}

# supplementary directories and info
set dir_suppl      = ${dir_inroot}/supplements
set template       = MNI152_2009_template_SSW.nii.gz

# --------------------------------------------------------------------------
# data and control variables
# --------------------------------------------------------------------------

# dataset inputs

# EPI dset names
##set taskname  = rest
##set label     = task-${taskname}
set label       = ""
set dset_epi_r1 = ( ${sdir_deob}/func/${subjid}*${label}*run-1_echo*.nii* )
set dset_epi_r2 = ( ${sdir_deob}/func/${subjid}*${label}*run-2_echo*.nii* )

if ( ! ${#dset_epi_r1} || ! ${#dset_epi_r2} ) then
    set ecode = 1
    goto COPY_AND_EXIT
endif

# anatomical dset names
set dset_anat = ( ${sdir_deob}/anat/${subjid}_*T1w.nii* )

if ( ${#dset_anat} != 1 ) then
    set ecode = 2
    goto COPY_AND_EXIT
endif

# control variables
set nt_rm = 0                    # number of time points to remove at start


# ----------------------------- biowulf-cmd --------------------------------
if ( $use_slurm ) then
    # try to use /lscratch for speed; store "real" output dir for later copy
    if ( -d /lscratch/$SLURM_JOBID ) then
        set usetemp  = 1
        set sdir_BW  = ${sdir_out}
        set sdir_out = /lscratch/$SLURM_JOBID/${subjid}

        # prep for group permission reset
        \mkdir -p ${sdir_BW}
        set grp_own  = `\ls -ld ${sdir_BW} | awk '{print $4}'`
    endif
endif
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# run programs
# ---------------------------------------------------------------------------

# make output directory and jump to it
\mkdir -p ${sdir_out}

cd ${sdir_out}

# create command script
set run_script = ap.cmd.${subjid}

cat << EOF >! ${run_script}

# AP: rest FMRI, simple
#
# single echo FMRI, simple processing for initial QC
# anatomical has skull on
#
# ============================================================================

ap_run_simple_rest_me.tcsh                                             \
    -run_ap                                                            \
    -subjid      ${subjid}                                             \
    -nt_rm       ${nt_rm}                                              \
    -anat        ${dset_anat}                                          \
    -epi_me_run  ${dset_epi_r1}                                        \
    -epi_me_run  ${dset_epi_r2}                                        \
    -echo_times  19.7  25.89  42.08                                    \
    -template    ${template}

EOF

if ( ${status} ) then
    set ecode = 3
    goto COPY_AND_EXIT
endif


# execute AP command to make processing script
tcsh -xef ${run_script} |& tee output.ap.cmd.${subjid}

if ( ${status} ) then
    set ecode = 4
    goto COPY_AND_EXIT
endif


# execute the proc script, saving text info
time tcsh -xef proc.${subjid} |& tee output.proc.${subjid}

if ( ${status} ) then
    set ecode = 5
    goto COPY_AND_EXIT
endif

echo "++ FINISHED ${lab_out}"

# ---------------------------------------------------------------------------

COPY_AND_EXIT:

# ----------------------------- biowulf-cmd --------------------------------
if ( $use_slurm ) then
    # if using /lscratch, copy back to "real" location
    if( ${usetemp} && -d ${sdir_out} ) then
        echo "++ Used /lscratch"
        echo "++ Copy from: ${sdir_out}"
        echo "          to: ${sdir_BW}"
        \cp -pr   ${sdir_out}/* ${sdir_BW}/.

        # reset group permission
        chgrp -R ${grp_own} ${sdir_BW}
    endif
endif
# ---------------------------------------------------------------------------

if ( ${ecode} ) then
    echo "++ BAD FINISH: ${lab_out} (ecode = ${ecode})"
else
    echo "++ GOOD FINISH: ${lab_out}"
endif

exit ${ecode}

