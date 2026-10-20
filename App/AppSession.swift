import Foundation
import Observation

/// Who's signed in, and the sign-in flows. The token itself lives only in the Keychain.
@MainActor
@Observable
final class AppSession {
    private(set) var isSignedIn = TokenStore.token != nil
    private(set) var person: CanopyPerson?
    /// Shown once after signing in, e.g. after taking over an unverified account.
    var notice: String?

    /// The ceremony for an email-code sign-in in progress. Memory only.
    private var emailCeremony: String?

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .canopyTokenRemoved, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.forget() }
        }
    }

    private func forget() {
        isSignedIn = false
        person = nil
        emailCeremony = nil
        Task { await SpeedActivity.end() }
    }

    private func signedIn(_ answer: CanopyAccount.SignedIn) {
        TokenStore.save(answer.token)
        emailCeremony = nil
        person = answer.person
        isSignedIn = true
        if answer.tookOver == true {
            notice = "This Canopy Account is yours now. Its phone, Instagram, Venmo, Cash App and photo were cleared. Check that the name is yours at account.canopysf.com."
        }
    }

    /// Fills in the person's name (`GET /me`). A signed-out answer has already deleted the token.
    func loadPerson() async {
        guard let token = TokenStore.token else { return forget() }
        if let person = try? await CanopyAccount.me(token: token) { self.person = person }
    }

    // MARK: Passkey

    /// Begin, options, the passkey, verify. Every options answer is good for one try, so each
    /// attempt starts over.
    func signInWithPasskey() async throws {
        let ceremony = try await CanopyAccount.begin()
        let options = try await CanopyAccount.passkeyOptions(ceremony: ceremony)
        let assertion = try await PasskeyAuthorizer.assert(options)
        signedIn(try await CanopyAccount.passkeyVerify(ceremony: ceremony, assertion: assertion))
    }

    // MARK: Email code

    /// Sends a code (again, for "Send a new code": the old one stops working).
    func sendCode(to email: String) async throws {
        if let ceremony = emailCeremony {
            do {
                _ = try await CanopyAccount.emailStart(ceremony: ceremony, email: email)
                return
            } catch let error as CanopyAccountError where error.reason == "expired" {
                emailCeremony = nil  // ran out: begin again below
            }
        }
        let ceremony = try await CanopyAccount.begin()
        emailCeremony = ceremony
        _ = try await CanopyAccount.emailStart(ceremony: ceremony, email: email)
    }

    func checkCode(_ code: String) async throws -> CanopyAccount.EmailVerified {
        guard let ceremony = emailCeremony else { throw CanopyAccountError(status: 400, reason: "expired", sentence: nil) }
        return try await CanopyAccount.emailVerify(ceremony: ceremony, code: code)
    }

    /// After the code proved an existing account's email: a new passkey on this phone.
    /// Fresh options each try.
    func signInWithNewPasskey() async throws {
        guard let ceremony = emailCeremony else { throw CanopyAccountError(status: 400, reason: "verify_first", sentence: nil) }
        let options = try await CanopyAccount.registerExisting(ceremony: ceremony)
        let registration = try await PasskeyAuthorizer.register(options)
        signedIn(try await CanopyAccount.registerVerify(ceremony: ceremony, registration: registration))
    }

    func cancelEmailSignIn() { emailCeremony = nil }

    // MARK: Signing out

    /// `POST /signout`, then delete the token whatever the answer (even with no network).
    func signOut() async {
        if let token = TokenStore.token { try? await CanopyAccount.signOut(token: token) }
        TokenStore.delete()
        forget()
    }
}
