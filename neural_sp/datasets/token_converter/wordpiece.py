#! /usr/bin/env python
# -*- coding: utf-8 -*-

# Copyright 2018 Kyoto University (Hirofumi Inaguma)
#  Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)

""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import codecs
import sentencepiece as spm


class Wp2idx(object):
    """Class for converting word-piece sequence into indices.

    Args:
        dict_path (str): path to a dictionary file

    """

    def __init__(self, dict_path, wp_model):
        # Load a dictionary file
        self.wp2idx = {}
        with codecs.open(dict_path, 'r', 'utf-8') as f:
            for line in f:
                wp, id = line.strip().encode('utf_8').split(' ')
                self.wp2idx[wp] = int(id)

        self.sp = spm.SentencePieceProcessor()
        self.sp.Load(wp_model)

    def __call__(self, text):
        """Convert word-piece sequence into indices.

        Args:
            text (str): word-piece sequence
        Returns:
            token_ids (list): word-piece indices

        """
        wp_list = self.sp.EncodeAsPieces(text)
        token_ids = []
        for wp in wp_list:
            if wp in self.wp2idx.keys():
                token_ids.append(self.wp2idx[wp])
            else:
                # Replace with <unk>
                token_ids.append(self.wp2idx['<unk>'])
        return token_ids


class Idx2wp(object):
    """Class for converting indices into word-piece sequence.

    Args:
        dict_path (str): path to a dictionary file

    """

    def __init__(self, dict_path, wp_model):
        # Load a dictionary file
        self.idx2wp = {}
        with codecs.open(dict_path, 'r', 'utf-8') as f:
            for line in f:
                wp, id = line.strip().encode('utf_8').split(' ')
                self.idx2wp[int(id)] = wp

        self.sp = spm.SentencePieceProcessor()
        self.sp.Load(wp_model)

    def __call__(self, token_ids, return_list=False):
        """Convert indices into word-piece sequence.

        Args:
            token_ids (np.ndarray or list): word-piece indices
            return_list (bool): if True, return list of words
        Returns:
            text (str): word-piece sequence
                or
            wp_list (list): list of words

        """
        wp_list = list(map(lambda wp: self.idx2wp[wp], token_ids))
        if return_list:
            return wp_list
        return self.sp.DecodePieces(wp_list)