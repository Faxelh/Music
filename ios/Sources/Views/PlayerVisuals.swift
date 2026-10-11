import SwiftUI

/// Temps de lecture « en direct » (entre deux relevés du moteur) pour des animations fluides.
func liveTime(_ player: AudioEngine, at date: Date) -> Double {
    guard player.isPlaying else { return player.currentTime }
    let elapsed = date.timeIntervalSince(player.timeStamp) * Double(player.rate)
    return min(player.duration, player.currentTime + max(0, min(elapsed, 1)))
}

// MARK: - Fonds animés

struct PlayerBackground: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var appearance = Appearance.shared
    @ObservedObject private var library = LibraryStore.shared

    var body: some View {
        let song = player.current
        let colors = library.colors(for: song)
        ZStack {
            Color.black
            switch appearance.background {
            case .aurora:
                AuroraView(colors: colors, animated: appearance.animations)
            case .artwork:
                ArtworkBackdrop(url: song.flatMap { library.artworkURL($0) }, colors: colors, animated: appearance.animations)
            case .photo:
                PhotoBackdrop(image: appearance.playerImage, colors: colors, animated: appearance.animations)
            case .gradient:
                RainbowBackdrop(colors: colors, animated: appearance.animations)
            case .black:
                LinearGradient(colors: [Color(white: 0.08), .black], startPoint: .top, endPoint: .bottom)
            }
            Color.black.opacity(appearance.background == .black ? 0 : appearance.backgroundDim)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: song?.id)
    }
}

/// Taches de couleur qui dérivent et respirent avec les basses.
struct AuroraView: View {
    @EnvironmentObject var player: AudioEngine
    let colors: [Color]
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let pulse = CGFloat(animated ? player.bass : 0)
            Canvas { canvas, size in
                let base = max(size.width, size.height)
                for (offset, color) in colors.prefix(4).enumerated() {
                    let phase = Double(offset) * 1.7
                    let speed = 0.09 + Double(offset) * 0.025
                    let x = size.width * (0.5 + 0.38 * CGFloat(sin(time * speed + phase)))
                    let y = size.height * (0.45 + 0.35 * CGFloat(cos(time * speed * 1.3 + phase * 0.7)))
                    let radius = base * (0.42 + 0.06 * CGFloat(sin(time * 0.3 + phase))) * (1 + pulse * 0.35)
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    canvas.fill(Path(ellipseIn: rect),
                                with: .radialGradient(Gradient(colors: [color.opacity(0.95), color.opacity(0)]),
                                                      center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius))
                }
            }
            .blur(radius: 30)
        }
    }
}

/// Pochette agrandie, floutée, qui tourne lentement.
struct ArtworkBackdrop: View {
    let url: URL?
    let colors: [Color]
    let animated: Bool

    var body: some View {
        GeometryReader { geometry in
            let side = max(geometry.size.width, geometry.size.height) * 1.6
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animated)) { context in
                let angle = animated ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 360) * 4 : 0
                ZStack {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let url = url {
                        LocalImage(url: url)
                    }
                }
                .frame(width: side, height: side)
                .rotationEffect(.degrees(angle))
                .blur(radius: 60)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
    }
}

/// Votre photo, avec un lent zoom (effet Ken Burns).
struct PhotoBackdrop: View {
    let image: UIImage?
    let colors: [Color]
    let animated: Bool

    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let scale = animated ? 1.12 + 0.08 * sin(time / 9) : 1.05
                    let dx = animated ? 14 * cos(time / 11) : 0
                    let dy = animated ? 10 * sin(time / 13) : 0
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(scale)
                        .offset(x: dx, y: dy)
                        .clipped()
                }
            } else {
                AuroraView(colors: colors, animated: animated)
            }
        }
    }
}

/// Dégradé qui tourne avec les couleurs de la pochette.
struct RainbowBackdrop: View {
    let colors: [Color]
    let animated: Bool

    var body: some View {
        GeometryReader { geometry in
            let side = max(geometry.size.width, geometry.size.height) * 1.5
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
                let angle = animated ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 360) * 12 : 0
                AngularGradient(colors: colors + [colors.first ?? .pink], center: .center)
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(angle))
                    .blur(radius: 50)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
    }
}

// MARK: - Pochette du lecteur

struct PlayerCover: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var meter = AudioEngine.shared.meter
    @ObservedObject private var appearance = Appearance.shared
    @ObservedObject private var library = LibraryStore.shared
    let song: Song
    let size: CGFloat
    let namespace: Namespace.ID
    @State private var tilt: CGSize = .zero

    var body: some View {
        ZStack {
            if appearance.coverStyle != .card {
                SurroundVisualizer(style: appearance.visualizer, size: size, color: appearance.accent)
            }
            switch appearance.coverStyle {
            case .square:
                SongArtwork(song: song, size: size, radius: 18)
                    .matchedGeometryEffect(id: "artwork", in: namespace)
                    .shadow(color: .black.opacity(0.45), radius: 26, y: 14)
                    .scaleEffect(player.isPlaying ? 1 + CGFloat(appearance.animations ? meter.bass : 0) * 0.04 : 0.84)
                    .animation(.spring(response: 0.5, dampingFraction: 0.68), value: player.isPlaying)
            case .vinyl:
                VinylView(song: song, size: size)
                    .matchedGeometryEffect(id: "artwork", in: namespace)
                    .scaleEffect(player.isPlaying ? 1 : 0.9)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
            case .card:
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !appearance.animations)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let swayX = appearance.animations ? sin(time * 0.8) * 6 : 0
                    let swayY = appearance.animations ? cos(time * 0.6) * 6 : 0
                    SongArtwork(song: song, size: size, radius: 22)
                        .matchedGeometryEffect(id: "artwork", in: namespace)
                        .overlay(
                            LinearGradient(colors: [.white.opacity(0.35), .clear, .clear],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        )
                        .shadow(color: .black.opacity(0.5), radius: 30, x: -tilt.width / 6, y: 18)
                        .rotation3DEffect(.degrees(Double(-tilt.height / 8) + swayY), axis: (x: 1, y: 0, z: 0))
                        .rotation3DEffect(.degrees(Double(tilt.width / 8) + swayX), axis: (x: 0, y: 1, z: 0))
                        .scaleEffect(player.isPlaying ? 1 : 0.88)
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in tilt = value.translation }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { tilt = .zero }
                        }
                )
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
            case .round:
                SongArtwork(song: song, size: size * 0.92, radius: size * 0.46)
                    .matchedGeometryEffect(id: "artwork", in: namespace)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 2))
                    .shadow(color: appearance.accent.opacity(0.35 + Double(meter.bass) * 0.5),
                            radius: 18 + CGFloat(meter.bass) * 30)
                    .scaleEffect(player.isPlaying ? 1 + CGFloat(appearance.animations ? meter.bass : 0) * 0.08 : 0.86)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: player.isPlaying)
            case .cd:
                CDView(song: song, size: size)
                    .matchedGeometryEffect(id: "artwork", in: namespace)
                    .scaleEffect(player.isPlaying ? 1 : 0.9)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
            case .cassette:
                CassetteView(song: song, width: size)
                    .matchedGeometryEffect(id: "artwork", in: namespace)
            case .polaroid:
                PolaroidView(song: song, size: size)
                    .matchedGeometryEffect(id: "artwork", in: namespace)
            case .neon:
                NeonCover(song: song, size: size)
                    .matchedGeometryEffect(id: "artwork", in: namespace)
            case .stack:
                StackCover(song: song, size: size)
                    .matchedGeometryEffect(id: "artwork", in: namespace)
            case .floating:
                FloatingCover(song: song, size: size)
                    .matchedGeometryEffect(id: "artwork", in: namespace)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Temps animé (pour les décors qui bougent même en pause).
private func animationTime(_ date: Date) -> Double {
    date.timeIntervalSinceReferenceDate
}

/// CD irisé qui tourne, la pochette imprimée dessus.
struct CDView: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var library = LibraryStore.shared
    let song: Song
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !player.isPlaying)) { context in
            let angle = liveTime(player, at: context.date) * 70
            ZStack {
                Circle().fill(
                    AngularGradient(colors: [Color(white: 0.85), .pink.opacity(0.7), .cyan.opacity(0.7), .yellow.opacity(0.6),
                                             Color(white: 0.9), .purple.opacity(0.6), .mint.opacity(0.7), Color(white: 0.85)],
                                    center: .center)
                )
                Artwork(url: library.artworkURL(song), seed: song.id, size: size * 0.9, radius: size * 0.45)
                    .opacity(0.88)
                // Reflet arc-en-ciel qui reste fixe pendant que le disque tourne.
                AngularGradient(colors: [.clear, .white.opacity(0.45), .clear, .cyan.opacity(0.25), .clear,
                                         .pink.opacity(0.3), .clear], center: .center)
                    .clipShape(Circle())
                    .blendMode(.screen)
                    .rotationEffect(.degrees(-angle))
                Circle().stroke(Color.white.opacity(0.5), lineWidth: 1)
                Circle().fill(Color(white: 0.75)).frame(width: size * 0.3, height: size * 0.3)
                Circle().stroke(Color.white.opacity(0.6), lineWidth: 1).frame(width: size * 0.3, height: size * 0.3)
                Circle().fill(Color.black).frame(width: size * 0.1, height: size * 0.1)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .rotationEffect(.degrees(angle))
            .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        }
    }
}

/// Cassette audio : les bobines tournent pendant la lecture.
struct CassetteView: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var library = LibraryStore.shared
    let song: Song
    let width: CGFloat

    var body: some View {
        let height = width * 0.64
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !player.isPlaying)) { context in
            let angle = liveTime(player, at: context.date) * 120
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                VStack(spacing: 0) {
                    // Étiquette avec la pochette et le titre.
                    HStack(spacing: 10) {
                        Artwork(url: library.artworkURL(song), seed: song.id, size: height * 0.32, radius: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .lineLimit(1)
                            Text(song.displayArtist)
                                .font(.system(size: 11, weight: .medium))
                                .opacity(0.7)
                                .lineLimit(1)
                        }
                        .foregroundColor(.black)
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.93)))
                    .padding(.horizontal, width * 0.07)
                    .padding(.top, height * 0.08)
                    Spacer(minLength: 0)
                    // Fenêtre et bobines.
                    ZStack {
                        Capsule().fill(Color.black.opacity(0.75)).frame(width: width * 0.62, height: height * 0.3)
                        HStack(spacing: width * 0.2) {
                            reel(angle, size: height * 0.26)
                            reel(angle * 1.15, size: height * 0.26)
                        }
                    }
                    .padding(.bottom, height * 0.1)
                }
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.5), radius: 22, y: 12)
        }
        .frame(width: width, height: width)
    }

    private func reel(_ angle: Double, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.85))
            ForEach(0..<6, id: \.self) { spoke in
                Capsule()
                    .fill(Color(white: 0.35))
                    .frame(width: size * 0.12, height: size * 0.42)
                    .offset(y: -size * 0.2)
                    .rotationEffect(.degrees(Double(spoke) * 60))
            }
            Circle().fill(Color(white: 0.25)).frame(width: size * 0.25, height: size * 0.25)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
    }
}

/// Photo Polaroid légèrement penchée, avec le titre écrit dessous.
struct PolaroidView: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var appearance = Appearance.shared
    let song: Song
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !appearance.animations)) { context in
            let sway = appearance.animations ? sin(animationTime(context.date) * 0.7) * 2.5 : 0
            VStack(spacing: 8) {
                SongArtwork(song: song, size: size * 0.8, radius: 2)
                Text(song.title)
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .italic()
                    .foregroundColor(Color(white: 0.2))
                    .lineLimit(1)
                    .frame(width: size * 0.8)
            }
            .padding(.horizontal, size * 0.05)
            .padding(.top, size * 0.05)
            .padding(.bottom, size * 0.07)
            .background(Color(white: 0.97))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
            .rotationEffect(.degrees(-3 + sway))
            .scaleEffect(player.isPlaying ? 1 : 0.92)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
        }
    }
}

/// Pochette entourée d'un néon qui tourne et brille avec les basses.
struct NeonCover: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var meter = AudioEngine.shared.meter
    @ObservedObject private var appearance = Appearance.shared
    let song: Song
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !appearance.animations)) { context in
            let angle = appearance.animations ? animationTime(context.date).truncatingRemainder(dividingBy: 360) * 90 : 0
            let glow = 0.5 + Double(meter.bass) * 0.5
            let ring = AngularGradient(colors: [appearance.accent, .cyan, .purple, .pink, appearance.accent], center: .center,
                                       angle: .degrees(angle))
            SongArtwork(song: song, size: size * 0.9, radius: 22)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ring, lineWidth: 4))
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(ring, lineWidth: 14)
                        .blur(radius: 18)
                        .opacity(glow)
                )
                .scaleEffect(player.isPlaying ? 1 : 0.88)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
        }
    }
}

/// Pile de pochettes : les prochains morceaux de la file apparaissent derrière.
struct StackCover: View {
    @EnvironmentObject var player: AudioEngine
    let song: Song
    let size: CGFloat

    var body: some View {
        let upcoming = Array(player.queue.dropFirst(player.index + 1).prefix(2))
        ZStack {
            ForEach(Array(upcoming.enumerated().reversed()), id: \.element.id) { offset, next in
                SongArtwork(song: next, size: size * 0.82, radius: 16)
                    .opacity(0.75 - Double(offset) * 0.25)
                    .rotationEffect(.degrees(Double(offset + 1) * 7))
                    .offset(x: CGFloat(offset + 1) * 14, y: -CGFloat(offset + 1) * 12)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            }
            SongArtwork(song: song, size: size * 0.82, radius: 16)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 12)
                .rotationEffect(.degrees(-3))
                .scaleEffect(player.isPlaying ? 1 : 0.9)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: song.id)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
    }
}

/// Pochette qui flotte doucement, avec son reflet en dessous.
struct FloatingCover: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var appearance = Appearance.shared
    let song: Song
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !appearance.animations)) { context in
            let bob = appearance.animations ? CGFloat(sin(animationTime(context.date) * 1.4)) * 8 : 0
            VStack(spacing: 6) {
                SongArtwork(song: song, size: size * 0.72, radius: 14)
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
                    .offset(y: bob)
                SongArtwork(song: song, size: size * 0.72, radius: 14)
                    .scaleEffect(x: 1, y: -1)
                    .frame(height: size * 0.22, alignment: .top)
                    .clipped()
                    .mask(LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    .offset(y: -bob * 0.5)
            }
            .scaleEffect(player.isPlaying ? 1 : 0.92)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
        }
    }
}

/// Disque vinyle qui tourne au rythme de la lecture, la pochette au centre.
struct VinylView: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var library = LibraryStore.shared
    let song: Song
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !player.isPlaying)) { context in
            let angle = liveTime(player, at: context.date) * 40
            ZStack {
                Circle().fill(
                    RadialGradient(colors: [Color(white: 0.16), Color(white: 0.04)], center: .center,
                                   startRadius: 0, endRadius: size / 2)
                )
                ForEach(0..<14, id: \.self) { ring in
                    Circle()
                        .stroke(Color.white.opacity(ring % 3 == 0 ? 0.08 : 0.04), lineWidth: 1)
                        .frame(width: size * (0.58 + CGFloat(ring) * 0.029), height: size * (0.58 + CGFloat(ring) * 0.029))
                }
                Artwork(url: library.artworkURL(song), seed: song.id, size: size * 0.5, radius: size * 0.25)
                Circle().fill(Color.black).frame(width: size * 0.05, height: size * 0.05)
                // Reflet de lumière fixe.
                AngularGradient(colors: [.clear, .white.opacity(0.12), .clear, .white.opacity(0.08), .clear],
                                center: .center)
                    .clipShape(Circle())
                    .rotationEffect(.degrees(-angle))
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        }
    }
}

// MARK: - Visualiseurs

/// Barres qui dansent avec la musique.
struct BarsVisualizer: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var meter = AudioEngine.shared.meter
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let count = meter.spectrum.count
            let spacing: CGFloat = 3
            let width = max(1, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(max(1, count)))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { band in
                    let level = CGFloat(meter.spectrum[band])
                    Capsule()
                        .fill(LinearGradient(colors: [color, color.opacity(0.55), .white.opacity(0.8)],
                                             startPoint: .bottom, endPoint: .top))
                        .frame(width: width, height: max(3, geometry.size.height * level))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.linear(duration: 0.06), value: meter.spectrum)
        }
    }
}

/// Onde lisse (miroir) qui suit le spectre.
struct WaveVisualizer: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var meter = AudioEngine.shared.meter
    let color: Color

    var body: some View {
        Canvas { canvas, size in
            let values = meter.spectrum
            guard values.count > 1 else { return }
            let middle = size.height / 2
            let step = size.width / CGFloat(values.count - 1)
            var top = Path()
            var bottom = Path()
            top.move(to: CGPoint(x: 0, y: middle))
            bottom.move(to: CGPoint(x: 0, y: middle))
            for (offset, value) in values.enumerated() {
                let x = CGFloat(offset) * step
                let height = CGFloat(value) * middle * 0.95
                let previousX = CGFloat(max(0, offset - 1)) * step
                let control = (previousX + x) / 2
                top.addQuadCurve(to: CGPoint(x: x, y: middle - height), control: CGPoint(x: control, y: middle - height))
                bottom.addQuadCurve(to: CGPoint(x: x, y: middle + height), control: CGPoint(x: control, y: middle + height))
            }
            top.addLine(to: CGPoint(x: size.width, y: middle))
            bottom.addLine(to: CGPoint(x: size.width, y: middle))
            var shape = top
            shape.addPath(bottom)
            canvas.fill(shape, with: .linearGradient(Gradient(colors: [color.opacity(0.9), .white.opacity(0.6), color.opacity(0.9)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
        }
    }
}

/// Anneau de rayons autour de la pochette.
struct RingVisualizer: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var meter = AudioEngine.shared.meter
    let radius: CGFloat
    let color: Color

    var body: some View {
        Canvas { canvas, size in
            let values = meter.spectrum
            guard !values.isEmpty else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let rays = values.count * 2
            for ray in 0..<rays {
                let band = ray < values.count ? ray : rays - 1 - ray
                let level = CGFloat(values[band])
                let angle = Double(ray) / Double(rays) * 2 * .pi - .pi / 2
                let length = 6 + level * 38
                let start = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
                let end = CGPoint(x: center.x + CGFloat(cos(angle)) * (radius + length),
                                  y: center.y + CGFloat(sin(angle)) * (radius + length))
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                canvas.stroke(path, with: .color(color.opacity(0.55 + Double(level) * 0.45)),
                              style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }
}

// MARK: - Choix du visualiseur

/// Visualiseurs dessinés sous la pochette.
struct BelowVisualizer: View {
    let style: Appearance.Visualizer
    let color: Color

    var body: some View {
        switch style {
        case .bars: BarsVisualizer(color: color)
        case .mirror: MirrorBarsVisualizer(color: color)
        case .rainbow: RainbowBarsVisualizer()
        case .dots: DotsVisualizer(color: color)
        case .wave: WaveVisualizer(color: color)
        case .line: LineVisualizer(color: color)
        default: EmptyView()
        }
    }
}

/// Visualiseurs dessinés autour de la pochette.
struct SurroundVisualizer: View {
    let style: Appearance.Visualizer
    let size: CGFloat
    let color: Color

    var body: some View {
        switch style {
        case .ring:
            RingVisualizer(radius: size / 2 + 8, color: color)
                .frame(width: size + 90, height: size + 90)
        case .particles:
            ParticlesVisualizer(radius: size / 2, color: color)
                .frame(width: size + 160, height: size + 160)
        case .pulse:
            PulseVisualizer(radius: size / 2, color: color)
                .frame(width: size + 160, height: size + 160)
        case .halo:
            HaloVisualizer(size: size, color: color)
        default:
            EmptyView()
        }
    }
}

/// Barres symétriques (vers le haut et vers le bas).
struct MirrorBarsVisualizer: View {
    @ObservedObject private var meter = AudioEngine.shared.meter
    let color: Color

    var body: some View {
        Canvas { canvas, size in
            let values = meter.spectrum
            guard !values.isEmpty else { return }
            let spacing: CGFloat = 3
            let width = max(1, (size.width - spacing * CGFloat(values.count - 1)) / CGFloat(values.count))
            let middle = size.height / 2
            for (offset, value) in values.enumerated() {
                let height = max(2, CGFloat(value) * middle)
                let rect = CGRect(x: CGFloat(offset) * (width + spacing), y: middle - height, width: width, height: height * 2)
                canvas.fill(Path(roundedRect: rect, cornerRadius: width / 2),
                            with: .linearGradient(Gradient(colors: [.white.opacity(0.9), color, .white.opacity(0.9)]),
                                                  startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            }
        }
    }
}

/// Barres aux couleurs de l'arc-en-ciel.
struct RainbowBarsVisualizer: View {
    @ObservedObject private var meter = AudioEngine.shared.meter

    var body: some View {
        Canvas { canvas, size in
            let values = meter.spectrum
            guard !values.isEmpty else { return }
            let spacing: CGFloat = 3
            let width = max(1, (size.width - spacing * CGFloat(values.count - 1)) / CGFloat(values.count))
            for (offset, value) in values.enumerated() {
                let height = max(3, CGFloat(value) * size.height)
                let rect = CGRect(x: CGFloat(offset) * (width + spacing), y: size.height - height, width: width, height: height)
                let hue = Double(offset) / Double(values.count)
                canvas.fill(Path(roundedRect: rect, cornerRadius: width / 2),
                            with: .color(Color(hue: hue, saturation: 0.75, brightness: 1)))
            }
        }
    }
}

/// Colonnes de points qui s'allument (comme un vieil égaliseur).
struct DotsVisualizer: View {
    @ObservedObject private var meter = AudioEngine.shared.meter
    let color: Color

    var body: some View {
        Canvas { canvas, size in
            let values = meter.spectrum
            guard !values.isEmpty else { return }
            let columns = values.count
            let rows = 6
            let step = size.width / CGFloat(columns)
            let dot = min(step * 0.7, size.height / CGFloat(rows) * 0.7)
            for (column, value) in values.enumerated() {
                let lit = Int((Double(value) * Double(rows)).rounded(.up))
                for row in 0..<rows {
                    let x = CGFloat(column) * step + (step - dot) / 2
                    let y = size.height - CGFloat(row + 1) * (size.height / CGFloat(rows)) + (size.height / CGFloat(rows) - dot) / 2
                    let on = row < lit
                    let shade: Color = row >= rows - 1 ? .white : color
                    canvas.fill(Path(ellipseIn: CGRect(x: x, y: y, width: dot, height: dot)),
                                with: .color(on ? shade : Color.white.opacity(0.08)))
                }
            }
        }
    }
}

/// Ligne lumineuse qui suit le spectre.
struct LineVisualizer: View {
    @ObservedObject private var meter = AudioEngine.shared.meter
    let color: Color

    var body: some View {
        Canvas { canvas, size in
            let values = meter.spectrum
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (offset, value) in values.enumerated() {
                let point = CGPoint(x: CGFloat(offset) * step, y: size.height - CGFloat(value) * size.height * 0.9 - 2)
                if offset == 0 {
                    path.move(to: point)
                } else {
                    let previous = CGPoint(x: CGFloat(offset - 1) * step,
                                           y: size.height - CGFloat(values[offset - 1]) * size.height * 0.9 - 2)
                    let middle = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
                    path.addQuadCurve(to: middle, control: previous)
                }
            }
            var glow = canvas
            glow.addFilter(.blur(radius: 6))
            glow.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            canvas.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Particules qui jaillissent autour de la pochette, plus vite avec les basses.
struct ParticlesVisualizer: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var appearance = Appearance.shared
    let radius: CGFloat
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40, paused: !player.isPlaying || !appearance.animations)) { context in
            let time = animationTime(context.date)
            let values = player.spectrum
            let bass = Double(player.bass)
            Canvas { canvas, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let count = 64
                for index in 0..<count {
                    let seed = Double(index) * 0.618_034
                    let angle = seed * 2 * .pi * 7
                    let speed = 0.25 + seed.truncatingRemainder(dividingBy: 1) * 0.35
                    let phase = (time * speed * (0.6 + bass) + seed).truncatingRemainder(dividingBy: 1)
                    let distance = radius + 6 + CGFloat(phase) * 70
                    let level = values.isEmpty ? 0 : CGFloat(values[index % values.count])
                    let dot = 2 + level * 5
                    let x = center.x + CGFloat(cos(angle)) * distance
                    let y = center.y + CGFloat(sin(angle)) * distance
                    canvas.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)),
                                with: .color((index % 3 == 0 ? Color.white : color).opacity(1 - phase)))
                }
            }
        }
    }
}

/// Ondes de choc qui partent de la pochette au rythme des basses.
struct PulseVisualizer: View {
    @EnvironmentObject var player: AudioEngine
    @ObservedObject private var appearance = Appearance.shared
    let radius: CGFloat
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40, paused: !player.isPlaying || !appearance.animations)) { context in
            let time = animationTime(context.date)
            let bass = Double(player.bass)
            Canvas { canvas, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for wave in 0..<3 {
                    let phase = (time * 0.55 + Double(wave) / 3).truncatingRemainder(dividingBy: 1)
                    let current = radius + CGFloat(phase) * 75
                    let rect = CGRect(x: center.x - current, y: center.y - current, width: current * 2, height: current * 2)
                    canvas.stroke(Path(ellipseIn: rect), with: .color(color.opacity((1 - phase) * (0.25 + bass * 0.75))),
                                  lineWidth: 2 + CGFloat(bass) * 6)
                }
            }
        }
    }
}

/// Halo de lumière derrière la pochette, qui grandit avec les basses.
struct HaloVisualizer: View {
    @ObservedObject private var meter = AudioEngine.shared.meter
    let size: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.85), color.opacity(0.3), .clear], center: .center,
                                 startRadius: 0, endRadius: size * 0.75))
            .frame(width: size * 1.5, height: size * 1.5)
            .scaleEffect(0.9 + CGFloat(meter.bass) * 0.45)
            .blur(radius: 20)
            .animation(.easeOut(duration: 0.12), value: meter.bass)
    }
}
