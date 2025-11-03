import Foundation
import OAuth2

final class AutomationAuthorizer: OAuth2AuthorizerUI {

    let oauth2: OAuth2Base
    var didOpenURL: ((URL) -> Void)?
    var transform: ((URL) -> URL)?

    init(
        oauth2: OAuth2Base,
        didOpenURL: ((URL) -> Void)? = nil,
        transform: ((URL) -> URL)? = nil
    ) {
        self.oauth2 = oauth2
        self.didOpenURL = didOpenURL
        self.transform = transform
    }

    func openAuthorizeURLInBrowser(_ url: URL) throws {
        try handle(url: url)
    }

    func authorizeEmbedded(with config: OAuth2AuthConfig, at url: URL) throws {
        try handle(url: url)
    }

    private func handle(url: URL) throws {
        let finalURL = transform?(url) ?? url
        didOpenURL?(finalURL)
        try ExternalLoginDriver.open(finalURL)
    }
}
