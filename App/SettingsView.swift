import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppViewModel

    @AppStorage(VisionBridgeFeatureKey.hearingTones) private var hearingTones: Bool = true
    @AppStorage(VisionBridgeFeatureKey.hearingTTS) private var hearingTTS: Bool = true
    @AppStorage(VisionBridgeFeatureKey.ttsCriticalOnly) private var ttsCriticalOnly: Bool = false
    @AppStorage(VisionBridgeFeatureKey.distanceUnits) private var distanceUnits: String = "metric"
    @AppStorage(VisionBridgeFeatureKey.ttsVoiceStyle) private var ttsVoiceStyle: String = "calm"
    @AppStorage(VisionBridgeFeatureKey.ttsVerbosity) private var ttsVerbosity: String = "low"
    @AppStorage(VisionBridgeFeatureKey.ttsTelemetryEnabled) private var ttsTelemetryEnabled: Bool = false
    @AppStorage(VisionBridgeFeatureKey.suppressedClassesCSV) private var suppressedClassesCSV: String = ""
    @AppStorage(VisionBridgeFeatureKey.haptics) private var haptics: Bool = true
    @AppStorage(VisionBridgeFeatureKey.payloadHUD) private var payloadHUD: Bool = true
    @AppStorage("bridgehax.visionBridgeBaseURLString") private var bridgeURLString: String = "http://127.0.0.1:8765"
    @AppStorage("shouldShowOnboarding") private var shouldShowOnboarding: Bool = true
    @State private var showOptionalComputer: Bool = false
    @State private var telemetryShareURL: URL?
    @State private var showTelemetryShareSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                VisionBridgeTheme.background.ignoresSafeArea()
                
                List {
                    Section {
                        HStack(spacing: 12) {
                            PresetButton(title: "Calm", icon: "moon.stars.fill", color: .blue) {
                                hearingTTS = true
                                ttsVerbosity = "low"
                                ttsVoiceStyle = "calm"
                                app.hearing.speakImmediate("Calm mode active")
                            }
                            .accessibilityLabel("Preset: Calm")
                            .accessibilityHint("Enables low-verbosity speech with a softer voice style.")
                            
                            PresetButton(title: "Active", icon: "bolt.fill", color: VisionBridgeTheme.accent) {
                                hearingTTS = true
                                ttsVerbosity = "normal"
                                ttsVoiceStyle = "clear"
                                app.hearing.speakImmediate("Full ocular sync active")
                            }
                            .accessibilityLabel("Preset: Active")
                            .accessibilityHint("Enables full-verbosity speech with clear distance estimates.")
                            
                            PresetButton(title: "Alerts Only", icon: "bell.badge.fill", color: VisionBridgeTheme.warmAlert) {
                                hearingTTS = false
                                ttsCriticalOnly = true
                                app.hearing.speakImmediate("High priority alerts only")
                            }
                            .accessibilityLabel("Preset: Alerts Only")
                            .accessibilityHint("Silences non-critical announcements. Only high-priority hazards will be spoken.")
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    } header: {
                        sectionHeader("Quick Presets", icon: "wand.and.stars")
                    }

                    Section {
                        Toggle(isOn: $hearingTones) { Label("Identify Objects", systemImage: "text.bubble.fill") }
                            .accessibilityLabel("Identify Objects")
                            .accessibilityHint("When enabled, the Auditory Twin will name every detected object.")
                        
                        Toggle(isOn: $hearingTTS) { Label("Speak Distance", systemImage: "ruler") }
                            .accessibilityLabel("Speak Distance")
                            .accessibilityHint("When enabled, announcements will include precise distance estimates.")
                        
                        Toggle(isOn: $ttsCriticalOnly) {
                            Label("High-Priority Only", systemImage: "exclamationmark.triangle.fill")
                        }
                        .accessibilityLabel("High-Priority Only")
                        .accessibilityHint("When enabled, only critical hazards will trigger voice alerts.")
                    } header: {
                        sectionHeader("Hearing Engine", icon: "ear")
                    } footer: {
                        Text("Configure how the 'Auditory Twin' communicates spatial telemetry.")
                    }

                    Section {
                        Picker("Voice Personality", selection: $ttsVoiceStyle) {
                            Text("Calm (Softer)").tag("calm")
                            Text("Clear (Standard)").tag("clear")
                            Text("Compact (Fast)").tag("compact")
                        }
                        Picker("Verbosity", selection: $ttsVerbosity) {
                            Text("Essential Only").tag("low")
                            Text("Full Scene").tag("normal")
                        }
                        Picker("Measurement", selection: $distanceUnits) {
                            Text("Metric (Meters)").tag("metric")
                            Text("Imperial (Feet)").tag("imperial")
                        }
                    } header: {
                        sectionHeader("Audio Style", icon: "waveform")
                    }

                    Section {
                        Toggle(isOn: $haptics) { Label("Tactile Feedback", systemImage: "iphone.radiowaves.left.and.right") }
                            .accessibilityLabel("Tactile Feedback")
                            .accessibilityHint("Enables physical vibration patterns for nearby objects.")
                        Toggle(isOn: $payloadHUD) { Label("Developer HUD", systemImage: "chart.bar.fill") }
                            .accessibilityLabel("Developer Head-Up Display")
                            .accessibilityHint("Shows technical vision data and latency on the main dashboard.")
                    } header: {
                        sectionHeader("Haptics & Visuals", icon: "hand.tap.fill")
                    }

                    Section {
                        DisclosureGroup(isExpanded: $showOptionalComputer) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("For developer or lab use only. Enter an address only if your team set one up.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Address", text: $bridgeURLString)
                                    .textContentType(.URL)
                                    .autocorrectionDisabled()
                                    .padding(10)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                    .onSubmit { applyBridgeURL() }
                                Button("Save", action: applyBridgeURL)
                                    .fontWeight(.semibold)
                                Divider()
                                Text("Suppressed classes (comma-separated)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("optional class names to silence, comma-separated", text: $suppressedClassesCSV)
                                    .autocorrectionDisabled()
                                    .padding(10)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                Toggle(isOn: $ttsTelemetryEnabled) {
                                    Label("Enable local TTS telemetry", systemImage: "waveform.path.ecg")
                                }
                                Button("Export TTS telemetry JSON") {
                                    do {
                                        telemetryShareURL = try TTSTelemetryStore.shared.exportJSONFile()
                                        showTelemetryShareSheet = telemetryShareURL != nil
                                    } catch {
                                        telemetryShareURL = nil
                                    }
                                }
                                .disabled(!ttsTelemetryEnabled)
                                .fontWeight(.semibold)
                            }
                            .padding(.top, 6)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Lab on Wi‑Fi (optional)")
                                    Text("Developers only")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            } icon: {
                                Image(systemName: "cable.connector")
                            }
                        }
                    } header: {
                        sectionHeader("Advanced", icon: "hammer")
                    } footer: {
                        Text("VisionBridge runs on this iPhone. No second device is required in normal use.")
                    }

                    Section {
                        if let session = app.session {
                            NavigationLink {
                                DetectionDebugView(session: session)
                            } label: {
                                Label("Raw detections (debug)", systemImage: "list.bullet.rectangle")
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Raw detections (debug)", systemImage: "list.bullet.rectangle")
                                Text("Not available until the on-device YOLO model is bundled in Xcode.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        sectionHeader("Debug", icon: "ladybug")
                    } footer: {
                        Text("Live text of every object in the last vision frame. Requires the on-device YOLO model in the app.")
                            .font(.caption)
                    }

                    Section {
                        Button {
                            if let u = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(u)
                            }
                        } label: {
                            HStack {
                                Label("iOS settings", systemImage: "gearshape")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } header: {
                        sectionHeader("System", icon: "app.badge")
                    }

                    Section {
                        Button {
                            shouldShowOnboarding = true
                            dismiss()
                        } label: {
                            Label("Show onboarding again", systemImage: "sparkles")
                        }
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0.0")
                                .foregroundStyle(.tertiary)
                        }
                    } header: {
                        sectionHeader("About", icon: "info.circle")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: { dismiss() })
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(VisionBridgeTheme.accent)
        .preferredColorScheme(.dark)
        .onChange(of: hearingTones) { on in
            HapticManager.shared.triggerDiscovery()
            app.hearing.speakImmediate(on ? "Object identification enabled" : "Object identification disabled")
            app.hearing.applyFeatureTogglesFromUserDefaults()
        }
        .onChange(of: ttsCriticalOnly) { on in
            HapticManager.shared.triggerDiscovery()
            app.hearing.speakImmediate(on ? "Alerts only mode active" : "Full scene narration active")
            app.hearing.applyFeatureTogglesFromUserDefaults()
        }
        .onChange(of: distanceUnits) { val in
            HapticManager.shared.triggerDiscovery()
            app.hearing.speakImmediate("Units set to \(val)")
            app.hearing.applyFeatureTogglesFromUserDefaults()
        }
        .onChange(of: ttsVoiceStyle) { val in
            HapticManager.shared.triggerDiscovery()
            app.hearing.speakImmediate("Voice style set to \(val)")
            app.hearing.applyFeatureTogglesFromUserDefaults()
        }
        .onChange(of: ttsVerbosity) { val in
            HapticManager.shared.triggerDiscovery()
            app.hearing.speakImmediate("Verbosity set to \(val)")
            app.hearing.applyFeatureTogglesFromUserDefaults()
        }
        .onChange(of: haptics) { on in
            HapticManager.shared.triggerDiscovery()
            app.hearing.speakImmediate(on ? "Tactile feedback on" : "Tactile feedback off")
            app.hearing.applyFeatureTogglesFromUserDefaults()
        }
        .onChange(of: ttsTelemetryEnabled) { on in
            TTSTelemetryStore.shared.setEnabled(on)
            HapticManager.shared.triggerDiscovery()
            app.hearing.applyFeatureTogglesFromUserDefaults()
        }
        .sheet(isPresented: $showTelemetryShareSheet) {
            if let url = telemetryShareURL {
                ActivityViewController(activityItems: [url])
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(VisionBridgeTheme.accent.opacity(0.8))
            .textCase(.uppercase)
            .tracking(1.2)
    }

    private func applyBridgeURL() {
        var s = bridgeURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = "http://127.0.0.1:8765" }
        if URL(string: s) == nil { return }
        if let u = URL(string: s) {
            app.hearing.reconfigure(bridgeBase: u)
        }
    }
}

private struct PresetButton: View {
    var title: String
    var icon: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.bold))
                Text(title)
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.1))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppViewModel())
}
