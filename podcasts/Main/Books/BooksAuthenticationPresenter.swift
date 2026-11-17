import AuthenticationServices
import UIKit

@MainActor
final class BooksAuthenticationPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    weak var window: UIWindow?
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?

    func authorize(_ attempt: DropboxOAuthAttempt) async throws -> URL {
        guard window != nil, session == nil else { throw BooksError.authorization }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(url: attempt.authorizationURL, callbackURLScheme: attempt.configuration.callbackScheme) { [weak self] url, error in
                Task { @MainActor in
                    if let url { self?.finish(.success(url)) }
                    else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { self?.finish(.failure(CancellationError())) }
                    else { self?.finish(.failure(BooksError.authorization)) }
                }
            }
            self.session = session
            session.presentationContextProvider = self
            if !session.start() { finish(.failure(BooksError.authorization)) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window ?? ASPresentationAnchor()
    }

    private func finish(_ result: Result<URL, Error>) {
        let pending = continuation
        continuation = nil
        session = nil
        pending?.resume(with: result)
    }
}
