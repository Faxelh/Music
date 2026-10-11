import MediaPlayer
import SwiftUI

/// Mini-lecteur flottant au-dessus de la barre d'onglets.
struct MiniPlayer: View {
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var app: AppState
    let namespace: Namespace.ID
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @AppStorage("miniCollapsed") private var collapsed = false
    @AppStorage("bubbleX") private var bubbleX: Double = 0
    @AppStorage("bubbleY") private var bubbleY: Double = 0
    @State private var bubbleDrag: CGSize = .zero

    var body: some View {
        if let song = player.current {
            if collapsed {
                bubble(song)
            } else {
                bar(song)
            }
        }
    }

    /// Bulle flottante (mini-lecteur rangé) : on la déplace où on veut, un toucher la rouvre.
    private func bubble(_ song: Song) -> some View {
        ZStack {
            SongArtwork(song: song, size: 54, radius: 27)
                .matchedGeometryEffect(id: "artwork", in: namespace)
            BubbleRing(clock: player.clock)
                .frame(width: 60, height: 60)
            if !player.isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 3)
            }
        }
        .frame(width: 62, height: 62)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 16)
        .offset(x: bubbleX + bubbleDrag.width, y: bubbleY + bubbleDrag.height)
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) { app.playerOpen = true }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { collapsed = false }
        }
        .onLongPressGesture {
            player.toggle()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .gesture(
            DragGesture()
                .onChanged { value in bubbleDrag = value.translation }
                .onEnded { value in
                    let screen = UIScreen.main.bounds
                    bubbleX = min(0, max(-Double(screen.width) + 100, bubbleX + value.translation.width))
                    bubbleY = min(0, max(-Double(screen.height) + 260, bubbleY + value.translation.height))
                    bubbleDrag = .zero
                }
        )
        .transition(.scale.combined(with: .opacity))
    }

    private func bar(_ song: Song) -> some View {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    SongArtwork(song: song, size: 44, radius: 8)
                        .matchedGeometryEffect(id: "artwork", in: namespace)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(song.displayArtist)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .offset(x: dragX * 0.4)
                    .opacity(1 - Double(min(abs(dragX), 120) / 200))
                    Spacer(minLength: 4)
                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                            .contentTransition(.interpolate)
                    }
                    .buttonStyle(BounceButtonStyle())
                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 19))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 40)
                    }
                    .buttonStyle(BounceButtonStyle())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                MiniProgress(clock: player.clock)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 10)
            .offset(y: max(0, dragY))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) { app.playerOpen = true }
            }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            dragX = value.translation.width
                        } else {
                            dragY = value.translation.height
                        }
                        if value.translation.height < -40 {
                            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) { app.playerOpen = true }
                        }
                    }
                    .onEnded { value in
                        if value.translation.width < -80 {
                            player.next()
                        } else if value.translation.width > 80 {
                            player.previous()
                        } else if value.translation.height > 40 {
                            // Glisser vers le bas : le mini-lecteur se range en bulle.
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { collapsed = true }
                        }
                        withAnimation(.spring()) {
                            dragX = 0
                            dragY = 0
                        }
                    }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

}

/// Lecteur plein écran : fond animé, pochette (carré, vinyle, carte 3D),
/// visualiseur, paroles synchronisées, file d'attente, égaliseur.
struct NowPlayingView: View {
    enum Panel {
        case cover, lyrics, queue
    }

    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var app: AppState
    @EnvironmentObject var sheets: SheetCenter
    @ObservedObject private var appearance = Appearance.shared
    @Environment(\.scenePhase) private var scenePhase
    let namespace: Namespace.ID

    @State private var panel: Panel = .cover
    @State private var dragY: CGFloat = 0
    @State private var showEqualizer = false
    @State private var heartBounce = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PlayerBackground()
                if let song = player.current {
                    VStack(spacing: 0) {
                        header(song)
                        content(song, size: geometry.size)
                        info(song)
                        progressBar
                        controls
                        VolumeSlider()
                            .frame(height: 34)
                            .padding(.horizontal, 30)
                            .padding(.top, 6)
                        bottomBar(song)
                        if panel == .cover {
                            nextUp
                                .padding(.horizontal, 24)
                                .padding(.bottom, 8)
                                .transition(.opacity)
                        }
                    }
                    .foregroundColor(.white)
                } else {
                    VStack(spacing: 16) {
                        EmptyState(icon: "music.note", title: L("Aucune lecture en cours"))
                        Button(L("Fermer"), action: close)
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.horizontal, 80)
                    }
                    .foregroundColor(.white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: dragY > 0 ? 34 : 0, style: .continuous))
            .offset(y: dragY)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard panel == .cover || value.startLocation.y < 140 else { return }
                        if value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width) {
                            dragY = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if dragY > 140 || value.predictedEndTranslation.height > 400 {
                            close()
                        } else {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { dragY = 0 }
                        }
                    }
            )
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onAppear { updateSpectrum() }
        .onDisappear { player.spectrumWanted = false }
        .onChange(of: appearance.visualizer) { _ in updateSpectrum() }
        .onChange(of: appearance.background) { _ in updateSpectrum() }
        .onChange(of: scenePhase) { _ in updateSpectrum() }
        .sheet(isPresented: $showEqualizer) {
            EqualizerView()
                .environmentObject(player)
        }
    }

    private func updateSpectrum() {
        let needed = appearance.visualizer != .none || appearance.background == .aurora
        player.spectrumWanted = needed && appearance.animations && scenePhase == .active
    }

    private func close() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            app.playerOpen = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dragY = 0 }
    }

    // MARK: - Haut

    private func header(_ song: Song) -> some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(Color.white.opacity(0.45))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            HStack {
                Button(action: close) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(BounceButtonStyle())
                Spacer()
                VStack(spacing: 1) {
                    Text(L("Lecture en cours").uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.7)
                    Text(L("{index} sur {count}", ["index": "\(player.index + 1)", "count": "\(player.queue.count)"])
                         + (song.album.map { " · " + $0 } ?? ""))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    SongMenu(song: song)
                    Section(L("Pochette")) {
                        Picker(L("Pochette"), selection: $appearance.coverStyle) {
                            ForEach(Appearance.CoverStyle.allCases) { style in
                                Label(style.name, systemImage: coverIcon(style)).tag(style)
                            }
                        }
                    }
                    Section(L("Fond")) {
                        Picker(L("Fond"), selection: $appearance.background) {
                            ForEach(Appearance.Background.allCases) { background in
                                Label(background.name, systemImage: background.icon).tag(background)
                            }
                        }
                    }
                    Section(L("Visualiseur")) {
                        Picker(L("Visualiseur"), selection: $appearance.visualizer) {
                            ForEach(Appearance.Visualizer.allCases) { visualizer in
                                Label(visualizer.name, systemImage: visualizerIcon(visualizer)).tag(visualizer)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
            }
            .padding(.horizontal, 14)
        }
    }

    // MARK: - Centre

    @ViewBuilder
    private func content(_ song: Song, size: CGSize) -> some View {
        let cover = min(size.width - 64, size.height * 0.4)
        ZStack {
            switch panel {
            case .cover:
                VStack(spacing: 18) {
                    Spacer(minLength: 0)
                    PlayerCover(song: song, size: cover, namespace: namespace)
                        .id(song.id)
                        .transition(.asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity),
                                                removal: .opacity))
                        .gesture(
                            DragGesture(minimumDistance: 30)
                                .onEnded { value in
                                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                        if value.translation.width < -60 { player.next() }
                                        if value.translation.width > 60 { player.previous() }
                                    }
                                }
                        )
                    if !appearance.visualizer.surroundsCover && appearance.visualizer != .none {
                        BelowVisualizer(style: appearance.visualizer, color: appearance.accent)
                            .frame(height: 50)
                            .padding(.horizontal, 28)
                            .opacity(player.isPlaying ? 1 : 0.3)
                    }
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            case .lyrics:
                VStack(spacing: 10) {
                    smallHeader(song)
                    LiveLyricsView(song: song)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            case .queue:
                VStack(spacing: 10) {
                    smallHeader(song)
                    UpNextView()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: song.id)
    }

    private func smallHeader(_ song: Song) -> some View {
        HStack(spacing: 12) {
            SongArtwork(song: song, size: 54, radius: 8)
                .matchedGeometryEffect(id: "artwork", in: namespace)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                Text(song.displayArtist)
                    .font(.system(size: 14))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
    }

    // MARK: - Titre, progression, commandes

    @ViewBuilder
    private func info(_ song: Song) -> some View {
        if panel == .cover {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                        .id("title" + song.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .opacity))
                    Text(song.displayArtist)
                        .font(.system(size: 17))
                        .opacity(0.7)
                        .lineLimit(1)
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: song.id)
                Spacer()
                Button {
                    library.toggleFavorite(song)
                    heartBounce.toggle()
                } label: {
                    Image(systemName: library.isFavorite(song) ? "heart.fill" : "heart")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(library.isFavorite(song) ? appearance.accent : .white)
                        .symbolEffectBounce(trigger: heartBounce)
                }
                .buttonStyle(BounceButtonStyle())
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
        }
    }

    private var progressBar: some View {
        ScrubBar(clock: player.clock) { player.seek(to: $0) }
    }

    private var controls: some View {
        HStack {
            Button {
                withAnimation { player.toggleShuffle() }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(player.shuffle ? appearance.accent : Color.white.opacity(0.75))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BounceButtonStyle())
            Spacer()
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { player.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32))
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(BounceButtonStyle())
            Spacer()
            Button {
                player.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 78, height: 78)
                        .shadow(color: appearance.accent.opacity(player.isPlaying ? 0.6 : 0), radius: 18)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.black)
                        .offset(x: player.isPlaying ? 0 : 3)
                        .contentTransition(.interpolate)
                }
            }
            .buttonStyle(BounceButtonStyle())
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: player.isPlaying)
            Spacer()
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32))
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(BounceButtonStyle())
            Spacer()
            Button {
                player.cycleRepeat()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(player.repeatMode == .off ? Color.white.opacity(0.75) : appearance.accent)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BounceButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private func bottomBar(_ song: Song) -> some View {
        HStack {
            panelButton(.lyrics, icon: "quote.bubble")
            Spacer()
            Menu {
                ForEach([0, 10, 15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button {
                        player.setSleepTimer(minutes: minutes)
                        if minutes > 0 {
                            AppState.shared.show(L("Pause dans {minutes} min.", ["minutes": "\(minutes)"]), .ok)
                        }
                    } label: {
                        Text(minutes == 0 ? L("Désactivé") : L("{minutes} min", ["minutes": "\(minutes)"]))
                    }
                }
            } label: {
                Image(systemName: player.sleepEnd == nil ? "moon.zzz" : "moon.zzz.fill")
                    .font(.system(size: 19))
                    .foregroundColor(player.sleepEnd == nil ? Color.white.opacity(0.75) : appearance.accent)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Menu {
                ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { value in
                    Button {
                        player.setRate(value)
                    } label: {
                        if value == player.rate {
                            Label(Fmt.rate(value), systemImage: "checkmark")
                        } else {
                            Text(Fmt.rate(value))
                        }
                    }
                }
            } label: {
                Text(Fmt.rate(player.rate))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(player.rate == 1 ? Color.white.opacity(0.75) : appearance.accent)
                    .frame(width: 48, height: 44)
            }
            Spacer()
            Button {
                showEqualizer = true
            } label: {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(player.eqEnabled ? appearance.accent : Color.white.opacity(0.75))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            AirPlayButton(tint: .white)
                .frame(width: 44, height: 44)
            Spacer()
            panelButton(.queue, icon: "list.bullet")
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func coverIcon(_ style: Appearance.CoverStyle) -> String {
        switch style {
        case .square: return "square.fill"
        case .round: return "circle.fill"
        case .vinyl: return "record.circle"
        case .cd: return "opticaldisc"
        case .cassette: return "recordingtape"
        case .card: return "rectangle.portrait.on.rectangle.portrait"
        case .polaroid: return "photo"
        case .neon: return "light.max"
        case .stack: return "square.stack.fill"
        case .floating: return "square.on.square"
        }
    }

    private func visualizerIcon(_ visualizer: Appearance.Visualizer) -> String {
        switch visualizer {
        case .bars: return "chart.bar.fill"
        case .mirror: return "waveform"
        case .rainbow: return "rainbow"
        case .dots: return "circle.grid.3x3.fill"
        case .wave: return "waveform.path"
        case .line: return "point.topleft.down.curvedto.point.bottomright.up"
        case .ring: return "circle.dashed"
        case .particles: return "sparkles"
        case .pulse: return "dot.radiowaves.left.and.right"
        case .halo: return "sun.max.fill"
        case .none: return "nosign"
        }
    }

    /// Petite carte « À suivre » : le morceau suivant, touchez pour y passer.
    @ViewBuilder
    private var nextUp: some View {
        if player.queue.indices.contains(player.index + 1) {
            let next = player.queue[player.index + 1]
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { player.jump(to: player.index + 1) }
            } label: {
                HStack(spacing: 10) {
                    SongArtwork(song: next, size: 38, radius: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("À suivre").uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .opacity(0.6)
                        Text(next.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 14))
                        .opacity(0.7)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(BounceButtonStyle())
        }
    }

    private func panelButton(_ target: Panel, icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                panel = panel == target ? .cover : target
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(panel == target ? .black : Color.white.opacity(0.75))
                .frame(width: 40, height: 40)
                .background(Circle().fill(panel == target ? Color.white : Color.clear))
        }
        .buttonStyle(BounceButtonStyle())
    }
}

extension View {
    /// Rebond de l'icône (cœur) : animation de ressort maison, compatible iOS 16.
    func symbolEffectBounce(trigger: Bool) -> some View {
        modifier(BounceOnChange(trigger: trigger))
    }
}

struct BounceOnChange: ViewModifier {
    let trigger: Bool
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: trigger) { _ in
                withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { scale = 1.35 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { scale = 1 }
                }
            }
    }
}

/// Curseur du volume de l'iPhone.
struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        view.setVolumeThumbImage(UIImage(systemName: "circle.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal),
                                 for: .normal)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// « À suivre » : la file de lecture, modifiable.
struct UpNextView: View {
    @EnvironmentObject var player: AudioEngine
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L("À suivre"))
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button(editing ? L("OK") : L("Modifier")) {
                    withAnimation { editing.toggle() }
                }
                .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 24)
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { offset, song in
                    HStack(spacing: 12) {
                        SongArtwork(song: song, size: 42, radius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.system(size: 15, weight: offset == player.index ? .bold : .regular))
                                .lineLimit(1)
                            Text(song.displayArtist)
                                .font(.system(size: 12))
                                .opacity(0.6)
                                .lineLimit(1)
                        }
                        Spacer()
                        if offset == player.index {
                            PlayingBars(playing: player.isPlaying, color: .white)
                        }
                    }
                    .foregroundColor(.white)
                    .opacity(offset < player.index ? 0.45 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture { player.jump(to: offset) }
                    .listRowBackground(offset == player.index ? Color.white.opacity(0.12) : Color.clear)
                    .listRowSeparator(.hidden)
                    .deleteDisabled(offset == player.index)
                }
                .onDelete { player.removeFromQueue(at: $0) }
                .onMove { player.moveInQueue(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(editing ? .active : .inactive))
        }
    }
}

/// Barre de progression du lecteur (la seule partie redessinée en continu).
struct ScrubBar: View {
    @ObservedObject var clock: EngineClock
    let seek: (Double) -> Void
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let fraction = clock.duration > 0
                    ? CGFloat((scrubbing ? scrubValue : clock.currentTime) / clock.duration) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.white)
                        .frame(width: geometry.size.width * min(1, max(0, fraction)))
                }
                .frame(height: scrubbing ? 12 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !scrubbing {
                                withAnimation(.spring(response: 0.25)) { scrubbing = true }
                            }
                            let ratio = min(1, max(0, value.location.x / max(1, geometry.size.width)))
                            scrubValue = Double(ratio) * clock.duration
                        }
                        .onEnded { _ in
                            seek(scrubValue)
                            withAnimation(.spring(response: 0.3)) { scrubbing = false }
                        }
                )
            }
            .frame(height: 22)
            HStack {
                Text(Fmt.clock(scrubbing ? scrubValue : clock.currentTime))
                Spacer()
                Text("-" + Fmt.clock(max(0, clock.duration - (scrubbing ? scrubValue : clock.currentTime))))
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .opacity(0.7)
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
    }

}

/// Fine barre de progression du mini-lecteur.
struct MiniProgress: View {
    @ObservedObject var clock: EngineClock

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Color.accentColor)
                .frame(width: geometry.size.width * progress, height: 2)
        }
        .frame(height: 2)
    }

    private var progress: CGFloat {
        guard clock.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, clock.currentTime / clock.duration)))
    }
}

/// Anneau de progression autour de la bulle.
struct BubbleRing: View {
    @ObservedObject var clock: EngineClock

    var body: some View {
        let progress = clock.duration > 0 ? min(1, max(0, clock.currentTime / clock.duration)) : 0
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Laisse la place au mini-lecteur sous les listes (on peut toucher la dernière ligne).
struct MiniPlayerInset: ViewModifier {
    @EnvironmentObject var player: AudioEngine
    @AppStorage("miniCollapsed") private var collapsed = false

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.current != nil && !collapsed {
                Color.clear.frame(height: 80)
            }
        }
    }
}

extension View {
    func miniPlayerInset() -> some View {
        modifier(MiniPlayerInset())
    }
}
