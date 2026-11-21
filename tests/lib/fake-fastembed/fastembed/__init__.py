# SPDX-License-Identifier: GPL-2.0-or-later
"""A stand-in for fastembed, for the tests that check what xymonapi-rag does
with vectors -- indexing, paging, reloading, serving, hiding -- rather than
how good the model is: xymonapi-rag-eval.sh checks that, with the real one.
Put first on PYTHONPATH, it is imported as fastembed.

TextEmbedding(MODEL) embeds a text as the 3-letter pieces of its words,
hashed into DIM places and made unit length: texts that share words, or most
of a word, are near. It loads nothing and needs no network; any model name
is taken, so an index still records the one it was built with.
"""
import hashlib
import re

import numpy as np

DIM = 384


def _vector(text: str) -> np.ndarray:
    v = np.zeros(DIM, dtype="float32")
    for word in re.findall(r"[a-z0-9]+", text.lower()):
        w = f" {word} "
        for i in range(max(1, len(w) - 2)):
            h = hashlib.blake2b(w[i:i + 3].encode(), digest_size=4).digest()
            v[int.from_bytes(h, "little") % DIM] += 1.0
    n = float(np.linalg.norm(v))
    return v / n if n else v


class TextEmbedding:
    def __init__(self, model_name: str = "", **kwargs):
        self.model_name = model_name

    def embed(self, texts, **kwargs):
        return (_vector(t) for t in texts)

    def query_embed(self, texts, **kwargs):
        if isinstance(texts, str):
            texts = [texts]
        return (_vector(t) for t in texts)
