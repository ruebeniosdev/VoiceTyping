import SwiftUI
import Speech
import AVFoundation
import UserNotifications

// NOTE: This file relies on Color, Font extensions and the Haptics enum
// defined in ContentView.swift (ink, fog, paper, accent, .mono(), .serif()).

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    @State private var page = 0
    @State private var primaryUseCase = ""
    @State private var micGranted    = false
    @State private var speechGranted = false
    @State private var notifGranted  = false
    @State private var showSettingsAlert   = false
    @State private var settingsAlertMessage = ""

    // Pages: 0 = welcome, 1 = use case, 2 = permissions, 3+ = features
    private let features: [FeaturePage] = [
        FeaturePage(icon: "waveform",             title: "Live Transcription",
                    detail: "Speak naturally. Words appear as you talk."),
        FeaturePage(icon: "clock",                title: "Auto-Saved Notes",
                    detail: "Every recording is stored and searchable."),
        FeaturePage(icon: "doc.richtext",         title: "Export as PDF",
                    detail: "Share clean, formatted transcripts anywhere."),
        FeaturePage(icon: "bell",                 title: "Smart Reminders",
                    detail: "Daily nudges to keep capturing your thoughts."),
    ]

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            switch page {
            case 0: welcomeScreen
            case 1: useCaseScreen
            case 2: permissionsScreen
            default: featuresScreen
            }
        }
        .animation(.easeInOut(duration: 0.25), value: page)
        .alert("Permission Required", isPresented: $showSettingsAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(settingsAlertMessage)
        }
    }

    // MARK: - Welcome

    private var welcomeScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // Accent mark
                Rectangle()
                    .fill(Color.accent)
                    .frame(width: 32, height: 2)

                Image(systemName: "mic")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundColor(.ink)

                VStack(spacing: 8) {
                    Text("Voice Notes")
                        .font(.serif(32, weight: .regular))
                        .foregroundColor(.ink)
                        .kerning(1)

                    Text("Your thoughts, captured")
                        .font(.mono(13))
                        .foregroundColor(.fog)
                        .tracking(1)
                }
            }

            Spacer()

            OnboardingButton(label: "Get started", style: .primary) {
                Haptics.impact(.medium)
                withAnimation { page = 1 }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }

    // MARK: - Use Case

    private var useCaseScreen: some View {
        VStack(spacing: 0) {
            stepHeader(back: { withAnimation { page = 0 } }, step: "1 / 3")

            Spacer()

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("How will you use it?")
                        .font(.serif(24, weight: .regular))
                        .foregroundColor(.ink)

                    Text("Select one to continue")
                        .font(.mono(12))
                        .foregroundColor(.fog)
                        .tracking(1)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(useCases, id: \.self) { uc in
                        UseCaseChip(label: uc, isSelected: primaryUseCase == uc) {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.25)) { primaryUseCase = uc }
                        }
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            OnboardingButton(
                label: "Continue",
                style: primaryUseCase.isEmpty ? .disabled : .primary
            ) {
                guard !primaryUseCase.isEmpty else { return }
                Haptics.impact(.medium)
                withAnimation { page = 2 }
            }
            .disabled(primaryUseCase.isEmpty)
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }

    private let useCases = ["Work", "Journal", "Meetings", "Writing", "Study", "Memos"]

    // MARK: - Permissions

    private var permissionsScreen: some View {
        VStack(spacing: 0) {
            stepHeader(back: { withAnimation { page = 1 } }, step: "2 / 3")

            Spacer()

            VStack(spacing: 36) {
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundColor(.ink)

                    Text("Permissions")
                        .font(.serif(24, weight: .regular))
                        .foregroundColor(.ink)

                    Text("Required to record and transcribe")
                        .font(.mono(12))
                        .foregroundColor(.fog)
                        .tracking(0.5)
                }

                VStack(spacing: 0) {
                    PermissionRow(
                        icon: "mic",
                        title: "Microphone",
                        detail: "To record your voice",
                        isGranted: micGranted
                    ) { requestMic() }

                    Divider()
                        .overlay(Color.inkLight.opacity(0.3))
                        .padding(.horizontal, 32)

                    PermissionRow(
                        icon: "waveform",
                        title: "Speech Recognition",
                        detail: "To transcribe in real time",
                        isGranted: speechGranted
                    ) { requestSpeech() }

                    Divider()
                        .overlay(Color.inkLight.opacity(0.3))
                        .padding(.horizontal, 32)

                    PermissionRow(
                        icon: "bell",
                        title: "Notifications",
                        detail: "For save confirmations & reminders",
                        isGranted: notifGranted
                    ) { requestNotifications() }
                }
            }

            Spacer()

            // Can proceed once mic + speech are granted; notifications are optional
            let canProceed = micGranted && speechGranted

            OnboardingButton(
                label: "Continue",
                style: canProceed ? .primary : .disabled
            ) {
                guard canProceed else { return }
                Haptics.impact(.medium)
                withAnimation { page = 3 }
            }
            .disabled(!canProceed)
            .padding(.horizontal, 32)

            if !canProceed {
                Text("Microphone and speech recognition are required")
                    .font(.mono(10))
                    .foregroundColor(.fog)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 40)
            }

            Spacer().frame(height: 52)
        }
        .onAppear { checkPermissions() }
    }

    // MARK: - Features

    private var featuresScreen: some View {
        let featureIndex = page - 3

        return VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    Haptics.impact(.light)
                    completeOnboarding()
                } label: {
                    Text("Skip")
                        .font(.mono(12))
                        .foregroundColor(.fog)
                        .tracking(1)
                }
                .padding(28)
            }

            Spacer()

            TabView(selection: Binding(
                get: { featureIndex },
                set: { newIndex in withAnimation { page = newIndex + 3 } }
            )) {
                ForEach(0..<features.count, id: \.self) { i in
                    FeatureSlide(feature: features[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)

            // Dot indicators
            HStack(spacing: 7) {
                ForEach(0..<features.count, id: \.self) { i in
                    Capsule()
                        .fill(i == featureIndex ? Color.accent : Color.fog.opacity(0.3))
                        .frame(width: i == featureIndex ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.3), value: featureIndex)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 36)

            OnboardingButton(
                label: featureIndex == features.count - 1 ? "Start recording" : "Next",
                style: .primary
            ) {
                Haptics.impact(.medium)
                if featureIndex < features.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    completeOnboarding()
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }

    // MARK: - Shared Components

    private func stepHeader(back: @escaping () -> Void, step: String) -> some View {
        HStack {
            Button(action: back) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .light))
                    Text("Back")
                        .font(.serif(15))
                }
                .foregroundColor(.inkMid)
            }
            Spacer()
            Text(step)
                .font(.mono(11))
                .foregroundColor(.fog)
                .tracking(1)
        }
        .padding(.horizontal, 28)
        .padding(.top, 58)
        .padding(.bottom, 8)
    }

    // MARK: - Permission Logic

    private func checkPermissions() {
        micGranted    = AVAudioSession.sharedInstance().recordPermission == .granted
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { notifGranted = s.authorizationStatus == .authorized }
        }
    }

    private func requestMic() {
        Haptics.impact(.light)
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                micGranted = granted
                if !granted {
                    settingsAlertMessage = "Microphone access is required to record your voice. Enable it in Settings."
                    showSettingsAlert = true
                } else {
                    Haptics.notification(.success)
                }
            }
        }
    }

    private func requestSpeech() {
        Haptics.impact(.light)
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                speechGranted = status == .authorized
                if status != .authorized {
                    settingsAlertMessage = "Speech recognition is required for transcription. Enable it in Settings."
                    showSettingsAlert = true
                } else {
                    Haptics.notification(.success)
                }
            }
        }
    }

    private func requestNotifications() {
        Haptics.impact(.light)
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    notifGranted = granted
                    if granted { Haptics.notification(.success) }
                }
            }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(primaryUseCase, forKey: "primaryUseCase")
        UserDefaults.standard.set(true,           forKey: "hasCompletedOnboarding")
        Haptics.notification(.success)
        withAnimation(.easeInOut(duration: 0.3)) { hasCompletedOnboarding = true }
    }
}

// MARK: - Use Case Chip

struct UseCaseChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.mono(13, weight: isSelected ? .medium : .regular))
                .tracking(0.5)
                .foregroundColor(isSelected ? .paper : .ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isSelected ? Color.ink : Color.clear)
                .overlay(
                    Rectangle()
                        .stroke(isSelected ? Color.ink : Color.inkLight.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let isGranted: Bool
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isGranted ? icon + ".fill" : icon)
                .font(.system(size: 18, weight: .light))
                .foregroundColor(isGranted ? .accent : .inkMid)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.serif(15))
                    .foregroundColor(.ink)
                Text(detail)
                    .font(.mono(11))
                    .foregroundColor(.fog)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accent)
            } else {
                Button(action: onRequest) {
                    Text("Allow")
                        .font(.mono(11, weight: .medium))
                        .tracking(1)
                        .foregroundColor(.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .overlay(Rectangle().stroke(Color.inkMid, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }
}

// MARK: - Feature Slide

struct FeaturePage {
    let icon: String
    let title: String
    let detail: String
}

struct FeatureSlide: View {
    let feature: FeaturePage

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(Color.inkLight.opacity(0.07))
                    .frame(width: 88, height: 88)
                Image(systemName: feature.icon)
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundColor(.ink)
            }

            VStack(spacing: 10) {
                Text(feature.title)
                    .font(.serif(22, weight: .regular))
                    .foregroundColor(.ink)
                    .kerning(0.5)

                Text(feature.detail)
                    .font(.mono(13))
                    .foregroundColor(.fog)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 48)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Onboarding Button

enum OnboardingButtonStyle { case primary, disabled }

struct OnboardingButton: View {
    let label: String
    let style: OnboardingButtonStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.mono(13, weight: .medium))
                .tracking(1.5)
                .foregroundColor(style == .primary ? .paper : .fog)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(style == .primary ? Color.ink : Color.inkLight.opacity(0.15))
        }
        .buttonStyle(.plain)
    }
}
