import SwiftUI
import Speech
import AVFoundation

// MARK: - Onboarding View - Minimalist Black & White

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var microphonePermissionGranted = false
    @State private var speechPermissionGranted = false
    @State private var primaryUseCase = ""
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    
    let useCases = ["Work", "Journal", "Meetings", "Writing", "Study", "Memos"]
    
    let features: [FeaturePage] = [
        FeaturePage(
            icon: "mic",
            title: "Real-Time Transcription",
            description: "Speak naturally and watch your words appear instantly."
        ),
        FeaturePage(
            icon: "pencil",
            title: "Smart Editor",
            description: "Edit, format, and organize your transcripts with ease."
        ),
        FeaturePage(
            icon: "clock",
            title: "History & Search",
            description: "All transcripts auto-saved. Find anything instantly."
        ),
        FeaturePage(
            icon: "square.and.arrow.up",
            title: "Export Anywhere",
            description: "Share as text, PDF, or audio. Your notes, your way."
        )
    ]
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            switch currentPage {
            case 0:
                welcomeScreen
            case 1:
                questionsScreen
            case 2:
                permissionsScreen
            default:
                featuresCarousel
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentPage)
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(permissionAlertMessage)
        }
    }
    
    // MARK: - Welcome Screen
    
    private var welcomeScreen: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Image(systemName: "mic")
                .font(.system(size: 60))
                .foregroundColor(.black)
            
            VStack(spacing: 12) {
                Text("Voice Notes")
                    .font(.system(size: 32, weight: .light))
                    .kerning(2)
                
                Text("Your thoughts, captured")
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation { currentPage = 1 }
            }) {
                Text("Start")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.black)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Questions Screen
    
    private var questionsScreen: some View {
        VStack(spacing: 30) {
            HStack {
                Button(action: { withAnimation { currentPage = 0 } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16))
                        .foregroundColor(.black)
                }
                Spacer()
                Text("1/3")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.gray)
            }
            .padding()
            
            Spacer()
            
            VStack(spacing: 24) {
                Text("How will you use it?")
                    .font(.system(size: 24, weight: .light))
                    .kerning(1)
                
                Text("Select your primary use")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(useCases, id: \.self) { useCase in
                        Button(action: {
                            withAnimation { primaryUseCase = useCase }
                        }) {
                            Text(useCase)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(primaryUseCase == useCase ? .white : .black)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(primaryUseCase == useCase ? Color.black : Color.clear)
                                .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 30)
            }
            
            Spacer()
            
            Button(action: { withAnimation { currentPage = 2 } }) {
                Text("Continue")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(validateInputs() ? .white : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(validateInputs() ? Color.black : Color.gray.opacity(0.3))
            }
            .disabled(!validateInputs())
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Permissions Screen
    
    private var permissionsScreen: some View {
        VStack(spacing: 30) {
            HStack {
                Button(action: { withAnimation { currentPage = 1 } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16))
                        .foregroundColor(.black)
                }
                Spacer()
                Text("2/3")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.gray)
            }
            .padding()
            
            Spacer()
            
            VStack(spacing: 40) {
                Image(systemName: "lock")
                    .font(.system(size: 40))
                    .foregroundColor(.black)
                
                Text("Permissions")
                    .font(.system(size: 24, weight: .light))
                    .kerning(1)
                
                VStack(spacing: 20) {
                    PermissionRow(
                        icon: "mic",
                        title: "Microphone",
                        isGranted: microphonePermissionGranted,
                        onRequest: requestMicrophonePermission
                    )
                    Divider().padding(.horizontal)
                    PermissionRow(
                        icon: "waveform",
                        title: "Speech Recognition",
                        isGranted: speechPermissionGranted,
                        onRequest: requestSpeechPermission
                    )
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: { withAnimation { currentPage = 3 } }) {
                Text("Continue")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor((microphonePermissionGranted && speechPermissionGranted) ? .white : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background((microphonePermissionGranted && speechPermissionGranted) ? Color.black : Color.gray.opacity(0.3))
            }
            .disabled(!(microphonePermissionGranted && speechPermissionGranted))
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .onAppear { checkPermissions() }
    }
    
    // MARK: - Features Carousel
    
    private var featuresCarousel: some View {
        // featureIndex is currentPage offset by 3 (pages 0–2 are welcome/questions/permissions)
        let featureIndex = currentPage - 3

        return VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: completeOnboarding) {
                    Text("Skip")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.gray)
                }
                .padding()
            }
            
            Spacer()
            
            TabView(selection: Binding(
                get: { featureIndex },
                set: { currentPage = $0 + 3 }
            )) {
                ForEach(0..<features.count, id: \.self) { index in
                    FeatureMinimalView(feature: features[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 350)
            
            HStack(spacing: 6) {
                ForEach(0..<features.count, id: \.self) { index in
                    Circle()
                        .fill(featureIndex == index ? Color.black : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 30)
            
            Button(action: {
                if featureIndex < features.count - 1 {
                    withAnimation { currentPage += 1 }
                } else {
                    completeOnboarding()
                }
            }) {
                Text(featureIndex == features.count - 1 ? "Get Started" : "Next")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.black)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Helpers
    
    private var currentPageIndex: Int { currentPage - 3 }  // read-only, no setter needed

    private func validateInputs() -> Bool { !primaryUseCase.isEmpty }
    
    private func checkPermissions() {
        microphonePermissionGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        speechPermissionGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                microphonePermissionGranted = granted
                if !granted {
                    permissionAlertMessage = "Microphone access is required to record your voice."
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    private func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                speechPermissionGranted = status == .authorized
                if status != .authorized {
                    permissionAlertMessage = "Speech recognition is required for transcription."
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(primaryUseCase, forKey: "primaryUseCase")
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        withAnimation { hasCompletedOnboarding = true }
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let icon: String
    let title: String
    let isGranted: Bool
    let onRequest: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.black)
            
            Text(title)
                .font(.system(size: 15, weight: .light))
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            } else {
                Button(action: onRequest) {
                    Text("Allow")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Feature Model

struct FeaturePage {
    let icon: String
    let title: String
    let description: String
}

// MARK: - Feature View

struct FeatureMinimalView: View {
    let feature: FeaturePage
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: feature.icon)
                .font(.system(size: 48))
                .foregroundColor(.black)
            
            VStack(spacing: 12) {
                Text(feature.title)
                    .font(.system(size: 20, weight: .light))
                    .kerning(1)
                
                Text(feature.description)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineSpacing(4)
            }
        }
    }
}
