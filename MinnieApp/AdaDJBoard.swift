import SwiftUI
import AVFoundation
import Combine

struct AudioTrack: Identifiable {
    let id: Int
    let title: String
    let fileName: String
}

class DJBoardViewModel: ObservableObject {
    @Published var isPlaying: [Int: Bool] = [:]
    @Published var isLooping: [Int: Bool] = [:]
    @Published var isMuted: [Int: Bool] = [:]
    @Published var volume: [Int: Float] = [:]
    @Published var speed: [Int: Float] = [:]
    @Published var currentTime: [Int: Double] = [:]
    @Published var hotCue: [Int: Double] = [:]
    @Published var tapBPM: [Int: Double] = [:]
    @Published var crossfader: Float = 0.5
    @Published var autoStopEnabled: Bool = false
    @Published var autoStopDuration: Double = 60
    @Published var autoStopRemaining: Double = 60

    var players: [Int: AVAudioPlayer] = [:]
    private var tapTimes: [Int: [Date]] = [:]
    private var displayTimer: Timer?
    private var autoStopTimer: Timer?

    let tracks: [AudioTrack] = [
        AudioTrack(id: 0, title: "1", fileName: "ex1"),
        AudioTrack(id: 1, title: "2", fileName: "ex2"),
        AudioTrack(id: 2, title: "3", fileName: "ex3")
    ]

    init() {
        for track in tracks {
            isPlaying[track.id] = false
            isLooping[track.id] = true
            isMuted[track.id] = false
            volume[track.id] = 0.8
            speed[track.id] = 1.0
            currentTime[track.id] = 0
            hotCue[track.id] = -1
            tapBPM[track.id] = 0
            tapTimes[track.id] = []
            loadSound(track: track)
        }
        startDisplayTimer()
    }

    private func startDisplayTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            for track in self.tracks {
                if let player = self.players[track.id] {
                    self.currentTime[track.id] = player.currentTime
                }
            }
        }
    }

    func loadSound(track: AudioTrack) {
        guard let url = Bundle.main.url(forResource: track.fileName, withExtension: "mp3") else {
            print("Missing file: \(track.fileName).mp3")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.numberOfLoops = -1
            player.volume = volume[track.id] ?? 0.8
            player.rate = speed[track.id] ?? 1.0
            player.prepareToPlay()
            players[track.id] = player
        } catch {
            print("Error loading \(track.fileName): \(error.localizedDescription)")
        }
    }

    func togglePlay(trackId: Int) {
        guard let player = players[trackId] else { return }
        if player.isPlaying { player.pause(); isPlaying[trackId] = false }
        else                 { player.play();  isPlaying[trackId] = true  }
    }

    func toggleLoop(trackId: Int) {
        let looping = !(isLooping[trackId] ?? true)
        isLooping[trackId] = looping
        players[trackId]?.numberOfLoops = looping ? -1 : 0
    }

    func toggleMute(trackId: Int) {
        let muted = !(isMuted[trackId] ?? false)
        isMuted[trackId] = muted
        if muted { players[trackId]?.volume = 0 }
        else      { applyCrossfaderToTrack(trackId) }
    }

    func setVolume(_ value: Float, trackId: Int) {
        volume[trackId] = value
        if isMuted[trackId] != true { applyCrossfaderToTrack(trackId) }
    }

    func setSpeed(_ value: Float, trackId: Int) {
        speed[trackId] = value
        players[trackId]?.rate = value
    }

    func resetTrack(trackId: Int) {
        guard let player = players[trackId] else { return }
        player.stop()
        player.currentTime = 0
        player.rate = speed[trackId] ?? 1.0
        isPlaying[trackId] = false
    }

    func stopAll() {
        disableAutoStop()
        for id in players.keys {
            players[id]?.stop()
            players[id]?.currentTime = 0
            isPlaying[id] = false
        }
    }

    func seek(to time: Double, trackId: Int) {
        players[trackId]?.currentTime = time
    }

    func setHotCue(trackId: Int) {
        hotCue[trackId] = players[trackId]?.currentTime ?? 0
    }

    func jumpToHotCue(trackId: Int) {
        guard let cue = hotCue[trackId], cue >= 0 else { return }
        players[trackId]?.currentTime = cue
    }

    func clearHotCue(trackId: Int) {
        hotCue[trackId] = -1
    }

    func tap(trackId: Int) {
        let now = Date()
        var taps = tapTimes[trackId] ?? []
        taps.append(now)
        taps = taps.filter { now.timeIntervalSince($0) < 3.0 }
        tapTimes[trackId] = taps
        guard taps.count >= 2 else { return }
        let intervals = zip(taps, taps.dropFirst()).map { $1.timeIntervalSince($0) }
        let avg = intervals.reduce(0, +) / Double(intervals.count)
        tapBPM[trackId] = (60.0 / avg).rounded()
    }

    func setCrossfader(_ value: Float) {
        crossfader = value
        for track in tracks where isMuted[track.id] != true {
            applyCrossfaderToTrack(track.id)
        }
    }

    private func applyCrossfaderToTrack(_ trackId: Int) {
        let base = volume[trackId] ?? 0.8
        let cf = crossfader
        let multiplier: Float
        switch trackId {
        case 0:  multiplier = cf < 0.5 ? 1.0 : (1.0 - cf) * 2.0
        case 1:  multiplier = cf > 0.5 ? 1.0 : cf * 2.0
        default: multiplier = 1.0
        }
        players[trackId]?.volume = base * multiplier
    }


    func toggleAutoStop() {
        autoStopEnabled ? disableAutoStop() : enableAutoStop()
    }

    private func enableAutoStop() {
        autoStopEnabled   = true
        autoStopRemaining = autoStopDuration
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.autoStopRemaining -= 1
            if self.autoStopRemaining <= 0 { self.stopAll() }
        }
    }

    private func disableAutoStop() {
        autoStopEnabled = false
        autoStopTimer?.invalidate()
        autoStopTimer     = nil
        autoStopRemaining = autoStopDuration
    }
}

struct AdaDJBoard: View {
    @StateObject private var vm = DJBoardViewModel()

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height

                ScrollView {
                    if isLandscape {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ],
                            spacing: 16
                        ) {
                            ForEach(vm.tracks) { track in trackView(track) }
                        }
                        .padding()
                    } else {
                        VStack(spacing: 16) {
                            ForEach(vm.tracks) { track in trackView(track) }
                        }
                        .padding()
                    }

                    autoStopView
                        .padding(.horizontal)
                    VStack(spacing: 6) {
                        HStack {
                            Label("Deck 1", systemImage: "chevron.left")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("CROSSFADER")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Label("Deck 2", systemImage: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                        .foregroundColor(.secondary)

                        Slider(
                            value: Binding(
                                get: { Double(vm.crossfader) },
                                set: { vm.setCrossfader(Float($0)) }
                            ),
                            in: 0...1
                        )
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.white)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray), lineWidth: 1))
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Button(role: .destructive) {
                        vm.stopAll()
                    } label: {
                        Label("Stop All", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .navigationTitle("#1 Non-Vocals")
            }
        }
    }

    var autoStopView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AUTO-STOP")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                Spacer()
                if vm.autoStopEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(formatTime(vm.autoStopRemaining))
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundColor(.orange)
                    }
                }
            }

            if !vm.autoStopEnabled {
                HStack {
                    Text("Duration: \(Int(vm.autoStopDuration))s")
                        .font(.caption)
                    Slider(value: $vm.autoStopDuration, in: 10...300, step: 5)
                }
            }

            Button {
                vm.toggleAutoStop()
            } label: {
                Label(
                    vm.autoStopEnabled ? "Cancel Timer" : "Start Timer",
                    systemImage: vm.autoStopEnabled ? "xmark.circle" : "timer"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(vm.autoStopEnabled ? .red : .orange)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.white)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray), lineWidth: 1))
    }

    @ViewBuilder
    func trackView(_ track: AudioTrack) -> some View {
        let ct     = vm.currentTime[track.id] ?? 0
        let dur    = vm.players[track.id]?.duration ?? 1
        let hasCue = (vm.hotCue[track.id] ?? -1) >= 0

        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text(track.title).font(.headline)
                Spacer()
                Text("\(formatTime(ct)) / \(formatTime(dur))")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                Spacer()
                Text(vm.isPlaying[track.id] == true ? "Playing" : "Stopped")
                    .font(.subheadline)
                    .foregroundStyle(vm.isPlaying[track.id] == true ? .green : .secondary)
            }

            Slider(
                value: Binding(
                    get: { ct },
                    set: { vm.seek(to: $0, trackId: track.id) }
                ),
                in: 0...max(dur, 1)
            )
            .tint(.blue)

            HStack(spacing: 12) {
                Button { vm.togglePlay(trackId: track.id) } label: {
                    Image(systemName: vm.isPlaying[track.id] == true ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)

                Button { vm.resetTrack(trackId: track.id) } label: {
                    Image(systemName: "backward.end.fill").frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)

                Button { vm.toggleLoop(trackId: track.id) } label: {
                    Image(systemName: vm.isLooping[track.id] == true ? "repeat.circle.fill" : "repeat")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)

                Button { vm.toggleMute(trackId: track.id) } label: {
                    Image(systemName: vm.isMuted[track.id] == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            HStack(spacing: 10) {

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text("TAP BPM")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        let bpm = vm.tapBPM[track.id] ?? 0
                        Text(bpm > 0 ? String(format: "%.0f", bpm) : "—")
                            .font(.callout.monospaced().weight(.bold))
                            .frame(minWidth: 36, alignment: .trailing)
                        Button("TAP") { vm.tap(trackId: track.id) }
                            .buttonStyle(.borderedProminent)
                            .font(.caption.weight(.bold))
                            .tint(.purple)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Volume: \(String(format: "%.2f", vm.volume[track.id] ?? 0.8))").font(.caption)
                Slider(
                    value: Binding(
                        get: { vm.volume[track.id] ?? 0.8 },
                        set: { vm.setVolume($0, trackId: track.id) }
                    ),
                    in: 0...1
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Speed: \(String(format: "%.2fx", vm.speed[track.id] ?? 1.0))").font(.caption)
                Slider(
                    value: Binding(
                        get: { vm.speed[track.id] ?? 1.0 },
                        set: { vm.setSpeed($0, trackId: track.id) }
                    ),
                    in: 0.5...2.0
                )
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.white)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.systemGray), lineWidth: 1))
    }

    func formatTime(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

#Preview {
    AdaDJBoard()
}
