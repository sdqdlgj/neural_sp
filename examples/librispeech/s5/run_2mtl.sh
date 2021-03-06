#!/bin/bash

# Copyright 2020 Kyoto University (Hirofumi Inaguma)
#  Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)

echo ============================================================================
echo "                                LibriSpeech                               "
echo ============================================================================

stage=0
stop_stage=5
gpu=
benchmark=true
speed_perturb=false
stdout=false

### vocabulary
unit=wp           # word/wp/word_char
vocab=10000
wp_type=bpe       # bpe/unigram (for wordpiece)
unit_sub1=phone
wp_type_sub1=bpe  # bpe/unigram (for wordpiece)
vocab_sub1=

#########################
# ASR configuration
#########################
conf=conf/asr/blstm_las_2mtl.yaml
conf2=
asr_init=


### path to save the model
model=/n/work2/inaguma/results/librispeech

### path to the model directory to resume training
resume=

### path to save preproecssed data
export data=/n/work2/inaguma/corpus/librispeech

### path to download data
data_download_path=/n/rd21/corpora_7/librispeech/

### data size
datasize=960     # 100/460/960
lm_datasize=960  # 100/460/960
use_external_text=true

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

set -e
set -u
set -o pipefail

if [ ${speed_perturb} = true ]; then
  if [ -z ${conf2} ]; then
    echo "Error: Set --conf2." 1>&2
    exit 1
  fi
fi

if [ -z ${gpu} ]; then
    echo "Error: set GPU number." 1>&2
    echo "Usage: ./run.sh --gpu 0" 1>&2
    exit 1
fi
n_gpus=$(echo ${gpu} | tr "," "\n" | wc -l)
if [ ${n_gpus} != 1 ]; then
    export OMP_NUM_THREADS=${n_gpus}
fi

# Base url for downloads.
data_url=www.openslr.org/resources/12
lm_url=www.openslr.org/resources/11

train_set=train_${datasize}
dev_set=dev_other
test_set="dev_clean dev_other test_clean test_other"
if [ ${speed_perturb} = true ]; then
    train_set=train_sp_${datasize}
    dev_set=dev_other_sp
    test_set="dev_clean_sp dev_other_sp test_clean_sp test_other_sp"
fi

# main
if [ ${unit} = char ]; then
    vocab=
fi
if [ ${unit} != wp ]; then
    wp_type=
fi
# sub1
if [ ${unit_sub1} = char ]; then
    vocab_sub1=
fi
if [ ${unit_sub1} != wp ]; then
    wp_type_sub1=
fi

if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ] && [ ! -e ${data}/.done_stage_0 ]; then
    echo ============================================================================
    echo "                       Data Preparation (stage:0)                          "
    echo ============================================================================

    # download data
    mkdir -p ${data}
    for part in dev-clean test-clean dev-other test-other train-clean-100 train-clean-360 train-other-500; do
        local/download_and_untar.sh ${data_download_path} ${data_url} ${part} || exit 1;
    done

    # download the LM resources
    local/download_lm.sh ${lm_url} ${data}/local/lm || exit 1;

    # format the data as Kaldi data directories
    for part in dev-clean test-clean dev-other test-other train-clean-100 train-clean-360 train-other-500; do
        # use underscore-separated names in data directories.
        local/data_prep.sh ${data_download_path}/LibriSpeech/${part} ${data}/$(echo ${part} | sed s/-/_/g) || exit 1;
    done

    # when the "--stage 3" option is used below we skip the G2P steps, and use the
    # lexicon we have already downloaded from openslr.org/11/
    local/prepare_dict.sh --stage 3 --nj 30 --cmd "$train_cmd" \
        ${data}/local/lm ${data}/local/lm ${data}/local/dict_nosp

    # utils/prepare_lang.sh ${data}/local/dict_nosp \
    #     "<UNK>" ${data}/local/lang_tmp_nosp ${data}/lang_nosp
    # local/format_lms.sh --src-dir ${data}/lang_nosp ${data}/local/lm

    # lowercasing
    for x in dev_clean test_clean dev_other test_other train_clean_100 train_clean_360 train_other_500; do
        cp ${data}/${x}/text ${data}/${x}/text.org
        paste -d " " <(cut -f 1 -d " " ${data}/${x}/text.org) \
            <(cut -f 2- -d " " ${data}/${x}/text.org | awk '{print tolower($0)}') > ${data}/${x}/text
    done

    touch ${data}/.done_stage_0 && echo "Finish data preparation (stage: 0)."
fi

if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ] && [ ! -e ${data}/.done_stage_1_${datasize}_sp${speed_perturb} ]; then
    echo ============================================================================
    echo "                    Feature extranction (stage:1)                          "
    echo ============================================================================

    if [ ! -e ${data}/.done_stage_1_${datasize}_spfalse ]; then
        for x in dev_clean test_clean dev_other test_other train_clean_100; do
            steps/make_fbank.sh --nj 32 --cmd "$train_cmd" --write_utt2num_frames true \
                ${data}/${x} ${data}/log/make_fbank/${x} ${data}/fbank || exit 1;
        done

        if [ ${datasize} == '100' ]; then
            utils/combine_data.sh --extra_files "utt2num_frames" ${data}/train_${datasize} \
                ${data}/train_clean_100 || exit 1;
        elif [ ${datasize} == '460' ]; then
            steps/make_fbank.sh --nj 32 --cmd "$train_cmd" --write_utt2num_frames true \
                ${data}/train_clean_360 ${data}/log/make_fbank/train_clean_360 ${data}/fbank || exit 1;
            utils/combine_data.sh --extra_files "utt2num_frames" ${data}/train_${datasize} \
                ${data}/train_clean_100 ${data}/train_clean_360 || exit 1;
        elif [ ${datasize} == '960' ]; then
            steps/make_fbank.sh --nj 32 --cmd "$train_cmd" --write_utt2num_frames true \
                ${data}/train_clean_360 ${data}/log/make_fbank/train_clean_360 ${data}/fbank || exit 1;
            steps/make_fbank.sh --nj 32 --cmd "$train_cmd" --write_utt2num_frames true \
                ${data}/train_other_500 ${data}/log/make_fbank/train_other_500 ${data}/fbank || exit 1;
            utils/combine_data.sh --extra_files "utt2num_frames" ${data}/train_${datasize} \
                ${data}/train_clean_100 ${data}/train_clean_360 ${data}/train_other_500 || exit 1;
        else
            echo "datasize is 100 or 460 or 960." && exit 1;
        fi
    fi

    if [ ${speed_perturb} = true ]; then
        speed_perturb_3way.sh ${data} train_${datasize} ${train_set}
        if [ ! -e ${data}/dev_clean_sp ]; then
            cp -rf ${data}/dev_clean ${data}/dev_clean_sp
            cp -rf ${data}/dev_other ${data}/dev_other_sp
            cp -rf ${data}/test_clean ${data}/test_clean_sp
            cp -rf ${data}/test_other ${data}/test_other_sp
        fi
    fi

    # Compute global CMVN
    compute-cmvn-stats scp:${data}/${train_set}/feats.scp ${data}/${train_set}/cmvn.ark || exit 1;

    # Apply global CMVN & dump features
    dump_feat.sh --cmd "$train_cmd" --nj 80 \
        ${data}/${train_set}/feats.scp ${data}/${train_set}/cmvn.ark ${data}/log/dump_feat/${train_set} ${data}/dump/${train_set} || exit 1;
    for x in ${test_set}; do
        dump_dir=${data}/dump/${x}_${datasize}
        dump_feat.sh --cmd "$train_cmd" --nj 32 \
            ${data}/${x}/feats.scp ${data}/${train_set}/cmvn.ark ${data}/log/dump_feat/${x}_${datasize} ${dump_dir} || exit 1;
    done

    touch ${data}/.done_stage_1_${datasize}_sp${speed_perturb} && echo "Finish feature extranction (stage: 1)."
fi

# main
dict=${data}/dict/${train_set}_${unit}${wp_type}${vocab}.txt; mkdir -p ${data}/dict
wp_model=${data}/dict/${train_set}_${wp_type}${vocab}
if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ] && [ ! -e ${data}/.done_stage_2_${datasize}_${unit}${wp_type}${vocab}_sp${speed_perturb} ]; then
    echo ============================================================================
    echo "                      Dataset preparation (stage:2, main)                  "
    echo ============================================================================

    if [ ${unit} = wp ]; then
        make_vocab.sh --unit ${unit} --speed_perturb ${speed_perturb} \
            --vocab ${vocab} --wp_type ${wp_type} --wp_model ${wp_model} \
            ${data} ${dict} ${data}/${train_set}/text || exit 1;
    else
        make_vocab.sh --unit ${unit} --speed_perturb ${speed_perturb} \
            ${data} ${dict} ${data}/${train_set}/text || exit 1;
    fi

    # Compute OOV rate
    if [ ${unit} = word ]; then
        mkdir -p ${data}/dict/word_count ${data}/dict/oov_rate
        echo "OOV rate:" > ${data}/dict/oov_rate/word${vocab}_${datasize}.txt
        for x in ${train_set} ${test_set}; do
            cut -f 2- -d " " ${data}/${x}/text | tr " " "\n" | sort | uniq -c | sort -n -k1 -r \
                > ${data}/dict/word_count/${x}_${datasize}.txt || exit 1;
            compute_oov_rate.py ${data}/dict/word_count/${x}_${datasize}.txt ${dict} ${x} \
                >> ${data}/dict/oov_rate/word${vocab}_${datasize}.txt || exit 1;
            # NOTE: speed perturbation is not considered
        done
        cat ${data}/dict/oov_rate/word${vocab}_${datasize}.txt
    fi

    echo "Making dataset tsv files for ASR ..."
    mkdir -p ${data}/dataset
    make_dataset.sh --feat ${data}/dump/${train_set}/feats.scp --unit ${unit} --wp_model ${wp_model} \
        ${data}/${train_set} ${dict} > ${data}/dataset/${train_set}_${unit}${wp_type}${vocab}.tsv || exit 1;
    for x in ${test_set}; do
        dump_dir=${data}/dump/${x}_${datasize}
        make_dataset.sh --feat ${dump_dir}/feats.scp --unit ${unit} --wp_model ${wp_model} \
            ${data}/${x} ${dict} > ${data}/dataset/${x}_${datasize}_${unit}${wp_type}${vocab}.tsv || exit 1;
    done

    touch ${data}/.done_stage_2_${datasize}_${unit}${wp_type}${vocab}_sp${speed_perturb} && echo "Finish creating dataset for ASR (stage: 2)."
fi

# sub1
dict_sub1=${data}/dict/${train_set}_${unit_sub1}${wp_type_sub1}${vocab_sub1}.txt
wp_model_sub1=${data}/dict/${train_set}_${wp_type_sub1}${vocab_sub1}
if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ] && [ ! -e ${data}/.done_stage_2_${datasize}_${unit_sub1}${wp_type_sub1}${vocab_sub1}_sp${speed_perturb} ]; then
    echo ============================================================================
    echo "                      Dataset preparation (stage:2, sub1)                  "
    echo ============================================================================

    if [ ${unit_sub1} = phone ]; then
        echo "Making a dictionary..."
        echo "<unk> 1" > ${dict_sub1}  # <unk> must be 1, 0 will be used for "blank" in CTC
        echo "<eos> 2" >> ${dict_sub1}  # <sos> and <eos> share the same index
        echo "<pad> 3" >> ${dict_sub1}
        offset=$(cat ${dict_sub1} | wc -l)
        lexicon=${data}/local/dict_nosp/lexicon.txt
        map2phone.py --text ${data}/${train_set}/text --lexicon ${lexicon} --noise SPN > ${data}/${train_set}/text.phone
        for x in ${test_set}; do
            map2phone.py --text ${data}/${x}/text --lexicon ${lexicon} --noise SPN > ${data}/${x}/text.phone
        done
        text2dict.py ${data}/${train_set}/text.phone --unit ${unit_sub1} --speed_perturb ${speed_perturb} | \
            awk -v offset=${offset} '{print $0 " " NR+offset}' >> ${dict_sub1} || exit 1;
    else
        make_vocab.sh --unit ${unit_sub1} --speed_perturb ${speed_perturb} --character_coverage 0.9995 \
            ${data} ${dict_sub1} ${data}/${train_set}/text || exit 1;
        # NOTE: bpe is not supported here
    fi

    echo "Making dataset tsv files for ASR ..."
    if [ ${unit_sub1} = phone ]; then
        make_dataset.sh --feat ${data}/dump/${train_set}/feats.scp --unit ${unit_sub1} --text ${data}/${train_set}/text.phone \
            ${data}/${train_set} ${dict_sub1} > ${data}/dataset/${train_set}_${unit_sub1}${wp_type_sub1}${vocab_sub1}.tsv || exit 1;
    else
        make_dataset.sh --feat ${data}/dump/${train_set}/feats.scp --unit ${unit_sub1} --wp_model ${wp_model_sub1} \
            ${data}/${train_set} ${dict_sub1} > ${data}/dataset/${train_set}_${unit_sub1}${wp_type_sub1}${vocab_sub1}.tsv || exit 1;
    fi
    for x in ${test_set}; do
        dump_dir=${data}/dump/${x}_${datasize}
        if [ ${unit_sub1} = phone ]; then
            make_dataset.sh --feat ${dump_dir}/feats.scp --unit ${unit_sub1} --text ${data}/${x}/text.phone \
                    ${data}/${x} ${dict_sub1} > ${data}/dataset/${x}_${datasize}_${unit_sub1}${wp_type_sub1}${vocab_sub1}.tsv || exit 1;
        else
            make_dataset.sh --feat ${dump_dir}/feats.scp --unit ${unit_sub1} --wp_model ${wp_model_sub1} \
                ${data}/${x} ${dict_sub1} > ${data}/dataset/${x}_${datasize}_${unit_sub1}${wp_type_sub1}${vocab_sub1}.tsv || exit 1;
        fi
    done

    touch ${data}/.done_stage_2_${datasize}_${unit_sub1}${wp_type_sub1}${vocab_sub1}_sp${speed_perturb} && echo "Finish creating dataset for ASR (stage: 2)."
fi

mkdir -p ${model}
if [ ${stage} -le 4 ] && [ ${stop_stage} -ge 4 ]; then
    echo ============================================================================
    echo "                       ASR Training stage (stage:4)                        "
    echo ============================================================================

    CUDA_VISIBLE_DEVICES=${gpu} ${NEURALSP_ROOT}/neural_sp/bin/asr/train.py \
        --corpus librispeech \
        --config ${conf} \
        --config2 ${conf2} \
        --n_gpus ${n_gpus} \
        --cudnn_benchmark ${benchmark} \
        --train_set ${data}/dataset/${train_set}_${unit}${wp_type}${vocab}.tsv \
        --train_set_sub1 ${data}/dataset/${train_set}_${unit_sub1}${wp_type_sub1}${vocab_sub1}.tsv \
        --dev_set ${data}/dataset/${dev_set}_${unit}${wp_type}${vocab}.tsv \
        --dev_set_sub1 ${data}/dataset/${dev_set}_${unit_sub1}${wp_type_sub1}${vocab_sub1}.tsv \
        --eval_sets ${data}/dataset/eval1_${datasize}_${unit}${wp_type}${vocab}.tsv \
        --unit ${unit} \
        --unit_sub1 ${unit_sub1} \
        --dict ${dict} \
        --dict_sub1 ${dict_sub1} \
        --wp_model ${wp_model}.model \
        --wp_model_sub1 ${wp_model_sub1}.model \
        --model_save_dir ${model}/asr \
        --asr_init ${asr_init} \
        --stdout ${stdout} \
        --resume ${resume} || exit 1;

    echo "Finish ASR model training (stage: 4)."
fi
