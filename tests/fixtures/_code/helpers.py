"""Helpers kept in their own file and brought into documents in several ways."""
import numpy as np


def moving_average(x, k=3):
    """Mean of each window of k values."""
    x = np.asarray(x, dtype=float)
    return np.convolve(x, np.ones(k) / k, mode="valid")


GREETING = "hello from _code/helpers.py"
