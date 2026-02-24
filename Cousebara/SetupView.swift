import SwiftUI

struct SetupView: View {
    let authService: GitHubAuthService
    let onAuthenticated: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            switch authService.phase {
            case .idle:
                idleView
            case .awaitingUser(let code, let verificationURL):
                awaitingUserView(code: code, verificationURL: verificationURL)
            case .success:
                successView
            case .error(let message):
                errorView(message)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No GitHub Copilot token found")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Sign in with your GitHub account to start monitoring your Copilot premium usage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                authService.startAuthentication()
            } label: {
                Label("Sign in with GitHub", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    // MARK: - Awaiting User

    private func awaitingUserView(code: String, verificationURL: String) -> some View {
        VStack(spacing: 10) {
            Text("Enter this code on GitHub:")
                .font(.caption)
                .foregroundStyle(.secondary)

            // User code display
            HStack(spacing: 6) {
                Text(code)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .tracking(2)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy code")
            }

            Button {
                if let url = URL(string: verificationURL) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open GitHub", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            // Polling indicator
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for authorization...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button("Cancel") {
                authService.reset()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)

            Text("Successfully authenticated!")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Loading your usage data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            // Brief delay so the user sees the success state, then trigger refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onAuthenticated()
            }
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.yellow)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                authService.startAuthentication()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Previews

#Preview("Idle - Needs Auth") {
    PopoverView(service: .previewNeedsAuth)
}

#Preview("Awaiting User") {
    let auth = GitHubAuthService()
    SetupView(authService: auth, onAuthenticated: {})
        .padding()
        .frame(width: 280)
}

#Preview("Error") {
    let auth = GitHubAuthService()
    SetupView(authService: auth, onAuthenticated: {})
        .padding()
        .frame(width: 280)
}
