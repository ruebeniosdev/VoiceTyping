import SwiftUI
import Speech
import AVFoundation
import UIKit
import PDFKit
import Combine
// MARK: - Design System

extension Color {
    static let ink       = Color(white: 0.06)
    static let inkLight  = Color(white: 0.14)
    static let inkMid    = Color(white: 0.24)
    static let fog       = Color(white: 0.58)
    static let paper     = Color(white: 0.96)
    static let accent    = Color(red: 1.0, green: 0.36, blue: 0.22) // warm vermillion
}

// Monospaced timing font helper
extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
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
         title: String = "", duration: TimeInterval = 0, segments: [TranscriptSegment] = []) {
        self.id = id
        self.transcript = transcript
        self.date = date
        self.title = title.isEmpty ? Self.defaultTitle(date) : title
        self.duration = duration
        self.segments = segments
    }

    static func defaultTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
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
        self.id = id; self.speaker = speaker; self.text = text; self.timestamp = timestamp
    }
}

// MARK: - Recording Manager

final class RecordingManager: ObservableObject {
    @Published var isRecording   = false
    @Published var isPaused      = false
    @Published var liveText      = ""
    @Published var segments: [TranscriptSegment] = []
    @Published var history: [Meeting] = []
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var audioRecorder: AVAudioRecorder?
    private var sessionActive = false
    private var startTime: Date?
    private(set) var currentAudioURL: URL?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        loadHistory()
        requestPermissions()
    }

    // MARK: Permissions
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    // MARK: Toggle
    func toggleRecording() {
        isRecording ? stop() : start()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            audioRecorder?.pause()
        } else {
            audioRecorder?.record()
        }
    }

    // MARK: Start
    private func start() {
        guard let rec = recognizer, rec.isAvailable else {
            errorMessage = "Speech recognition unavailable."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            sessionActive = true
        } catch {
            errorMessage = "Audio session failed."
            return
        }

        // Audio file
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rec_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        audioRecorder = try? AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.record()
        currentAudioURL = url

        // Recognition
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        let fmt = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            self?.request?.append(buf)
        }

        task = rec.recognitionTask(with: request!) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                DispatchQueue.main.async {
                    let txt = result.bestTranscription.formattedString
                    if self.segments.isEmpty {
                        self.segments.append(TranscriptSegment(
                            speaker: "Speaker 1", text: txt,
                            timestamp: Date().timeIntervalSince(self.startTime ?? Date())))
                    } else {
                        self.segments[self.segments.count - 1].text = txt
                    }
                    self.liveText = txt
                }
            }
        }

        engine.prepare()
        try? engine.start()
        startTime = Date()
        isRecording = true
        isPaused    = false
    }

    // MARK: Stop
    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        audioRecorder?.stop()
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
        isRecording = false
        isPaused    = false
    }

    // MARK: Save
    func save(duration: TimeInterval) {
        guard !segments.isEmpty else { return }
        let full = segments.map(\.text).joined(separator: " ")
        let m = Meeting(transcript: full, duration: duration, segments: segments)
        history.insert(m, at: 0)
        saveHistory()
    }

    func discard() {
        segments = []
        liveText  = ""
    }

    // MARK: Delete
    func delete(_ meeting: Meeting) {
        history.removeAll { $0.id == meeting.id }
        saveHistory()
    }

    // MARK: Persistence
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "meetings_v2")
        }
    }
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "meetings_v2"),
              let arr = try? JSONDecoder().decode([Meeting].self, from: data) else { return }
        history = arr
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var recorder = RecordingManager()
    @State private var tab: Tab = .record

    enum Tab { case record, history }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.paper.ignoresSafeArea()

            Group {
                if tab == .record {
                    RecordView(recorder: recorder)
                        .transition(.opacity)
                } else {
                    HistoryView(recorder: recorder)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: tab)

            BottomBar(tab: $tab)
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - Bottom Bar

struct BottomBar: View {
    @Binding var tab: ContentView.Tab

    var body: some View {
        HStack(spacing: 0) {
            tabButton("mic",     label: "RECORD",  t: .record)
            tabButton("list.bullet", label: "NOTES", t: .history)
        }
        .background(Color.paper.shadow(.inner(color: .black.opacity(0.06), radius: 0, y: -1)))
    }

    private func tabButton(_ icon: String, label: String, t: ContentView.Tab) -> some View {
        Button { tab = t } label: {
            VStack(spacing: 4) {
                Image(systemName: tab == t ? icon + ".fill" : icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(tab == t ? .accent : .fog)
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
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Content
            if recorder.segments.isEmpty && !recorder.isRecording {
                idleState
            } else {
                liveTranscript
            }

            Spacer(minLength: 0)

            // Controls
            controls
                .padding(.bottom, 90) // above tab bar
        }
        .alert("Error", isPresented: Binding(
            get: { recorder.errorMessage != nil },
            set: { if !$0 { recorder.errorMessage = nil } }
        )) { Button("OK") {} } message: {
            Text(recorder.errorMessage ?? "")
        }
    }

    // MARK: Header
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("VOICE")
                .font(.serif(28, weight: .regular))
                .foregroundColor(.ink)
            Spacer()
            if recorder.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulse ? 1.3 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                        .onAppear { pulse = true }
                        .onDisappear { pulse = false }
                    Text(formatTime(elapsed))
                        .font(.mono(14))
                        .foregroundColor(.accent)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 58)
        .padding(.bottom, 24)
    }

    // MARK: Idle State
    private var idleState: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Tap to begin")
                .font(.serif(17))
                .foregroundColor(.fog)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Live Transcript
    private var liveTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(recorder.segments) { seg in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatTime(seg.timestamp))
                                .font(.mono(10))
                                .foregroundColor(.fog)
                                .tracking(1)
                            Text(seg.text.isEmpty ? "…" : seg.text)
                                .font(.serif(17))
                                .foregroundColor(seg.text.isEmpty ? .fog : .ink)
                                .lineSpacing(5)
                                .id(seg.id)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
            .onChange(of: recorder.segments.last?.text) { _ in
                if let last = recorder.segments.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: Controls
    private var controls: some View {
        VStack(spacing: 24) {
            // Divider line
            Rectangle()
                .fill(Color.inkLight.opacity(0.3))
                .frame(height: 1)
                .padding(.horizontal, 28)

            HStack(spacing: 48) {
                // Pause / empty
                if recorder.isRecording {
                    Button(action: recorder.togglePause) {
                        Image(systemName: recorder.isPaused ? "play" : "pause")
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(.inkMid)
                            .frame(width: 44, height: 44)
                    }
                } else {
                    // Save button (only after stopped with content)
                    if !recorder.segments.isEmpty {
                        Button(action: { recorder.save(duration: elapsed); stopTimer() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.to.line")
                                    .font(.system(size: 14, weight: .regular))
                                Text("SAVE")
                                    .font(.mono(11, weight: .medium))
                                    .tracking(2)
                            }
                            .foregroundColor(.ink)
                            .frame(width: 88, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.inkMid, lineWidth: 1)
                            )
                        }
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }

                // Main record button
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
                .scaleEffect(recorder.isRecording ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: recorder.isRecording)

                // Discard
                if !recorder.segments.isEmpty && !recorder.isRecording {
                    Button(action: { recorder.discard(); elapsed = 0 }) {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(.fog)
                            .frame(width: 44, height: 44)
                    }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .padding(.bottom, 8)

            // Word count
            if !recorder.segments.isEmpty {
                Text("\(wordCount) words")
                    .font(.mono(11))
                    .foregroundColor(.fog)
                    .tracking(0.5)
            }
        }
    }

    // MARK: Helpers
    private var wordCount: Int {
        recorder.segments.reduce(0) { $0 + $1.text.split { $0.isWhitespace }.count }
    }

    private func handleMainButton() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if recorder.isRecording {
            recorder.stop()
            stopTimer()
        } else {
            elapsed = 0
            recorder.discard()
            recorder.toggleRecording()
            startTimer()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if !recorder.isPaused { elapsed += 0.5 }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - History View

struct HistoryView: View {
    @ObservedObject var recorder: RecordingManager
    @State private var selectedMeeting: Meeting?
    @State private var shareItems: [Any]?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("NOTES")
                    .font(.serif(28, weight: .regular))
                    .foregroundColor(.ink)
                Spacer()
                Text("\(recorder.history.count)")
                    .font(.mono(13))
                    .foregroundColor(.fog)
            }
            .padding(.horizontal, 28)
            .padding(.top, 58)
            .padding(.bottom, 24)

            if recorder.history.isEmpty {
                Spacer()
                Text("No recordings yet")
                    .font(.serif(17))
                    .foregroundColor(.fog)
                Spacer()
            } else {
                List {
                    ForEach(recorder.history) { meeting in
                        MeetingRow(meeting: meeting)
                            .listRowBackground(Color.paper)
                            .listRowSeparatorTint(Color.inkLight.opacity(0.3))
                            .listRowInsets(EdgeInsets(top: 0, leading: 28, bottom: 0, trailing: 28))
                            .onTapGesture { selectedMeeting = meeting }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    recorder.delete(meeting)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    shareItems = [meeting.transcript]
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .tint(Color.inkMid)
                            }
                    }
                }
                .listStyle(.plain)
                .background(Color.paper)
            }

            Spacer(minLength: 0)
                .frame(height: 90)
        }
        .sheet(item: $selectedMeeting) { meeting in
            MeetingDetailView(meeting: meeting)
        }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems {
                ActivityVC(items: items)
            }
        }
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

            HStack(spacing: 12) {
                Text(formatDur(meeting.duration))
                    .font(.mono(11))
                    .foregroundColor(.fog)
                Text("·")
                    .foregroundColor(.fog)
                    .font(.mono(11))
                Text(wordCount(meeting.transcript))
                    .font(.mono(11))
                    .foregroundColor(.fog)
            }
        }
        .padding(.vertical, 16)
    }

    private func formatDur(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func wordCount(_ text: String) -> String {
        let n = text.split { $0.isWhitespace }.count
        return "\(n) words"
    }
}

// MARK: - Meeting Detail

struct MeetingDetailView: View {
    let meeting: Meeting
    @Environment(\.dismiss) var dismiss
    @State private var shareItems: [Any]?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Meta
                    VStack(alignment: .leading, spacing: 6) {
                        Text(meeting.date, style: .date)
                            .font(.mono(12))
                            .foregroundColor(.fog)
                            .tracking(1)
                        Text(meeting.title)
                            .font(.serif(26, weight: .regular))
                            .foregroundColor(.ink)
                    }

                    Divider().overlay(Color.inkLight.opacity(0.3))

                    // Segments or plain transcript
                    if meeting.segments.isEmpty {
                        Text(meeting.transcript)
                            .font(.serif(17))
                            .foregroundColor(.ink)
                            .lineSpacing(6)
                    } else {
                        ForEach(meeting.segments) { seg in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatTS(seg.timestamp))
                                    .font(.mono(10))
                                    .foregroundColor(.fog)
                                    .tracking(1)
                                Text(seg.text)
                                    .font(.serif(17))
                                    .foregroundColor(.ink)
                                    .lineSpacing(5)
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
                    Button("Close") { dismiss() }
                        .font(.serif(16))
                        .foregroundColor(.ink)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            shareItems = [meeting.transcript]
                        } label: {
                            Label("Share as Text", systemImage: "doc.plaintext")
                        }

                        Button {
                            if let pdfURL = TranscriptPDFMaker.make(from: meeting) {
                                shareItems = [pdfURL]
                            }
                        } label: {
                            Label("Export as PDF", systemImage: "doc.richtext")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(.ink)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems {
                ActivityVC(items: items)
            }
        }
    }

    private func formatTS(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - PDF Generator

enum TranscriptPDFMaker {

    static func make(from meeting: Meeting) -> URL? {
        let pageSize   = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 points
        let margin: CGFloat = 56
        let contentW   = pageSize.width - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: pageSize)

        // Temp file
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(meeting.title.sanitized)_\(UUID().uuidString).pdf")

        do {
            try renderer.writePDF(to: url) { ctx in
                // ── Shared typography ──────────────────────────────────────
                let titleFont    = UIFont(name: "Georgia", size: 22) ?? .systemFont(ofSize: 22, weight: .light)
                let metaFont     = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                let bodyFont     = UIFont(name: "Georgia", size: 13) ?? .systemFont(ofSize: 13)
                let tsFont       = UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)
                let speakerFont  = UIFont.monospacedSystemFont(ofSize: 9, weight: .medium)

                let inkColor: UIColor  = UIColor(white: 0.06, alpha: 1)
                let fogColor: UIColor  = UIColor(white: 0.55, alpha: 1)
                let accentColor: UIColor = UIColor(red: 1.0, green: 0.36, blue: 0.22, alpha: 1)

                var y: CGFloat = 0  // current vertical cursor

                // ── Helper: start new page ─────────────────────────────────
                func newPage() {
                    ctx.beginPage()
                    y = margin
                }

                // ── Helper: draw text, paginate automatically ──────────────
                @discardableResult
                func draw(_ string: String, font: UIFont, color: UIColor,
                          indent: CGFloat = 0, spacing: CGFloat = 6) -> CGFloat {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color
                    ]
                    let avail = CGSize(width: contentW - indent, height: .greatestFiniteMagnitude)
                    let bounds = (string as NSString).boundingRect(
                        with: avail, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
                    let h = ceil(bounds.height)

                    if y + h > pageSize.height - margin {
                        // Draw page number at bottom before flipping
                        drawPageNumber(ctx, pageSize: pageSize, margin: margin,
                                       font: metaFont, color: fogColor)
                        newPage()
                    }

                    (string as NSString).draw(
                        in: CGRect(x: margin + indent, y: y, width: contentW - indent, height: h),
                        withAttributes: attrs)
                    y += h + spacing
                    return h
                }

                func drawPageNumber(_ ctx: UIGraphicsPDFRendererContext,
                                    pageSize: CGRect, margin: CGFloat,
                                    font: UIFont, color: UIColor) {
                    // Page numbers aren't directly accessible from UIGraphicsPDFRenderer,
                    // so we use a placeholder via context page count heuristic.
                    // We skip this for simplicity — page numbers require tracking manually.
                }

                func drawRule(color: UIColor = UIColor(white: 0.85, alpha: 1)) {
                    if y + 1 > pageSize.height - margin { newPage() }
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: margin, y: y))
                    path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
                    color.setStroke()
                    path.lineWidth = 0.5
                    path.stroke()
                    y += 16
                }

                // ════════════════════════════════════════════════
                // PAGE 1 — Title block
                // ════════════════════════════════════════════════
                newPage()

                // Accent rule at top
                let topBar = UIBezierPath(rect: CGRect(x: margin, y: margin - 12, width: 32, height: 2))
                accentColor.setFill(); topBar.fill()
                y = margin + 8

                draw(meeting.title, font: titleFont, color: inkColor, spacing: 10)

                // Date · duration · words
                let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .short
                let words = meeting.transcript.split { $0.isWhitespace }.count
                let dur   = formatDuration(meeting.duration)
                let meta  = "\(df.string(from: meeting.date))   ·   \(dur)   ·   \(words) words"
                draw(meta, font: metaFont, color: fogColor, spacing: 20)

                drawRule()

                // ── Transcript body ───────────────────────────────────────
                if meeting.segments.isEmpty {
                    draw(meeting.transcript, font: bodyFont, color: inkColor, spacing: 0)
                } else {
                    for seg in meeting.segments {
                        // Timestamp + speaker header
                        let ts = formatTimestamp(seg.timestamp)
                        let header = "\(ts)   \(seg.speaker.uppercased())"
                        draw(header, font: speakerFont, color: fogColor, spacing: 4)
                        draw(seg.text, font: bodyFont, color: inkColor, spacing: 18)
                    }
                }
            }
            return url
        } catch {
            print("PDF render error: \(error)")
            return nil
        }
    }

    private static func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    private static func formatTimestamp(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

private extension String {
    var sanitized: String {
        self.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -_")).inverted)
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
