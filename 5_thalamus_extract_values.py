import pandas as pd
import os
import re
import numpy as np
import nibabel
import argparse
import textwrap
import time
from multiprocessing import Pool
from numpy import count_nonzero
import statsmodels
import itertools

import matplotlib
import matplotlib.pyplot as plt
import seaborn as sns

from statsmodels.formula.api import ols
from statsmodels.stats.anova import anova_lm
from scipy import stats


dataLoc = '/Volumes/CCNC_4T/OCD_longitudinal_20180611/analyses/BL'
cortices = [ 'SMC', 'PC', 'OFC', 'OCC', 'MTC', 'MPFC', 'LTC', 'LPFC']
subjects = [x for x in os.listdir(dataLoc) if x.startswith('NOR') or x.startswith('DNO') or x.startswith('UMO')]


def get_map(f):
    '''
    Load nifti file and return the data matrix of the image file
    '''
    return nibabel.load(f).get_data()


class thalamus:
    def __init__(self, param):
        # Expand from the input tuple
        dataLoc, subject = param

        subjDir = os.path.join(dataLoc, subject)
        roiDir = os.path.join(subjDir, 'ROI')
        dkiDir = os.path.join(subjDir, 'DKI')
        dtiDir = os.path.join(subjDir, 'DTI')
        fsDir = os.path.join(subjDir, 'FREESURFER')

        ## Intracranial volume
        with open(os.path.join(fsDir, 'stats', 'aseg.stats'), 'r') as f:
            lines = f.read()
        intra_vol = float(re.search('Intracranial Volume, (\d+\.\d+)', lines).group(1))

        df = pd.DataFrame()

        for side_s in 'lh', 'rh':
            if side_s=='lh':
                side = 'left'
            else:
                side = 'right'

            segDir = os.path.join(subjDir, 'Segmentation_KCho', side)

            # MK file in original diffusion space
            mk_file = os.path.join(dkiDir, 'kmean.nii')
            mk_map = get_map(mk_file)


            ## Save the volume of the thalamus (in FS space) in self.thalamus_vol
            thalamus_file = os.path.join(roiDir, '{0}_thalamus.nii.gz'.format(side_s))
            thalamus_map = get_map(thalamus_file)
            thalamus_vol = count_nonzero(thalamus_map)

            for cortex in cortices:
                seeds_in_raw = os.path.join(segDir, 'seeds_to_{side_s}_{cortex}.nii.gz'.format(side_s=side_s, cortex=cortex))
                seeds_in_raw_map = get_map(seeds_in_raw)
                total_connectivity_raw = sum(seeds_in_raw_map[seeds_in_raw_map != 0])

                cortical_roi = os.path.join(roiDir, '{side}_{cortex}.nii.gz'.format(side=side_s, cortex=cortex))
                cortex_map = get_map(cortical_roi)
                cortical_roi_vol = count_nonzero(cortex_map)

                for threshold in ['5', '10', '20', '90', '95']:
                    thrDir = os.path.join(segDir, threshold+'thrP')


                    # seeds file in DTI space
                    seeds_in_dti = os.path.join(thrDir, '{threshold}_seeds_to_{side_s}_{cortex}.nii.gz'.format(side_s=side_s, cortex=cortex, threshold=threshold))
                    seeds_in_dti_map = get_map(seeds_in_dti)
                    dti_total_connectivity = sum(seeds_in_dti_map[seeds_in_dti_map != 0])
                    dti_thal_seg_volume = count_nonzero(seeds_in_dti_map)


                    # seeds file in DKI space
                    seeds_in_dki = os.path.join(thrDir, 'dki_{threshold}_seeds_to_{side_s}_{cortex}.nii.gz'.format(side_s=side_s, cortex=cortex, threshold=threshold))
                    seeds_in_dki_map = get_map(seeds_in_dki)
                    dki_total_connectivity = sum(seeds_in_dki_map[seeds_in_dki_map != 0])
                    dki_thal_seg_volume = count_nonzero(seeds_in_dki_map)
                    thal_seg_mk = np.mean(mk_map[(seeds_in_dki_map > 0) & (mk_map != 0)])

                    df = pd.concat([df,
                                    pd.DataFrame([[subject, side, cortex, threshold,
                                                   intra_vol,
                                                   cortical_roi_vol,
                                                   thalamus_vol, 
                                                   dti_thal_seg_volume, 
                                                   dti_total_connectivity,
                                                   thal_seg_mk,
                                                   dki_total_connectivity,
                                                   dki_thal_seg_volume, 
                                                   total_connectivity_raw]],
                                                 columns = ['subject',
                                                            'side',
                                                            'cortex',
                                                            'threshold',
                                                            'intra_vol',
                                                            'cortex_volume', 
                                                            'thalamus_volume',
                                                            'dti_thalamus_seg_volume', 
                                                            'dti_total_connectivity',
                                                            'thalamus_seg_mk',
                                                            'dki_total_connectivity',
                                                            'dki_thalamus_seg_volume', 
                                                            'total_connectivity_raw']),
                               ])
        self.df = df.reset_index().drop('index', axis=1)


f = thalamus((dataLoc, subjects[0]))

a = [[dataLoc], subjects]
all_combinations = list(itertools.product(*a))
pool = Pool()
outs = pool.map(thalamus, all_combinations)
merged_df = pd.concat([x.df for x in outs])
merged_df.to_csv('/Volumes/CCNC_4T/OCD_longitudinal_20180611/analyses/BL/BL_thalamus.csv')




