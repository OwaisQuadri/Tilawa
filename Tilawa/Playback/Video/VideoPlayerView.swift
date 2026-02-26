import SwiftUI
import AVKit
import AuthenticationServices
import Combine

/// Detachable sheet presenting a video source alongside the Mushaf.
///
/// Layout:
///   ┌─────────────────────────┐
///   │    AVPlayer video       │  ← VideoPlayer (AVKit)
///   ├─────────────────────────┤
///   │  Current ayah info      │  ← highlighted ref from PlaybackViewModel
///   │  + dismissal hint       │
///   └─────────────────────────┘
///
/// Behavior:
/// - localFile: full AVPlayer with background audio (UIBackgroundModes: audio)
/// - googleDrive: streams via AVPlayer after OAuth; same background audio support
/// - Dismiss the sheet: video audio keeps playing via AVPlayer background audio
struct VideoPlayerView: View {

    let source: VideoSource
    @ObservedObject private var playerModel: VideoPlayerModel

    init(source: VideoSource) {
        self.source = source
        self.playerModel = VideoPlayerModel(source: source)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let player = playerModel.player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
            } else if playerModel.isAuthenticating {
                ProgressView("Connecting to Google Drive…")
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let error = playerModel.errorMessage {
                ContentUnavailableView(
                    "Video Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(minHeight: 200)
            } else {
                ProgressView()
                    .frame(minHeight: 200)
            }

            Divider()

            VStack(spacing: 8) {
                Text("Video playing in background when sheet is dismissed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if source.sourceType == .googleDrive, playerModel.player == nil, !playerModel.isAuthenticating {
                    Button("Connect Google Drive") {
                        playerModel.startGoogleDriveAuth()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .onAppear { playerModel.prepare() }
        .onDisappear { /* AVPlayer keeps playing — intentional */ }
    }
}

// MARK: - ViewModel

@MainActor
final class VideoPlayerModel: ObservableObject {

    @Published private(set) var player: AVPlayer?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var errorMessage: String?

    private let source: VideoSource

    init(source: VideoSource) {
        self.source = source
    }

    func prepare() {
        switch source.sourceType {
        case .localFile:
            guard let url = source.localURL else {
                errorMessage = "Video file not found."
                return
            }
            player = AVPlayer(url: url)
            player?.play()

        case .googleDrive:
            if let urlString = source.streamURLString,
               let url = URL(string: urlString) {
                // Stream URL already obtained (e.g. restored from a previous session)
                player = AVPlayer(url: url)
                player?.play()
            }
            // Otherwise user taps "Connect Google Drive" to initiate OAuth
        }
    }

    func startGoogleDriveAuth() {
        isAuthenticating = true
        Task {
            await authenticateGoogleDrive()
        }
    }

    // MARK: - Google Drive OAuth

    private func authenticateGoogleDrive() async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        guard let authURL = buildGoogleOAuthURL() else {
            errorMessage = "Could not build authentication URL."
            return
        }

        do {
            let callbackURL: URL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: "tilawa"
                ) { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: GoogleDriveError.authCancelled)
                    }
                }
                session.prefersEphemeralWebBrowserSession = false
                session.presentationContextProvider = PresentationContextProvider.shared
                session.start()
            }

            let token = try extractToken(from: callbackURL)
            let streamURL = try await fetchDriveStreamURL(token: token)
            let avPlayer = AVPlayer(url: streamURL)
            avPlayer.play()
            player = avPlayer

        } catch GoogleDriveError.authCancelled {
            // User cancelled — no error shown
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildGoogleOAuthURL() -> URL? {
        // OAuth 2.0 — read-only Drive scope
        // Client ID must be registered in Google Cloud Console with tilawa:// redirect URI
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id",     value: GoogleDriveConfig.clientId),
            URLQueryItem(name: "redirect_uri",  value: "tilawa://oauth/google"),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope",         value: "https://www.googleapis.com/auth/drive.readonly"),
        ]
        return components?.url
    }

    private func extractToken(from url: URL) throws -> String {
        guard let fragment = url.fragment else { throw GoogleDriveError.missingToken }
        let params = fragment.split(separator: "&").reduce(into: [String: String]()) { dict, pair in
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { dict[kv[0]] = kv[1] }
        }
        guard let token = params["access_token"] else { throw GoogleDriveError.missingToken }
        return token
    }

    private func fetchDriveStreamURL(token: String) async throws -> URL {
        // Obtain the webContentLink (direct download URL) for the user's selected file.
        // In practice, the user picks a file via a Drive file picker; here we use the
        // file ID stored in source.streamURLString (set when the user first imports).
        guard let fileId = source.streamURLString else { throw GoogleDriveError.noFileId }
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Use the direct streaming URL (alt=media returns the file bytes)
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        return url
    }
}

// MARK: - Google Drive Config

enum GoogleDriveConfig {
    /// Replace with your app's Google OAuth 2.0 Client ID from Google Cloud Console.
    static let clientId = "YOUR_GOOGLE_CLIENT_ID"
}

enum GoogleDriveError: LocalizedError {
    case authCancelled
    case missingToken
    case noFileId

    var errorDescription: String? {
        switch self {
        case .authCancelled: return "Authentication was cancelled."
        case .missingToken:  return "No access token received from Google."
        case .noFileId:      return "No Google Drive file ID associated with this source."
        }
    }
}

// MARK: - ASWebAuthentication Presentation Context

import UIKit

final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
            ?? ASPresentationAnchor()
    }
}
