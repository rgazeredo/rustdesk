import Foundation
import Security

@main struct IdentityTest {
    static func main() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("azsign-native-test-" + UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: dir) }
        func write(_ name: String, _ data: Data) throws {
            let file = dir.appendingPathComponent(name)
            try data.write(to: file)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        func openssl(_ args: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/opt/openssl@3/bin/openssl")
            process.currentDirectoryURL = dir
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw AzsignIdentity.fail() }
        }
        func generate() throws -> SecKey {
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits: 2048] as CFDictionary, &error) else { throw AzsignIdentity.fail() }
            return key
        }
        func rejects(_ action: () throws -> Void) throws {
            do { try action() } catch { return }
            throw NSError(domain: "Test unexpectedly accepted invalid input", code: 1)
        }
        let identity = UUID().uuidString.lowercased()
        let key = try generate()
        try write("device.csr", Data(AzsignIdentity.csr(identity, key).utf8))
        try openssl(["req", "-in", "device.csr", "-verify", "-noout"])
        let privateBytes = try AzsignIdentity.export(key)
        try write("key.der", AzsignIdentity.der(0x30, Data([2, 1, 0]) + AzsignIdentity.rsaAlgorithm + AzsignIdentity.der(4, privateBytes)))
        try openssl(["pkey", "-inform", "DER", "-in", "key.der", "-check", "-noout"])
        try openssl(["req", "-x509", "-newkey", "rsa:2048", "-noenc", "-sha256", "-days", "1", "-subj", "/CN=Disposable Native Test CA", "-keyout", "ca.key", "-out", "ca.pem", "-addext", "basicConstraints=critical,CA:TRUE,pathlen:0"])
        try write("client.ext", Data("basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth\n".utf8))
        try openssl(["x509", "-req", "-in", "device.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial", "-days", "1", "-sha256", "-extfile", "client.ext", "-out", "leaf.pem"])
        let leaf = try AzsignIdentity.certificate(String(contentsOf: dir.appendingPathComponent("leaf.pem"), encoding: .utf8))
        let ca = try AzsignIdentity.certificate(String(contentsOf: dir.appendingPathComponent("ca.pem"), encoding: .utf8))
        try AzsignIdentity.validate(leaf, ca: ca, identity: identity, privateKey: key)
        try rejects { try AzsignIdentity.validate(leaf, ca: ca, identity: UUID().uuidString, privateKey: key) }
        try rejects { try AzsignIdentity.validate(leaf, ca: ca, identity: identity, privateKey: generate()) }
        try rejects { _ = try AzsignIdentity.csr("not-a-uuid", key) }
        try rejects { _ = try AzsignIdentity.certificate("invalid") }
        try write("server.ext", Data("basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n".utf8))
        try openssl(["x509", "-req", "-in", "device.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial", "-days", "1", "-sha256", "-extfile", "server.ext", "-out", "server.pem"])
        let server = try AzsignIdentity.certificate(String(contentsOf: dir.appendingPathComponent("server.pem"), encoding: .utf8))
        try rejects { try AzsignIdentity.validate(server, ca: ca, identity: identity, privateKey: key) }
        _ = try AzsignIdentity.date("2026-09-29T00:00:00.000000Z")
        print("PASS: native RSA CSR signature, PKCS8, certificate trust, clientAuth, CN/key binding and malformed input")
    }
}
