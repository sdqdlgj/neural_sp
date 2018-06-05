#! /usr/bin/env python
# -*- coding: utf-8 -*-

"""Define evaluation method of character-level models (CSJ corpus)."""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import re
from tqdm import tqdm
import pandas as pd

from utils.evaluation.edit_distance import compute_wer


def eval_char(models, dataset, eval_batch_size, beam_width,
              max_decode_len, min_decode_len=1,
              length_penalty=0, coverage_penalty=0, progressbar=False):
    """Evaluate trained model by Character Error Rate.
    Args:
        models (list): the models to evaluate
        dataset: An instance of a `Dataset' class
        eval_batch_size (int): the batch size when evaluating the model
        beam_width: (int): the size of beam
        max_decode_len (int): the maximum sequence length to emit in seq2seq
        min_decode_len (int): the minimum sequence length to emit in seq2seq
        length_penalty (float): length penalty in beam search decoding
        coverage_penalty (float): coverage penalty in beam search decoding
        progressbar (bool): if True, visualize the progressbar
        temperature (int):
    Returns:
        wer (float): Word error rate
        cer (float): Character error rate
        df_char (pd.DataFrame): dataframe of substitution, insertion, and deletion
    """
    # Reset data counter
    dataset.reset()

    model = models[0]
    # TODO: fix this

    cer, wer = 0, 0
    sub_char, ins_char, del_char = 0, 0, 0
    sub_word, ins_word, del_word = 0, 0, 0
    num_words, num_chars = 0, 0
    if progressbar:
        pbar = tqdm(total=len(dataset))  # TODO: fix this
    while True:
        batch, is_new_epoch = dataset.next(batch_size=eval_batch_size)

        # Decode
        if model.model_type in ['ctc', 'attention']:
            best_hyps, _, perm_idx = model.decode(
                batch['xs'],
                beam_width=beam_width,
                max_decode_len=max_decode_len,
                length_penalty=length_penalty,
                coverage_penalty=coverage_penalty)
            ys = [batch['ys'][i] for i in perm_idx]
            task_index = 0
        else:
            best_hyps, _, perm_idx = model.decode(
                batch['xs'],
                beam_width=beam_width,
                max_decode_len=max_decode_len,
                length_penalty=length_penalty,
                coverage_penalty=coverage_penalty,
                task_index=1)
            ys = [batch['ys_sub'][i] for i in perm_idx]
            task_index = 1
        # TODO: add nested_attention

        for b in range(len(batch['xs'])):
            ##############################
            # Reference
            ##############################
            if dataset.is_test:
                str_ref = ys[b]
                # NOTE: transcript is seperated by space('_')
            else:
                # Convert from list of index to string
                str_ref = dataset.idx2char(ys[b])

            ##############################
            # Hypothesis
            ##############################
            str_hyp = dataset.idx2char(best_hyps[b])
            str_hyp = re.sub(r'(.*)>(.*)', r'\1', str_hyp)
            # NOTE: Trancate by the first <EOS>

            # Remove garbage labels
            str_ref = re.sub(r'[@>]+', '', str_ref)
            str_hyp = re.sub(r'[@>]+', '', str_hyp)
            # NOTE: @ means <sp>

            # Remove consecutive spaces
            str_ref = re.sub(r'[_]+', '_', str_ref)
            str_hyp = re.sub(r'[_]+', '_', str_hyp)

            if dataset.label_type == 'character_wb' or (task_index > 0 and dataset.label_type_sub == 'character_wb'):
                # Compute WER
                try:
                    wer_b, sub_b, ins_b, del_b = compute_wer(
                        ref=str_ref.split('_'),
                        hyp=str_hyp.split('_'),
                        normalize=False)
                    wer += wer_b
                    sub_word += sub_b
                    ins_word += ins_b
                    del_word += del_b
                    num_words += len(str_ref.split('_'))
                except:
                    pass

            # Compute CER
            try:
                cer_b, sub_b, ins_b, del_b = compute_wer(
                    ref=list(str_ref.replace('_', '')),
                    hyp=list(str_hyp.replace('_', '')),
                    normalize=False)
                cer += cer_b
                sub_char += sub_b
                ins_char += ins_b
                del_char += del_b
                num_chars += len(str_ref.replace('_', ''))
            except:
                pass

            if progressbar:
                pbar.update(1)

        if is_new_epoch:
            break

    if progressbar:
        pbar.close()

    # Reset data counters
    dataset.reset()

    if dataset.label_type == 'character_wb' or (task_index > 0 and dataset.label_type_sub == 'character_wb'):
        wer /= num_words
        sub_word /= num_words
        ins_word /= num_words
        del_word /= num_words
    else:
        wer = sub_word = ins_word = del_word = 0

    cer /= num_chars
    sub_char /= num_chars
    ins_char /= num_chars
    del_char /= num_chars

    df_char = pd.DataFrame(
        {'SUB': [sub_word * 100, sub_char * 100],
         'INS': [ins_word * 100, ins_char * 100],
         'DEL': [del_word * 100, del_char * 100]},
        columns=['SUB', 'INS', 'DEL'], index=['WER', 'CER'])

    return wer, cer, df_char
