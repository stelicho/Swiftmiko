// Tests/SwiftmikoTests/SSHKeyLoaderTests.swift
//
// Keys embedded below were generated with real `ssh-keygen` (not
// synthesized), then round-tripped end-to-end: decrypt with
// SSHKeyLoader, re-derive the public key, and confirm it matches the
// real .pub file byte-for-byte. That's the strongest correctness
// signal available without live network hardware to authenticate
// against.
import XCTest
import NIOSSH
@testable import Swiftmiko

final class SSHKeyLoaderTests: XCTestCase {
    private func writeTempKey(_ pem: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sshkeyloadertests-\(UUID().uuidString)")
        try pem.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    // ssh-keygen -t ed25519 -N "correcthorsebatterystaple" -C "swiftmiko-test"
    private let encryptedEd25519CTR = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABA5dif/4O
    jXooiXF+VyaXaCAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIKGNOO4p7AcbdXpS
    idKTe2nI/dc64afDT/s7Sg7oUs3gAAAAoIOng6yGPZ4gLDO6rSTP6wetsJLsXe5bM/Vw9t
    UWnHKSlKTH9MbChl8tWI38v0yrz/f5m1NSRG67hKBRHzxt/k5VHurUW4BaBDqia6JGg0yb
    eneOYfX831Yfpk1rpz9YhFm9rNmN75zGSBa2Po9yFjsaKQFyvopcrPiK+yAenA05h5aTza
    XDRataiMQU02yDIidfWGdFb8MmLvZgyGayxiY=
    -----END OPENSSH PRIVATE KEY-----
    """
    private let encryptedEd25519CTRPublicKeyBase64 = "AAAAC3NzaC1lZDI1NTE5AAAAIKGNOO4p7AcbdXpSidKTe2nI/dc64afDT/s7Sg7oUs3g"

    // ssh-keygen -t ecdsa -b 256 -N "anotherpassphrase123" -C "swiftmiko-ecdsa-test"
    private let encryptedECDSA = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABB+rbZXh6
    5m+WjVDSilv4pYAAAAGAAAAAEAAABoAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlz
    dHAyNTYAAABBBOzfbta2Wi5rG+4pyFCXaGqykYFdjzv5VR2A3U+F70BmGARMTNA1kTeXHi
    LVtWBW+dVImp2wUGted+fyq/ndlIoAAACwf52R5dG/3QPg94PnguLRsvRkTTOkueo+S8uF
    YthFlbZmjJu+09QzQiCKsX55l4eig+pBi9jrZ6gaJfFC3n6O6rHArt3AlYHz1kT1+TlIzh
    P9EWBU7yLbkvKEyNLxP+tWx+nnKvr1HAoVeB3Do6L3jAMs7wgHwqKm8r5TAktJ+/+2GOD4
    CDU2kMG/AkhKLTi6It3kFB6TT9SPUITLj3s3pPIyQt7QA9eRzvY+BGGSID0=
    -----END OPENSSH PRIVATE KEY-----
    """
    private let encryptedECDSAPublicKeyBase64 =
        "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOzfbta2Wi5rG+4pyFCXaGqykYFdjzv5VR2A3U+F70BmGARMTNA1kTeXHiLVtWBW+dVImp2wUGted+fyq/ndlIo="

    // ssh-keygen -t ed25519 -N "cbcpassphrase" -C "swiftmiko-cbc-test" -Z aes256-cbc
    private let encryptedEd25519CBC = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jYmMAAAAGYmNyeXB0AAAAGAAAABDC7k5TE1
    pcg04elBhZtH+zAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIPP4T+nejRX3Lddm
    jfN3Mh/6nd1iZRC2Sja7D+w83QgNAAAAoPx/zixvy/I+DJLmpkpdFNxNSX9OYL1aQNBjOD
    wBx+5v6EdO96JaLOPNmTF6pxUMTZKeN4ZTzuZlnkzXdwHi8cGgwjBq5MNucJQCUHt17WI2
    szTehu8wsn27czuXyfj3B7hIovI4NSpHXZXiQ6xOkVNj1rR7gmCOcH5Y9ZIlJzSUhIEkGP
    T01mwqhlH0keGS3XAY1jV2s+M+NFzE2pZff30=
    -----END OPENSSH PRIVATE KEY-----
    """
    private let encryptedEd25519CBCPublicKeyBase64 = "AAAAC3NzaC1lZDI1NTE5AAAAIPP4T+nejRX3LddmjfN3Mh/6nd1iZRC2Sja7D+w83QgN"

    // ssh-keygen -t rsa -b 2048 -N "" -C "swiftmiko-rsa-test"
    // Full signing (not just parsing) was additionally verified against
    // a real, independent asyncssh server — this key successfully
    // authenticated a live SSH session, meaning asyncssh's own SSH
    // implementation validated the RSA signature Swiftmiko produced.
    // That round trip isn't repeatable here since NIOSSHPrivateKey.sign
    // is internal to the vendored NIOSSH module, not reachable from
    // this test target.
    private let unencryptedRSA = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABFwAAAAdzc2gtcn
    NhAAAAAwEAAQAAAQEAtMDVLnI3+m+ZHor+Gvud2ibXud6lexGx09oXJTfp3hqAMJVWRGky
    Vkg3NVpqtWPUV0VYM0EUAZze7VkfSg83bXTAXntoYEJkijLJ2UBb13OYTcU2dgln3vM0gP
    s4lqz+bi4Po+5T8E1wBO5K2kWhCyrXQuAXWYoVZS9WjOYDEtCVvrFC0k0Msd5hK5BucK8k
    UCuMlmtmOhFNEEgJSMp5lPsd76qb5Ls+WXyiKnrRqhqgX4D58KMopcSKuqxV/B8c8cDTIn
    CmjCBAaDuzM+7bItDTALQ0DdZYsJ1DRAPqGdDZF1d5O/lUhdZvNjIOgs7PYby9MZ+WSG2i
    dMB/kup8cwAAA8j7pLM2+6SzNgAAAAdzc2gtcnNhAAABAQC0wNUucjf6b5keiv4a+53aJt
    e53qV7EbHT2hclN+neGoAwlVZEaTJWSDc1Wmq1Y9RXRVgzQRQBnN7tWR9KDzdtdMBee2hg
    QmSKMsnZQFvXc5hNxTZ2CWfe8zSA+ziWrP5uLg+j7lPwTXAE7kraRaELKtdC4BdZihVlL1
    aM5gMS0JW+sULSTQyx3mErkG5wryRQK4yWa2Y6EU0QSAlIynmU+x3vqpvkuz5ZfKIqetGq
    GqBfgPnwoyilxIq6rFX8HxzxwNMicKaMIEBoO7Mz7tsi0NMAtDQN1liwnUNEA+oZ0NkXV3
    k7+VSF1m82Mg6Czs9hvL0xn5ZIbaJ0wH+S6nxzAAAAAwEAAQAAAQEAniBYHyLS7+bzSDIG
    LKrUpET40mUB1ZFcRV50gx3QHXqHjHkImB6DZ9ITYjxwP7FO0O4cQ/J5wxNuPquJ4OtA7S
    OHKuDBJfzPIctepA1WizxYECkoBMkjsnqHAxNDpSVADDmFez8C9aV5CwdAOoVRZoia+qk6
    JB3Vq8hm6ipKpAiVO4z0IR3oel7Gf1X6AKw7/d+yIQd5ueL98aTLvOP7A1O5K7r12QXglb
    5z6BToKfF2qHMYNyXNdgcWr8OvXJgpuv0Rcni23Sy0P6LRayHA6UdkKdvR7lCLsgQBHk5k
    zYTJVeZ9Jci4uS8tv+RnNZhVjfPQKrEJAqa/jntyUssTWQAAAIBosdYq/C04t2n3YLvMcy
    6k5MqlRjykMCFX0f3ztYttMocOLxXE9AfZAYjFIeqvYai4K5sSgmQ0/IW/2TqB/jfPJyyA
    JTLh3P5fKjcX7xGgZoChLeJ8bk34jae8Jf7/80rzKIREYKS6HqcPPc/giqebvChV+GE1r+
    gk5R7V9kHMUwAAAIEA8PVrn5rjDemOhDTXCEN3tLBRrW/W4tWKC2RKDYKr1JIT6C1zzCVd
    HoXNFuQj1PMHSCvrnjip+DtozYRpTMbMBWX7NFILwJDz/vDE2FSQlk9Nao2vrEOQTfmjD/
    XFXCijBQyeKe/Uvcl1RM4WQFCqTC+DjUlwBRkobKpGXSTWU+cAAACBAMAJUJHVVkdrj5ca
    BgT7IUbrcV6WS5gXaqYsxb9u8YroIHtuQony0PcOsBzYTl5MCfFWoaXZDRQgBSy3VYVmiF
    ZcZc9TTW2Wh86fJnElqYYv1CrERkD47YCkIHmae/+xJpT+18i9OSYFzytQEnNVrseHiYcl
    CS5/Wo++oYyWckGVAAAAEnN3aWZ0bWlrby1yc2EtdGVzdA==
    -----END OPENSSH PRIVATE KEY-----
    """
    private let unencryptedRSAPublicKeyBase64 =
        "AAAAB3NzaC1yc2EAAAADAQABAAABAQC0wNUucjf6b5keiv4a+53aJte53qV7EbHT2hclN+neGoAwlVZEaTJWSDc1Wmq1Y9RXRVgzQRQBnN7tWR9KDzdtdMBee2hgQmSKMsnZQFvXc5hNxTZ2CWfe8zSA+ziWrP5uLg+j7lPwTXAE7kraRaELKtdC4BdZihVlL1aM5gMS0JW+sULSTQyx3mErkG5wryRQK4yWa2Y6EU0QSAlIynmU+x3vqpvkuz5ZfKIqetGqGqBfgPnwoyilxIq6rFX8HxzxwNMicKaMIEBoO7Mz7tsi0NMAtDQN1liwnUNEA+oZ0NkXV3k7+VSF1m82Mg6Czs9hvL0xn5ZIbaJ0wH+S6nxz"

    func testParsesOpenSSHFormatRSAKeyAndReconstructsMatchingPublicKey() throws {
        let path = try writeTempKey(unencryptedRSA)
        let key = try SSHKeyLoader.load(path: path, passphrase: nil)
        XCTAssertTrue(String(openSSHPublicKey: key.publicKey).contains(unencryptedRSAPublicKeyBase64))
    }

    func testDecryptsAes256CtrEncryptedEd25519Key() throws {
        let path = try writeTempKey(encryptedEd25519CTR)
        let key = try SSHKeyLoader.load(path: path, passphrase: "correcthorsebatterystaple")
        XCTAssertTrue(String(openSSHPublicKey: key.publicKey).contains(encryptedEd25519CTRPublicKeyBase64))
    }

    func testDecryptsAes256CtrEncryptedECDSAKey() throws {
        let path = try writeTempKey(encryptedECDSA)
        let key = try SSHKeyLoader.load(path: path, passphrase: "anotherpassphrase123")
        XCTAssertTrue(String(openSSHPublicKey: key.publicKey).contains(encryptedECDSAPublicKeyBase64))
    }

    func testDecryptsAes256CbcEncryptedEd25519Key() throws {
        let path = try writeTempKey(encryptedEd25519CBC)
        let key = try SSHKeyLoader.load(path: path, passphrase: "cbcpassphrase")
        XCTAssertTrue(String(openSSHPublicKey: key.publicKey).contains(encryptedEd25519CBCPublicKeyBase64))
    }

    func testWrongPassphraseThrowsRatherThanProducingWrongKeyMaterial() throws {
        let path = try writeTempKey(encryptedEd25519CTR)
        XCTAssertThrowsError(try SSHKeyLoader.load(path: path, passphrase: "wrong-passphrase")) { error in
            guard case SwiftmikoError.authenticationFailed = error else {
                return XCTFail("Expected authenticationFailed, got \(error)")
            }
        }
    }

    func testMissingPassphraseOnEncryptedKeyThrowsClearError() throws {
        let path = try writeTempKey(encryptedEd25519CTR)
        XCTAssertThrowsError(try SSHKeyLoader.load(path: path, passphrase: nil)) { error in
            guard case SwiftmikoError.authenticationFailed(let message) = error else {
                return XCTFail("Expected authenticationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("passphrase"))
        }
    }

    // ssh-keygen -t ed25519 -N "" -C "swiftmiko-unencrypted-test"
    // Regression check that the pre-existing unencrypted parse path
    // still works unchanged.
    private let unencryptedEd25519 = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACBEZoTTsj7qsXmX9LOVEDpIXbIkHl2sQB9rz+Se9ndhOQAAAKBrfwpEa38K
    RAAAAAtzc2gtZWQyNTUxOQAAACBEZoTTsj7qsXmX9LOVEDpIXbIkHl2sQB9rz+Se9ndhOQ
    AAAEDscoWynP6joQvBIPawb7RXbdmFTFRmQz8B3Pk1S6sB+ERmhNOyPuqxeZf0s5UQOkhd
    siQeXaxAH2vP5J72d2E5AAAAGnN3aWZ0bWlrby11bmVuY3J5cHRlZC10ZXN0AQID
    -----END OPENSSH PRIVATE KEY-----
    """
    private let unencryptedEd25519PublicKeyBase64 = "AAAAC3NzaC1lZDI1NTE5AAAAIERmhNOyPuqxeZf0s5UQOkhdsiQeXaxAH2vP5J72d2E5"

    func testUnencryptedKeyStillLoadsWithoutAPassphrase() throws {
        let path = try writeTempKey(unencryptedEd25519)
        let key = try SSHKeyLoader.load(path: path, passphrase: nil)
        XCTAssertTrue(String(openSSHPublicKey: key.publicKey).contains(unencryptedEd25519PublicKeyBase64))
    }
}
