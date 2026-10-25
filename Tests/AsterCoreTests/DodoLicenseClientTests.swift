import Foundation
import XCTest
@testable import AsterCore

final class DodoLicenseClientTests: XCTestCase {
    private let configuration = DodoConfiguration(environment: .test, businessID: "bus_aster", productID: "prod_aster")

    func testCheckoutIsFixedHTTPSHostAndQuantityWithoutLicenseOrCustomerData() {
        XCTAssertEqual(configuration.checkoutURL?.absoluteString, "https://test.checkout.dodopayments.com/buy/prod_aster?quantity=1")
        let live = DodoConfiguration(environment: .live, businessID: "bus_aster", productID: "prod_aster")
        XCTAssertEqual(live.checkoutURL?.absoluteString, "https://checkout.dodopayments.com/buy/prod_aster?quantity=1")
        for product in ["", "../other", "id?quantity=100", "id/other", "id#redirect", "id%2Fother"] {
            XCTAssertNil(DodoConfiguration(environment: .live, businessID: "bus_aster", productID: product).checkoutURL)
        }
    }

    func testConfigurationCodableUsesPublicIdentifiersOnly() throws {
        let data = try JSONEncoder().encode(configuration)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(Set(json.keys), ["environment", "businessID", "productID"])
        XCTAssertEqual(try JSONDecoder().decode(DodoConfiguration.self, from: data), configuration)
    }

    func testActivationUsesPublicEndpointWithoutBearerTokenAndDecodesProvenance() async throws {
        let transport = StubDodoTransport(status: 201, body: #"{"id":"lki_mac","business_id":"bus_aster","product":{"product_id":"prod_aster"},"customer":{"email":"unused@example.com"}}"#)
        let client = DodoAPIClient(configuration: configuration, transport: transport)
        let result = try await client.activate(key: "secret-key", name: "Aster Mac opaque-id")
        XCTAssertEqual(result.businessID, "bus_aster")
        XCTAssertEqual(result.productID, "prod_aster")
        XCTAssertEqual(result.instanceID, "lki_mac")
        let sent = await transport.lastRequest()
        let request = try XCTUnwrap(sent)
        XCTAssertEqual(request.url?.absoluteString, "https://test.dodopayments.com/licenses/activate")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try body(request), ["license_key": "secret-key", "name": "Aster Mac opaque-id"])
    }

    func testMissingProductStaysMissingForFailClosedControllerCheck() async throws {
        let transport = StubDodoTransport(status: 201, body: #"{"id":"lki_mac","business_id":"bus_aster"}"#)
        let result = try await DodoAPIClient(configuration: configuration, transport: transport).activate(key: "key", name: "Mac")
        XCTAssertNil(result.productID)
    }

    func testValidateAlwaysSendsBothKeyAndInstance() async throws {
        let transport = StubDodoTransport(status: 200, body: #"{"valid":true}"#)
        let result = try await DodoAPIClient(configuration: configuration, transport: transport).validate(key: "key", instanceID: "lki_mac")
        XCTAssertTrue(result)
        let sent = await transport.lastRequest()
        let request = try XCTUnwrap(sent)
        XCTAssertEqual(try body(request), ["license_key": "key", "license_key_instance_id": "lki_mac"])
    }

    func testDeactivateAcceptsDocumentedEmpty200And204() async throws {
        for status in [200, 204] {
            let transport = StubDodoTransport(status: status, body: "")
            try await DodoAPIClient(configuration: configuration, transport: transport).deactivate(key: "key", instanceID: "lki_mac")
            let sent = await transport.lastRequest()
            let request = try XCTUnwrap(sent)
            XCTAssertEqual(try body(request), ["license_key": "key", "license_key_instance_id": "lki_mac"])
        }
    }

    func testTemporaryAndRevokedHTTPResponsesAreDistinct() async {
        for (status, expected) in [(403, DodoLicenseError.invalidLicense), (404, .notFound), (429, .unavailable), (503, .unavailable), (302, .rejected)] {
            let transport = StubDodoTransport(status: status, body: "secret-key must never appear in user error")
            do {
                _ = try await DodoAPIClient(configuration: configuration, transport: transport).validate(key: "key", instanceID: "lki_mac")
                XCTFail("Expected an error for \(status)")
            } catch {
                XCTAssertEqual(error as? DodoLicenseError, expected)
                XCTAssertFalse(error.localizedDescription.contains("secret-key"))
            }
        }
    }

    func testMalformedValidationCannotUnlock() async {
        for payload in [#"{"valid":"true"}"#, #"{"valid":1}"#, #"{"paid":true}"#, "", "<html>OK</html>"] {
            let transport = StubDodoTransport(status: 200, body: payload)
            do {
                _ = try await DodoAPIClient(configuration: configuration, transport: transport).validate(key: "key", instanceID: "lki_mac")
                XCTFail("Malformed response unexpectedly succeeded")
            } catch {
                XCTAssertEqual(error as? DodoLicenseError, .malformedResponse)
            }
        }
    }

    func testTransportFailureMapsToOfflineError() async {
        let transport = StubDodoTransport(status: 200, body: "", throwsNetworkError: true)
        do {
            _ = try await DodoAPIClient(configuration: configuration, transport: transport).validate(key: "key", instanceID: "lki_mac")
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? DodoLicenseError, .unavailable)
        }
    }

    private func body(_ request: URLRequest) throws -> [String: String] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
    }
}

private actor StubDodoTransport: DodoHTTPTransport {
    let response: DodoHTTPResponse
    let throwsNetworkError: Bool
    var requests: [URLRequest] = []
    init(status: Int, body: String, throwsNetworkError: Bool = false) {
        response = DodoHTTPResponse(status: status, data: Data(body.utf8))
        self.throwsNetworkError = throwsNetworkError
    }
    func send(_ request: URLRequest) async throws -> DodoHTTPResponse {
        requests.append(request)
        if throwsNetworkError { throw URLError(.notConnectedToInternet) }
        return response
    }
    func lastRequest() -> URLRequest? { requests.last }
}
