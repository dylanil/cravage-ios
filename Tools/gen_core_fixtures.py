#!/usr/bin/env python3
"""Generate CravageCore's Python-oracle fixtures.

Writes CravageCore/Tests/CravageCoreTests/Fixtures/core_vectors.json. The arithmetic oracle uses
Python's unbounded integers reduced mod 2^64 (the JS/Python protocol's own wire semantics), so the
Swift wrapping Int64 implementation is checked against something that cannot itself overflow. The
crypto vectors are produced with the same `cryptography` calls verify_round.py uses, so a Swift
verify of a Python signature is a real cross-language check, not a self-check.

Deterministic for the arithmetic (seeded); ECDSA signatures are randomized by design, so the
signature vectors change on every run but stay valid. Re-run only when the fixture set changes.

    python3 Tools/gen_core_fixtures.py
"""
import base64
import hashlib
import json
import os
import random
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

TWO64 = 1 << 64
TWO63 = 1 << 63
CAP = 10 ** 18
LETTERS = "ABCDEFGH"


def to_signed(u):
    u %= TWO64
    return u - TWO64 if u >= TWO63 else u


def b64(raw):
    return base64.b64encode(raw).decode()


def raw_pub(key):
    return key.public_key().public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)


def sign_raw(sk, msg):
    der = sk.sign(msg.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    return b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))


def derive_mask(my_ecdh, their_pub_raw, lo, hi):
    their = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), their_pub_raw)
    shared = my_ecdh.exchange(ec.ECDH(), their)
    out = HKDF(algorithm=hashes.SHA256(), length=8, salt=b"",
               info=b"SMPC mask " + (lo + hi).encode()).derive(shared)
    return to_signed(int.from_bytes(out, "big"))


def random_figure(rng):
    kind = rng.randrange(6)
    if kind == 0:
        return rng.choice([0, 1, -1, CAP - 1, -(CAP - 1), 10 ** 12, -(10 ** 12)])
    if kind == 1:
        return rng.randrange(-10 ** 9, 10 ** 9)
    return rng.randrange(-(CAP - 1), CAP)


def rounds(rng):
    """Full-round arithmetic vectors: shares built the SMPC way, sums exact."""
    out = []
    for n in list(range(3, 9)) * 12:
        parties = list(LETTERS[:n])
        figures = {p: random_figure(rng) for p in parties}
        if rng.randrange(4) == 0:  # every party at the same extreme, the sum-correctness edge
            extreme = rng.choice([CAP - 1, -(CAP - 1)])
            figures = {p: extreme for p in parties}
        masks = {}
        for i, lo in enumerate(parties):
            for hi in parties[i + 1:]:
                masks[lo + hi] = to_signed(rng.getrandbits(64))
        shares = {}
        for me in parties:
            share = figures[me]
            for other in parties:
                if other == me:
                    continue
                lo, hi = sorted([me, other])
                r = masks[lo + hi]
                share += r if me < other else -r
            shares[me] = to_signed(share)
        total = sum(figures.values())
        assert abs(total) < TWO63
        assert to_signed(sum(shares.values())) == total
        out.append({
            "parties": parties,
            "figures": {p: str(figures[p]) for p in parties},
            "masks": {k: str(v) for k, v in masks.items()},
            "shares": {p: str(shares[p]) for p in parties},
            "sum": str(total),
        })
    return out


def wrapping_adds(rng):
    out = []
    edge = [0, 1, -1, TWO63 - 1, -TWO63, TWO63 - 2, -TWO63 + 1]
    pairs = [(a, b) for a in edge for b in edge]
    pairs += [(to_signed(rng.getrandbits(64)), to_signed(rng.getrandbits(64))) for _ in range(200)]
    for a, b in pairs:
        out.append({"a": str(a), "b": str(b), "sum": str(to_signed(a + b)), "product": str(to_signed(a * b))})
    return out


def crypto_vectors():
    k1 = ec.derive_private_key(0x1111111111111111111111111111111111111111111111111111111111111111, ec.SECP256R1())
    k2 = ec.derive_private_key(0x2222222222222222222222222222222222222222222222222222222222222222, ec.SECP256R1())
    m_ab = derive_mask(k1, raw_pub(k2), "A", "B")
    assert m_ab == derive_mask(k2, raw_pub(k1), "A", "B") == 5107112043798890199
    signatures = []
    for scalar, message in [
        (0x1111111111111111111111111111111111111111111111111111111111111111, "share|ABCDEF|A|123"),
        (0x2222222222222222222222222222222222222222222222222222222222222222, "pubkey|ROOM1|B|BASE64=="),
        (0x0000000000000000000000000000000000000000000000000000000000000003, "control|S|host|{\"a\":1}"),
        (0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, ""),
        (0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef, "unicode £ ☃ test"),
    ]:
        sk = ec.derive_private_key(scalar, ec.SECP256R1())
        signatures.append({
            "private_scalar_hex": "%064x" % scalar,
            "vk": b64(raw_pub(sk)),
            "message": message,
            "signature": sign_raw(sk, message),
        })
    masks = [{"lo_scalar_hex": "11" * 32, "hi_scalar_hex": "22" * 32, "lo": "A", "hi": "B", "mask": str(m_ab)}]
    for scalar_a, scalar_b, lo, hi in [
        (0x11 * 0 + 5, 7, "A", "C"),
        (0xabcdef, 0x123456, "C", "H"),
        (0x11 * 0 + 5, 7, "B", "A"),  # deliberately unsorted: info string is lo+hi as given
    ]:
        ka = ec.derive_private_key(scalar_a, ec.SECP256R1())
        kb = ec.derive_private_key(scalar_b, ec.SECP256R1())
        m = derive_mask(ka, raw_pub(kb), lo, hi)
        assert m == derive_mask(kb, raw_pub(ka), lo, hi)
        masks.append({"lo_scalar_hex": "%064x" % scalar_a, "hi_scalar_hex": "%064x" % scalar_b,
                      "lo": lo, "hi": hi, "mask": str(m)})
    multiblock = ("SMPC-contract-vector multiblock v1: this string is deliberately "
                  "longer than sixty-four bytes so SHA-256 spans multiple blocks.")
    digests = [
        {"input": "SMPC-contract-vector v1", "sha256": hashlib.sha256(b"SMPC-contract-vector v1").hexdigest()},
        {"input": multiblock, "sha256": hashlib.sha256(multiblock.encode()).hexdigest()},
        {"input": "", "sha256": hashlib.sha256(b"").hexdigest()},
    ]
    assert digests[0]["sha256"] == "8daf9b4afa1031808e15d1756a5b611089f9866f96890ec45e0d08ca5b081529"
    assert digests[1]["sha256"] == "8fb355047678afde0e3f4844bb2688f740b077c897585343fc73b54c0af7111b"
    return {"signatures": signatures, "masks": masks, "digests": digests}


CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def lp(b):
    """Length-prefixed field: 4-byte big-endian length, then the bytes."""
    return len(b).to_bytes(4, "big") + b


def crockford(five):
    n = int.from_bytes(five, "big")
    s = "".join(CROCKFORD[(n >> (35 - 5 * i)) & 31] for i in range(8))
    return s[:4] + "-" + s[4:]


def roster_vectors():
    """Second implementation of Roster.rosterHash / RoomFingerprint (docs/SPEC.md section 3,
    PLAN.md RoomFingerprint) so the Swift encoding is pinned by a file, not only by itself."""
    out = []
    cases = [
        ("ab" * 16, "Salary", [(1, 11, "one"), (2, 12, "two"), (3, 13, "three")]),
        ("00" * 16, "Average bonus (£) ☃", [(9, 90, "z"), (5, 50, "y"), (7, 70, "x"), (3, 30, "w")]),
        ("ff" * 16, "x", [(i, 100 + i, "p%d" % i) for i in range(1, 9)]),
    ]
    for session, label, spec in cases:
        entries = []
        for scalar, mask_scalar, nickname in spec:
            sk = ec.derive_private_key(int(("%02x" % scalar) * 32, 16), ec.SECP256R1())
            mk = ec.derive_private_key(int(("%02x" % mask_scalar) * 32, 16), ec.SECP256R1())
            entries.append({"scalar_hex": ("%02x" % scalar) * 32, "mask_scalar_hex": ("%02x" % mask_scalar) * 32,
                            "nickname": nickname, "vk": raw_pub(sk), "mask": raw_pub(mk)})
        ordered = sorted(entries, key=lambda e: e["vk"])
        letters = {id(e): LETTERS[i] for i, e in enumerate(ordered)}
        h = hashlib.sha256()
        h.update(lp(b"cravage-roster-1"))
        h.update(lp(session.encode()))
        h.update(bytes([len(entries)]))
        for e in ordered:
            h.update(lp(e["vk"]))
            h.update(lp(e["mask"]))
            h.update(lp(e["nickname"].encode()))
        roster_hash = h.digest()
        f = hashlib.sha256()
        f.update(lp(b"cravage-fingerprint-1"))
        f.update(lp(session.encode()))
        f.update(lp(label.encode()))
        f.update(bytes([len(entries)]))
        f.update(lp(roster_hash))
        out.append({
            "session": session,
            "label": label,
            "entries": [{"scalar_hex": e["scalar_hex"], "mask_scalar_hex": e["mask_scalar_hex"], "nickname": e["nickname"]} for e in entries],
            "letters": [letters[id(e)] for e in entries],
            "roster_hash": roster_hash.hex(),
            "fingerprint": crockford(f.digest()[:5]),
        })
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(here, "..", "CravageCore", "Tests", "CravageCoreTests", "Fixtures", "core_vectors.json")
    rng = random.Random(20260913)
    fixture = {
        "generator": "Tools/gen_core_fixtures.py",
        "rounds": rounds(rng),
        "wrapping_adds": wrapping_adds(rng),
        "rosters": roster_vectors(),
        **crypto_vectors(),
    }
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(fixture, f, indent=1, sort_keys=True)
        f.write("\n")
    print(f"wrote {os.path.normpath(out_path)}: {len(fixture['rounds'])} rounds, "
          f"{len(fixture['wrapping_adds'])} wrapping adds, {len(fixture['signatures'])} signatures, "
          f"{len(fixture['masks'])} masks, {len(fixture['rosters'])} rosters")
    return 0


if __name__ == "__main__":
    sys.exit(main())
