import SwiftUI

/// Vitesse, tonalité et boucle A–B du lecteur.
struct PlaybackTuningView: View {
    @EnvironmentObject var player: AudioEngine
    @Environment(\.dismiss) private var dismiss
    @State private var speed: Double = 1
    @State private var pitch: Double = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(L("Vitesse"), systemImage: "speedometer")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Text(Fmt.rate(Float(speed)))
                            .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(.accentColor)
                    }
                    Slider(value: $speed, in: 0.5...2, step: 0.05)
                        .onChange(of: speed) { value in
                            let rounded = Float((value * 20).rounded() / 20)
                            if rounded != player.rate { player.setRate(rounded) }
                        }
                    HStack(spacing: 8) {
                        ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { value in
                            Button {
                                speed = value
                                player.setRate(Float(value))
                            } label: {
                                Text(Fmt.rate(Float(value)))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(abs(speed - value) < 0.01 ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                                    .background(Capsule().fill(abs(speed - value) < 0.01 ? Color.accentColor : Color(.tertiarySystemFill)))
                            }
                            .buttonStyle(BounceButtonStyle())
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(L("Tonalité"), systemImage: "tuningfork")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Button {
                            setPitch(pitch - 1)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 36, height: 32)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                        .disabled(pitch <= -6)
                        Text(pitch == 0 ? "0" : String(format: "%+.0f", pitch))
                            .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(.accentColor)
                            .frame(minWidth: 40)
                        Button {
                            setPitch(pitch + 1)
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 36, height: 32)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                        .disabled(pitch >= 6)
                    }
                    .buttonStyle(BounceButtonStyle())
                    Slider(value: $pitch, in: -6...6, step: 1)
                        .onChange(of: pitch) { value in
                            if Float(value.rounded()) != player.semitones { setPitch(value) }
                        }
                    Text(L("Monte ou baisse la voix et les instruments (en demi-tons) sans changer la vitesse. Idéal pour chanter dans votre tonalité."))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        player.cycleLoop()
                    } label: {
                        Label(loopText, systemImage: "repeat.circle")
                    }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
                    Button {
                        speed = 1
                        player.setRate(1)
                        setPitch(0)
                        player.clearLoop()
                    } label: {
                        Label(L("Réinitialiser"), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(L("Vitesse et tonalité"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
            }
        }
        .onAppear {
            speed = Double(player.rate)
            pitch = Double(player.semitones)
        }
    }

    private var loopText: String {
        if player.loopA == nil { return L("Placer A") }
        if player.loopB == nil { return L("Placer B") }
        return L("Sans boucle")
    }

    private func setPitch(_ value: Double) {
        pitch = max(-6, min(6, value.rounded()))
        player.setPitch(semitones: Float(pitch))
    }
}

/// Fiche d'un morceau : balises, qualité audio, fichier, écoutes.
struct TrackInfoView: View {
    @EnvironmentObject var player: AudioEngine
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let song: Song

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        SongArtwork(song: song, size: 72, radius: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.title)
                                .font(.system(size: 18, weight: .bold))
                                .lineLimit(2)
                            Text(song.displayArtist)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section(L("Morceau")) {
                    row(L("Album"), song.album)
                    row(L("Genre"), song.genre)
                    row(L("Année"), song.year.map { "\($0)" })
                    row(L("Piste"), song.trackNumber.map { "\($0)" })
                    row(L("Durée"), Fmt.duration(song.duration))
                }
                Section(L("Qualité")) {
                    row(L("Format"), format)
                    if player.current?.id == song.id, let info = player.fileFormatInfo {
                        row(L("Échantillonnage"), String(format: "%.1f kHz", info.sampleRate / 1000))
                        row(L("Canaux"), info.channels == 1 ? L("Mono") : info.channels == 2 ? L("Stéréo") : "\(info.channels)")
                    }
                    if song.size > 0 && song.duration > 0 {
                        row(L("Débit moyen"), "\(Int(song.size * 8 / song.duration / 1000)) kbps")
                    }
                    row(L("Taille"), Fmt.size(song.size))
                }
                Section(L("Écoute")) {
                    row(L("Écoutes"), "\(library.playCounts[song.id] ?? 0)")
                    row(L("Dernière écoute"), library.lastPlayed[song.id].map {
                        Date(timeIntervalSince1970: $0).formatted(.dateTime.day().month().year().hour().minute().locale(Lang.locale))
                    })
                    row(L("Ajouté le"), song.added > 0
                        ? Date(timeIntervalSince1970: song.added).formatted(.dateTime.day().month().year().locale(Lang.locale)) : nil)
                    row(L("Emplacement"), song.folder)
                }
                Section {
                    Button {
                        player.play(library.radio(for: song))
                        dismiss()
                    } label: {
                        Label(L("Radio de ce morceau"), systemImage: "dot.radiowaves.left.and.right")
                    }
                    Button {
                        library.toggleFavorite(song)
                    } label: {
                        if library.isFavorite(song) {
                            Label(L("Retirer des favoris"), systemImage: "heart.slash")
                        } else {
                            Label(L("Favori"), systemImage: "heart")
                        }
                    }
                }
            }
            .navigationTitle(L("Informations"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("OK")) { dismiss() }
                }
            }
        }
    }

    private var format: String {
        if song.isIpod { return L("Musique de l'iPhone") }
        let ext = song.url.pathExtension.uppercased()
        return ext.isEmpty ? "—" : ext
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value = value, !value.isEmpty {
            HStack {
                Text(label).foregroundColor(.secondary)
                Spacer(minLength: 12)
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }
}
