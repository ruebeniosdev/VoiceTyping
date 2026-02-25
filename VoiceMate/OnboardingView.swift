//
//  OnboardingView.swift
//  VoiceMate
//
//  Created by Fenuku kekeli on 11/5/25.
//

import SwiftUI
import Speech
import AVFoundation

// MARK: - Onboarding View with Animations, Permissions & Questions

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var microphonePermissionGranted = false
    @State private var speechPermissionGranted = false
    @State private var primaryUseCase = ""
    @State private var animateWelcome = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var onboardingProgress: Double = 0.0
    @State private var currentFeatureIndex = 0
    
    let useCases = ["Work Notes", "Journaling", "Meeting Minutes", "Creative Writing", "Study Notes", "Voice Memos"]
    
    // Feature pages data
    let features: [FeaturePage] = [
        FeaturePage(
            icon: "mic.circle.fill",
            title: "Real-Time Transcription",
            description: "Speak naturally and watch your words appear instantly with high accuracy powered by Apple's Speech Recognition.",
            color: .blue
        ),
        FeaturePage(
            icon: "square.and.pencil",
            title: "Advanced Text Editor",
            description: "Format with bold, italic, underline. Adjust font sizes, add bullet points, and transform text case effortlessly.",
            color: .purple
        ),
        FeaturePage(
            icon: "clock.arrow.circlepath",
            title: "Smart History",
            description: "All transcriptions auto-saved. Search by keyword, mark favorites, and organize with tags for quick access.",
            color: .green
        ),
        FeaturePage(
            icon: "square.and.arrow.up",
            title: "Export & Share",
            description: "Export as beautiful PDFs, copy to clipboard, or share directly to any app. Your notes, everywhere.",
            color: .orange
        )
    ]
    
    var body: some View {
        ZStack {
            if currentPage == 0 {
                welcomeScreen
            } else if currentPage == 1 {
                questionsScreen
            } else if currentPage == 2 {
                permissionsScreen
            } else {
                featuresCarousel
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: currentPage)
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings", role: .none) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(permissionAlertMessage)
        }
        .onChange(of: currentPage) { _ in
            updateProgress()
        }
    }
    
    // MARK: - Welcome Screen
    
    private var welcomeScreen: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: animateWelcome ? .topLeading : .bottomTrailing,
                endPoint: animateWelcome ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animateWelcome)
            
            VStack(spacing: 40) {
                Spacer()
                
                // Animated icon
                ZStack {
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                            .frame(width: 120 + CGFloat(index * 40), height: 120 + CGFloat(index * 40))
                            .scaleEffect(animateWelcome ? 1.2 : 0.8)
                            .opacity(animateWelcome ? 0 : 0.5)
                            .animation(
                                .easeOut(duration: 2)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.3),
                                value: animateWelcome
                            )
                    }
                    
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .scaleEffect(animateWelcome ? 1.0 : 0.9)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateWelcome)
                }
                .frame(height: 200)
                
                VStack(spacing: 16) {
                    Text("Voice Typing")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                        )
                    
                    Text("Your thoughts, perfectly captured")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .offset(y: animateWelcome ? 0 : 20)
                .opacity(animateWelcome ? 1 : 0)
                
                Spacer()
                
                Button(action: {
                    provideHapticFeedback(.medium)
                    withAnimation(.spring()) {
                        currentPage = 1
                    }
                }) {
                    HStack(spacing: 12) {
                        Text("Get Started")
                            .font(.system(size: 20, weight: .semibold))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 24))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(20)
                    .shadow(color: .blue.opacity(0.4), radius: 20, y: 10)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 50)
                .scaleEffect(animateWelcome ? 1 : 0.9)
                .opacity(animateWelcome ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
                animateWelcome = true
            }
        }
    }
    
    // MARK: - Questions Screen
    
    private var questionsScreen: some View {
        ZStack {
            LinearGradient(
                colors: [Color.purple.opacity(0.1), Color.pink.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Header
                HStack {
                    Button(action: {
                        provideHapticFeedback(.light)
                        withAnimation(.spring()) {
                            currentPage = 0
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Text("1 of 3")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding()
                
                Spacer()
                
                VStack(spacing: 20) {
                    Text("How will you use Voice Notes?")
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text("Choose your primary use case to help us personalize your experience")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    
                    // Use case selection
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(useCases, id: \.self) { useCase in
                            Button(action: {
                                provideHapticFeedback(.light)
                                withAnimation(.spring(response: 0.3)) {
                                    primaryUseCase = useCase
                                }
                            }) {
                                Text(useCase)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(primaryUseCase == useCase ? .white : .primary)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        primaryUseCase == useCase ?
                                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing) :
                                        LinearGradient(colors: [Color(.systemGray6), Color(.systemGray6)], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(primaryUseCase == useCase ? Color.clear : Color(.systemGray4), lineWidth: 1)
                                    )
                            }
                            .scaleEffect(primaryUseCase == useCase ? 1.05 : 1.0)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 10)
                }
                
                Spacer()
                
                Button(action: {
                    provideHapticFeedback(.medium)
                    withAnimation(.spring()) {
                        currentPage = 2
                    }
                }) {
                    HStack(spacing: 12) {
                        Text("Continue")
                            .font(.system(size: 18, weight: .semibold))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(16)
                    .shadow(color: .purple.opacity(0.4), radius: 12, y: 6)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
                .opacity(validateInputs() ? 1 : 0.5)
                .disabled(!validateInputs())
            }
        }
    }
    
    // MARK: - Permissions Screen
    
    private var permissionsScreen: some View {
        ZStack {
            LinearGradient(
                colors: [Color.orange.opacity(0.1), Color.red.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Header
                HStack {
                    Button(action: {
                        provideHapticFeedback(.light)
                        withAnimation(.spring()) {
                            currentPage = 1
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Text("2 of 3")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding()
                
                Spacer()
                
                // Icon
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                    .padding(.bottom, 20)
                
                VStack(spacing: 16) {
                    Text("Permissions Required")
                        .font(.system(size: 32, weight: .bold))
                        .multilineTextAlignment(.center)
                    
                    Text("Voice Notes needs access to:")
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
                
                VStack(spacing: 20) {
                    // Microphone permission
                    PermissionCard(
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "Record your voice for transcription",
                        color: .blue,
                        isGranted: microphonePermissionGranted,
                        onRequest: {
                            provideHapticFeedback(.medium)
                            requestMicrophonePermission()
                        }
                    )
                    
                    // Speech recognition permission
                    PermissionCard(
                        icon: "waveform",
                        title: "Speech Recognition",
                        description: "Convert your speech to text accurately",
                        color: .purple,
                        isGranted: speechPermissionGranted,
                        onRequest: {
                            provideHapticFeedback(.medium)
                            requestSpeechPermission()
                        }
                    )
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)
                
                Spacer()
                
                Button(action: {
                    provideHapticFeedback(.medium)
                    if microphonePermissionGranted && speechPermissionGranted {
                        withAnimation(.spring()) {
                            currentPage = 3
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        Text("Continue")
                            .font(.system(size: 18, weight: .semibold))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        microphonePermissionGranted && speechPermissionGranted ?
                        LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing) :
                        LinearGradient(colors: [Color.gray, Color.gray], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(16)
                    .shadow(color: (microphonePermissionGranted && speechPermissionGranted) ? .orange.opacity(0.4) : .clear, radius: 12, y: 6)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
                .disabled(!(microphonePermissionGranted && speechPermissionGranted))
            }
        }
        .onAppear {
            checkPermissions()
        }
    }
    
    // MARK: - Features Carousel
    
    private var featuresCarousel: some View {
        ZStack {
            LinearGradient(
                colors: [features[currentFeatureIndex].color.opacity(0.1), features[currentFeatureIndex].color.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentFeatureIndex)
            
            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button(action: {
                        provideHapticFeedback(.medium)
                        completeOnboarding()
                    }) {
                        Text(currentFeatureIndex == features.count - 1 ? "Get Started" : "Skip")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(features[currentFeatureIndex].color)
                    }
                    .padding()
                }
                
                Spacer()
                
                // Page content
                TabView(selection: $currentFeatureIndex) {
                    ForEach(0..<features.count, id: \.self) { index in
                        FeaturePageView(feature: features[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 500)
                
                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<features.count, id: \.self) { index in
                        Circle()
                            .fill(currentFeatureIndex == index ? features[index].color : Color.gray.opacity(0.3))
                            .frame(width: currentFeatureIndex == index ? 10 : 8, height: currentFeatureIndex == index ? 10 : 8)
                            .scaleEffect(currentFeatureIndex == index ? 1.2 : 1.0)
                            .animation(.spring(response: 0.3), value: currentFeatureIndex)
                    }
                }
                .padding(.vertical, 30)
                
                // Action button
                Button(action: {
                    provideHapticFeedback(.medium)
                    if currentFeatureIndex < features.count - 1 {
                        withAnimation(.spring()) {
                            currentFeatureIndex += 1
                        }
                    } else {
                        completeOnboarding()
                    }
                }) {
                    HStack(spacing: 12) {
                        Text(currentFeatureIndex == features.count - 1 ? "Start Using Voice Notes" : "Next")
                            .font(.system(size: 18, weight: .semibold))
                        
                        Image(systemName: currentFeatureIndex == features.count - 1 ? "checkmark.circle.fill" : "arrow.right")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: [features[currentFeatureIndex].color, features[currentFeatureIndex].color.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: features[currentFeatureIndex].color.opacity(0.4), radius: 12, y: 6)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func validateInputs() -> Bool {
        guard !primaryUseCase.isEmpty else {
            return false
        }
        return true
    }
    
    private func checkPermissions() {
        // Check microphone with more detailed status
        let audioSession = AVAudioSession.sharedInstance()
        switch audioSession.recordPermission {
        case .granted:
            microphonePermissionGranted = true
        case .denied, .undetermined:
            microphonePermissionGranted = false
        @unknown default:
            microphonePermissionGranted = false
        }
        
        // Check speech recognition
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechPermissionGranted = true
        case .denied, .restricted, .notDetermined:
            speechPermissionGranted = false
        @unknown default:
            speechPermissionGranted = false
        }
    }
    
    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.microphonePermissionGranted = granted
                if !granted {
                    self.permissionAlertMessage = "Microphone access is required to record your voice. Please enable it in Settings to use all features of Voice Notes."
                    self.showingPermissionAlert = true
                }
            }
        }
    }
    
    private func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.speechPermissionGranted = (status == .authorized)
                if status != .authorized {
                    self.permissionAlertMessage = "Speech Recognition access is required to transcribe your voice. Please enable it in Settings to use all features of Voice Notes."
                    self.showingPermissionAlert = true
                }
            }
        }
    }
    
    private func provideHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    private func updateProgress() {
        let totalPages = 4 // welcome + questions + permissions + features
        onboardingProgress = Double(currentPage) / Double(totalPages - 1)
    }
    
    private func completeOnboarding() {
        // Save user preferences
        UserDefaults.standard.set(primaryUseCase, forKey: "primaryUseCase")
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        
        withAnimation(.spring()) {
            hasCompletedOnboarding = true
        }
    }
}

// MARK: - Supporting Views

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let isGranted: Bool
    let onRequest: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Button(action: onRequest) {
                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(color)
                }
            }
            .disabled(isGranted)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }
}

struct FeaturePage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct FeaturePageView: View {
    let feature: FeaturePage
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 30) {
            // Icon
            ZStack {
                Circle()
                    .fill(feature.color.opacity(0.15))
                    .frame(width: 160, height: 160)
                    .scaleEffect(isAnimating ? 1.0 : 0.8)
                    .opacity(isAnimating ? 1.0 : 0.0)
                
                Circle()
                    .fill(feature.color.opacity(0.25))
                    .frame(width: 130, height: 130)
                    .scaleEffect(isAnimating ? 1.0 : 0.8)
                    .opacity(isAnimating ? 1.0 : 0.0)
                
                Image(systemName: feature.icon)
                    .font(.system(size: 60))
                    .foregroundColor(feature.color)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .opacity(isAnimating ? 1.0 : 0.0)
            }
            .padding(.top, 40)
            
            VStack(spacing: 16) {
                Text(feature.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .offset(y: isAnimating ? 0 : 20)
                    .opacity(isAnimating ? 1.0 : 0.0)
                
                Text(feature.description)
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 40)
                    .offset(y: isAnimating ? 0 : 20)
                    .opacity(isAnimating ? 1.0 : 0.0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                isAnimating = true
            }
        }
        .onDisappear {
            isAnimating = false
        }
    }
}
