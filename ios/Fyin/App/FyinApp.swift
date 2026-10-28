import CoreText
import SwiftUI

@main
struct FyinApp: App {
    @State private var showSplash = true
    // Raiz de composição: as dependências reais são montadas só aqui.
    @State private var home = HomeViewModel(repository: LiveHomeRepository(
        api: APIClient(baseURL: Secrets.apiURL, token: Secrets.apiToken)))

    init() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView(model: home)
                if showSplash { SplashView { showSplash = false } }
            }
        }
    }
}
