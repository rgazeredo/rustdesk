import Foundation
import Security

/// Native-only enrollment. Private bytes never cross the Flutter channel.
/// Calls must be serialized on `queue`, including logout.
enum AzsignIdentity {
    static let queue = DispatchQueue(label: "com.azsign.rustdesk.enrollment")
    static let account = "azsign_desktop_enrollment"
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: AzsignKeychain.service,
         kSecAttrAccount as String: account]
    }
    static func fail() -> NSError { AzsignKeychain.failure(errSecParam) }

    static func read() throws -> [String: Any]? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data,
              data.count <= 32768,
              let record = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AzsignKeychain.failure(status) }
        return record
    }

    static func save(_ record: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        guard data.count <= 32768 else { throw fail() }
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AzsignKeychain.failure(status) }
    }

    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AzsignKeychain.failure(status) }
    }

    // DER framing only; RSA generation and signing are provided by Security.framework.
    static func der(_ tag: UInt8, _ bytes: Data) -> Data {
        var length = bytes.count
        var encoded = Data()
        if length < 128 { encoded.append(UInt8(length)) }
        else {
            while length > 0 { encoded.insert(UInt8(length & 255), at: 0); length >>= 8 }
            encoded.insert(0x80 | UInt8(encoded.count), at: 0)
        }
        return Data([tag]) + encoded + bytes
    }
    static let rsaAlgorithm = Data([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
    static let sha256RSA = Data([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b, 0x05, 0x00])

    static func key(_ bytes: Data) throws -> SecKey {
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(bytes as CFData,
            [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary, &error)
        else { throw fail() }
        return key
    }
    static func export(_ key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let bytes = SecKeyCopyExternalRepresentation(key, &error) else { throw fail() }
        return bytes as Data
    }
    static func csr(_ identity: String, _ key: SecKey) throws -> String {
        guard UUID(uuidString: identity) != nil, let publicKey = SecKeyCopyPublicKey(key) else { throw fail() }
        let subject = der(0x30, der(0x31, der(0x30, Data([0x06, 0x03, 0x55, 0x04, 0x03]) + der(0x0c, Data(identity.utf8)))))
        let spki = der(0x30, rsaAlgorithm + der(0x03, Data([0]) + (try export(publicKey))))
        let request = der(0x30, Data([0x02, 0x01, 0x00]) + subject + spki + Data([0xa0, 0x00]))
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, request as CFData, &error)
        else { throw fail() }
        let encoded = der(0x30, request + sha256RSA + der(0x03, Data([0]) + (signature as Data)))
        return "-----BEGIN CERTIFICATE REQUEST-----\n" + encoded.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed]) + "\n-----END CERTIFICATE REQUEST-----\n"
    }

    static func prepare(_ identity: String) throws -> [String: String] {
        guard UUID(uuidString: identity) != nil else { throw fail() }
        var record = try read()
        let privateKey: SecKey
        if let current = record, current["identity_id"] as? String == identity,
           let encoded = current["private_pkcs1"] as? String, let bytes = Data(base64Encoded: encoded) {
            privateKey = try key(bytes)
        } else {
            var error: Unmanaged<CFError>?
            guard let generated = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits: 2048] as CFDictionary, &error) else { throw fail() }
            privateKey = generated
            let bytes = try export(generated)
            record = ["identity_id": identity, "active": false,
                      "private_pkcs1": bytes.base64EncodedString(),
                      "private_pkcs8": der(0x30, Data([0x02, 0x01, 0]) + rsaAlgorithm + der(0x04, bytes)).base64EncodedString()]
            try save(record!)
        }
        return ["identity_id": identity, "csr": try csr(identity, privateKey)]
    }

    static func certificate(_ pem: String) throws -> SecCertificate {
        guard pem.utf8.count <= 16384 else { throw fail() }
        let body = pem.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let data = Data(base64Encoded: body),
              let cert = SecCertificateCreateWithData(nil, data as CFData) else { throw fail() }
        return cert
    }

    static func date(_ value: Any?) throws -> Date {
        guard let text = value as? String else { throw fail() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: text) else { throw fail() }
        return date
    }

    static func validate(_ leaf: SecCertificate, ca: SecCertificate, identity: String, privateKey: SecKey) throws {
        var cn: CFString?
        guard SecCertificateCopyCommonName(leaf, &cn) == errSecSuccess, cn as String? == identity,
              let leafKey = SecCertificateCopyKey(leaf), let ownKey = SecKeyCopyPublicKey(privateKey),
              try export(leafKey) == export(ownKey) else { throw fail() }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates([leaf] as CFArray, SecPolicyCreateSSL(false, nil), &trust) == errSecSuccess,
              let checked = trust,
              SecTrustSetAnchorCertificates(checked, [ca] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(checked, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(checked, false) == errSecSuccess,
              SecTrustEvaluateWithError(checked, nil) else { throw fail() }
    }

    static func install(_ args: [String: Any]) throws -> [String: Any] {
        guard let identity = args["identity_id"] as? String,
              var record = try read(), record["identity_id"] as? String == identity,
              let privateData = record["private_pkcs1"] as? String, let bytes = Data(base64Encoded: privateData),
              let pem = args["certificate"] as? String, let caPEM = args["ca_certificate"] as? String,
              let profile = args["profile"] as? [String: Any],
              let host = profile["host"] as? String, let serverName = profile["server_name"] as? String,
              host.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$", options: .regularExpression) != nil,
              serverName.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$", options: .regularExpression) != nil
        else { throw fail() }
        for name in ["registration", "rendezvous", "relay"] {
            guard let port = profile[name] as? Int, (1024...65535).contains(port) else { throw fail() }
        }
        let leaf = try certificate(pem), ca = try certificate(caPEM)
        try validate(leaf, ca: ca, identity: identity, privateKey: key(bytes))
        let expiry = min(try date(args["expires_at"]), try date(args["session_expires_at"]))
        guard expiry > Date() else { throw fail() }
        record["profile"] = profile
        record["certificate_base64"] = (SecCertificateCopyData(leaf) as Data).base64EncodedString()
        record["ca_base64"] = (SecCertificateCopyData(ca) as Data).base64EncodedString()
        record["expires_at"] = UInt64(expiry.timeIntervalSince1970 * 1000)
        record["active"] = true
        try save(record)
        return ["identity_id": identity, "expires_at": record["expires_at"]!]
    }
}
