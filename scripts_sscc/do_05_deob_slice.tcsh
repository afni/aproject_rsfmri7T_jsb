#!/bin/tcsh

# DEOBandSLICE: deoblique any anatomical that has obliquity, and add slice
# timing info to any FMRI dset that has it

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

# subject directories
set sdir_basic     = ${dir_basic}/${subjpa}
set sdir_func      = ${sdir_basic}/func
set sdir_fmap      = ${sdir_basic}/fmap
set sdir_anat      = ${sdir_basic}/anat
set sdir_deob      = ${dir_deob}/${subjpa}

set sdir_out       = ${sdir_deob}                 # *** set output directory
set lab_out        = ${sdir_out:t}

# supplementary directories and info
set dir_suppl      = ${dir_inroot}/supplements
set template       = ${dir_suppl}/MNI152_2009_template_SSW.nii.gz

# --------------------------------------------------------------------------
# data and control variables
# --------------------------------------------------------------------------

# dataset inputs: find each dset (and json) with full paths

# EPI data: >=1 FMRI dset
set taskname = rest
set label    = task-${taskname}
set dset_epi = `find ${sdir_func} -name "${subjid}*${label}*_bold.nii*" \
                    | sort`
set json_epi = `find ${sdir_func} -name "${subjid}*${label}*_bold.json" \
                    | sort`

if ( ! ${#dset_epi} ) then
    set ecode = 1
    goto COPY_AND_EXIT
endif

# fmap data: 1 rev (this is really a reverse phase encode dset)
set dset_rev = `find ${sdir_fmap} -name "${subjid}*${label}*fmap.nii*" \
                    | sort`
set json_rev = `find ${sdir_fmap} -name "${subjid}*${label}*fmap.json" \
                    | sort`

if ( ${#dset_rev} != 1 ) then
    set ecode = 2
    goto COPY_AND_EXIT
endif

# anat data: 1 acq-uni T1w
set dset_anat = `find ${sdir_anat} -name "${subjid}*acq-uni*T1w.nii*" \
                    | sort`
set json_anat = `find ${sdir_anat} -name "${subjid}*acq-uni*T1w.json" \
                    | sort`

if ( ${#dset_anat} != 1 ) then
    set ecode = 3
    goto COPY_AND_EXIT
endif

# control variables
# ***

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

\mkdir -p anat
\mkdir -p func
\mkdir -p fmap

# 1) anat + epi: remove obl from anat and apply to EPIs; copy both with jsons

echo "++ Proc 1, obl: ${dset_anat}"

# remove obl from anat, copy it to new dir, and apply to EPIs
set base_anat = `basename ${dset_anat}`
obliquity_remover.py                                                  \
    -inset            ${dset_anat}                                    \
    -prefix           anat/${base_anat}                               \
    -child_dsets      ${dset_epi}                                     \
    -child_outdir     func

if ( ${status} ) then
    set ecode = 6
    goto COPY_AND_EXIT
endif

# json anat: copy if present
foreach json ( ${json_anat} ) 
    \cp ${json} anat/.
end

# json epi: copy if present
foreach json ( ${json_epi} ) 
    \cp ${json} func/.
end

# 2) anat + fmap: remove obl from anat and apply to EPIs; copy both with jsons
#                 BUT also treat anat here like tmp file and remove (bc it has
#                 already been processed+copied above)

echo "++ Proc 2, obl: ${dset_anat}"

# remove obl from anat, copy it to new dir, and apply to EPIs
obliquity_remover.py                                                  \
    -inset            ${dset_anat}                                    \
    -prefix           anat/TMP.nii                                    \
    -child_dsets      ${dset_rev}                                     \
    -child_outdir     fmap

if ( ${status} ) then
    set ecode = 7
    goto COPY_AND_EXIT
endif

# json fmap: copy if present
foreach json ( ${json_rev} ) 
    \cp ${json} fmap/.
end

# clean up extraneous anat dset copy
\rm anat/TMP.nii anat/TMP_mat*.aff12.1D

# 3) EPI: add slice timing to header if present in jsons
echo "++ Proc 3, slicetime"

cd func

foreach full_json ( ${json_epi} )
    # name pieces: no path, and no ext
    set json = `basename ${full_json}`
    set json_root = `basename ${json} .json`

    # get associated dset
    set dset = ( ${json_root}.nii* )
    if ( ${#dset} != 1 ) then
        set ecode = 11
        goto COPY_AND_EXIT
    endif

    # check for slice timing in JSON, and add to dset header if present
    set check_st = `abids_json_info.py                    \
                        -json   ${json}                   \
                        -field  SliceTiming`
    if ( "${check_st}" != "None" ) then
        echo "++ Attach slice timing for: ${dset}"
        abids_tool.py                                     \
            -add_slice_times                              \
            -input            ${dset}
    else
        echo "+* No SliceTiming to copy: ${json}"
    endif
end


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

