import SwiftUI
import Speech
import AVFoundation
import UIKit
import PDFKit
import UserNotifications
import Combine
// MARK: - Design System

extension Color {
    static let ink      = Color(white: 0.06)
    static let inkLight = Color(white: 0.14)
    static let inkMid   = Color(white: 0.24)
    static let fog      = Color(white: 0.58)
    static let paper    = Color(white: 0.96)
    static let accent   = Color(red: 1.0, green: 0.36, blue: 0.22)
}

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Haptics

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard AppSettings.shared.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard AppSettings.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    static func selection() {
        guard AppSettings.shared.hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - App Settings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var hapticsEnabled: Bool {
        didSet { ud.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }
    @Published var notificationsEnabled: Bool {
        didSet { ud.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    @Published var autoSave: Bool {
        didSet { ud.set(autoSave, forKey: "autoSave") }
    }
    @Published var showTimestamps: Bool {
        didSet { ud.set(showTimestamps, forKey: "showTimestamps") }
    }
    @Published var recordingLanguage: String {
        didSet { ud.set(recordingLanguage, forKey: "recordingLanguage") }
    }
    @Published var colorSchemePreference: ColorSchemePreference {
        didSet { ud.set(colorSchemePreference.rawValue, forKey: "colorScheme") }
    }
    @Published var dailyReminderEnabled: Bool {
        didSet { ud.set(dailyReminderEnabled, forKey: "dailyReminderEnabled") }
    }
    @Published var reminderHour: Int {
        didSet { ud.set(reminderHour, forKey: "reminderHour") }
    }

    enum ColorSchemePreference: String, CaseIterable {
        case system = "System", light = "Light", dark = "Dark"
        var scheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light:  return .light
            case .dark:   return .dark
            }
        }
    }

    static let languages: [(label: String, locale: String)] = [
        ("English (US)", "en-US"), ("English (UK)", "en-GB"),
        ("Spanish",      "es-ES"), ("French",       "fr-FR"),
        ("German",       "de-DE"), ("Portuguese",   "pt-BR"),
        ("Italian",      "it-IT"), ("Japanese",     "ja-JP"),
        ("Chinese",      "zh-CN"),
    ]

    private let ud = UserDefaults.standard

    private init() {
        hapticsEnabled       = ud.object(forKey: "hapticsEnabled")       as? Bool   ?? true
        notificationsEnabled = ud.object(forKey: "notificationsEnabled") as? Bool   ?? true
        autoSave             = ud.object(forKey: "autoSave")             as? Bool   ?? false
        showTimestamps       = ud.object(forKey: "showTimestamps")       as? Bool   ?? true
        dailyReminderEnabled = ud.object(forKey: "dailyReminderEnabled") as? Bool   ?? false
        reminderHour         = ud.object(forKey: "reminderHour")         as? Int    ?? 9
        recordingLanguage    = ud.string(forKey: "recordingLanguage")               ?? "en-US"
        colorSchemePreference = ColorSchemePreference(
            rawValue: ud.string(forKey: "colorScheme") ?? "") ?? .system
    }
}

// MARK: - Notification Manager

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
    }

    func sendSaved(title: String, duration: TimeInterval, wordCount: Int) {
        guard AppSettings.shared.notificationsEnabled else { return }
        let c      = UNMutableNotificationContent()
        c.title    = "Note saved"
        c.body     = "\(title) · \(fmt(duration)) · \(wordCount) words"
        c.sound    = .default
        let req    = UNNotificationRequest(
            identifier: UUID().uuidString, content: c,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    func scheduleReminder(at hour: Int) {
        cancelReminder()
        guard AppSettings.shared.notificationsEnabled else { return }
        let c      = UNMutableNotificationContent()
        c.title    = "Daily reminder"
        c.body     = "Capture your thoughts for today."
        c.sound    = .default
        var comps  = DateComponents(); comps.hour = hour; comps.minute = 0
        let req    = UNNotificationRequest(
            identifier: "dailyReminder", content: c,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
        UNUserNotificationCenter.current().add(req)
    }

    func cancelReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["dailyReminder"])
    }

    func checkStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { completion(s.authorizationStatus) }
        }
    }

    private func fmt(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Data Models

struct Meeting: Identifiable, Equatable, Codable {
    let id: UUID
    var transcript: String
    let date: Date
    var title: String
    var duration: TimeInterval
    var segments: [TranscriptSegment]

    init(id: UUID = UUID(), transcript: String, date: Date = Date(),
         title: String = "", duration: TimeInterval = 0,
         segments: [TranscriptSegment] = []) {
        self.id         = id
        self.transcript = transcript
        self.date       = date
        self.title      = title.isEmpty ? Self.defaultTitle(date) : title
        self.duration   = duration
        self.segments   = segments
    }

    static func defaultTitle(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d · h:mm a"
        return f.string(from: date)
    }

    static func == (lhs: Meeting, rhs: Meeting) -> Bool { lhs.id == rhs.id }
}

struct TranscriptSegment: Identifiable, Codable {
    let id: UUID
    var speaker: String
    var text: String
    var timestamp: TimeInterval

    init(id: UUID = UUID(), speaker: String, text: String, timestamp: TimeInterval) {
        self.id = id; self.speaker = speaker
        self.text = text; self.timestamp = timestamp
    }
}

// MARK: - Recording Manager

final class RecordingManager: ObservableObject {
    @Published var isRecording  = false
    @Published var isPaused     = false
    @Published var segments: [TranscriptSegment] = []
    @Published var history: [Meeting] = []
    @Published var errorMessage: String?
    @Published var currentSpeaker = "Speaker 1"

    // Speakers roster — persisted so they survive app restarts
    @Published var speakers: [String] = ["Speaker 1", "Speaker 2", "Speaker 3", "Guest"] {
        didSet {
            if let data = try? JSONEncoder().encode(speakers) {
                UserDefaults.standard.set(data, forKey: "speakers")
            }
        }
    }

    private let engine  = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var audioRecorder: AVAudioRecorder?
    private var sessionActive  = false
    private var startTime: Date?
    private(set) var currentAudioURL: URL?

    // Silence timeout — restart recognition after 60 s of no speech
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 55

    init() {
        recognizer = SFSpeechRecognizer(
            locale: Locale(identifier: AppSettings.shared.recordingLanguage))
        loadHistory()
        loadSpeakers()
        requestPermissions()
    }

    // Called from Settings when language changes
    func refreshRecognizer() {
        recognizer = SFSpeechRecognizer(
            locale: Locale(identifier: AppSettings.shared.recordingLanguage))
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        NotificationManager.shared.requestPermission()
    }

    // MARK: - Recording control

    func toggleRecording() { isRecording ? stop() : start() }

    func togglePause() {
        guard isRecording else { return }
        isPaused.toggle()
        Haptics.impact(.light)
        if isPaused {
            audioRecorder?.pause()
            silenceTimer?.invalidate()
        } else {
            audioRecorder?.record()
            resetSilenceTimer()
        }
    }

    /// Switch active speaker — starts a new segment
    func switchSpeaker(to speaker: String) {
        guard isRecording && !isPaused else {
            currentSpeaker = speaker; return
        }
        currentSpeaker = speaker
        let ts = Date().timeIntervalSince(startTime ?? Date())
        segments.append(TranscriptSegment(speaker: speaker, text: "", timestamp: ts))
    }

    func addSpeaker(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !speakers.contains(trimmed) else { return }
        speakers.append(trimmed)
    }

    // MARK: - Start

    private func start() {
        guard let rec = recognizer, rec.isAvailable else {
            errorMessage = "Speech recognition is unavailable. Check permissions in Settings."
            return
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            errorMessage = "Speech recognition not authorized. Go to Settings → Privacy → Speech Recognition."
            return
        }
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            errorMessage = "Microphone not authorized. Go to Settings → Privacy → Microphone."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            sessionActive = true
        } catch {
            errorMessage = "Audio session failed: \(error.localizedDescription)"; return
        }

        // Start audio file recording
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rec_\(UUID().uuidString).m4a")
        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: audioSettings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            currentAudioURL = url
        } catch {
            errorMessage = "Could not start audio recorder: \(error.localizedDescription)"; return
        }

        startTime   = Date()
        isRecording = true
        isPaused    = false
        Haptics.notification(.success)

        beginRecognition(recognizer: rec)
        resetSilenceTimer()
    }

    private func beginRecognition(recognizer: SFSpeechRecognizer) {
        // Tear down any existing recognition
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        engine.inputNode.removeTap(onBus: 0)

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let req = request else { return }
        req.shouldReportPartialResults = true
        if #available(iOS 13, *) { req.requiresOnDeviceRecognition = false }

        let inputNode = engine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            self?.request?.append(buf)
        }

        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    let txt = result.bestTranscription.formattedString
                    guard !txt.isEmpty else { return }

                    // Find or create segment for current speaker
                    if let idx = self.segments.lastIndex(where: {
                        $0.speaker == self.currentSpeaker }) {
                        self.segments[idx].text = txt
                    } else {
                        let ts = Date().timeIntervalSince(self.startTime ?? Date())
                        self.segments.append(
                            TranscriptSegment(speaker: self.currentSpeaker,
                                              text: txt, timestamp: ts))
                    }
                    self.resetSilenceTimer()
                }
            }

            if let error = error {
                let nsErr = error as NSError
                // Code 216 = session cancelled normally; 1110 = no speech detected — both are safe to ignore
                let safeCode = nsErr.code == 216 || nsErr.code == 1110
                if !safeCode && self.isRecording {
                    DispatchQueue.main.async {
                        // Restart recognition rather than surfacing error to user
                        self.restartRecognition()
                    }
                }
            }
        }
    }

    /// Silently restart the recognition task (Speech API has a ~1 min hard limit)
    private func restartRecognition() {
        guard isRecording, !isPaused,
              let rec = recognizer, rec.isAvailable else { return }
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        engine.inputNode.removeTap(onBus: 0)
        // Small delay to let the previous session wind down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isRecording else { return }
            self.beginRecognition(recognizer: rec)
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            self?.restartRecognition()
        }
    }

    // MARK: - Stop

    func stop() {
        silenceTimer?.invalidate(); silenceTimer = nil
        task?.cancel(); task = nil
        request?.endAudio(); request = nil

        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioRecorder?.stop()

        if sessionActive {
            try? AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }

        isRecording = false
        isPaused    = false
        Haptics.notification(.warning)
    }

    // MARK: - Save / Discard

    func save(duration: TimeInterval) -> Meeting? {
        let validSegments = segments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !validSegments.isEmpty else { return nil }

        let full    = validSegments.map(\.text).joined(separator: " ")
        let meeting = Meeting(transcript: full, duration: duration, segments: validSegments)
        history.insert(meeting, at: 0)
        saveHistory()
        Haptics.notification(.success)

        let words = full.split { $0.isWhitespace }.count
        NotificationManager.shared.sendSaved(
            title: meeting.title, duration: duration, wordCount: words)
        return meeting
    }

    func discard() {
        segments = []
        Haptics.impact(.rigid)
    }

    // MARK: - History management

    func update(_ meeting: Meeting) {
        if let idx = history.firstIndex(where: { $0.id == meeting.id }) {
            history[idx] = meeting
            saveHistory()
        }
    }

    func delete(_ meeting: Meeting) {
        history.removeAll { $0.id == meeting.id }
        saveHistory()
        Haptics.impact(.medium)
    }

    func deleteAll() {
        history.removeAll()
        saveHistory()
        Haptics.notification(.warning)
    }

    // MARK: - Persistence

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "meetings_v2")
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "meetings_v2"),
              let arr  = try? JSONDecoder().decode([Meeting].self, from: data) else { return }
        history = arr
    }

    private func loadSpeakers() {
        guard let data = UserDefaults.standard.data(forKey: "speakers"),
              let arr  = try? JSONDecoder().decode([String].self, from: data) else { return }
        if !arr.isEmpty { speakers = arr }
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var recorder = RecordingManager()
    @StateObject private var settings = AppSettings.shared
    @State private var tab: Tab = .record

    enum Tab { case record, history, settings }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.paper.ignoresSafeArea()

            Group {
                switch tab {
                case .record:
                    RecordView(recorder: recorder)
                        .transition(.opacity)
                case .history:
                    HistoryView(recorder: recorder)
                        .transition(.opacity)
                case .settings:
                    SettingsView(recorder: recorder)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: tab)

            BottomBar(tab: $tab, isRecording: recorder.isRecording)
        }
        .preferredColorScheme(settings.colorSchemePreference.scheme)
    }
}

// MARK: - Bottom Bar

struct BottomBar: View {
    @Binding var tab: ContentView.Tab
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 0) {
            tabBtn("mic",         label: "RECORD",   t: .record)
            tabBtn("list.bullet", label: "NOTES",    t: .history)
            tabBtn("gearshape",   label: "SETTINGS", t: .settings)
        }
        .background(
            Color.paper
                .overlay(Rectangle().fill(Color.inkLight.opacity(0.12)).frame(height: 1),
                         alignment: .top)
        )
    }

    private func tabBtn(_ icon: String, label: String, t: ContentView.Tab) -> some View {
        Button {
            Haptics.selection()
            tab = t
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab == t ? icon + ".fill" : icon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(tab == t ? .accent : .fog)
                    // Live recording indicator dot on Record tab
                    if t == .record && isRecording && tab != .record {
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 7, height: 7)
                            .offset(x: 6, y: -4)
                    }
                }
                Text(label)
                    .font(.mono(9, weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(tab == t ? .accent : .fog)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Record View

struct RecordView: View {
    @ObservedObject var recorder: RecordingManager
    @ObservedObject private var settings = AppSettings.shared

    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var pulse           = false
    @State private var showDiscard     = false
    @State private var showSpeaker     = false
    @State private var toastText       = ""
    @State private var showToast       = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                if recorder.segments.isEmpty && !recorder.isRecording {
                    idleState
                } else {
                    liveTranscript
                }

                Spacer(minLength: 0)
                controls.padding(.bottom, 90)
            }

            // Toast
            if showToast {
                VStack {
                    Spacer()
                    Text(toastText)
                        .font(.mono(12))
                        .foregroundColor(.paper)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.ink.opacity(0.85)))
                        .padding(.bottom, 110)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { recorder.errorMessage != nil },
            set: { if !$0 { recorder.errorMessage = nil } }
        )) { Button("OK") {} } message: { Text(recorder.errorMessage ?? "") }

        .confirmationDialog("Discard this recording?",
                            isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                recorder.discard(); elapsed = 0
            }
            Button("Cancel", role: .cancel) {}
        }

        .sheet(isPresented: $showSpeaker) {
            SpeakerPickerView(recorder: recorder)
                .presentationDetents([.medium])
        }
    }

    // MARK: Header
    private var header: some View {
        HStack(alignment: .center) {
            Text("VOICE")
                .font(.serif(28, weight: .regular))
                .foregroundColor(.ink)

            Spacer()

            // Speaker badge — visible while recording
            if recorder.isRecording {
                Button { showSpeaker = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                        Text(recorder.currentSpeaker)
                            .font(.mono(11))
                            .lineLimit(1)
                    }
                    .foregroundColor(.inkMid)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.inkLight.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // Timer / recording indicator
            if recorder.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulse ? 1.4 : 1.0)
                        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                                   value: pulse)
                        .onAppear  { pulse = true  }
                        .onDisappear { pulse = false }
                    Text(formatTime(elapsed))
                        .font(.mono(14))
                        .foregroundColor(recorder.isPaused ? .fog : .accent)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 58)
        .padding(.bottom, 24)
    }

    // MARK: Idle state
    private var idleState: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "mic")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundColor(.fog.opacity(0.5))
                Text("Tap to begin")
                    .font(.serif(17))
                    .foregroundColor(.fog)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Live transcript
    private var liveTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(recorder.segments) { seg in
                        if !seg.text.trimmingCharacters(in: .whitespaces).isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    if settings.showTimestamps {
                                        Text(formatTime(seg.timestamp))
                                            .font(.mono(9))
                                            .foregroundColor(.fog)
                                            .tracking(1)
                                    }
                                    Text(seg.speaker)
                                        .font(.mono(9, weight: .medium))
                                        .foregroundColor(.accent)
                                        .tracking(0.5)
                                }
                                Text(seg.text)
                                    .font(.serif(17))
                                    .foregroundColor(.ink)
                                    .lineSpacing(5)
                                    .id(seg.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .onChange(of: recorder.segments.last?.text) { _ in
                if let last = recorder.segments.last(where: {
                    !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: Controls
    private var controls: some View {
        VStack(spacing: 24) {
            Rectangle()
                .fill(Color.inkLight.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 28)

            HStack(spacing: 48) {

                // Left slot
                Group {
                    if recorder.isRecording {
                        // Pause / Resume
                        Button(action: recorder.togglePause) {
                            Image(systemName: recorder.isPaused ? "play.fill" : "pause")
                                .font(.system(size: 20, weight: .light))
                                .foregroundColor(.inkMid)
                                .frame(width: 44, height: 44)
                        }
                    } else if !recorder.segments.isEmpty {
                        // Save
                        Button {
                            if let saved = recorder.save(duration: elapsed) {
                                recorder.discard()
                                stopTimer()
                                elapsed = 0
                                showToastMessage("\"\(saved.title)\" saved")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.to.line")
                                    .font(.system(size: 13, weight: .regular))
                                Text("SAVE")
                                    .font(.mono(11, weight: .medium))
                                    .tracking(2)
                            }
                            .foregroundColor(.ink)
                            .frame(width: 88, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.inkMid, lineWidth: 1))
                        }
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }

                // Main record / stop button
                Button(action: handleMainButton) {
                    ZStack {
                        Circle()
                            .fill(recorder.isRecording ? Color.accent : Color.ink)
                            .frame(width: 68, height: 68)
                        if recorder.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.paper)
                                .frame(width: 22, height: 22)
                        } else {
                            Circle()
                                .fill(Color.paper)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(recorder.isRecording ? (recorder.isPaused ? 0.95 : 1.06) : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: recorder.isRecording)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: recorder.isPaused)

                // Right slot — speaker switcher while recording, discard after
                Group {
                    if recorder.isRecording {
                        Button { showSpeaker = true } label: {
                            Image(systemName: "person.2")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(.inkMid)
                                .frame(width: 44, height: 44)
                        }
                    } else if !recorder.segments.isEmpty {
                        Button { showDiscard = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(.fog)
                                .frame(width: 44, height: 44)
                        }
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
            }
            .padding(.bottom, 8)

            // Word count / paused label
            Group {
                if recorder.isPaused {
                    Text("PAUSED")
                        .font(.mono(10, weight: .medium))
                        .foregroundColor(.fog)
                        .tracking(2)
                } else if !recorder.segments.isEmpty {
                    Text("\(wordCount) words")
                        .font(.mono(11))
                        .foregroundColor(.fog)
                        .tracking(0.5)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: wordCount)
                }
            }
        }
    }

    // MARK: Helpers

    private var wordCount: Int {
        recorder.segments.reduce(0) { $0 + $1.text.split { $0.isWhitespace }.count }
    }

    private func handleMainButton() {
        Haptics.impact(.medium)
        if recorder.isRecording {
            recorder.stop()
            stopTimer()
            if settings.autoSave {
                if let saved = recorder.save(duration: elapsed) {
                    recorder.discard()
                    elapsed = 0
                    showToastMessage("Auto-saved · \"\(saved.title)\"")
                }
            }
        } else {
            elapsed = 0
            recorder.discard()
            recorder.toggleRecording()
            startTimer()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                if !self.recorder.isPaused { self.elapsed += 0.5 }
            }
        }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }

    private func formatTime(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }

    private func showToastMessage(_ msg: String) {
        toastText = msg
        withAnimation(.spring()) { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showToast = false }
        }
    }
}

// MARK: - Speaker Picker

struct SpeakerPickerView: View {
    @ObservedObject var recorder: RecordingManager
    @Environment(\.dismiss) var dismiss
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.fog.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            Text("SPEAKER")
                .font(.mono(10, weight: .medium))
                .tracking(3)
                .foregroundColor(.fog)
                .padding(.bottom, 20)

            Divider().overlay(Color.inkLight.opacity(0.2))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(recorder.speakers, id: \.self) { speaker in
                        Button {
                            Haptics.selection()
                            recorder.switchSpeaker(to: speaker)
                            dismiss()
                        } label: {
                            HStack {
                                Text(speaker)
                                    .font(.serif(16))
                                    .foregroundColor(.ink)
                                Spacer()
                                if speaker == recorder.currentSpeaker {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.accent)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Color.inkLight.opacity(0.15)).padding(.horizontal, 28)
                    }
                }
            }

            // Add new speaker
            HStack(spacing: 12) {
                TextField("Add speaker…", text: $newName)
                    .font(.serif(15))
                    .foregroundColor(.ink)
                    .submitLabel(.done)
                    .onSubmit { addAndSelect() }

                Button(action: addAndSelect) {
                    Text("Add")
                        .font(.mono(12, weight: .medium))
                        .foregroundColor(newName.trimmingCharacters(in: .whitespaces).isEmpty ? .fog : .accent)
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(Color.inkLight.opacity(0.05))
        }
        .background(Color.paper)
    }

    private func addAndSelect() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        recorder.addSpeaker(name)
        recorder.switchSpeaker(to: name)
        Haptics.impact(.medium)
        newName = ""
        dismiss()
    }
}

// MARK: - History View

struct HistoryView: View {
    @ObservedObject var recorder: RecordingManager
    @State private var selectedMeeting: Meeting?
    @State private var shareItems: [Any]?
    @State private var searchText = ""

    private var filtered: [Meeting] {
        guard !searchText.isEmpty else { return recorder.history }
        return recorder.history.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.transcript.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("NOTES")
                    .font(.serif(28, weight: .regular))
                    .foregroundColor(.ink)
                Spacer()
                if !recorder.history.isEmpty {
                    Text("\(recorder.history.count)")
                        .font(.mono(13))
                        .foregroundColor(.fog)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 58)
            .padding(.bottom, 16)

            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.fog)
                TextField("Search notes…", text: $searchText)
                    .font(.serif(15))
                    .foregroundColor(.ink)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = ""; Haptics.impact(.light) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.fog)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color.inkLight.opacity(0.07)))
            .padding(.horizontal, 28)
            .padding(.bottom, 8)

            if filtered.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filtered) { meeting in
                        MeetingRow(meeting: meeting)
                            .listRowBackground(Color.paper)
                            .listRowSeparatorTint(Color.inkLight.opacity(0.3))
                            .listRowInsets(EdgeInsets(top: 0, leading: 28, bottom: 0, trailing: 28))
                            .onTapGesture {
                                Haptics.selection()
                                selectedMeeting = meeting
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { recorder.delete(meeting) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    Haptics.impact(.light)
                                    shareItems = [meeting.transcript]
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .tint(Color.inkMid)

                                Button {
                                    Haptics.impact(.light)
                                    if let url = TranscriptPDFMaker.make(from: meeting) {
                                        shareItems = [url]
                                    }
                                } label: {
                                    Label("PDF", systemImage: "doc.richtext")
                                }
                                .tint(Color.accent)
                            }
                    }
                }
                .listStyle(.plain)
                .background(Color.paper)
            }

            Spacer(minLength: 0).frame(height: 90)
        }
        .sheet(item: $selectedMeeting) { meeting in
            MeetingDetailView(meeting: meeting, recorder: recorder)
        }
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            if let items = shareItems { ActivityVC(items: items) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundColor(.fog.opacity(0.5))
            Text(searchText.isEmpty ? "No recordings yet" : "No results")
                .font(.serif(17))
                .foregroundColor(.fog)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Meeting Row

struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.serif(16))
                .foregroundColor(.ink)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(meeting.date, style: .date)
                    .font(.mono(11))
                    .foregroundColor(.fog)
                Text("·").font(.mono(11)).foregroundColor(.fog.opacity(0.5))
                Text(formatDur(meeting.duration))
                    .font(.mono(11))
                    .foregroundColor(.fog)
                Text("·").font(.mono(11)).foregroundColor(.fog.opacity(0.5))
                Text(wordCount(meeting.transcript))
                    .font(.mono(11))
                    .foregroundColor(.fog)
            }
        }
        .padding(.vertical, 16)
    }

    private func formatDur(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
    private func wordCount(_ text: String) -> String {
        "\(text.split { $0.isWhitespace }.count) words"
    }
}

// MARK: - Meeting Detail View

struct MeetingDetailView: View {
    @State var meeting: Meeting
    let recorder: RecordingManager
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var settings = AppSettings.shared

    @State private var shareItems: [Any]?
    @State private var isEditingTitle = false
    @State private var editedTitle = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {

                    // Title + date
                    VStack(alignment: .leading, spacing: 6) {
                        Text(meeting.date, style: .date)
                            .font(.mono(12)).foregroundColor(.fog).tracking(1)

                        if isEditingTitle {
                            TextField("Title", text: $editedTitle)
                                .font(.serif(26, weight: .regular))
                                .foregroundColor(.ink)
                                .submitLabel(.done)
                                .onSubmit { commitTitle() }
                        } else {
                            Text(meeting.title)
                                .font(.serif(26, weight: .regular))
                                .foregroundColor(.ink)
                                .onTapGesture {
                                    editedTitle = meeting.title
                                    Haptics.selection()
                                    isEditingTitle = true
                                }
                        }

                        // Stats row
                        HStack(spacing: 8) {
                            Text(formatDur(meeting.duration))
                                .font(.mono(11)).foregroundColor(.fog)
                            Text("·").font(.mono(11)).foregroundColor(.fog.opacity(0.4))
                            Text(wordCount)
                                .font(.mono(11)).foregroundColor(.fog)
                            if meeting.segments.count > 1 {
                                Text("·").font(.mono(11)).foregroundColor(.fog.opacity(0.4))
                                Text("\(meeting.segments.count) speakers")
                                    .font(.mono(11)).foregroundColor(.fog)
                            }
                        }
                    }

                    Divider().overlay(Color.inkLight.opacity(0.3))

                    // Transcript
                    if meeting.segments.isEmpty {
                        Text(meeting.transcript.isEmpty ? "No transcript recorded." : meeting.transcript)
                            .font(.serif(17)).foregroundColor(.ink).lineSpacing(6)
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(meeting.segments.filter {
                                !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
                            }) { seg in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        if settings.showTimestamps {
                                            Text(formatTS(seg.timestamp))
                                                .font(.mono(9)).foregroundColor(.fog).tracking(1)
                                        }
                                        Text(seg.speaker)
                                            .font(.mono(9, weight: .medium))
                                            .foregroundColor(.accent).tracking(0.5)
                                    }
                                    Text(seg.text)
                                        .font(.serif(17)).foregroundColor(.ink).lineSpacing(5)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 60)
            }
            .background(Color.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        if isEditingTitle { commitTitle() }
                        dismiss()
                    }
                    .font(.serif(16)).foregroundColor(.ink)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Rename shortcut
                        if isEditingTitle {
                            Button("Done") { commitTitle() }
                                .font(.mono(13)).foregroundColor(.accent)
                        }

                        Menu {
                            Button {
                                editedTitle = meeting.title
                                isEditingTitle = true
                            } label: { Label("Rename", systemImage: "pencil") }

                            Divider()

                            Button {
                                Haptics.impact(.light)
                                shareItems = [meeting.transcript]
                            } label: { Label("Share as Text", systemImage: "doc.plaintext") }

                            Button {
                                Haptics.impact(.light)
                                if let url = TranscriptPDFMaker.make(from: meeting) {
                                    shareItems = [url]
                                }
                            } label: { Label("Export as PDF", systemImage: "doc.richtext") }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16))
                                .foregroundColor(.ink)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            if let items = shareItems { ActivityVC(items: items) }
        }
    }

    private func commitTitle() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            meeting.title = trimmed
            recorder.update(meeting)
        }
        isEditingTitle = false
    }

    private var wordCount: String {
        "\(meeting.transcript.split { $0.isWhitespace }.count) words"
    }

    private func formatDur(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
    private func formatTS(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    let recorder: RecordingManager
    @ObservedObject private var settings = AppSettings.shared
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SETTINGS")
                    .font(.serif(28, weight: .regular))
                    .foregroundColor(.ink)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 58)
            .padding(.bottom, 24)

            List {

                // ── Recording ────────────────────────────────────────────────
                Section {
                    // Language picker
                    Picker(selection: $settings.recordingLanguage) {
                        ForEach(AppSettings.languages, id: \.locale) { lang in
                            Text(lang.label).tag(lang.locale)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Language").font(.serif(15)).foregroundColor(.ink)
                            Text("Transcription language").font(.mono(11)).foregroundColor(.fog)
                        }
                    }
                    .onChange(of: settings.recordingLanguage) { _ in
                        Haptics.selection()
                        recorder.refreshRecognizer()
                    }

                    SettingsToggle(
                        label: "Auto-save",
                        detail: "Save recording immediately when stopped",
                        isOn: $settings.autoSave)

                    SettingsToggle(
                        label: "Show timestamps",
                        detail: "Display time markers in transcripts",
                        isOn: $settings.showTimestamps)

                } header: { sectionLabel("Recording") }
                .listRowBackground(Color.paper)

                // ── Appearance ───────────────────────────────────────────────
                // ── Haptics ──────────────────────────────────────────────────
                Section {
                    SettingsToggle(
                        label: "Haptic feedback",
                        detail: "Vibrations on record, save, and actions",
                        isOn: $settings.hapticsEnabled)
                } header: { sectionLabel("Haptics") }
                .listRowBackground(Color.paper)

                // ── Notifications ────────────────────────────────────────────
                Section {
                    // Blocked warning
                    if notifStatus == .denied {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.accent)
                            Text("Notifications are blocked")
                                .font(.mono(11))
                                .foregroundColor(.fog)
                            Spacer()
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.mono(11, weight: .medium))
                            .foregroundColor(.accent)
                        }
                        .padding(.vertical, 4)
                    }

                    SettingsToggle(
                        label: "Save confirmations",
                        detail: "Notify when a note is saved",
                        isOn: $settings.notificationsEnabled)
                    .disabled(notifStatus == .denied)

                    // Daily reminder toggle
                    SettingsToggle(
                        label: "Daily reminder",
                        detail: "Morning nudge to capture your thoughts",
                        isOn: $settings.dailyReminderEnabled)
                    .disabled(notifStatus == .denied)
                    .onChange(of: settings.dailyReminderEnabled) { enabled in
                        Haptics.selection()
                        if enabled {
                            NotificationManager.shared.requestPermission { granted in
                                if granted {
                                    NotificationManager.shared.scheduleReminder(at: settings.reminderHour)
                                    notifStatus = .authorized
                                } else {
                                    settings.dailyReminderEnabled = false
                                    notifStatus = .denied
                                }
                            }
                        } else {
                            NotificationManager.shared.cancelReminder()
                        }
                    }

                    // Reminder time — only shown when daily reminder is active
                    if settings.dailyReminderEnabled && notifStatus != .denied {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reminder time")
                                    .font(.serif(15)).foregroundColor(.ink)
                                Text(String(format: "Daily at %02d:00", settings.reminderHour))
                                    .font(.mono(11)).foregroundColor(.fog)
                            }
                            Spacer()
                            Stepper("", value: $settings.reminderHour, in: 5...22)
                                .labelsHidden()
                                .onChange(of: settings.reminderHour) { h in
                                    Haptics.selection()
                                    NotificationManager.shared.scheduleReminder(at: h)
                                }
                        }
                    }

                } header: { sectionLabel("Notifications") }
                .listRowBackground(Color.paper)

                // ── Data ────────────────────────────────────────────────────
                Section {
                    HStack {
                        Text("Recordings").font(.serif(15)).foregroundColor(.ink)
                        Spacer()
                        Text("\(recorder.history.count)")
                            .font(.mono(13)).foregroundColor(.fog)
                    }

                    HStack {
                        Text("Total duration").font(.serif(15)).foregroundColor(.ink)
                        Spacer()
                        Text(totalDuration)
                            .font(.mono(13)).foregroundColor(.fog)
                    }

                    Button {
                        Haptics.impact(.medium)
                        showClearConfirm = true
                    } label: {
                        HStack {
                            Text("Delete all recordings")
                                .font(.serif(15))
                                .foregroundColor(.accent)
                            Spacer()
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundColor(.accent)
                        }
                    }
                    .disabled(recorder.history.isEmpty)

                } header: { sectionLabel("Data") }
                .listRowBackground(Color.paper)

                // ── About ────────────────────────────────────────────────────
                Section {
                    HStack {
                        Text("Version").font(.serif(15)).foregroundColor(.ink)
                        Spacer()
                        Text("1.0.0").font(.mono(13)).foregroundColor(.fog)
                    }
                    HStack {
                        Text("Build").font(.serif(15)).foregroundColor(.ink)
                        Spacer()
                        Text(buildNumber).font(.mono(13)).foregroundColor(.fog)
                    }
                } header: { sectionLabel("About") }
                .listRowBackground(Color.paper)

                // Spacer above tab bar
                Section { Color.clear.frame(height: 40) }
                    .listRowBackground(Color.clear)
                    .listSectionSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.paper)
        }
        .background(Color.paper.ignoresSafeArea())
        .onAppear { refreshNotifStatus() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshNotifStatus()
        }
        .confirmationDialog(
            "Delete all \(recorder.history.count) recording\(recorder.history.count == 1 ? "" : "s")?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { recorder.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func refreshNotifStatus() {
        NotificationManager.shared.checkStatus { notifStatus = $0 }
    }

    private var totalDuration: String {
        let t = recorder.history.reduce(0) { $0 + $1.duration }
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.mono(10, weight: .medium))
            .tracking(2)
            .foregroundColor(.fog)
            .padding(.top, 4)
    }
}

// MARK: - Settings Toggle

struct SettingsToggle: View {
    let label: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.serif(15)).foregroundColor(.ink)
                Text(detail).font(.mono(11)).foregroundColor(.fog)
            }
        }
        .tint(Color.accent)
        .onChange(of: isOn) { _ in Haptics.selection() }
    }
}

// MARK: - PDF Generator

enum TranscriptPDFMaker {

    static func make(from meeting: Meeting) -> URL? {
        let pageSize = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 56
        let contentW = pageSize.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageSize)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(meeting.title.sanitized)_\(UUID().uuidString).pdf")

        do {
            try renderer.writePDF(to: url) { ctx in
                let titleFont   = UIFont(name: "Georgia", size: 22) ?? .systemFont(ofSize: 22)
                let metaFont    = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                let bodyFont    = UIFont(name: "Georgia", size: 13) ?? .systemFont(ofSize: 13)
                let labelFont   = UIFont.monospacedSystemFont(ofSize: 9,  weight: .medium)
                let inkColor    = UIColor(white: 0.06, alpha: 1)
                let fogColor    = UIColor(white: 0.55, alpha: 1)
                let accentUI    = UIColor(red: 1.0, green: 0.36, blue: 0.22, alpha: 1)

                var y: CGFloat = 0

                func newPage() { ctx.beginPage(); y = margin }

                @discardableResult
                func draw(_ str: String, font: UIFont, color: UIColor,
                          indent: CGFloat = 0, spacing: CGFloat = 6) -> CGFloat {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font, .foregroundColor: color]
                    let avail = CGSize(width: contentW - indent, height: .greatestFiniteMagnitude)
                    let h = ceil((str as NSString).boundingRect(
                        with: avail, options: .usesLineFragmentOrigin,
                        attributes: attrs, context: nil).height)
                    if y + h > pageSize.height - margin { newPage() }
                    (str as NSString).draw(
                        in: CGRect(x: margin + indent, y: y,
                                   width: contentW - indent, height: h),
                        withAttributes: attrs)
                    y += h + spacing
                    return h
                }

                func drawRule() {
                    if y + 1 > pageSize.height - margin { newPage() }
                    let p = UIBezierPath()
                    p.move(to: CGPoint(x: margin, y: y))
                    p.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
                    UIColor(white: 0.85, alpha: 1).setStroke()
                    p.lineWidth = 0.5; p.stroke(); y += 16
                }

                newPage()
                // Accent bar
                let bar = UIBezierPath(rect: CGRect(x: margin, y: margin - 12, width: 32, height: 2))
                accentUI.setFill(); bar.fill()
                y = margin + 8

                draw(meeting.title, font: titleFont, color: inkColor, spacing: 10)
                let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .short
                let wc = meeting.transcript.split { $0.isWhitespace }.count
                draw("\(df.string(from: meeting.date))   ·   \(fmt(meeting.duration))   ·   \(wc) words",
                     font: metaFont, color: fogColor, spacing: 20)
                drawRule()

                let validSegs = meeting.segments.filter {
                    !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }

                if validSegs.isEmpty {
                    draw(meeting.transcript, font: bodyFont, color: inkColor)
                } else {
                    for seg in validSegs {
                        draw("\(fmtTS(seg.timestamp))   \(seg.speaker.uppercased())",
                             font: labelFont, color: fogColor, spacing: 4)
                        draw(seg.text, font: bodyFont, color: inkColor, spacing: 18)
                    }
                }
            }
            return url
        } catch { print("PDF error: \(error)"); return nil }
    }

    private static func fmt(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
    private static func fmtTS(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

private extension UIBezierPath {
    func apply(_ block: (UIBezierPath) -> Void) { block(self) }
}

private extension String {
    var sanitized: String {
        components(separatedBy: CharacterSet.alphanumerics
            .union(.init(charactersIn: " -_")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - Activity View Controller

struct ActivityVC: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
