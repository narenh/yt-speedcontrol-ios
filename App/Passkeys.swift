import AuthenticationServices
import UIKit

// MARK: - Options from the server (WebAuthn JSON, binary fields base64url)

struct PasskeyCredentialDescriptor: Decodable {
    let id: String
}

/// `PublicKeyCredentialRequestOptionsJSON`: for using a passkey.
struct PasskeyRequestOptions: Decodable {
    let challenge: String
    let rpId: String
    let allowCredentials: [PasskeyCredentialDescriptor]?
    let userVerification: String?
}

/// `PublicKeyCredentialCreationOptionsJSON`: for making a passkey.
struct PasskeyCreationOptions: Decodable {
    struct RelyingParty: Decodable { let id: String }
    struct User: Decodable {
        let id: String
        let name: String
    }
    struct Selection: Decodable { let userVerification: String? }

    let challenge: String
    let rp: RelyingParty
    let user: User
    let excludeCredentials: [PasskeyCredentialDescriptor]?
    let authenticatorSelection: Selection?
}

// MARK: - What goes back: {"response": <this>}

struct PasskeyResponse: Encodable {
    struct Inner: Encodable {
        let clientDataJSON: String
        // Registration
        var attestationObject: String?
        var transports: [String]?
        // Assertion
        var authenticatorData: String?
        var signature: String?
        var userHandle: String?
    }
    struct NoExtensions: Encodable {}

    let id: String
    let rawId: String
    let type = "public-key"
    let response: Inner
    let clientExtensionResults = NoExtensions()
    let authenticatorAttachment = "platform"
}

extension Data {
    init?(base64URLEncoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        self.init(base64Encoded: s)
    }

    /// base64url, no padding.
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - The passkey sheet, as async/await

enum PasskeyError: LocalizedError {
    /// The person tapped Cancel: not an error to show.
    case canceled
    case badOptions
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .canceled: "Canceled."
        case .badOptions: "Canopy Account sent passkey options the app couldn't read."
        case .failed(let message): message
        }
    }
}

/// Wraps ASAuthorizationController. Each instance runs one request.
@MainActor
final class PasskeyAuthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var controller: ASAuthorizationController?

    /// Uses a passkey with the server's request options.
    static func assert(_ options: PasskeyRequestOptions) async throws -> PasskeyResponse {
        guard let challenge = Data(base64URLEncoded: options.challenge) else { throw PasskeyError.badOptions }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rpId)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        if let allowed = options.allowCredentials, !allowed.isEmpty {
            request.allowedCredentials = allowed.compactMap { Data(base64URLEncoded: $0.id) }
                .map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        }
        if let pref = options.userVerification { request.userVerificationPreference = .init(rawValue: pref) }

        let authorization = try await PasskeyAuthorizer().perform(request)
        guard let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw PasskeyError.failed("That wasn't a passkey.")
        }
        let id = assertion.credentialID.base64URL
        return PasskeyResponse(id: id, rawId: id, response: .init(
            clientDataJSON: assertion.rawClientDataJSON.base64URL,
            authenticatorData: assertion.rawAuthenticatorData.base64URL,
            signature: assertion.signature.base64URL,
            userHandle: assertion.userID.base64URL
        ))
    }

    /// Makes a passkey with the server's creation options.
    static func register(_ options: PasskeyCreationOptions) async throws -> PasskeyResponse {
        guard let challenge = Data(base64URLEncoded: options.challenge),
              let userID = Data(base64URLEncoded: options.user.id) else { throw PasskeyError.badOptions }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rp.id)
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: options.user.name, userID: userID)
        // iOS 17.4+ (the deployment target is 26): don't make a second passkey for an account
        // that already has one on this phone.
        if let excluded = options.excludeCredentials, !excluded.isEmpty {
            request.excludedCredentials = excluded.compactMap { Data(base64URLEncoded: $0.id) }
                .map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        }
        if let pref = options.authenticatorSelection?.userVerification {
            request.userVerificationPreference = .init(rawValue: pref)
        }

        let authorization = try await PasskeyAuthorizer().perform(request)
        guard let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let attestation = registration.rawAttestationObject else {
            throw PasskeyError.failed("The passkey wasn't saved.")
        }
        let id = registration.credentialID.base64URL
        return PasskeyResponse(id: id, rawId: id, response: .init(
            clientDataJSON: registration.rawClientDataJSON.base64URL,
            attestationObject: attestation.base64URL,
            transports: ["internal", "hybrid"]
        ))
    }

    private func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            // The controller holds its delegate weakly: `self` lives through this call, and
            // keeps the controller until it answers.
            self.controller = controller
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            continuation?.resume(returning: authorization)
            continuation = nil
            self.controller = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            let mapped: Error
            if let auth = error as? ASAuthorizationError, auth.code == .canceled {
                mapped = PasskeyError.canceled
            } else {
                mapped = PasskeyError.failed(error.localizedDescription)
            }
            continuation?.resume(throwing: mapped)
            continuation = nil
            self.controller = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap(\.windows)
            // Sign-in only runs from a button on screen, so there's always a scene.
            return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor(windowScene: scenes[0])
        }
    }
}
