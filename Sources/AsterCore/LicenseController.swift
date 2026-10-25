import Foundation
import Observation

public struct LicenseRecord: Codable, Equatable, Sendable {
    public let key: String
    public let instanceID: String
    public let businessID: String
    public let productID: String
    public let environment: DodoEnvironment
    public var lastValidatedAt: Date?
    public var revoked: Bool

    public init(key: String, instanceID: String, businessID: String, productID: String,
                environment: DodoEnvironment, lastValidatedAt: Date?, revoked: Bool = false) {
        self.key = key
        self.instanceID = instanceID
        self.businessID = businessID
        self.productID = productID
        self.environment = environment
        self.lastValidatedAt = lastValidatedAt
        self.revoked = revoked
    }
}

@MainActor public protocol LicenseStore {
    func load() throws -> LicenseRecord?
    func save(_ record: LicenseRecord) throws
    func delete() throws
    /// Persist this non-secret marker independently of credential storage. It prevents an old
    /// cached entitlement from returning after revocation when Keychain cannot be updated.
    func requiresOnlineVerification() throws -> Bool
    func setRequiresOnlineVerification(_ required: Bool) throws
}

@MainActor @Observable public final class LicenseController {
    public static let offlineGrace: TimeInterval = 7 * 24 * 60 * 60
    public let requiresLicense: Bool
    public let configuration: DodoConfiguration?
    public private(set) var isBusy = false
    public private(set) var message: String?
    public private(set) var errorMessage: String?
    private var record: LicenseRecord?
    private var mustVerifyOnline = false
    @ObservationIgnored private let store: any LicenseStore
    @ObservationIgnored private let client: (any DodoLicenseClient)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var storageReadable = true

    public init(configuration: DodoConfiguration?, store: any LicenseStore,
                client: (any DodoLicenseClient)? = nil, now: @escaping () -> Date = Date.init,
                requiresLicense: Bool = AsterAccessPolicy.requiresLicense) {
        self.requiresLicense = requiresLicense
        self.configuration = requiresLicense ? configuration.flatMap { $0.isValid ? $0 : nil } : nil
        self.store = store
        self.client = requiresLicense ? (client ?? self.configuration.map { DodoAPIClient(configuration: $0) }) : nil
        self.now = now
        // Free releases never read license storage, construct a payment client, or perform
        // activation checks. Old or revoked paid credentials cannot restrict free access.
        guard requiresLicense else { return }
        do {
            mustVerifyOnline = try store.requiresOnlineVerification()
            record = try store.load()
        } catch {
            storageReadable = false
            errorMessage = "Your saved license could not be read from Keychain. Unlock Keychain and reopen Aster."
        }
    }

    public var checkoutURL: URL? { requiresLicense ? configuration?.checkoutURL : nil }
    public var hasSavedLicense: Bool { record != nil }
    public var lastValidatedAt: Date? { matchingRecord?.lastValidatedAt }
    public var offlineUntil: Date? {
        guard !mustVerifyOnline, let record = matchingRecord, !record.revoked, let date = record.lastValidatedAt else { return nil }
        return date.addingTimeInterval(Self.offlineGrace)
    }
    /// Evaluates the clock at the point of use, including immediately before cleanup.
    public var isPro: Bool {
        guard requiresLicense else { return true }
        guard !mustVerifyOnline, let record = matchingRecord, !record.revoked, let validated = record.lastValidatedAt else { return false }
        let current = now()
        return current >= validated.addingTimeInterval(-300) && current < validated.addingTimeInterval(Self.offlineGrace)
    }

    private var matchingRecord: LicenseRecord? {
        guard let record, let configuration,
              record.environment == configuration.environment,
              record.businessID == configuration.businessID,
              record.productID == configuration.productID,
              !record.instanceID.isEmpty, !record.key.isEmpty else { return nil }
        return record
    }

    public func activate(_ enteredKey: String) async {
        guard requiresLicense else { clearPaidMessages(); return }
        guard !isBusy else { return }
        guard let configuration, let client, storageReadable else { setupError(); return }
        let key = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= 512, !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            errorMessage = "Paste the license key from your purchase email."
            return
        }
        if let saved = record {
            guard saved.key == key, matchingRecord != nil else {
                errorMessage = "Deactivate the saved license before using a different key or product."
                return
            }
            await refresh()
            return
        }
        isBusy = true
        errorMessage = nil
        message = nil
        defer { isBusy = false }
        do {
            let activation = try await client.activate(key: key, name: "Aster Mac \(UUID().uuidString.prefix(8))")
            guard activation.businessID == configuration.businessID,
                  activation.productID == configuration.productID,
                  !activation.instanceID.isEmpty else {
                if !activation.instanceID.isEmpty {
                    do {
                        try await client.deactivate(key: key, instanceID: activation.instanceID)
                    } catch {
                        let pendingRelease = LicenseRecord(key: key, instanceID: activation.instanceID,
                                                           businessID: activation.businessID,
                                                           productID: activation.productID ?? "",
                                                           environment: configuration.environment,
                                                           lastValidatedAt: nil, revoked: true)
                        record = pendingRelease
                        mustVerifyOnline = true
                        try? store.setRequiresOnlineVerification(true)
                        do {
                            try store.save(pendingRelease)
                            errorMessage = "This key belongs to another product, and its temporary activation could not be released. Retry Deactivate to free its Mac slot."
                        } catch {
                            errorMessage = "This key belongs to another product. Its temporary activation could not be released or saved. Keep Aster open and retry Deactivate to free its Mac slot."
                        }
                        return
                    }
                }
                errorMessage = "This key does not belong to this Aster product. Use the key from your Aster purchase email."
                return
            }
            let pending = LicenseRecord(key: key, instanceID: activation.instanceID,
                                        businessID: activation.businessID, productID: configuration.productID,
                                        environment: configuration.environment, lastValidatedAt: nil)
            do {
                // Save the instance before another request: a retry must not consume another Mac slot.
                try store.save(pending)
                record = pending
            } catch {
                do {
                    try await client.deactivate(key: key, instanceID: activation.instanceID)
                    errorMessage = "Keychain could not save your license. No Mac activation was kept. Unlock Keychain and try again."
                } catch {
                    // Keep the instance in memory so the user can retry deactivation without losing it.
                    record = pending
                    errorMessage = "Keychain could not save your license, and Dodo could not release this activation. Keep Aster open and retry Deactivate; contact purchase support if needed."
                }
                return
            }
            await validateSaved(using: client)
        } catch {
            errorMessage = safeMessage(error)
        }
    }

    public func refresh() async {
        guard requiresLicense else { clearPaidMessages(); return }
        guard !isBusy else { return }
        guard record != nil else { return }
        guard matchingRecord != nil, let client, storageReadable else { setupError(); return }
        isBusy = true
        errorMessage = nil
        message = nil
        defer { isBusy = false }
        await validateSaved(using: client)
    }

    public func deactivate() async {
        guard requiresLicense else { clearPaidMessages(); return }
        guard !isBusy, let saved = record else { return }
        guard let configuration, saved.environment == configuration.environment, let client else { setupError(); return }
        isBusy = true
        errorMessage = nil
        message = nil
        defer { isBusy = false }
        do {
            do {
                try await client.deactivate(key: saved.key, instanceID: saved.instanceID)
            } catch DodoLicenseError.notFound {
                // A previously deleted instance is already released.
            }
            var disabled = saved
            disabled.revoked = true
            mustVerifyOnline = true
            let markerSaved = (try? store.setRequiresOnlineVerification(true)) != nil
            record = disabled
            do {
                try store.delete()
                record = nil
                do {
                    try store.setRequiresOnlineVerification(false)
                    mustVerifyOnline = false
                } catch {
                    // No saved credential remains. A later activation can clear this conservative marker.
                }
                message = "License deactivated on this Mac. You can activate it on another Mac."
            } catch {
                let disabledSaved = (try? store.save(disabled)) != nil
                errorMessage = !markerSaved && !disabledSaved
                    ? "Dodo released this Mac, but its status could not be saved locally. Keep Aster open, unlock Keychain, and retry Deactivate."
                    : "Dodo released this Mac, but Keychain could not remove the saved license. Unlock Keychain and retry Deactivate."
            }
        } catch {
            errorMessage = safeMessage(error)
        }
    }

    private func validateSaved(using client: any DodoLicenseClient) async {
        guard var saved = matchingRecord else { return }
        do {
            let valid = try await client.validate(key: saved.key, instanceID: saved.instanceID)
            guard valid else { revokeSaved(); return }
            saved.lastValidatedAt = now()
            saved.revoked = false
            do {
                try store.save(saved)
                record = saved
                if mustVerifyOnline {
                    try store.setRequiresOnlineVerification(false)
                    mustVerifyOnline = false
                }
                message = "Aster Pro is active on this Mac."
            } catch {
                // Never extend the offline allowance unless the verified timestamp was durably stored.
                errorMessage = "Dodo verified your license, but Keychain could not save the update. Unlock Keychain and retry."
            }
        } catch DodoLicenseError.invalidLicense {
            revokeSaved()
        } catch DodoLicenseError.notFound {
            revokeSaved()
        } catch {
            errorMessage = safeMessage(error)
            if isPro {
                message = "Using your previously verified license. Reconnect before the offline allowance ends."
            } else {
                message = "Free features remain available. Connect to the internet and verify your license to enable Pro."
            }
        }
    }

    private func revokeSaved() {
        guard var saved = record else { return }
        saved.revoked = true
        mustVerifyOnline = true
        let markerSaved = (try? store.setRequiresOnlineVerification(true)) != nil
        record = saved
        do {
            try store.save(saved)
        } catch {
            // Delete the old entitlement if updating its revocation marker fails.
            do { try store.delete() } catch {
                errorMessage = markerSaved
                    ? "This license is no longer valid. Keychain could not save its status; unlock Keychain and verify again."
                    : "This license is no longer valid, and its status could not be saved locally. Keep Aster open, unlock Keychain, and verify again."
                return
            }
        }
        errorMessage = "This license is no longer valid for this Mac. Free features remain available."
    }

    private func clearPaidMessages() {
        message = nil
        errorMessage = nil
    }

    private func setupError() {
        errorMessage = storageReadable
            ? "Purchasing is not configured for this build, or the saved license belongs to a different build."
            : "Your saved license could not be read from Keychain. Unlock Keychain and reopen Aster."
    }

    private func safeMessage(_ error: Error) -> String {
        // Never surface a server response or arbitrary error description containing the key.
        (error as? DodoLicenseError)?.errorDescription ?? "The license request could not be completed. Please try again."
    }
}
