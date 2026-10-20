import SwiftUI

/// The signed-out screen: sign in with a passkey, or with a code sent to your email.
struct SignInView: View {
    @Environment(AppSession.self) private var session
    @State private var path: [SignInRoute] = []
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var offerEmailCode = false

    enum SignInRoute: Hashable { case emailCode }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 32) {
                Spacer()
                Wordmark()
                Spacer()
                VStack(spacing: 14) {
                    Button {
                        Task { await signInWithPasskey() }
                    } label: {
                        Label("Sign in with passkey", systemImage: "person.badge.key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    NavigationLink(value: SignInRoute.emailCode) {
                        Text("Email me a code").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                    Text("Sign in with your Canopy Account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    Link("No Canopy Account? Create one at account.canopysf.com", destination: CanopyAccount.website)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .disabled(isWorking)
            }
            .padding(32)
            .overlay { if isWorking { ProgressView() } }
            .navigationDestination(for: SignInRoute.self) { _ in EmailCodeSignInView() }
            .errorAlert("Couldn't sign in", message: $errorMessage)
            .alert("Passkey not found", isPresented: $offerEmailCode) {
                Button("Email me a code") { path = [.emailCode] }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("That passkey isn't linked to a Canopy Account any more. Sign in with a code sent to your email instead.")
            }
        }
    }

    private func signInWithPasskey() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.signInWithPasskey()
        } catch PasskeyError.canceled {
            // Tapping Cancel isn't an error.
        } catch let error as CanopyAccountError where error.reason == "unknown_passkey" {
            offerEmailCode = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct Wordmark: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text("Canopy Control")
                .font(.largeTitle.weight(.bold))
            Text("YouTube speed and captions for your TVs.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Signing in with a code sent to your email: the email, then the code, then (for an existing
/// account) a new passkey on this phone. An email with no account isn't signed up here: it points
/// to account.canopysf.com.
struct EmailCodeSignInView: View {
    @Environment(AppSession.self) private var session
    @State private var email = ""
    @State private var code = ""
    @State private var step = Step.email
    @State private var isWorking = false
    @State private var errorMessage: String?

    enum Step: Equatable {
        case email
        case code
        /// The code proved the email of an account. `unverified` means saving a passkey takes it over.
        case existing(firstName: String?, unverified: Bool)
        case noAccount
    }

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(step != .email)
            } footer: {
                if step == .email { Text("We'll email you a code to sign in with your Canopy Account.") }
            }

            switch step {
            case .email:
                Section {
                    Button("Send code") { Task { await sendCode() } }
                        .disabled(isWorking || !email.contains("@"))
                }

            case .code:
                Section {
                    TextField("6-digit code", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Code")
                } footer: {
                    Text("Sent to \(email). It's good for 10 minutes.")
                }
                Section {
                    Button("Continue") { Task { await checkCode() } }
                        .disabled(isWorking || code.filter(\.isNumber).count != 6)
                    Button("Send a new code") { Task { await sendCode() } }
                        .disabled(isWorking)
                    Button("Use a different email") { reset() }
                        .disabled(isWorking)
                }

            case .existing(let firstName, let unverified):
                Section {
                    if unverified {
                        Label("This account's email was never confirmed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.headline)
                        Text("Whoever set it up may not have been you. Saving a passkey on this phone confirms the email and makes the account yours alone: every passkey it had is removed, every other browser and app is signed out, and its phone, Instagram, Venmo, Cash App and photo are cleared. The name stays, and you can change it at account.canopysf.com.")
                    } else {
                        Text("Save a passkey on this phone to sign in\(firstName.map { " as \($0)" } ?? ""). Next time, just tap Sign in with passkey.")
                    }
                }
                Section {
                    Button(unverified ? "Take over and save passkey" : "Save passkey") {
                        Task { await savePasskey() }
                    }
                    .disabled(isWorking)
                    Button("Use a different email") { reset() }
                        .disabled(isWorking)
                }

            case .noAccount:
                Section {
                    Text("There's no Canopy Account for \(email).")
                        .font(.headline)
                    Text("Create one at account.canopysf.com, then come back and sign in.")
                    Link("Open account.canopysf.com", destination: CanopyAccount.website)
                }
                Section {
                    Button("Use a different email") { reset() }
                }
            }
        }
        .navigationTitle("Email me a code")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isWorking { ProgressView() } }
        .errorAlert("Couldn't sign in", message: $errorMessage)
        .onDisappear { if !session.isSignedIn { session.cancelEmailSignIn() } }
    }

    private func reset() {
        session.cancelEmailSignIn()
        code = ""
        step = .email
    }

    private func sendCode() async {
        await run {
            try await session.sendCode(to: email.trimmingCharacters(in: .whitespaces))
            code = ""
            step = .code
        }
    }

    private func checkCode() async {
        await run {
            let answer = try await session.checkCode(code.filter(\.isNumber))
            if answer.state == "existing" {
                let unverified = answer.unverified == true
                step = .existing(firstName: answer.firstName, unverified: unverified)
                // Nothing to warn about: go straight to the passkey sheet.
                if !unverified { try await session.signInWithNewPasskey() }
            } else {
                step = .noAccount
            }
        }
    }

    private func savePasskey() async {
        await run { try await session.signInWithNewPasskey() }
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch PasskeyError.canceled {
            // Not an error. The step's button asks for fresh options to try again.
        } catch let error as CanopyAccountError {
            switch (error.reason, step) {
            case ("expired", .code):
                errorMessage = "That code ran out. Send a new one."
            case ("verify_first", _):
                reset()
                errorMessage = error.localizedDescription
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    /// An alert with an OK button, shown while `message` isn't nil.
    func errorAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK") {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
