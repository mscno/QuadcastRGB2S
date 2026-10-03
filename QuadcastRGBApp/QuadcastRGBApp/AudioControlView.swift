import SwiftUI

struct AudioControlView: View {
    @EnvironmentObject var audio: AudioManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !audio.state.connected {
                    ContentUnavailableView("Connect your QuadCast 2 S", systemImage: "mic.slash",
                                           description: Text("Audio controls become available when macOS detects the microphone."))
                }
                volumes
                monitoring
                patterns
                microphoneTest
            }
            .padding(28)
            .frame(maxWidth: 580, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("audio-content")
        .navigationTitle("Audio")
        .navigationSubtitle("QuadCast 2 S")
        .toolbar {
            ToolbarItem(placement: .status) {
                Label(audio.state.connected ? "Connected" : "Disconnected",
                      systemImage: audio.state.connected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(audio.state.connected ? Color.green : Color.secondary)
                    .font(.caption).labelStyle(.titleAndIcon).fixedSize()
                    .accessibilityIdentifier("audio-connection-status")
            }
        }
        .alert("Audio", isPresented: Binding(get: { audio.error != nil }, set: { if !$0 { audio.error = nil } })) {
            Button("OK") { audio.error = nil }
        } message: { Text(audio.error ?? "") }
        .onDisappear { audio.stopCapture(discard: true) }
    }

    private var volumes: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Microphone", systemImage: "mic.fill").font(.headline)
                Spacer()
                Button(audio.state.micMuted == true ? "Unmute in macOS" : "Mute in macOS",
                       systemImage: audio.state.micMuted == true ? "mic.slash.fill" : "mic.fill") {
                    audio.set(.micMute, value: audio.state.micMuted == true ? 0 : 1)
                }
                .buttonStyle(.glass)
                .disabled(audio.state.micMuted == nil)
                .accessibilityIdentifier("audio-mute")
            }
            volume("Mic volume", value: audio.state.micVolume, control: .micVolume, id: "mic-volume")
            HStack(spacing: 18) {
                Label(audio.state.micMuted.map { $0 ? "macOS muted" : "macOS unmuted" } ?? "macOS mute unavailable",
                      systemImage: audio.state.micMuted == true ? "mic.slash" : "mic")
                Label(audio.hardwareMuted.map { $0 ? "Tap-to-mute: muted" : "Tap-to-mute: unmuted" } ?? "Tap-to-mute: awaiting device",
                      systemImage: audio.hardwareMuted == true ? "hand.raised.fill" : "hand.tap")
                    .accessibilityIdentifier("hardware-mute-status")
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("Tap-to-mute is separate from macOS mute. Hardware status appears only after a supported device event; it cannot be inferred from silence.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Label("Headphones", systemImage: "headphones").font(.headline)
            volume("Headphone volume", value: audio.state.headphoneVolume, control: .headphoneVolume, id: "headphone-volume")
            if audio.state.headphoneVolume == nil {
                note("Adjust headphone volume with the microphone’s multifunction knob. This firmware does not expose it to macOS.")
            }
        }
    }
    private var monitoring: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Monitoring / playback", systemImage: "slider.horizontal.3").font(.headline)
            if let value = audio.state.monitorVolume {
                volume("Mic monitoring", value: value, control: .monitorVolume, id: "monitor-volume")
                note("Adjusts direct monitoring in the microphone’s headphone jack. Playback volume is controlled separately above.")
            } else {
                note("Use monitor-mix mode on the microphone’s knob to balance your voice with computer playback in its headphone jack. This firmware does not expose the mix to macOS.")
            }
        }
    }
    private var patterns: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Polar pattern", systemImage: "dot.radiowaves.left.and.right").font(.headline)
            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(PolarPattern.allCases, id: \.self) { pattern in
                        if audio.state.availablePatterns.contains(pattern) {
                            Button { audio.select(pattern) } label: { patternLabel(pattern) }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                                .accessibilityIdentifier("pattern-\(pattern.rawValue)")
                                .accessibilityValue(audio.state.pattern == pattern ? "Selected" : "")
                        } else {
                            patternLabel(pattern)
                                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                                .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            if audio.state.availablePatterns.isEmpty {
                note("Hold the microphone’s knob for 2 seconds to enter pattern selection, then turn it. The LED ring shows the selected pattern. Software selection is unavailable on this firmware.")
            }
        }
    }
    private func patternLabel(_ pattern: PolarPattern) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(pattern.label, systemImage: pattern.icon).font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
                if audio.state.pattern == pattern { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            Text(pattern.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 95, alignment: .topLeading)
    }
    private var microphoneTest: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Microphone test", systemImage: "waveform").font(.headline)
            HStack {
                ProgressView(value: audio.level.fraction).tint(audio.level.clipped ? .red : .green)
                    .accessibilityLabel("Microphone level")
                    .accessibilityValue("\(Int(audio.level.rmsDB)) decibels")
                    .accessibilityIdentifier("audio-level")
                Text(audio.metering ? "\(Int(audio.level.rmsDB)) dBFS" : "— dBFS")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 75)
            }
            HStack {
                Text(audio.level.clipped ? "Clipping — lower mic volume" : "Peak \(audio.metering ? String(Int(audio.level.peakDB)) : "—") dBFS")
                Spacer()
                if audio.recording { Text("Recording · \(audio.clipDuration, specifier: "%.1f") / 5 s").monospacedDigit() }
            }.font(.caption).foregroundStyle(audio.level.clipped ? Color.red : Color.secondary)
            GlassEffectContainer {
                HStack {
                    Button(audio.metering ? "Stop meter" : "Start meter", systemImage: "waveform", action: audio.toggleMeter)
                        .buttonStyle(.glass).disabled(!audio.state.connected || audio.recording)
                        .accessibilityIdentifier("start-meter")
                    Button(audio.recording ? "Stop test" : "Record 5 s", systemImage: audio.recording ? "stop.fill" : "record.circle", action: audio.toggleRecording)
                        .buttonStyle(.glassProminent).disabled(!audio.state.connected)
                        .accessibilityIdentifier("record-test")
                    Button(audio.playing ? "Stop playback" : "Play", systemImage: audio.playing ? "stop.fill" : "play.fill", action: audio.playTest)
                        .buttonStyle(.glass).disabled(audio.clipDuration == 0 || audio.recording)
                        .accessibilityIdentifier("play-test")
                    if audio.clipDuration > 0 {
                        Button("Discard", systemImage: "trash", action: audio.discardTest)
                            .labelStyle(.iconOnly).buttonStyle(.glass).accessibilityIdentifier("discard-test")
                    }
                }
            }
            note("Capture starts only when you start a meter or test. The five-second recording stays in memory and is discarded when you leave Audio. Playback uses your Mac’s selected output.")
            if audio.permissionDenied {
                Button("Allow Microphone Access in System Settings", action: audio.openMicrophoneSettings).buttonStyle(.glass)
                note("Enable QuadCast RGB under Privacy & Security → Microphone, then start the meter again.")
            }
        }
    }
    private func note(_ text: String) -> some View { Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    private func volume(_ label: String, value: Float?, control: AudioControl, id: String) -> some View {
        AudioVolumeSlider(label: label, value: value, id: id) { audio.set(control, value: $0) }
    }
}

private struct AudioVolumeSlider: View {
    let label: String
    let value: Float?
    let id: String
    let change: (Double) -> Void
    @State private var draft: Double = 0
    @State private var editing = false
    @State private var writeTask: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(value == nil ? "On microphone" : "\(Int((draft * 100).rounded()))%")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $draft, in: 0...1, onEditingChanged: { active in
                editing = active
                if !active { writeTask?.cancel(); change(draft) }
            })
            .disabled(value == nil).accessibilityLabel(label).accessibilityIdentifier(id)
        }
        .onAppear { draft = Double(value ?? 0) }
        .onChange(of: value) { _, next in if !editing { draft = Double(next ?? 0) } }
        .onChange(of: draft) { _, next in
            guard editing else { return }
            writeTask?.cancel()
            writeTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                change(next)
            }
        }
        .onDisappear { writeTask?.cancel() }
    }
}
