#!/usr/bin/env python3
"""Offline check of a cravage-transcript-2 file (docs/SPEC.md section 4, docs/WIRE.md).

Interim, independent Python twin of CravageCore's TranscriptVerifier. It is the draft of the
version-2 mode that docs/PLAN.md R6 adds to verify_round.py in the SMPC repository (approved, not
yet implemented there). Once that lands and is re-vendored and re-pinned, CI switches to it and
this file is deleted. Pure integer arithmetic; trusts nothing but the file.

    python3 Tools/check_transcript_v2.py <transcript.json>
"""
import base64
import hashlib
import json
import sys
import unicodedata

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

FORMAT = "cravage-transcript-2"
SCALE = 1_000_000
MODULUS = 1 << 64
CLAIM = ("This transcript shows that the listed keys signed the listed shares, that they sum and "
         "average as stated, and that every listed key signed agreement to this exact set of shares. "
         "It does not prove who the participants were, that separate devices or people were "
         "involved, or that any input was truthful.")
LETTERS = "ABCDEFGH"
HEX = set("0123456789abcdef")


def lp(b):
    return len(b).to_bytes(4, "big") + b


def result_digest(session_hex, roster_hash, shares_in_letter_order):
    h = hashlib.sha256()
    h.update(lp(b"cravage-result-confirm-1"))
    h.update(lp(session_hex.encode()))
    h.update(lp(roster_hash))
    h.update(bytes([len(shares_in_letter_order)]))
    for share in shares_in_letter_order:
        h.update(lp(share.encode()))
    return h.hexdigest()


def format_average_fixed(sum_fixed, n, max_dp=2):
    """Mirror smpc-core.js formatAverageFixed: half away from zero, trailing zeros stripped, no -0."""
    neg = sum_fixed < 0
    abs_v = -sum_fixed if neg else sum_fixed
    divisor = n * SCALE
    units, rem = divmod(abs_v * 10 ** max_dp, divisor)
    if rem * 2 >= divisor:
        units += 1
    if units == 0:
        return "0"
    whole, frac_units = divmod(units, 10 ** max_dp)
    frac = str(frac_units).zfill(max_dp).rstrip("0")
    return ("-" if neg else "") + str(whole) + ("." + frac if frac else "")


def canonical_share(text):
    """Canonical signed decimal Int64: ^-?[0-9]+$, no leading zeros, no -0. Returns int or None."""
    if not isinstance(text, str) or not text or len(text) > 20:
        return None
    body = text[1:] if text.startswith("-") else text
    if not body or not all(c in "0123456789" for c in body):
        return None
    if (len(body) > 1 and body[0] == "0") or text == "-0":
        return None
    value = int(text)
    return value if -(1 << 63) <= value < (1 << 63) else None


def to_signed64(u):
    u %= MODULUS
    return u - MODULUS if u >= (1 << 63) else u


def verify(vk_b64, sig_b64, message):
    try:
        raw = base64.b64decode(sig_b64, validate=True)
        point = base64.b64decode(vk_b64, validate=True)
        if len(raw) != 64 or len(point) != 65:
            return False
        vk = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), point)
        der = encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
        vk.verify(der, message.encode(), ec.ECDSA(hashes.SHA256()))
        return True
    except (InvalidSignature, ValueError, TypeError):
        return False


def check_transcript_v2(t):
    """Return a list of failure strings; empty means verified."""
    if not isinstance(t, dict):
        return ["not a JSON object"]
    failures = []
    if t.get("format") != FORMAT:
        failures.append("format is not " + FORMAT)
    if t.get("scale") != str(SCALE):
        failures.append("scale is not 1000000")
    if t.get("modulus") != str(MODULUS):
        failures.append("modulus is not 2^64")
    if t.get("claim") != CLAIM:
        failures.append("claim does not match the pinned text")
    session = t.get("session")
    parts = session.split(".") if isinstance(session, str) else []
    if len(parts) != 2 or len(parts[0]) != 32 or len(parts[1]) != 64 or not set(session) - {"."} <= HEX:
        return failures + ["session is not a roster-bound session id"]
    session_hex, roster_hash = parts[0], bytes.fromhex(parts[1])
    parties = t.get("parties")
    if not isinstance(parties, list) or not 3 <= len(parties) <= 8 or parties != list(LETTERS[:len(parties)]):
        return failures + ["parties must be the letters A.. in order, three to eight of them"]
    for name in ("shares", "share_sigs", "vks", "confirms"):
        m = t.get(name)
        if not isinstance(m, dict) or set(m.keys()) != set(parties) or not all(isinstance(v, str) for v in m.values()):
            failures.append(name + " does not have exactly one entry per party")
    if failures:
        return failures

    values = []
    for p in parties:
        value = canonical_share(t["shares"][p])
        if value is None:
            failures.append(p + ": share is not a canonical 64-bit decimal")
            continue
        values.append(value)
        if not verify(t["vks"][p], t["share_sigs"][p], "share|%s|%s|%s" % (session, p, t["shares"][p])):
            failures.append(p + ": share signature does not verify under the listed key")
    if failures:
        return failures
    points = [base64.b64decode(t["vks"][p]) for p in parties]
    if points != sorted(points) or len(set(points)) != len(points):
        failures.append("letters are not assigned by bytewise order of distinct keys")

    total = to_signed64(sum(values))
    if t.get("sum") != str(total):
        failures.append("shares sum (mod 2^64) differs from the stated sum")
    if t.get("average") != format_average_fixed(total, len(parties)):
        failures.append("stated average does not follow from the sum")

    digest = result_digest(session_hex, roster_hash, [t["shares"][p] for p in parties])
    for p in parties:
        if not verify(t["vks"][p], t["confirms"][p], "result_confirm|%s|%s|%s" % (session, p, digest)):
            failures.append(p + ": agreement signature does not cover this exact set of shares")
    return failures


def _clean(s, max_len=300):
    return "".join(ch for ch in str(s) if unicodedata.category(ch) != "Cc")[:max_len]


def main(argv):
    if len(argv) != 2:
        print("usage: check_transcript_v2.py <transcript.json>")
        return 2
    with open(argv[1], "rb") as f:
        raw = f.read()
    if len(raw) > 64_000:
        print("FAIL: file too large for a transcript")
        return 1
    try:
        t = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        print("FAIL: not a readable JSON file")
        return 1
    failures = check_transcript_v2(t)
    if failures:
        for line in failures:
            print("FAIL:", _clean(line))
        return 1
    print("PASS: %d share signatures and %d agreement signatures verify; sum and average recomputed (average = %s)"
          % (len(t["parties"]), len(t["parties"]), _clean(t["average"], 40)))
    print("Scope: " + CLAIM)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
