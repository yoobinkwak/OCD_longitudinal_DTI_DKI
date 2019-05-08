#!/bin/bash
for subj in $@
do
       

######## DKI Preprocessing ########

    ## change file name for conveniecne ##
    if [ ! -e ${subj}/DKI/bvals ] ; then
        #DKI-preprocessing1. name change
        mv $subj/DKI/*bval $subj/DKI/bvals
        mv $subj/DKI/*bvec $subj/DKI/bvecs
        cp -r $subj/DKI/*.nii.gz $subj/DKI/data.nii.gz
    fi

    ##### Eddy current correction ####
    if [ ! -e ${subj}/DKI/data.ecc* ] ; then
        eddy_correct $subj/DKI/data.nii.gz $subj/DKI/data 0
    fi
    
    ##### B0 image extraction ####
    if [ ! -e ${subj}/DKI/nodif.nii.gz ] ; then
        fslroi $subj/DKI/data.nii.gz $subj/DKI/nodif 0 1
    fi

    #### Bet brain extraction ####
    if [ ! -e ${subj}/DKI/nodif_brain.nii.gz ] ; then
        bet $subj/DKI/nodif $subj/DKI/nodif_brain -m -f 0.30
    fi
    
    #### FDT_DTIFIT with DKI####
    if [ ! -e ${subj}/DKI/dti_FA.nii.gz ] ; then
    #if [ ! -e ${subj}/DKI/dki_FA.nii.gz ] ; then
        dtifit -k $subj/DKI/data -m $subj/DKI/nodif_brain_mask -r $subj/DKI/bvecs -b $subj/DKI/bvals -o $subj/DKI/dti
        #dtifit -k $subj/DKI/data -m $subj/DKI/nodif_brain_mask -r $subj/DKI/bvecs -b $subj/DKI/bvals -o $subj/DKI/dki
    fi
    

######## Registration ########

    T1Dir=${subj}/T1
    fsDir=${subj}/FREESURFER
    rawT1=${subj}/T1/20*nii.gz
    reorient_rawT1=${subj}/T1/reorient_rawT1.nii.gz
    rawT1_mask_mgz=${fsDir}/mri/brainmask.mgz
    rawT1_mask=${fsDir}/mri/brainmask_in_rawavg.nii.gz
    reorient_rawT1_mask=${fsDir}/mri/brainmask_in_rawavg_reorient.nii.gz
    reorient_rawT1_mask_bin=${fsDir}/mri/bin_brainmask_in_rawavg_reorient.nii.gz
    reorient_rawT1_brain=${subj}/T1/reorient_rawT1_brain.nii.gz
    
    mni=${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz
    mniMask=${FSLDIR}/data/standard/MNI152_T1_2mm_brain_mask.nii.gz
    
    dkiDir=${subj}/DKI
    regDir=${dkiDir}/Registration
    if [ ! -e ${regDir} ] ; then
        mkdir ${regDir}
    fi
    
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

    #### T1 to DKI ####
    reorient_t1w2nodif="${regDir}/reorient_t1w2nodifDKI"
    if [ ! -e ${reorient_t1w2nodif}.mat ] ; then
	    flirt -in ${reorient_rawT1_brain} -ref ${dkiDir}/nodif_brain.nii.gz -omat ${reorient_t1w2nodif}.mat -out ${reorient_t1w2nodif}.nii.gz -cost mutualinfo -dof 6 -searchrx -180 180 -searchry -180 180 -searchrz -180 180 
    fi

    #### MNI to T1 to DKI #### 
    reorient_mni2t1w2nodif=${regDir}/mni2reorient_t1w2nodifDKI_coeff.nii.gz
    if [ ! -e ${reorient_mni2t1w2nodif} ] ; then
	    convertwarp --ref=${dkiDir}/nodif_brain.nii.gz --warp1=${reorient_mni2t1w_fnirt} --postmat=${reorient_t1w2nodif}.mat --out=${reorient_mni2t1w2nodif}
    fi

    reorient_nodif2t1w2mni=${regDir}/reorient_nodifDKI2t1w2mni_coeff.nii.gz
    if [ ! -e ${reorient_nodif2t1w2mni} ] ; then
	    invwarp -w ${reorient_mni2t1w2nodif} -o ${reorient_nodif2t1w2mni} -r ${mni}
    fi


    ## FS to Diffusion ##

    FS2DKI_mat=${regDir}/FREESURFERT1toNodifDKI.mat 
    if [ ! -e ${FS2DKI_mat} ] ; then
        /usr/local/fsl/bin/flirt \
            -in ${subj}/FREESURFER/mri/brain.nii.gz \
            -ref ${subj}/DKI/nodif_brain.nii.gz \
            -out ${regDir}/FREESURFERT1toNodifDKI \
            -omat ${regDir}/FREESURFERT1toNodifDKI.mat \
            -bins 256 \
            -cost mutualinfo \
            -searchrx -180 180 \
            -searchry -180 180 \
            -searchrz -180 180 \
            -dof 6  -interp trilinear
    fi

    DKI2FS_mat=${regDir}/NodifDKItoFREESURFERT1.mat
    if [ ! -e ${DKI2FS_mat} ] ; then
        convert_xfm -omat ${DKI2FS_mat} -inverse ${FS2DKI_mat}
    fi
           
    FS2DTI_mat=${subj}/DTI/Registration/FREESURFERT1toNodif.mat 
    if [ ! -e ${FS2DTI_mat} ] ; then
        /usr/local/fsl/bin/flirt \
            -in ${subj}/FREESURFER/mri/brain.nii.gz \
            -ref ${subj}/DTI/nodif_brain.nii.gz \
            -out ${subj}/DTI/Registraion/FREESURFERT1toNodif \
            -omat ${subj}/DTI/Registraion/FREESURFERT1toNodif.mat \
            -bins 256 \
            -cost mutualinfo \
            -searchrx -180 180 \
            -searchry -180 180 \
            -searchrz -180 180 \
            -dof 6  -interp trilinear
        fi

    DTI2FS_mat=${subj}/DTI/Registration/NodiftoFREESURFERT1.mat
    if [ ! -e ${DTI2FS_mat} ] ; then
        convert_xfm -omat ${DTI2FS_mat} -inverse ${FS2DTI_mat}
    fi


    #### Targets to Diffusion ####
    
    for side in left right
    do
        case $side in
            left)
                sside=lh
                ;;
            right)
                sside=rh
                ;;
        esac

        for cortex in SMC PC OFC OCC MTC MPFC LTC LPFC thalamus
        do
            mask=${subj}/ROI/${sside}_${cortex}.nii.gz
            mask_dti=${subj}/ROI/dti_${sside}_${cortex}.nii.gz
            if [ ! -e ${mask_dti} ] ; then
               flirt \
                    -in ${mask} \
                    -ref ${subj}/DTI/nodif_brain.nii.gz \
                    -applyxfm -init ${FS2DTI_mat} \
                    -interp nearestneighbour \
                    -out ${mask_dti}
            fi

            mask_dki=${subj}/ROI/dki_${sside}_${cortex}.nii.gz
            if [ ! -e ${mask_dki} ]
            then
                flirt \
                    -in ${mask} \
                    -ref ${dkiDir}/nodif_brain.nii.gz \
                    -applyxfm -init ${FS2DKI_mat} \
                    -interp nearestneighbour \
                    -out ${mask_dki}
            fi
        done
        
        for cortex in caudalMotor cognitive limbic rostralMotor parietal temporal occipital
        do

            mask=striatum_masks/ROIs/${sside}_${cortex}_GMmasked_2mm.nii.gz
            mask_dti=${subj}/ROI/dti_${sside}_${cortex}.nii.gz
            if [ ! -e ${mask_dti} ] ; then
               flirt \
                    -in ${mask} \
                    -ref ${subj}/DTI/nodif_brain.nii.gz \
                    -applyxfm -init ${FS2DTI_mat} \
                    -interp nearestneighbour \
                    -out ${mask_dti}
            fi

            mask_dki=${subj}/ROI/dki_${sside}_${cortex}.nii.gz
            if [ ! -e ${mask_dki} ]
            then
                flirt \
                    -in ${mask} \
                    -ref ${dkiDir}/nodif_brain.nii.gz \
                    -applyxfm -init ${FS2DKI_mat} \
                    -interp nearestneighbour \
                    -out ${mask_dki}
            fi
        done
    done


    #### Thresholding ####
    
    for segDir in ${subj}/Segmentation_KCho ${subj}/Segmentation_YKwak
    do
        for side in left right
        do
            if [ "$side" == "left" ] ; then
                sside='lh'
            else
                sside='rh'
            fi
            
            ## find the bigest ##
            
            if [ ! -e ${segDir}/${side}/biggest.nii.gz ] ; then
                find_the_biggest ${segDir}/${side}/seed* ${segDir}/${side}/biggest.nii.gz
            fi

            if [ ! -e ${segDir}/${side}/dki_biggest.nii.gz ] ; then
                flirt \
                    -in ${segDir}/${side}/biggest.nii.gz \
                    -ref ${dkiDir}/nodif_brain.nii.gz \
                    -applyxfm -init ${FS2DTI_mat} \
                    -interp nearestneighbour \
                    -out ${segDir}/${side}/dki_biggest.nii.gz
            fi

            for imgs in ${segDir}/${side}/seeds*
            do
                filename=`basename "${imgs}"`
                if [ ! -e ${segDir}/${side}/dki_${filename} ] ; then
                    flirt \
                        -in ${imgs} \
                        -ref ${dkiDir}/nodif_brain.nii.gz \
                        -applyxfm -init ${FS2DKI_mat} \
                        -out ${segDir}/${side}/dki_${filename}
                fi
            done

            for thr in 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95
            do
                if [ ! -d ${segDir}/${side}/${thr}thrP ] ; then
                    mkdir ${segDir}/${side}/${thr}thrP

                fi

                for imgs in ${segDir}/${side}/seeds*
                do
                    filename=`basename "${imgs}"`

                    if [ ! -e ${segDir}/${side}/${thr}thrP/${thr}_${filename} ] ; then
                        fslmaths ${imgs} -thrP ${thr} \
                        ${segDir}/${side}/${thr}thrP/${thr}_${filename}
                    fi

                    if [ ! -e ${segDir}/${side}/${thr}thrP/dki_${thr}_${filename} ] ; then
                        flirt \
                            -in ${segDir}/${side}/${thr}thrP/${thr}_${filename} \
                            -ref ${dkiDir}/nodif_brain.nii.gz \
                            -applyxfm -init ${FS2DKI_mat} \
                            -out ${segDir}/${side}/${thr}thrP/dki_${thr}_${filename}
                    fi
                done


            
                if [ ! -e ${segDir}/${side}/${thr}thrP/${thr}_biggest.nii.gz ] ; then
                    find_the_biggest ${segDir}/${side}/${thr}thrP/${thr}_seeds* \
                        ${segDir}/${side}/${thr}thrP/${thr}_biggest.nii.gz
                fi

            
#                if [ ! -e ${segDir}/${side}/${thr}thrP/dki_${thr}_biggest.nii.gz ] ; then
#                    find_the_biggest ${segDir}/${side}/${thr}thrP/dki_*seeds* \
#                        ${segDir}/${side}/${thr}thrP/dki_${thr}_biggest.nii.gz
#                fi
            done
        done
    done


    #### MNI Targets to subject's T1 ####
    Str_MNImask_dir=striatum_masks/ROIs/
    Str_T1mask_dir=${subj}/ROI

    for side in left right
    do
        case ${side} in
            left)
                sside=lh
                ;;
            right)
                sside=rh
                ;;
        esac

        for cortex in caudalMotor cognitive limbic rostralMotor parietal temporal occipital
        do
            MNI_mask=${Str_MNImask_dir}/${sside}_${cortex}_GMmasked_2mm.nii.gz
            T1_mask=${Str_T1mask_dir}/${sside}_${cortex}.nii.gz

            if [ ! -e ${T1_mask} ] ; then
                applywarp \
                    -r ${T1Dir}/reorient_rawT1_brain.nii.gz \
                    -i ${MNI_mask} \
                    -w ${subj}/DTI/Registration/reorient_mni2t1w_fnirt_coeff.nii.gz \
                    -o ${T1_mask}
            fi
        done

        T1_striatum=${Str_T1mask_dir}/${sside}_striatum.nii.gz
        if [ ! -e ${T1_striatum} ] ; then
                applywarp \
                    -r ${T1Dir}/reorient_rawT1_brain.nii.gz \
                    -i ${Str_MNImask_dir}/${sside}_striatum.nii.gz \
                    -w ${subj}/DTI/Registration/reorient_mni2t1w_fnirt_coeff.nii.gz \
                    -o ${T1_striatum}
        fi
    done
    
    if [ ! -e ${subj}/DKI/kmean.nii ] ; then 
        cp -r run_DKI/${subj}/${subj}_kmean.nii ${subj}/DKI/kmean.nii
    fi

done
