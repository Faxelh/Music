import MediaPlayer
import SwiftUI

@main
struct MusicApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = AudioEngine.shared
    @StateObject private var app = AppState.shared
    @StateObject private var sheets = SheetCenter.shared
    @StateObject private var appearance = Appearance.shared
    @AppStorage("theme") private var theme = "system"
    @AppStorage("language") private var language = "system"
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Lang.apply(UserDefaults.standard.string(forKey: "language") ?? "system")
    }

    private var scheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            let _ = Lang.apply(language)
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(app)
                .environmentObject(sheets)
                .tint(appearance.accent)
                .accentColor(appearance.accent)
                .preferredColorScheme(scheme)
                .id(language)
                .onAppear {
                    player.onMessage = { text in AppState.shared.show(text, .warn) }
                    if library.loaded { player.restore(from: library) }
                    if MPMediaLibrary.authorizationStatus() == .notDetermined {
                        library.enableMediaLibrary(true)
                    }
                }
                .onChange(of: library.loaded) { loaded in
                    if loaded { player.restore(from: library) }
                }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        library.scan()
                    case .background:
                        player.saveForBackground()
                    default:
                        break
                    }
                }
                .onOpenURL { url in
                    if url.isFileURL { library.importFiles([url]) }
                }
                .updatePrompt()
        }
    }
}

struct RootView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var app: AppState
    @Namespace private var namespace

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $app.tab) {
                HomeView()
                    .tabItem { Label(L("Accueil"), systemImage: "house.fill") }
                    .tag(AppTab.home)
                LibraryView()
                    .tabItem { Label(L("Bibliothèque"), systemImage: "square.stack.fill") }
                    .tag(AppTab.library)
                ForYouView()
                    .tabItem { Label(L("Découvrir"), systemImage: "sparkles") }
                    .tag(AppTab.search)
                SettingsView()
                    .tabItem { Label(L("Réglages"), systemImage: "gearshape.fill") }
                    .tag(AppTab.settings)
            }

            if !app.playerOpen {
                MiniPlayer(namespace: namespace)
                    .padding(.bottom, 54)
            }

            if app.playerOpen {
                NowPlayingView(namespace: namespace)
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
        }
        .overlay(alignment: .top) {
            if let toast = app.toast {
                ToastBanner(toast: toast)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation { app.toast = nil }
                    }
                    .zIndex(3)
            }
        }
        .sharedSheets()
    }
}
