"""Eclypse Z7 / Zmod Scope 1410-105 acquisition contract.

The ADC resolution is 14 bits. Digilent ZmodScopeController's calibrated
output is two signed 16-bit samples packed into one 32-bit word, CH1 upper.
These are different formats; never mask a calibrated sample down to 14 bits.
"""
import numpy as np

DEFAULT_FS_HZ = 100_000_000.0
MAX_FS_HZ = 105_000_000.0
CONTROLLER_BITS = 16
ADC_BITS = 14
MAX_SAMPLES = 16_384
PLATFORM = "Eclypse Z7 + Zmod Scope 1410-105"
VENDOR_IP_COMMIT = "f4613fff005b098065fd5d619a2b88e55720a423"


def validate_sample_rate(fs_hz):
    """Validate a declared Zmod rate; this does not configure its physical clock."""
    fs_hz = float(fs_hz)
    if not np.isfinite(fs_hz) or not 0 < fs_hz <= MAX_FS_HZ:
        raise ValueError("Zmod Scope 1410-105 requires 0 < Fs <= 105 MSPS")
    return fs_hz


def decode_scope_words(words, receiver_channel=1):
    """Extract CH1 or CH2 from calibrated controller words, preserving int16.

    Input is an unsigned 32-bit numeric array (file bytes must be little-endian).
    The legacy ZmodADC1410_Controller packing is NOT this interface.
    """
    if receiver_channel not in (1, 2):
        raise ValueError("receiver_channel must be 1 or 2")
    a = np.asarray(words)
    if (not np.issubdtype(a.dtype, np.integer) or np.any(a < 0)
            or np.any(a > 0xffffffff)):
        raise ValueError("Scope controller data must be unsigned 32-bit words")
    shift = 16 if receiver_channel == 1 else 0
    half = ((a.astype(np.uint32) >> shift) & 0xffff).astype(np.int32)
    return np.where(half >= 0x8000, half - 0x10000, half).astype(np.int16)
