import Foundation

public enum DodoEnvironment: String, Codable, Sendable {
    case test, live

    var apiURL: URL {
        URL(string: "https://\(rawValue).dodopayments.com")!
    }

    var checkoutHost: String {
        self == .live ? "checkout.dodopayments.com" : "test.checkout.dodopayments.com"
    }
}

/// Public merchant identifiers only. A Dodo API secret must never be bundled in Aster.
public struct DodoConfiguration: Codable, Equatable, Sendable {
    public let environment: DodoEnvironment
    public let businessID: String
    public let productID: String

    public init(environment: DodoEnvironment, businessID: String, productID: String) {
        self.environment = environment
        self.businessID = businessID
        self.productID = productID
    }

    public var isValid: Bool {
        Self.validIdentifier(businessID) && Self.validIdentifier(productID)
    }

    public var checkoutURL: URL? {
        guard isValid else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = environment.checkoutHost
        components.path = "/buy/\(productID)"
        components.queryItems = [URLQueryItem(name: "quantity", value: "1")]
        return components.url
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 256 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
        }
    }
}
