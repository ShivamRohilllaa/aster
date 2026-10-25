import Foundation

public struct DodoActivation: Sendable {
    public let instanceID: String
    public let businessID: String
    public let productID: String?

    public init(instanceID: String, businessID: String, productID: String?) {
        self.instanceID = instanceID
        self.businessID = businessID
        self.productID = productID
    }
}

public enum DodoLicenseError: Error, Equatable, LocalizedError {
    case unavailable, invalidLicense, notFound, activationLimit, malformedResponse, rejected

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Dodo could not be reached. Check your connection and try again."
        case .invalidLicense: "This license is inactive, expired, or has been revoked."
        case .notFound: "This license or activation could not be found. Check the key in your purchase email."
        case .activationLimit: "This license has reached its Mac limit. Deactivate it on your other Mac, or contact purchase support."
        case .malformedResponse: "Dodo returned an unexpected response. Please try again."
        case .rejected: "Dodo could not complete this license request. Check your key and try again."
        }
    }
}

public protocol DodoLicenseClient: Sendable {
    func activate(key: String, name: String) async throws -> DodoActivation
    func validate(key: String, instanceID: String) async throws -> Bool
    func deactivate(key: String, instanceID: String) async throws
}

public struct DodoHTTPResponse: Sendable {
    public let status: Int
    public let data: Data

    public init(status: Int, data: Data) {
        self.status = status
        self.data = data
    }
}

public protocol DodoHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> DodoHTTPResponse
}

/// Ephemeral requests never cache license keys and never forward them through redirects.
public final class DodoURLSessionTransport: DodoHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: DodoRedirectBlocker(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ request: URLRequest) async throws -> DodoHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 1_048_576 else {
            throw DodoLicenseError.malformedResponse
        }
        return DodoHTTPResponse(status: response.statusCode, data: data)
    }
}

private final class DodoRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct DodoAPIClient: DodoLicenseClient {
    private let configuration: DodoConfiguration
    private let transport: any DodoHTTPTransport

    public init(configuration: DodoConfiguration, transport: any DodoHTTPTransport = DodoURLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    public func activate(key: String, name: String) async throws -> DodoActivation {
        let response = try await request("activate", body: ["license_key": key, "name": name])
        guard response.status == 201 else { throw DodoLicenseError.malformedResponse }
        struct Payload: Decodable {
            struct Product: Decodable { let product_id: String }
            let id: String
            let business_id: String
            let product: Product?
        }
        guard let result = try? JSONDecoder().decode(Payload.self, from: response.data), !result.id.isEmpty else {
            throw DodoLicenseError.malformedResponse
        }
        return DodoActivation(instanceID: result.id, businessID: result.business_id, productID: result.product?.product_id)
    }

    public func validate(key: String, instanceID: String) async throws -> Bool {
        let response = try await request("validate", body: ["license_key": key, "license_key_instance_id": instanceID])
        guard response.status == 200 else { throw DodoLicenseError.malformedResponse }
        struct Payload: Decodable { let valid: Bool }
        guard let result = try? JSONDecoder().decode(Payload.self, from: response.data) else {
            throw DodoLicenseError.malformedResponse
        }
        return result.valid
    }

    public func deactivate(key: String, instanceID: String) async throws {
        let response = try await request("deactivate", body: ["license_key": key, "license_key_instance_id": instanceID])
        guard response.status == 200 || response.status == 204 else { throw DodoLicenseError.malformedResponse }
    }

    private func request(_ endpoint: String, body: [String: String]) async throws -> DodoHTTPResponse {
        guard configuration.isValid else { throw DodoLicenseError.rejected }
        var request = URLRequest(url: configuration.environment.apiURL.appendingPathComponent("licenses/\(endpoint)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        let response: DodoHTTPResponse
        do {
            response = try await transport.send(request)
        } catch is URLError {
            throw DodoLicenseError.unavailable
        } catch is CancellationError {
            throw DodoLicenseError.unavailable
        }
        switch response.status {
        case 200..<300: return response
        case 401, 403: throw DodoLicenseError.invalidLicense
        case 404: throw DodoLicenseError.notFound
        case 422 where endpoint == "activate": throw DodoLicenseError.activationLimit
        case 408, 429, 500...599: throw DodoLicenseError.unavailable
        default: throw DodoLicenseError.rejected
        }
    }
}
