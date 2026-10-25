import Foundation
import Security
import CryptoKit
import AsterCore

/// Paid licensing is intentionally dormant during the free release.
/// Restore the public merchant/product configuration only after gateway approval.
enum LicenseConfiguration {
    static func bundled() -> DodoConfiguration? {
        guard AsterAccessPolicy.requiresLicense,
              let url = Bundle.main.url(forResource: "DodoConfiguration", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(DodoConfiguration.self, from: data),
              configuration.isValid else { return nil }
        return configuration
    }
}

/// License secrets never enter preferences, URLs, analytics or application logs.
/// In the free release LicenseController never reads or writes this store.
@MainActor
final class KeychainLicenseStore: LicenseStore {
    private let service: String
    private let account: String
    private let verificationMarkerURL: URL

    init(configuration: DodoConfiguration?, bundleIdentifier: String? = Bundle.main.bundleIdentifier,
         markerDirectory: URL? = nil) {
        service = (bundleIdentifier ?? "com.aster.storage.dev") + ".license"
        account = "dodo." + (configuration.map { "\($0.environment.rawValue).\($0.businessID).\($0.productID)" } ?? "unconfigured")
        let namespace = SHA256.hash(data: Data((service + account).utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = markerDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aster/LicenseVerification", isDirectory: true)
        verificationMarkerURL = directory.appendingPathComponent(namespace + ".verify-online")
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> LicenseRecord? {
        var request = query
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError() }
        do { return try JSONDecoder().decode(LicenseRecord.self, from: data) }
        catch { throw KeychainError() }
    }

    func save(_ record: LicenseRecord) throws {
        let data = try JSONEncoder().encode(record)
        let updates = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw KeychainError() }
        } else if status != errSecSuccess { throw KeychainError() }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError() }
    }

    func requiresOnlineVerification() throws -> Bool {
        do {
            _ = try Data(contentsOf: verificationMarkerURL)
            return true
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return false
        } catch { throw KeychainError() }
    }

    func setRequiresOnlineVerification(_ required: Bool) throws {
        if required {
            try FileManager.default.createDirectory(at: verificationMarkerURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data("Online verification required".utf8).write(to: verificationMarkerURL, options: .atomic)
        } else {
            do { try FileManager.default.removeItem(at: verificationMarkerURL) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError { }
        }
    }

    private struct KeychainError: LocalizedError {
        var errorDescription: String? {
            "Aster could not access its license in Keychain. Unlock your Mac and try again."
        }
    }
}
