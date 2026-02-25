import SwiftUI
import PDFKit
import Foundation
import Speech
import AVFoundation
import Combine
import UIKit
import RevenueCatUI
// MARK: - Data Models

struct Transcription: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let date: Date
    var title: String
    var tags: [String]
    var isFavorite: Bool
    
    init(id: UUID = UUID(), text: String, date: Date = Date(), title: String = "", tags: [String] = [], isFavorite: Bool = false) {
        self.id = id
        self.text = text
        self.date = date
        self.title = title.isEmpty ? "Note \(date.formatted(date: .abbreviated, time: .shortened))" : title
        self.tags = tags
        self.isFavorite = isFavorite
    }
    
    static func == (lhs: Transcription, rhs: Transcription) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Main View

struct SpeechToTextView: View {
    @StateObject private var manager = SpeechRecognitionManager()
    @State private var showCopiedToast = false
    @State private var showShareSheet = false
    @State private var exportURL: URL?
    @State private var showHistory = false
    @State private var pulseAnimation = false
    @State private var showTextEditor = false
    @State private var toastMessage = ""
    @State private var shareItem: ShareItem?
    @State private var showPaywall = false
    @EnvironmentObject var subscriptionManager: SubscriptionManager


    @AppStorage("mustShowPaywall") private var mustShowPaywall = false
 
    @State private var recordTapCount = 0



    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Text Editor Area
                textEditorArea
                
                // Bottom Controls
                bottomControls
            }
            
            // History Sidebar
            if showHistory {
                HistoryView(
                    isShowing: $showHistory,
                    transcriptions: $manager.transcriptionHistory,
                    onSelect: { transcription in
                        manager.transcribedText = transcription.text
                        generateHaptic(.light)
                    },
                    onDelete: { transcription in
                        if let index = manager.transcriptionHistory.firstIndex(where: { $0.id == transcription.id }) {
                            manager.transcriptionHistory.remove(at: index)
                            manager.saveHistory()
                        }
                    },
                    onToggleFavorite: { transcription in
                        manager.toggleFavorite(transcription)
                    }
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
            
            // Advanced Text Editor
            if showTextEditor {
                AdvancedTextEditorView(
                    text: $manager.transcribedText,
                    isShowing: $showTextEditor,
                    onSave: {
                        manager.saveCurrentTranscription()
                        showToast("Saved successfully")
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
            
            // Toast
            if !toastMessage.isEmpty {
                toastView
            }
        }
        .alert(isPresented: $manager.showAlert) {
            Alert(
                title: Text("Error"),
                message: Text(manager.alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(item: $shareItem) { item in
            ActivityViewController(activityItems: item.items)
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            // Title - left
            Text("Transcribe")
                .font(.system(size: 28, weight: .bold))
                .lineLimit(1)
            
            Spacer()
            
            // PRO capsule - center
            Button(action: {
                generateHaptic(.light)
                
                // Only show paywall if user is NOT subscribed
                if !subscriptionManager.isSubscribed {
                    showPaywall = true
                } else {
                    print("User is already subscribed")
                    // Optionally: show a message or do nothing
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                    Text("PRO")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(radius: 1)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }

            
            Spacer()
            
            // Clock button - right
            Button(action: {
                generateHaptic(.light)

                if !subscriptionManager.isSubscribed {
                    showPaywall = true
                } else {
                    print("User is already subscribed")
                    withAnimation(.spring()) {
                        showHistory.toggle()
                    }
                }
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())

                    if !manager.transcriptionHistory.isEmpty {
                        Text("\(manager.transcriptionHistory.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 6, y: -2)
                    }
                }
            }


        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }



    private var textEditorArea: some View {
        ZStack(alignment: .topTrailing) {
            TextEditor(text: $manager.transcribedText)
                .font(.system(size: 17))
                .padding(16)
                .background(Color(.systemBackground))
                .disabled(manager.isRecording)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(manager.isRecording ? Color.red.opacity(0.3) : Color(.systemGray5), lineWidth: 2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            
            if manager.transcribedText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.blue.opacity(0.3))
                    
                    Text("Tap record to start")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    Text("Your transcription will appear here")
                        .font(.subheadline)
                        .foregroundColor(.gray.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
            
            // Word count badge
            if !manager.transcribedText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "text.word.spacing")
                        .font(.caption2)
                    Text("\(wordCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.blue)
                        .shadow(color: .blue.opacity(0.3), radius: 4)
                )
                .foregroundColor(.white)
                .padding(.trailing, 20)
                .padding(.top, 12)
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Record button
            Button(action: {
                generateHaptic(.medium)

                // 🚫 If user is locked & not subscribed → force paywall
                if mustShowPaywall && !subscriptionManager.isSubscribed {
                    showPaywall = true
                    return
                }

                // 👇 Count taps for NON-SUB users only
                if !subscriptionManager.isSubscribed {
                    recordTapCount += 1

                    if recordTapCount == 5 {
                        mustShowPaywall = true   // 🔒 persist lock
                        showPaywall = true
                        recordTapCount = 0
                        return
                    }
                }

                // 🎙 Existing logic (UNCHANGED)
                manager.toggleRecording()

                if manager.isRecording {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        pulseAnimation = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        pulseAnimation = false
                    }
                }

            }) {
                // 👇 UI UNCHANGED
                HStack(spacing: 16) {
                    Image(systemName: manager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .scaleEffect(manager.isRecording ? 1.1 : 1.0)
                        .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: manager.isRecording)

                    Text(manager.isRecording ? "Stop Recording" : "Start Recording")
                        .font(.system(size: 17, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(manager.isRecording ? Color.red.opacity(0.9) : Color.blue.opacity(0.9))
                )
            }
            .padding(.horizontal)


            
            // Action buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ActionButton(icon: "square.and.pencil", title: "Edit", color: .purple) {
                        generateHaptic(.light)
                        withAnimation(.spring()) { showTextEditor = true }
                    }
                    .disabled(manager.transcribedText.isEmpty)
                    
                    ActionButton(icon: "doc.on.doc", title: "Copy", color: .green) {
                        generateHaptic(.light)
                        UIPasteboard.general.string = manager.transcribedText
                        showToast("Copied to clipboard")
                    }
                    .disabled(manager.transcribedText.isEmpty)
                    
                    ActionButton(icon: "square.and.arrow.up", title: "Share", color: .blue) {
                        generateHaptic(.light)
                        
                        // Only show paywall if user is not subscribed
                        if !subscriptionManager.isSubscribed {
                            showPaywall = true
                        } else {
                            // User is subscribed — perform the normal action instead
                            shareText()
                        }
                    }
                    .disabled(manager.transcribedText.isEmpty)
                    .sheet(isPresented: $showPaywall) {
                        PaywallView()
                    }


                    
                    ActionButton(icon: "doc.text", title: "PDF", color: .orange) {
                        generateHaptic(.light)
                        
                        if subscriptionManager.isSubscribed {
                            // ✅ Subscribed: allow PDF export
                            exportAsPDF()
                        } else {
                            // 🚫 Not subscribed: show paywall
                            showPaywall = true
                        }
                    }
                    .disabled(manager.transcribedText.isEmpty)
                    
                    ActionButton(icon: "arrow.down.doc", title: "Save", color: .teal) {
                        generateHaptic(.light)
                        manager.saveCurrentTranscription()
                        showToast("Saved to history")
                    }
                    .disabled(manager.transcribedText.isEmpty)
                    
                    ActionButton(icon: "trash", title: "Clear", color: .red) {
                        generateHaptic(.medium)
                        withAnimation(.spring()) { manager.transcribedText = "" }
                    }
                    .disabled(manager.transcribedText.isEmpty)
                }
                .padding(.horizontal)
            }.sheet(isPresented: $showPaywall) {
                PaywallView(displayCloseButton: true)
                    .preferredColorScheme(.light)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture())
        }
        .padding(.vertical, 16)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.08), radius: 10, y: -5)
        )
    }
    
    private var toastView: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 20))
                Text(toastMessage)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
            )
            .padding(.top, 80)
            
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(3)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    toastMessage = ""
                }
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var wordCount: Int {
        manager.transcribedText.split { $0 == " " || $0.isNewline }.count
    }
    
    // MARK: - Helper Methods
    
    private func generateHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    private func showToast(_ message: String) {
        withAnimation {
            toastMessage = message
        }
    }
    
    private func shareText() {
        shareItem = ShareItem(items: [manager.transcribedText])
    }
    
    private func exportAsPDF() {
        let fileName = "VoiceNote_\(Date().formatted(date: .abbreviated, time: .shortened))"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        
        if let url = generateTranscriptionPDF(
            title: "Voice Transcription",
            subtitle: nil,
            text: manager.transcribedText,
            fileName: fileName
        ) {
            shareItem = ShareItem(items: [url])
        } else {
            showToast("Failed to generate PDF")
        }
    }
    
    func generateTranscriptionPDF(
        title: String = "Voice Transcription",
        subtitle: String? = nil,
        text: String,
        fileName: String = "Transcription.pdf"
    ) -> URL? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ No text to export")
            return nil
        }
        
        let safeFileName = fileName.replacingOccurrences(of: " ", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeFileName).pdf")
        
        let pageWidth: CGFloat = 595.2
        let pageHeight: CGFloat = 841.8
        let margin: CGFloat = 50
        let textWidth = pageWidth - 2 * margin
        
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        
        do {
            try renderer.writePDF(to: url) { context in
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 22),
                    .foregroundColor: UIColor.black
                ]
                let subtitleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: UIColor.darkGray
                ]
                let dateAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.gray
                ]
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 4
                
                let textAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13),
                    .paragraphStyle: paragraphStyle,
                    .foregroundColor: UIColor.black
                ]
                
                let dateString = Date().formatted(date: .long, time: .shortened)
                
                context.beginPage()
                
                // Header
                (title as NSString).draw(in: CGRect(x: margin, y: 50, width: textWidth, height: 30), withAttributes: titleAttrs)
                if let subtitle = subtitle {
                    (subtitle as NSString).draw(in: CGRect(x: margin, y: 80, width: textWidth, height: 20), withAttributes: subtitleAttrs)
                }
                (dateString as NSString).draw(in: CGRect(x: margin, y: 105, width: textWidth, height: 20), withAttributes: dateAttrs)
                
                // Divider
                UIColor.lightGray.setFill()
                UIRectFill(CGRect(x: margin, y: 130, width: textWidth, height: 1))
                
                // Content
                let contentRect = CGRect(x: margin, y: 150, width: textWidth, height: pageHeight - 200)
                (text as NSString).draw(in: contentRect, withAttributes: textAttrs)
                
                // Footer
                let footer = "Generated by Voice Notes"
                let footerStyle = NSMutableParagraphStyle()
                footerStyle.alignment = .center
                (footer as NSString).draw(in: CGRect(x: 0, y: pageHeight - 40, width: pageWidth, height: 20), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.gray,
                    .paragraphStyle: footerStyle
                ])
            }
            
            print("✅ PDF generated at \(url)")
            return url
            
        } catch {
            print("❌ Failed to generate PDF: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Share Item

struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Activity View Controller

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Advanced Text Editor

struct AdvancedTextEditorView: View {
    @Binding var text: String
    @Binding var isShowing: Bool
    let onSave: () -> Void
    
    @State private var undoStack: [String] = []
    @State private var redoStack: [String] = []
    @State private var fontSize: CGFloat = 17
    @State private var showStats = true
    @State private var textSelection: NSRange = NSRange(location: 0, length: 0)
    @FocusState private var isEditorFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation(.spring()) {
                        isShowing = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                        Text("Done")
                    }
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text("Editor")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    onSave()
                    withAnimation(.spring()) {
                        isShowing = false
                    }
                }) {
                    Text("Save")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
            
            // Formatting Toolbar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Undo/Redo
                    Group {
                        Button(action: undo) {
                            Image(systemName: "arrow.uturn.backward")
                                .foregroundColor(undoStack.isEmpty ? .gray : .blue)
                        }
                        .disabled(undoStack.isEmpty)
                        
                        Button(action: redo) {
                            Image(systemName: "arrow.uturn.forward")
                                .foregroundColor(redoStack.isEmpty ? .gray : .blue)
                        }
                        .disabled(redoStack.isEmpty)
                    }
                    .font(.system(size: 20))
                    .padding(.horizontal, 8)
                    
                    Divider().frame(height: 30)
                    
                    // Font Size
                    HStack(spacing: 8) {
                        Button(action: { adjustFontSize(-1) }) {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.blue)
                        }
                        
                        Text("\(Int(fontSize))pt")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 40)
                        
                        Button(action: { adjustFontSize(1) }) {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    Divider().frame(height: 30)
                    
                    // Text Formatting
                    FormatButton(icon: "list.bullet", label: "List") {
                        addPrefix("• ")
                    }
                    
                    FormatButton(icon: "textformat.abc", label: "Lower") {
                        transformText { $0.lowercased() }
                    }
                    
                    FormatButton(icon: "textformat.abc.dottedunderline", label: "Upper") {
                        transformText { $0.uppercased() }
                    }
                    
                    FormatButton(icon: "textformat.alt", label: "Title") {
                        transformText { $0.capitalized }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
            
            // Text Editor
            TextEditor(text: $text)
                .font(.system(size: fontSize))
                .padding()
                .focused($isEditorFocused)
                .onChange(of: text) { newValue in
                    if !newValue.isEmpty && (undoStack.isEmpty || undoStack.last != newValue) {
                        saveToUndoStack()
                    }
                }
            
            // Stats Bar
            if showStats {
                HStack(spacing: 20) {
                    StatLabel(icon: "text.word.spacing", value: "\(wordCount)", label: "words")
                    StatLabel(icon: "character", value: "\(characterCount)", label: "chars")
                    StatLabel(icon: "text.alignleft", value: "\(lineCount)", label: "lines")
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            showStats.toggle()
                        }
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            isEditorFocused = true
            undoStack = []
            redoStack = []
        }
    }
    
    // MARK: - Stats
    
    private var wordCount: Int {
        text.split { $0 == " " || $0.isNewline }.count
    }
    
    private var characterCount: Int {
        text.count
    }
    
    private var lineCount: Int {
        text.components(separatedBy: .newlines).count
    }
    
    // MARK: - Helper Methods
    
    private func saveToUndoStack() {
        undoStack.append(text)
        redoStack.removeAll()
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }
    
    private func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(text)
        text = undoStack.removeLast()
    }
    
    private func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(text)
        text = redoStack.removeLast()
    }
    
    private func adjustFontSize(_ delta: CGFloat) {
        fontSize = max(12, min(32, fontSize + delta))
    }
    
    private func addPrefix(_ prefix: String) {
        saveToUndoStack()
        let lines = text.components(separatedBy: .newlines)
        text = lines.map { prefix + $0 }.joined(separator: "\n")
    }
    
    private func transformText(_ transform: (String) -> String) {
        saveToUndoStack()
        text = transform(text)
    }
}

struct FormatButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(.blue)
            .frame(width: 60, height: 50)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

struct StatLabel: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - History View

struct HistoryView: View {
    @Binding var isShowing: Bool
    @Binding var transcriptions: [Transcription]
    let onSelect: (Transcription) -> Void
    let onDelete: (Transcription) -> Void
    let onToggleFavorite: (Transcription) -> Void
    
    @State private var filterFavorites = false
    @State private var searchQuery = ""
    
    var filteredTranscriptions: [Transcription] {
        var result = transcriptions
        
        if filterFavorites {
            result = result.filter { $0.isFavorite }
        }
        
        if !searchQuery.isEmpty {
            result = result.filter { $0.text.localizedCaseInsensitiveContains(searchQuery) || $0.title.localizedCaseInsensitiveContains(searchQuery) }
        }
        
        return result.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring()) {
                        isShowing = false
                    }
                }
            
            // Sidebar
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("History")
                            .font(.system(size: 26, weight: .bold))
                        Text("\(transcriptions.count) notes")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring()) {
                            isShowing = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                
                // Search & Filter
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search notes...", text: $searchQuery)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    Button(action: {
                        withAnimation {
                            filterFavorites.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: filterFavorites ? "star.fill" : "star")
                            Text(filterFavorites ? "All Notes" : "Favorites Only")
                                .font(.subheadline)
                        }
                        .foregroundColor(filterFavorites ? .yellow : .blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(filterFavorites ? Color.yellow.opacity(0.2) : Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                
                Divider()
                    .padding(.vertical, 8)
                
                // List
                if filteredTranscriptions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: filterFavorites ? "star.slash" : "tray")
                            .font(.system(size: 56))
                            .foregroundColor(.gray.opacity(0.3))
                        
                        Text(filterFavorites ? "No favorites yet" : "No notes yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        Text(filterFavorites ? "Star notes to save them here" : "Your transcriptions will appear here")
                            .font(.subheadline)
                            .foregroundColor(.gray.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredTranscriptions) { transcription in
                                HistoryItemCard(
                                    transcription: transcription,
                                    onSelect: {
                                        onSelect(transcription)
                                        withAnimation(.spring()) {
                                            isShowing = false
                                        }
                                    },
                                    onDelete: {
                                        withAnimation {
                                            onDelete(transcription)
                                        }
                                    },
                                    onToggleFavorite: {
                                        onToggleFavorite(transcription)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
            .frame(width: UIScreen.main.bounds.width * 0.85)
            .background(Color(.systemBackground))
        }
    }
}

struct HistoryItemCard: View {
    let transcription: Transcription
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    
    @State private var showFullText = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transcription.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    
                    Text(transcription.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button(action: onToggleFavorite) {
                    Image(systemName: transcription.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 20))
                        .foregroundColor(transcription.isFavorite ? .yellow : .gray)
                }
            }
            
            // Content Preview
            Text(transcription.text)
                .font(.system(size: 14))
                .lineLimit(showFullText ? nil : 3)
                .foregroundColor(.primary)
            
            // Tags
            if !transcription.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(transcription.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                        }
                    }
                }
            }
            
            // Footer
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "text.word.spacing")
                        .font(.caption2)
                    Text("\(transcription.text.split { $0 == " " || $0.isNewline }.count)")
                        .font(.caption)
                }
                .foregroundColor(.gray)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: {
                        withAnimation {
                            showFullText.toggle()
                        }
                    }) {
                        Text(showFullText ? "Less" : "More")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: onSelect) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Use")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    }
                    
                    Button(action: { showDeleteAlert = true }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .alert("Delete Note", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this transcription?")
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isEnabled ? color : .gray)
            .frame(width: 80, height: 70)
            .background(isEnabled ? color.opacity(0.12) : Color(.systemGray6))
            .cornerRadius(14)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .pressEvents {
            if isEnabled {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = true
                }
            }
        } onRelease: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = false
            }
        }
    }
}

// MARK: - Press Events Modifier

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEventModifier(onPress: onPress, onRelease: onRelease))
    }
}

struct PressEventModifier: ViewModifier {
    let onPress: () -> Void
    let onRelease: () -> Void
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded { _ in onRelease() }
            )
    }
}

// MARK: - Speech Recognition Manager

final class SpeechRecognitionManager: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var transcriptionHistory: [Transcription] = []

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recordingTimeoutTimer: Timer?
    private var isUserInitiatedStop = false
    private var audioSessionConfigured = false

    // MARK: - Init
    
    init(locale: String = "en-US") {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            DispatchQueue.main.async {
                self.showAlert(message: "Speech recognition is not supported on this device.")
            }
            return
        }
        
        requestPermissions()
        loadHistory()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Permissions
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    break
                case .denied:
                    self.showAlert(message: "Speech recognition access denied. Please enable it in Settings.")
                case .restricted:
                    self.showAlert(message: "Speech recognition is restricted on this device.")
                case .notDetermined:
                    break
                @unknown default:
                    break
                }
            }
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if !granted {
                    self.showAlert(message: "Microphone access denied. Please enable it in Settings.")
                }
            }
        }
    }

    // MARK: - Recording Control
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            showAlert(message: "Speech recognition service is currently unavailable.")
            return
        }
        
        // Check permissions before starting
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        guard authStatus == .authorized else {
            showAlert(message: "Please enable speech recognition in Settings.")
            return
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        do {
            try configureAudioSession()
            resetRecognition()
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                showAlert(message: "Unable to start recognition request.")
                return
            }

            recognitionRequest.shouldReportPartialResults = true
            
            // Add timeout for request
            if #available(iOS 13, *) {
                recognitionRequest.requiresOnDeviceRecognition = false
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            // Ensure previous taps are removed
            inputNode.removeTap(onBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                var isFinal = false
                
                if let result = result {
                    DispatchQueue.main.async {
                        self.transcribedText = result.bestTranscription.formattedString
                    }
                    isFinal = result.isFinal
                    self.resetTimeoutTimer()
                }

                if error != nil || isFinal {
                    DispatchQueue.main.async {
                        if !self.isUserInitiatedStop && error != nil {
                            // Only show error if it's not a user-initiated stop
                            if let nsError = error as NSError?, nsError.code != 216 { // 216 is cancelled
                                self.handleRecognitionError(error!)
                            }
                        }
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            audioSessionConfigured = true
            resetTimeoutTimer()

        } catch {
            handleAudioSessionError(error)
        }
    }

    private func stopRecording(save: Bool = true) {
        recordingTimeoutTimer?.invalidate()
        recordingTimeoutTimer = nil
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        // Set flag BEFORE canceling to prevent error alert
        isUserInitiatedStop = true
        
        // Stop audio engine safely
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Tell the recognition request that no more audio will come
        recognitionRequest?.endAudio()
        
        // ❌ DO NOT cancel recognitionTask — this clears partial text
        // recognitionTask?.cancel()  ← remove this line entirely

        // ✅ Instead, finish gracefully and keep the last recognized text
        recognitionTask = nil
        recognitionRequest = nil
        
        // Deactivate audio session
        if audioSessionConfigured {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                audioSessionConfigured = false
            } catch {
                print("Failed to deactivate audio session: \(error)")
            }
        }
        
        isRecording = false
        
        // Reset flag after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isUserInitiatedStop = false
        }
    }

    
    private func cleanup() {
        recordingTimeoutTimer?.invalidate()
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        
        if audioSessionConfigured {
            try? AVAudioSession.sharedInstance().setActive(false)
            audioSessionConfigured = false
        }
    }

    // MARK: - Public Methods
    
    func saveCurrentTranscription() {
        guard !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let transcription = Transcription(text: transcribedText, date: Date())
        transcriptionHistory.append(transcription)
        saveHistory()
    }
    
    func toggleFavorite(_ transcription: Transcription) {
        if let index = transcriptionHistory.firstIndex(where: { $0.id == transcription.id }) {
            transcriptionHistory[index].isFavorite.toggle()
            saveHistory()
        }
    }

    // MARK: - Helpers
    
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func resetRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func resetTimeoutTimer() {
        recordingTimeoutTimer?.invalidate()
        recordingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard !self.isUserInitiatedStop else { return }
                self.showAlert(message: "Recording stopped due to inactivity.")
                self.stopRecording(save: false)
            }
        }
    }

    private func handleRecognitionError(_ error: Error) {
        guard !isUserInitiatedStop else {
            isUserInitiatedStop = false
            return
        }

        DispatchQueue.main.async {
            let nsError = error as NSError
            if nsError.code != 216 { // Ignore cancellation errors
                self.showAlert(message: "Recognition error: \(error.localizedDescription)")
            }
            self.stopRecording(save: false)
        }
    }

    private func handleAudioSessionError(_ error: Error) {
        DispatchQueue.main.async {
            self.showAlert(message: "Audio session error: \(error.localizedDescription)")
            self.isRecording = false
        }
    }

    // MARK: - Persistence
    
    func saveHistory() {
        do {
            let data = try JSONEncoder().encode(transcriptionHistory)
            UserDefaults.standard.set(data, forKey: "transcriptionHistory")
        } catch {
            print("Error saving history: \(error)")
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "transcriptionHistory") else { return }
        do {
            transcriptionHistory = try JSONDecoder().decode([Transcription].self, from: data)
        } catch {
            print("Error loading history: \(error)")
            transcriptionHistory = []
        }
    }

    private func showAlert(message: String) {
        DispatchQueue.main.async {
            self.alertMessage = message
            self.showAlert = true
        }
    }
}
