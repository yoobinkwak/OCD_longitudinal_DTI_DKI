import os
from os.path import join, basename, dirname, isfile, isdir
import re
from multiprocessing import Pool
import sys


dataLoc = '/Volumes/CCNC_4T/OCD_longitudinal_20180611/analyses/BL'
cortices = [ 'caudalMotor', 'cognitive', 'limbic', 'rostralMotor', 'parietal', 'temporal', 'occipital' ] 

class subject:
    def __init__(self, subject):
        self.gpu_num = 0
        self.subject = subject
        self.subject_dir = join(dataLoc, subject)
        self.segmentation_dir = join(self.subject_dir, 'Segmentation_YKwak')
        self.bedpost_dir = join(self.subject_dir, 'DTI.bedpostX')
        self.reg_dir = join(self.subject_dir, 'DTI/Registration')
        self.left_seg_dir = join(self.segmentation_dir, 'left')
        self.right_seg_dir = join(self.segmentation_dir, 'right')

def run_commands(subject_class):
    for directory in [subject_class.segmentation_dir, subject_class.left_seg_dir, subject_class.right_seg_dir]:
        try:
            os.mkdir(directory)
        except:
            pass

    ROI_dir = 'striatum_masks/ROIs'
    commands = []
    for sside, side in zip(['lh', 'rh'], ['left', 'right']):
        with open(join(subject_class.segmentation_dir, side, 'targets.txt'), 'w') as f:
            for cortex in cortices:
                f.write(join(ROI_dir, '{}_{}_GMmasked_2mm.nii.gz'.format(sside, cortex)) +'\n')

        command = 'CUDA_VISIBLE_DEVICES={gpu_num} /usr/local/fsl/bin/probtrackx2_gpu \
            -x {striatal_roi} \
            -l \
            --onewaycondition \
            -c 0.2 \
            -S 2000 \
            --steplength=0.5 \
            -P 5000 \
            --fibthresh=0.01 \
            --distthresh=0.0 \
            --sampvox=0.0 \
            --forcedir \
            --opd \
            -s {bedpostDir}/merged \
            -m {bedpostDir}/nodif_brain_mask \
            --xfm={reorient_mni2t1w2nodif} \
            --invxfm={reorient_nodif2t1w2mni} \
            --dir={outdir} \
            --targetmasks={targets} \
            --os2t'.format(gpu_num=subject_class.gpu_num,
                           striatal_roi = join(ROI_dir, '{}_striatum.nii.gz'.format(sside)),
                           bedpostDir = subject_class.bedpost_dir,
                           reorient_mni2t1w2nodif = join(subject_class.reg_dir, 'mni2reorient_t1w2nodif_coeff.nii.gz'),
                           reorient_nodif2t1w2mni = join(subject_class.reg_dir, 'reorient_nodif2t1w2mni_coeff.nii.gz'),
                           outdir = join(subject_class.segmentation_dir, side),
                           targets = join(subject_class.segmentation_dir, side, 'targets.txt'))
        if not isfile(join(subject_class.segmentation_dir, side, 'fdt_paths.nii.gz')):
            commands.append(re.sub('\s+', ' ', command))
    subject_class.commands = ';'.join(commands)
    os.popen(subject_class.commands).read()

def run_probtrackx_parallel(subject_classes):
    pool = Pool(processes=7)
    # minimum number of commands in different GPUs
    print(subject_classes.keys())
    min_num = min([len(x) for x in subject_classes.values()])
    print(min_num)
    for num in range(min_num):
        batch_subject_classes = [x[num] for x in subject_classes.values()]
        pool.map(run_commands, batch_subject_classes)

    batch_subject_classes = []
    for i in subject_classes.values():
        if len(i)>min_num:
            batch_subject_classes += i
    pool.map(run_commands, batch_subject_classes)

if __name__ == '__main__':
    data_dir = join(dirname(os.getcwd()), 'BL')
    subject_classes = [subject(join(data_dir, x)) for x in os.listdir(data_dir) if re.search('(DNO|NOR|UMO)\d+', x)]

    # For multi-gpu support
    new_subject_classes = {0:[], 1:[], 2:[],
                           3:[], 4:[], 5:[], 6:[]}
    gpu_num=0
    for subject_class in subject_classes:
        current_subject_list = new_subject_classes[gpu_num]
        subject_class.gpu_num = gpu_num
        print(subject_class.gpu_num)
        current_subject_list += [subject_class]
        new_subject_classes[gpu_num] = current_subject_list
        if gpu_num == 6:
            gpu_num = 0
        else:
            gpu_num+=1

    #print([[y.gpu_num for y in x] for x in new_subject_classes.values()])
    run_probtrackx_parallel(new_subject_classes)
    #run_bedpostx(new_subject_classes)



