#!/bin/bash
for subj in $@
do
       

######## DTI Preprocessing ########

    ## change file name for conveniecne ##
    if [ ! -e ${subj}/DTI/bvals ] ; then
        #DTI-preprocessing1. name change
        mv $subj/DTI/*bval $subj/DTI/bvals
        mv $subj/DTI/*bvec $subj/DTI/bvecs
        cp -r $subj/DTI/*.nii.gz $subj/DTI/data.nii.gz
    fi

    ##### Eddy current correction ####
    if [ ! -e ${subj}/DTI/data.ecc* ] ; then
        eddy_correct $subj/DTI/data.nii.gz $subj/DTI/data 0
    fi
    
    ##### B0 image extraction ####
    if [ ! -e ${subj}/DTI/nodif.nii.gz ] ; then
        fslroi $subj/DTI/data.nii.gz $subj/DTI/nodif 0 1
    fi

    #### Bet brain extraction ####
    if [ ! -e ${subj}/DTI/nodif_brain.nii.gz ] ; then
        bet $subj/DTI/nodif $subj/DTI/nodif_brain -m -f 0.30
    fi
    
    #### FDT_DTIFIT ####
    if [ ! -e ${subj}/DTI/dti_FA.nii.gz ] ; then
        dtifit -k $subj/DTI/data -m $subj/DTI/nodif_brain_mask -r $subj/DTI/bvecs -b $subj/DTI/bvals -o $subj/DTI/dti
    fi
    
    #### Bedpostx ####
    ## RAN WITH GPU SERVER VERSION ##
#    if [ ! -e ${subj}/DTI.bedpostX/merged_th2samples.nii.gz ] ; then
#        bedpostx $subj/DTI 
#    else
#        echo ${subj} 'Bedpost is done'
#    fi

######## T1 Preprocessing ########

    T1Dir=${subj}/T1
    fsDir=${subj}/FREESURFER
    rawT1=${subj}/T1/20*nii.gz
    reorient_rawT1=${subj}/T1/reorient_rawT1.nii.gz
    rawT1_mask_mgz=${fsDir}/mri/brainmask.mgz
    rawT1_mask=${fsDir}/mri/brainmask_in_rawavg.nii.gz
    reorient_rawT1_mask=${fsDir}/mri/brainmask_in_rawavg_reorient.nii.gz
    reorient_rawT1_mask_bin=${fsDir}/mri/bin_brainmask_in_rawavg_reorient.nii.gz
    reorient_rawT1_brain=${subj}/T1/reorient_rawT1_brain.nii.gz
    
    ## Remove unncessary SCOUT images ##
    rm -rf ${T1Dir}/*SCOUT*

    #### T1 brain extraction ####
    
    ## Freesurfer for brain mask ##
    if [ -e ${T1Dir}/FREESURFER/mri/brainmask.mgz ] ; then
        mv ${T1Dir}/FREESURFER ${subj}/
    fi

#    if [ ! -e ${subj}/FREESURFER/mri/brainmask.mgz ] ; then
#        export SUBJECTS_DIR=${subj}
#        recon-all -subjid FREESURFER -i ${subj}/T1/20*.nii.gz -autorecon1
#    fi

    ## Reorient T1 ##
    if [ ! -e ${reorient_rawT1} ] ; then
	    fslreorient2std ${rawT1} ${reorient_rawT1}
    fi

    ## Convert Freesurfer brain mask to nifti, reorient, & binazrize ##
    if [ ! -e ${reorient_rawT1_mask_bin} ] ; then
        mri_vol2vol --mov ${rawT1_mask_mgz} --targ ${fsDir}/mri/rawavg.mgz --regheader --o ${fsDir}/mri/brainmask_in_rawavg.mgz --no-save-reg
        mri_convert ${fsDir}/mri/brainmask_in_rawavg.mgz ${rawT1_mask}
        fslreorient2std ${rawT1_mask} ${reorient_rawT1_mask}
        fslmaths ${reorient_rawT1_mask} -bin ${reorient_rawT1_mask_bin}
    fi

    ## Mask T1 with brain mask ##
    if [ ! -e ${reorient_rawT1_brain} ] ; then
	    fslmaths ${reorient_rawT1} -mas ${reorient_rawT1_mask_bin} ${reorient_rawT1_brain}
    fi


######## Registration ########

    dtiDir=${subj}/DTI
    regDir=${dtiDir}/Registration
    if [ ! -e ${regDir} ] ; then
        mkdir ${regDir}
    fi
    mni=${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz
    mniMask=${FSLDIR}/data/standard/MNI152_T1_2mm_brain_mask.nii.gz
    
    #### T1 to MNI ####
    ## FLIRT ##
    reorient_t1w2mni_flirt="${regDir}/reorient_t1w2mni"
    if [ ! -e ${reorient_t1w2mni_flirt}.mat ] ; then
	    flirt -in ${reorient_rawT1_brain} -ref ${mni} -omat ${reorient_t1w2mni_flirt}.mat -out ${reorient_t1w2mni_flirt}.nii.gz -cost mutualinfo -dof 12 -searchrx -180 180 -searchry -180 180 -searchrz -180 180 #-usesqform
    fi
    
    ## FNIRT ##
    reorient_t1w2mni_fnirt=${regDir}/reorient_t1w2mni_fnirt_coeff.nii.gz
    reorient_t1w2mni_fnirt_img=${regDir}/reorient_t1w2mni_fnirt_img.nii.gz
    if [ ! -e ${reorient_t1w2mni_fnirt} ] ; then
	    fnirt --in=${reorient_rawT1_brain} --ref=${mni} --aff=${reorient_t1w2mni_flirt}.mat --inmask=${reorient_rawT1_mask_bin} --refmask=${mniMask} --cout=${reorient_t1w2mni_fnirt}  --iout=${reorient_t1w2mni_fnirt_img}
    fi

    reorient_mni2t1w_fnirt=${regDir}/reorient_mni2t1w_fnirt_coeff.nii.gz
    if [ ! -e ${reorient_mni2t1w_fnirt} ] ; then
	    invwarp -w ${reorient_t1w2mni_fnirt} -o ${reorient_mni2t1w_fnirt} -r ${reorient_rawT1_brain}
    fi

    #### T1 to DTI ####
    reorient_t1w2nodif="${regDir}/reorient_t1w2nodif"
    if [ ! -e ${reorient_t1w2nodif}.mat ] ; then
	    flirt -in ${reorient_rawT1_brain} -ref ${dtiDir}/nodif_brain.nii.gz -omat ${reorient_t1w2nodif}.mat -out ${reorient_t1w2nodif}.nii.gz -cost mutualinfo -dof 6 -searchrx -180 180 -searchry -180 180 -searchrz -180 180 
    fi

    #### MNI to T1 to DTI #### 
    reorient_mni2t1w2nodif=${regDir}/mni2reorient_t1w2nodif_coeff.nii.gz
    if [ ! -e ${reorient_mni2t1w2nodif} ] ; then
	    convertwarp --ref=${dtiDir}/nodif_brain.nii.gz --warp1=${reorient_mni2t1w_fnirt} --postmat=${reorient_t1w2nodif}.mat --out=${reorient_mni2t1w2nodif}
    fi

    reorient_nodif2t1w2mni=${regDir}/reorient_nodif2t1w2mni_coeff.nii.gz
    if [ ! -e ${reorient_nodif2t1w2mni} ] ; then
	    invwarp -w ${reorient_mni2t1w2nodif} -o ${reorient_nodif2t1w2mni} -r ${mni}
    fi




######## For Cortical Target Extraction ########
    
#    if [ ! -e ${subj}/FREESURFER/mri/aparc+aseg.mgz ] ; then      ## RAN AT BI
#        export SUBJECTS_DIR=${subj}
#        recon-all -autorecon2 -subjid FREESURFER
#        recon-all -autorecon3 -subjid FREESURFER
#    fi


    if [ ! -e ${subj}/FREESURFER/mri/brain.nii.gz ]
    then
        mri_convert ${subj}/FREESURFER/mri/brain.mgz ${subj}/FREESURFER/mri/brain.nii.gz
    fi

    if [ ! -e ${regDir}/freesurferT1toNodif.mat ]
        then
            /usr/local/fsl/bin/flirt \
                -in ${subj}/FREESURFER/mri/brain.nii.gz \
                -ref ${subj}/DTI/nodif_brain.nii.gz \
                -out ${regDir}/FREESURFERT1toNodif \
                -omat ${regDir}/FREESURFERT1toNodif.mat \
                -bins 256 \
                -cost mutualinfo \
                -searchrx -180 180 \
                -searchry -180 180 \
                -searchrz -180 180 \
                -dof 6  -interp trilinear
        fi


done








