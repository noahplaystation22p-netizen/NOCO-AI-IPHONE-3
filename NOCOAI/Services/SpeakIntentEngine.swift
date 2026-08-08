import Foundation

/// Style / quality hints extracted from natural speech.
struct SpeakStyleHints: Equatable {
    var preferThink = false
    var shorter = false
    var longer = false
    var creative = false
    var professional = false
    var highQuality = false

    var prefersDepth: Bool { preferThink || highQuality || creative || longer }
}

/// What NOCO Speak understood and wants to do.
enum SpeakActionKind: Equatable {
    case conversation(depth: AIMode)
    case createImage(prompt: String)
    case runAgent(goal: String)
    case visionAnalyze
    case magicEraser
    case summarize
    case screenMemory
    case endSpeak
}

struct SpeakIntent: Equatable {
    var action: SpeakActionKind
    var style: SpeakStyleHints
    var confidence: Double
    /// When true, conversation path forces Live Knowledge web context.
    var useLiveKnowledge: Bool = false

    var needsToolAccess: Bool {
        switch action {
        case .createImage, .runAgent, .magicEraser: return true
        default: return false
        }
    }

    var confirmationQuestion: String {
        switch action {
        case .createImage:
            return "Ich würde den Bildgenerator starten. Soll ich starten?"
        case .runAgent:
            return "Ich würde den Agent starten und die Aufgabe planen. Soll ich starten?"
        case .magicEraser:
            return "Ich würde den Magischen Radierer öffnen. Soll ich starten?"
        case .visionAnalyze:
            return "Ich würde das Bild jetzt analysieren. Soll ich starten?"
        case .summarize:
            return "Ich würde eine Zusammenfassung erstellen. Soll ich starten?"
        default:
            return "Soll ich fortfahren?"
        }
    }

    var spokenAck: String {
        if useLiveKnowledge, case .conversation = action {
            return SpeakIntentEngine.randomWebAck()
        }
        switch action {
        case .createImage: return "Alles klar — ich erstelle das Bild."
        case .runAgent: return "Gut — ich plane die Aufgabe und arbeite sie ab."
        case .magicEraser: return "Okay — ich öffne den Magischen Radierer."
        case .visionAnalyze: return "Einen Moment — ich schaue mir das an."
        case .summarize: return "Ich fasse das zusammen."
        case .conversation(let depth):
            return depth == .think ? "Ich denke kurz gründlicher nach." : ""
        case .screenMemory: return ""
        case .endSpeak: return "Alles klar, Voice AI beendet."
        }
    }

    var statusLine: String {
        if useLiveKnowledge, case .conversation = action {
            return "NOCO sucht im Internet…"
        }
        switch action {
        case .createImage: return "NOCO erstellt dein Bild…"
        case .runAgent: return "NOCO arbeitet…"
        case .magicEraser: return "Magischer Radierer…"
        case .visionAnalyze: return "NOCO sieht…"
        case .summarize: return "Zusammenfassen…"
        case .conversation:
            return "NOCO denkt…"
        case .screenMemory: return "Erinnerung…"
        case .endSpeak: return "Voice AI beendet"
        }
    }

    var islandTitle: String {
        if useLiveKnowledge, case .conversation = action {
            return SpeakActivityPhase.webSearch.title
        }
        switch action {
        case .createImage: return SpeakActivityPhase.creatingImage.title
        case .runAgent: return SpeakActivityPhase.agentWorking.title
        case .magicEraser: return "Magischer Radierer"
        case .visionAnalyze: return SpeakActivityPhase.vision.title
        case .summarize: return "Zusammenfassung"
        case .conversation:
            return SpeakActivityPhase.thinking.title
        case .screenMemory: return "Erinnert sich"
        case .endSpeak: return "Voice AI beendet"
        }
    }
}

/// Assistant-facing Island / UI phase (richer than raw mic phase).
enum SpeakAssistantPhase: String, Equatable {
    case idle
    case listening
    case thinking
    case webSearch
    case creatingImage
    case agentWorking
    case vision
    case awaitingConfirm
    case speaking
    case error

    var activityPhase: SpeakActivityPhase {
        switch self {
        case .idle: return .idle
        case .listening: return .listening
        case .thinking: return .thinking
        case .webSearch: return .webSearch
        case .creatingImage: return .creatingImage
        case .agentWorking: return .agentWorking
        case .vision: return .vision
        case .awaitingConfirm: return .awaitingConfirm
        case .speaking: return .speaking
        case .error: return .error
        }
    }
}

enum SpeakFullAccess {
    static let defaultsKey = "nocoai.speakFullAccess"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}

/// Natural-language intent engine for NOCO Speak.
enum SpeakIntentEngine {
    static func classify(
        _ text: String,
        cameraOn: Bool,
        screenShareOn: Bool,
        hasPendingFrame: Bool,
        lastAssistantHadImage: Bool = false
    ) -> SpeakIntent {
        let t = normalize(text)
        var style = extractStyle(from: t)

        if isEndSpeak(t) {
            return SpeakIntent(action: .endSpeak, style: style, confidence: 0.95)
        }
        if isScreenMemory(t) {
            return SpeakIntent(action: .screenMemory, style: style, confidence: 0.9)
        }
        if let prompt = imagePrompt(from: t) {
            if style.highQuality || style.preferThink { style.preferThink = true }
            return SpeakIntent(action: .createImage(prompt: prompt), style: style, confidence: 0.92)
        }
        // Context: "mach das schöner" after an image → eraser / image polish.
        if matches(t, #"\b(mach(e)? (das|es) sch[oö]ner|versch[oö]ner|verbesser(e)? (das|es) bild|polier)\b"#) {
            if lastAssistantHadImage || hasPendingFrame {
                return SpeakIntent(action: .magicEraser, style: style, confidence: 0.8)
            }
            style.professional = true
            style.preferThink = true
            return SpeakIntent(action: .conversation(depth: .think), style: style, confidence: 0.75)
        }
        if isMagicEraser(t) {
            return SpeakIntent(action: .magicEraser, style: style, confidence: 0.9)
        }
        if isAgent(t) {
            return SpeakIntent(action: .runAgent(goal: text.trimmingCharacters(in: .whitespacesAndNewlines)), style: style, confidence: 0.88)
        }
        if isSummarize(t) {
            return SpeakIntent(action: .summarize, style: style, confidence: 0.9)
        }

        let visionCue = isVision(t)
        let hasEyes = cameraOn || screenShareOn || hasPendingFrame
        if visionCue && hasEyes {
            return SpeakIntent(action: .visionAnalyze, style: style, confidence: 0.9)
        }
        if visionCue && !hasEyes {
            // Still route to vision intent — session will ask for camera/frame.
            return SpeakIntent(action: .visionAnalyze, style: style, confidence: 0.75)
        }

        let depth: AIMode = style.prefersDepth ? .think : .flash
        let speakPolicy = SpeakLiveKnowledgePolicy.current
        let needsWeb =
            speakPolicy == .web
            || (speakPolicy == .auto && LiveKnowledgeRouting.likelyNeedsWeb(text))
            || matches(t, #"\b(schau(e)? nach|recherchier|im (internet|web)|aktuell(e|er|es)?|was gibt.?s neues|wer hat gewonnen)\b"#)
        return SpeakIntent(
            action: .conversation(depth: depth),
            style: style,
            confidence: 0.7,
            useLiveKnowledge: needsWeb && speakPolicy != .local
        )
    }

    static func randomWebAck() -> String {
        [
            "Ich schaue kurz nach.",
            "Ich prüfe das gerade.",
            "Einen Moment — ich hole aktuelle Infos."
        ].randomElement() ?? "Ich schaue kurz nach."
    }

    static func isAffirmation(_ text: String) -> Bool {
        let t = normalize(text)
        if t.count > 48 { return false }
        let hits = [
            "ja", "jap", "jo", "yes", "ok", "okay", "mach", "mach das", "mach es",
            "starten", "start", "los", "bitte", "klar", "gerne", "einverstanden",
            "natürlich", "sicher", "auf geht", "leg los", "tu das", "ja bitte", "mach mal"
        ]
        return hits.contains(where: { t == $0 || t.hasPrefix($0 + " ") || t.contains(" " + $0) })
            || t.range(of: #"^(ja|ok|okay|mach|starten|los)\b"#, options: .regularExpression) != nil
    }

    static func isDenial(_ text: String) -> Bool {
        let t = normalize(text)
        if t.count > 48 { return false }
        let hits = [
            "nein", "nö", "nee", "abbrechen", "stopp", "stop", "nicht", "lieber nicht",
            "nein danke", "kein", "lass", "vergiss", "cancel"
        ]
        return hits.contains(where: { t == $0 || t.hasPrefix($0 + " ") })
            || t.range(of: #"^(nein|stopp|stop|abbrechen)\b"#, options: .regularExpression) != nil
    }

    // MARK: - Detectors

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractStyle(from t: String) -> SpeakStyleHints {
        var s = SpeakStyleHints()
        if matches(t, #"\b(mach dir (richtig )?muhe|sei grundlich|denk (richtig |mal )?nach|think|hohe qualitat|beste qualitat|richtig gut|gib gas beim denken)\b"#) {
            s.preferThink = true
            s.highQuality = true
        }
        if matches(t, #"\b(sei kreativ|kreativ|uberraschend|originell)\b"#) {
            s.creative = true
            s.preferThink = true
        }
        if matches(t, #"\b(erklar(e)? (mir )?(das )?genauer|ausfuhrlicher|mehr details|genauer)\b"#) {
            s.longer = true
            s.preferThink = true
        }
        if matches(t, #"\b(mach (mal )?schneller|kurz(er)?|knapp|tl;dr|in einem satz)\b"#) {
            s.shorter = true
        }
        if matches(t, #"\b(professionell|formell|serio|geschaftlich|offiziell)\b"#) {
            s.professional = true
        }
        return s
    }

    private static func imagePrompt(from t: String) -> String? {
        let patterns = [
            #"^(mach|erstell|generier|zeichn|mal)(e|en)?\s+(mir\s+)?(ein|eine|einen)?\s*(bild|foto|illustration|render|visual)"#,
            #"\b(bild|foto|illustration)\s+(von|mit|aus)\b"#,
            #"\b(generiere|erzeuge)\s+(ein|eine|einen)?\s*(bild|foto)"#,
            #"\bcyberpunk\b.*\b(bild|porsche|auto|stadt)\b"#,
            #"\b(porsche|auto|landschaft|portrait|logo)\b.*\b(bild|generier|erstell|zeichn)\b"#
        ]
        guard patterns.contains(where: { matches(t, $0) }) else { return nil }
        // Strip command scaffolding for a cleaner SD/chat image prompt.
        var prompt = t
        let strip = [
            #"^(mach|erstell|generier|zeichn|mal)(e|en)?\s+(mir\s+)?"#,
            #"\b(bitte|mal|doch)\b"#
        ]
        for p in strip {
            prompt = prompt.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty { prompt = t }
        // Capitalize naturally for German image compose
        if let first = prompt.first {
            prompt = String(first).uppercased() + prompt.dropFirst()
        }
        if !prompt.lowercased().hasPrefix("erstelle") && !prompt.lowercased().hasPrefix("mach") {
            prompt = "Erstelle ein Bild: \(prompt)"
        }
        return prompt
    }

    private static func isMagicEraser(_ t: String) -> Bool {
        matches(t, #"\b(entferne|losch|radiere|weg\s*damit)\b.*\b(gegenstand|objekt|ding|person|auto|baum|text|logo|hintergrund|rechts|links|mitte)\b"#)
            || matches(t, #"\bmagischer radierer\b"#)
            || matches(t, #"\b(entferne|radiere)\s+(das|den|die)\b"#)
            || matches(t, #"\baus dem bild (entfernen|loschen|radieren)\b"#)
    }

    private static func isAgent(_ t: String) -> Bool {
        matches(t, #"\b(plane|plan|erledige|organisier|automatisier|workflow|mehrere schritte|tag(es)?plan|tagesplan|to-?do|checkliste|recherchiere und|bau(e)? mir|richt(e)? ein)\b"#)
            || matches(t, #"\b(als agent|agent modus|ubernehme das|kummere dich darum)\b"#)
    }

    private static func isSummarize(_ t: String) -> Bool {
        matches(t, #"\b(zusammenfassung|fass(e)?\s+(das|es|mir)?\s*zusammen|summar(y|ize)|kurzfassung|auf den punkt)\b"#)
    }

    private static func isVision(_ t: String) -> Bool {
        matches(t, #"\b(was sehe ich|was siehst du|was ist das|was soll ich|wo tippe|wo klicke|schau(e)? mal|erkenne|beschreib(e)?.*(bild|foto|das)|analysiere.*(bild|foto|das|bildschirm)|sieh(e)? (dir|mal)|kamera|bildschirm|screen|fenster|fehlermeldung|was ist hier)\b"#)
    }

    private static func isScreenMemory(_ t: String) -> Bool {
        matches(t, #"\b(was war|nochmal.*(bildschirm|screen)|vorher.*(bildschirm|fenster)|erinnerst du|was stand|was war auf)\b"#)
    }

    private static func isEndSpeak(_ t: String) -> Bool {
        if t.contains("bedeutet") || t.contains("heisst") || t.contains("erklare") || t.contains("erkläre") {
            return false
        }
        if t.count > 72 { return false }
        let phrases = [
            "sprachmodus verlassen", "sprachmodus beenden", "sprachmodus deaktivieren",
            "beende sprachmodus", "stopp sprachmodus", "deaktiviere sprachmodus",
            "speak verlassen", "speak beenden", "end speak", "stop speak", "exit speak",
            "voice verlassen", "voice beenden", "stop voice", "exit voice", "voice ai verlassen",
            "voice ai beenden", "stop voice ai", "noco verlassen", "noco beenden",
            "nocospeak beenden", "noco speak beenden", "nocospeak verlassen",
            "zuruck zum chat", "zurück zum chat", "back to chat",
            "assistent beenden", "modus verlassen", "beenden",
            // Farewells end Speak (bye / goodbye / tschüss …)
            "goodbye", "good bye", "bye bye", "see you", "see ya",
            "tschuss", "tschüss", "tschau", "ciao", "auf wiedersehen",
            "auf wiederhoeren", "auf wiederhören", "machs gut", "mach's gut",
            "bis bald", "bis dann", "bis spater", "bis später"
        ]
        if phrases.contains(where: { t.contains($0) }) { return true }
        // Exact short stops / farewells only
        return [
            "stopp", "stop", "ende", "exit", "fertig",
            "bye", "goodbye", "tschuss", "tschüss", "tschau", "ciao"
        ].contains(t)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
