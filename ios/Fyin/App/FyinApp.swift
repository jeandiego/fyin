import CoreText
import SwiftUI

@main
struct FyinApp: App {
    @State private var showSplash = true
    // Raiz de composição: as dependências reais são montadas só aqui.
    @State private var home: HomeViewModel
    @State private var settings: SettingsViewModel
    @State private var showSettings = false

    init() {
        let api = APIClient(baseURL: Secrets.apiURL, token: Secrets.apiToken)
        let home = HomeViewModel(repository: LiveHomeRepository(api: api))
        _home = State(initialValue: home)
        // Terminado um sync, a home relê os números novos.
        _settings = State(initialValue: SettingsViewModel(repository: LiveSettingsRepository(api: api)) { await home.refresh() })
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                NavigationStack {
                    HomeView(model: home, syncing: settings.syncing) { showSettings = true }
                        .toolbarVisibility(.hidden, for: .navigationBar)
                        .navigationDestination(isPresented: $showSettings) {
                            SettingsView(model: settings)
                                .toolbarVisibility(.hidden, for: .navigationBar)
                        }
                }
                if showSplash { SplashView { showSplash = false } }
            }
        }
    }
}
