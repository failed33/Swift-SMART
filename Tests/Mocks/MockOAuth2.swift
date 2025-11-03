import OAuth2

final class MockOAuth2: OAuth2 {
    var tryCallCount = 0
    var nextResult: (OAuth2JSON?, OAuth2Error?) = (["access_token": "refreshed-token"], nil)
    private var tokenStorage: String?
    var forceTokenExpiration = true

    override init(settings: OAuth2JSON = [:]) {
        super.init(settings: settings)
    }

    override var accessToken: String? {
        get { tokenStorage }
        set { tokenStorage = newValue }
    }

    override func hasUnexpiredAccessToken() -> Bool {
        guard let tokenStorage, !tokenStorage.isEmpty else { return false }
        return !forceTokenExpiration
    }

    override func tryToObtainAccessTokenIfNeeded(
        params: OAuth2StringDict? = nil,
        callback: @escaping ((OAuth2JSON?, OAuth2Error?) -> Void)
    ) {
        tryCallCount += 1
        if let token = nextResult.0?["access_token"] as? String {
            tokenStorage = token
            forceTokenExpiration = false
        }
        callback(nextResult.0, nextResult.1)
    }
}


