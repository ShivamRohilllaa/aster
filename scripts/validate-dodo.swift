import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// build-app.sh prepends the same AsterAccessPolicy source used by the app.
// The free release needs no merchant configuration and must not package it.
if ProcessInfo.processInfo.environment["ASTER_DISTRIBUTION_BUILD"] == "1" {
    guard let identity = ProcessInfo.processInfo.environment["ASTER_SIGN_IDENTITY"], !identity.isEmpty else {
        fail("Distribution build requires ASTER_SIGN_IDENTITY. Notarization must follow signing before release.")
    }
}
if !AsterAccessPolicy.requiresLicense {
    print("free")
    exit(0)
}

guard CommandLine.arguments.count == 2,
      let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      Set(object.keys) == Set(["environment", "businessID", "productID"]),
      let environment = object["environment"] as? String,
      ["test", "live"].contains(environment),
      let business = object["businessID"] as? String,
      let product = object["productID"] as? String else {
    fail("Invalid Dodo configuration. Use only environment, businessID and productID. Never include API secrets.")
}
let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
guard [business, product].allSatisfy({ $0.count <= 256 && $0.unicodeScalars.allSatisfy(allowed.contains) }) else {
    fail("Invalid public Dodo identifiers. Copy IDs from your own Dodo product and business.")
}
let configured = !business.isEmpty && !product.isEmpty
if ProcessInfo.processInfo.environment["ASTER_DISTRIBUTION_BUILD"] == "1" {
    guard configured, environment == "live" else {
        fail("Distribution build requires configured live Dodo identifiers. Test or unconfigured builds are for local review only.")
    }
    guard let identity = ProcessInfo.processInfo.environment["ASTER_SIGN_IDENTITY"], !identity.isEmpty else {
        fail("Distribution build requires ASTER_SIGN_IDENTITY. Notarization must follow signing before release.")
    }
}
print("paid")
