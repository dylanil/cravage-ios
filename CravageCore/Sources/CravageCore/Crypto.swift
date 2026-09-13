// Crypto: the CryptoKit primitives behind the protocol (PLAN.md "Crypto via CryptoKit").
//
// Signing: P-256 ECDSA over SHA-256 of the UTF-8 canonical message. Verifying keys travel as the
// 65-byte X9.63 uncompressed point, base64; signatures as raw r||s (64 bytes), base64. These are
// WebCrypto's raw forms and what verify_round.py reads back.
// Masks: P-256 ECDH shared secret (the x coordinate) into HKDF-SHA256 with empty salt and info
// "SMPC mask " + lo + hi, 8 bytes big-endian as a signed Int64. Pinned vector 5107112043798890199.
//
// Signing keys and mask keys are distinct Swift types with no conversion between them, so a
// signing key can never be used for agreement or the reverse. Private key material is never
// printed: neither type conforms to CustomStringConvertible or exposes its raw bytes.

import CryptoKit
import Foundation

public enum CryptoError: Error, Equatable, Sendable {
    case invalidBase64
    case invalidPublicKey
    case invalidPrivateKey
    case invalidSignatureEncoding
}

// MARK: - Signing

/// A P-256 ECDSA signature in raw r||s form (64 bytes).
public struct Signature: Hashable, Sendable {
    public let raw: Data

    public init(raw: Data) throws {
        guard raw.count == 64 else { throw CryptoError.invalidSignatureEncoding }
        self.raw = raw
    }

    public init(base64: String) throws {
        guard let data = Data(base64Encoded: base64) else { throw CryptoError.invalidBase64 }
        try self.init(raw: data)
    }

    public var base64: String { raw.base64EncodedString() }
}

/// A P-256 verifying key. Orders bytewise on its X9.63 encoding, which is how letters are assigned.
public struct VerifyingKey: Hashable, Comparable, Sendable {
    public let x963: Data
    private let key: P256.Signing.PublicKey

    fileprivate init(_ key: P256.Signing.PublicKey) {
        self.key = key
        self.x963 = key.x963Representation
    }

    public init(x963: Data) throws {
        guard x963.count == 65, x963.first == 0x04, let key = try? P256.Signing.PublicKey(x963Representation: x963) else {
            throw CryptoError.invalidPublicKey
        }
        self.init(key)
    }

    public init(base64: String) throws {
        guard let data = Data(base64Encoded: base64) else { throw CryptoError.invalidBase64 }
        try self.init(x963: data)
    }

    public var base64: String { x963.base64EncodedString() }

    /// Verifies `signature` over the UTF-8 bytes of `message` (ECDSA with SHA-256).
    public func verify(_ signature: Signature, message: String) -> Bool {
        guard let ecdsa = try? P256.Signing.ECDSASignature(rawRepresentation: signature.raw) else { return false }
        return key.isValidSignature(ecdsa, for: Data(message.utf8))
    }

    public static func == (lhs: VerifyingKey, rhs: VerifyingKey) -> Bool { lhs.x963 == rhs.x963 }
    public func hash(into hasher: inout Hasher) { hasher.combine(x963) }
    public static func < (lhs: VerifyingKey, rhs: VerifyingKey) -> Bool {
        lhs.x963.lexicographicallyPrecedes(rhs.x963)
    }
}

/// A per-round P-256 signing key. Fresh on every round and restart; never persisted.
public struct SigningKey: Sendable {
    private let key: P256.Signing.PrivateKey
    public let verifyingKey: VerifyingKey

    public init() {
        self.init(key: P256.Signing.PrivateKey())
    }

    /// Deterministic construction from the 32-byte scalar, for tests and fixtures only.
    public init(rawRepresentation: Data) throws {
        guard let key = try? P256.Signing.PrivateKey(rawRepresentation: rawRepresentation) else {
            throw CryptoError.invalidPrivateKey
        }
        self.init(key: key)
    }

    private init(key: P256.Signing.PrivateKey) {
        self.key = key
        self.verifyingKey = VerifyingKey(key.publicKey)
    }

    /// Signs the UTF-8 bytes of `message` (ECDSA with SHA-256). Randomized: two signatures over
    /// the same message differ, which is why first-write-wins compares content, not signatures.
    public func sign(_ message: String) -> Signature {
        // Signing with a valid key over finite data cannot fail; a failure here is a CryptoKit
        // invariant violation, which is a programming error rather than a recoverable state.
        let signature = try! key.signature(for: Data(message.utf8))
        return try! Signature(raw: signature.rawRepresentation)
    }
}

// MARK: - Masks

/// A P-256 key-agreement public key, sent inside the signed hello.
public struct MaskPublicKey: Hashable, Sendable {
    public let x963: Data
    fileprivate let key: P256.KeyAgreement.PublicKey

    fileprivate init(_ key: P256.KeyAgreement.PublicKey) {
        self.key = key
        self.x963 = key.x963Representation
    }

    public init(x963: Data) throws {
        guard x963.count == 65, x963.first == 0x04,
              let key = try? P256.KeyAgreement.PublicKey(x963Representation: x963) else {
            throw CryptoError.invalidPublicKey
        }
        self.init(key)
    }

    public init(base64: String) throws {
        guard let data = Data(base64Encoded: base64) else { throw CryptoError.invalidBase64 }
        try self.init(x963: data)
    }

    public var base64: String { x963.base64EncodedString() }

    public static func == (lhs: MaskPublicKey, rhs: MaskPublicKey) -> Bool { lhs.x963 == rhs.x963 }
    public func hash(into hasher: inout Hasher) { hasher.combine(x963) }
}

/// A per-round P-256 key-agreement key. Fresh on every round and restart; never persisted.
public struct MaskPrivateKey: Sendable {
    private let key: P256.KeyAgreement.PrivateKey
    public let publicKey: MaskPublicKey

    public init() {
        self.init(key: P256.KeyAgreement.PrivateKey())
    }

    /// Deterministic construction from the 32-byte scalar, for tests and fixtures only.
    public init(rawRepresentation: Data) throws {
        guard let key = try? P256.KeyAgreement.PrivateKey(rawRepresentation: rawRepresentation) else {
            throw CryptoError.invalidPrivateKey
        }
        self.init(key: key)
    }

    private init(key: P256.KeyAgreement.PrivateKey) {
        self.key = key
        self.publicKey = MaskPublicKey(key.publicKey)
    }

    /// The pair mask r(lo, hi): ECDH with `other`, HKDF-SHA256, empty salt, info
    /// "SMPC mask " + lo + hi, 8 bytes big-endian as signed Int64. Symmetric: both members of the
    /// pair derive the same value when they pass the same (lo, hi) letters.
    public func mask(with other: MaskPublicKey, lo: PartyLabel, hi: PartyLabel) -> Int64 {
        // Both keys are validated on-curve P-256 points, so agreement cannot fail.
        let shared = try! key.sharedSecretFromKeyAgreement(with: other.key)
        let derived = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(),
                                                     sharedInfo: Data(("SMPC mask " + lo.letter + hi.letter).utf8),
                                                     outputByteCount: 8)
        let bytes = derived.withUnsafeBytes { Data($0) }
        return Wraparound.signedInt64BigEndian(bytes)
    }
}

// MARK: - Digest

public enum Digest {
    public static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
