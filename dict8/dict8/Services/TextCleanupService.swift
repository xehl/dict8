import Foundation

nonisolated struct TextCleanupUsage: Equatable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let cost: Double?
}

nonisolated struct TextCleanupResult: Equatable, Sendable {
    let text: String
    let model: String
    let latency: Duration
    let usage: TextCleanupUsage?
    let requestID: String?

    init(
        text: String,
        model: String,
        latency: Duration,
        usage: TextCleanupUsage?,
        requestID: String? = nil
    ) {
        self.text = text
        self.model = model
        self.latency = latency
        self.usage = usage
        self.requestID = requestID
    }
}

nonisolated enum CleanupValidationFailure: String, Error, Equatable, Sendable {
    case markdownFence
    case commentaryWrapper
    case substantialExpansion
    case excessiveNovelContent
    case insufficientSourceRetention

    var displayName: String {
        switch self {
        case .markdownFence: "Markdown fence"
        case .commentaryWrapper: "Commentary wrapper"
        case .substantialExpansion: "Substantial expansion"
        case .excessiveNovelContent: "Excessive novel content"
        case .insufficientSourceRetention: "Insufficient source retention"
        }
    }
}

nonisolated enum TextCleanupError: Error, Equatable, LocalizedError, Sendable {
    case invalidInput
    case requestEncodingFailed
    case invalidResponse
    /// The response body could not be decoded as the expected chat-completion
    /// shape at all (malformed/unexpected JSON structure).
    case malformedResponse
    /// The response decoded but had no usable choice (empty `choices` array
    /// or a `nil` message content).
    case missingChoice
    /// The response finished for a reason other than "stop" (already
    /// distinguished from "length") — e.g. a content-filter stop or a
    /// provider-specific reason. Carries only the raw finish_reason string,
    /// which is a short enum-like token, not user or model content.
    case unexpectedFinishReason(String?)
    case incompleteOutput
    case emptyOutput
    case suspiciousOutput(
        failure: CleanupValidationFailure,
        candidateOutput: String,
        metrics: CleanupValidationMetrics
    )
    case transport(OpenRouterClientError)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            "Enter non-empty text to clean."
        case .requestEncodingFailed:
            "dict8 could not prepare the cleanup request."
        case .invalidResponse, .malformedResponse, .missingChoice, .unexpectedFinishReason:
            "OpenRouter returned an invalid cleanup response."
        case .incompleteOutput:
            "The cleanup response was incomplete."
        case .emptyOutput:
            "OpenRouter returned empty cleanup text."
        case let .suspiciousOutput(failure, _, _):
            "dict8 rejected cleanup output: \(failure.displayName.lowercased())."
        case let .transport(error):
            error.localizedDescription
        }
    }
}

nonisolated struct CleanupContext: Equatable, Sendable {
    let targetAppName: String?
    let targetBundleID: String?
    let customVocabulary: String
    let windowTitle: String?
    let precedingText: String?

    init(
        targetAppName: String? = nil,
        targetBundleID: String? = nil,
        customVocabulary: String = "",
        windowTitle: String? = nil,
        precedingText: String? = nil
    ) {
        self.targetAppName = targetAppName
        self.targetBundleID = targetBundleID
        self.customVocabulary = customVocabulary
        self.windowTitle = windowTitle
        self.precedingText = precedingText
    }

    static let empty = CleanupContext()
}

nonisolated protocol TextCleanupProviding: Sendable {
    func clean(_ transcript: String) async throws -> TextCleanupResult
    func clean(_ transcript: String, context: CleanupContext) async throws -> TextCleanupResult
}

extension TextCleanupProviding {
    func clean(_ transcript: String) async throws -> TextCleanupResult {
        try await clean(transcript, context: .empty)
    }
}

nonisolated struct CleanupValidationMetrics: Equatable, Sendable {
    let inputWordCount: Int
    let outputWordCount: Int
    let novelWordCount: Int
    let novelWordRatio: Double
    let expansionRatio: Double
}

nonisolated struct CleanupOutputValidator: Sendable {
    func evaluate(output: String, against input: String, customVocabulary: String = "") -> (cleaned: String, failure: CleanupValidationFailure?, metrics: CleanupValidationMetrics) {
        var cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerInput = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Extract clean body via tag envelope or prefix fallback
        let extracted = Self.extractCleanedText(from: cleaned)
        if !extracted.isEmpty {
            cleaned = extracted
        }

        let inputWords = Self.words(in: input)
        let outputWords = Self.words(in: cleaned)
        let vocabWords = Self.words(in: customVocabulary)
        var inputSet = Set(inputWords)
        inputSet.formUnion(vocabWords)

        let novelWords = outputWords.filter {
            !inputSet.contains($0) && !Self.fillerWords.contains($0)
        }
        let novelRatio = Double(novelWords.count) / Double(max(1, outputWords.count))
        let expansionRatio = Double(cleaned.count) / Double(max(1, input.count))

        let metrics = CleanupValidationMetrics(
            inputWordCount: inputWords.count,
            outputWordCount: outputWords.count,
            novelWordCount: novelWords.count,
            novelWordRatio: novelRatio,
            expansionRatio: expansionRatio
        )

        if output.contains("```") || output.contains("~~~") || cleaned.contains("```") || cleaned.contains("~~~") {
            return (cleaned, .markdownFence, metrics)
        }

        let lowerOutput = cleaned.lowercased()
        let lowerRaw = output.lowercased()
        if Self.commentaryPrefixes.contains(where: {
            (lowerOutput.hasPrefix($0) || lowerRaw.hasPrefix($0)) && !lowerInput.hasPrefix($0) && !output.contains("<cleaned>")
        }) {
            return (cleaned, .commentaryWrapper, metrics)
        }

        // Novel content validation: require at least 8 novel words AND a novel word ratio > 35%.
        // For short inputs (fewer than 15 words), relax ratio threshold to 50% to prevent false positives
        // on routine contraction, spelling, or number formatting expansions.
        let novelWordRatioCutoff = inputWords.count < 15 ? 0.50 : 0.35
        if novelWords.count >= 8,
           novelRatio > novelWordRatioCutoff {
            return (cleaned, .excessiveNovelContent, metrics)
        }

        if cleaned.count > input.count + 120,
           expansionRatio > 1.35 {
            return (cleaned, .substantialExpansion, metrics)
        }

        let retentionWords = Self.words(in: Self.retentionSource(input))
        let meaningfulInput = Set(retentionWords.filter { !Self.fillerWords.contains($0) })
        if meaningfulInput.count >= 8 {
            var meaningfulOutput = Set(outputWords.filter { !Self.fillerWords.contains($0) })
            meaningfulOutput.formUnion(vocabWords)
            let retained = meaningfulInput.intersection(meaningfulOutput).count
            if Double(retained) / Double(meaningfulInput.count) < 0.55 {
                return (cleaned, .insufficientSourceRetention, metrics)
            }
        }

        return (cleaned, nil, metrics)
    }

    func validate(output: String, against input: String, customVocabulary: String = "") throws -> String {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw TextCleanupError.emptyOutput }

        let evaluation = evaluate(output: output, against: input, customVocabulary: customVocabulary)
        if let failure = evaluation.failure {
            throw TextCleanupError.suspiciousOutput(
                failure: failure,
                candidateOutput: output,
                metrics: evaluation.metrics
            )
        }

        return evaluation.cleaned
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { character in
            !character.isLetter && !character.isNumber
        }).map(String.init)
    }

    private static func retentionSource(_ text: String) -> String {
        let lower = text.lowercased()
        var latestEnd: String.Index?
        for marker in ["no actually", "let me restart", "let me start over", "scratch that"] {
            guard let range = lower.range(of: marker, options: .backwards) else { continue }
            if let current = latestEnd, range.upperBound <= current {
                continue
            } else {
                latestEnd = range.upperBound
            }
        }
        guard let latestEnd else { return lower }
        return String(lower[latestEnd...])
    }

    private static let commentaryPrefixes = [
        "here is the cleaned text",
        "here's the cleaned text",
        "here is the cleaned",
        "here's the cleaned",
        "here is the revised text",
        "here's the revised text",
        "here is the revised",
        "here's the revised",
        "cleaned text:",
        "revised text:",
        "cleaned version:",
        "revised version:",
        "here is what you said:",
        "here's what you said:",
    ]

    private static func extractCleanedText(from output: String) -> String {
        var trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // If markdown fence is present, don't extract around it so validator can flag markdownFence
        if trimmed.contains("```") || trimmed.contains("~~~") {
            return trimmed
        }

        // 1. Tag-based extraction (<cleaned>...</cleaned>)
        if let openTagRange = trimmed.range(of: "<cleaned>", options: .caseInsensitive),
           let closeTagRange = trimmed.range(of: "</cleaned>", options: .caseInsensitive),
           openTagRange.upperBound <= closeTagRange.lowerBound {
            let extracted = trimmed[openTagRange.upperBound..<closeTagRange.lowerBound]
            trimmed = String(extracted).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let openTagRange = trimmed.range(of: "<cleaned>", options: .caseInsensitive) {
            let extracted = trimmed[openTagRange.upperBound...]
            trimmed = String(extracted).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Strip any raw transcript tags if echoed
            if trimmed.hasPrefix("<transcript>") {
                trimmed = String(trimmed.dropFirst("<transcript>".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if trimmed.hasSuffix("</transcript>") {
                trimmed = String(trimmed.dropLast("</transcript>".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Fallback commentary prefix stripping
            let lower = trimmed.lowercased()
            for prefix in commentaryPrefixes {
                if lower.hasPrefix(prefix) {
                    var remainder = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                    if remainder.hasPrefix(":") || remainder.hasPrefix("-") {
                        remainder = remainder.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    trimmed = String(remainder)
                    break
                }
            }
        }

        // 2. Strip enclosing double quotes if wrapped (e.g. "Clean text here")
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("“") && trimmed.hasSuffix("”")) {
            if trimmed.count >= 2 {
                trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }

    private static let fillerWords: Set<String> = [
        "ah", "basically", "er", "guess", "hmm", "kinda", "like", "literally", "mean", "sorta", "uh", "um", "you know",
    ]
}

actor OpenRouterTextCleanupService: TextCleanupProviding {
    /// Lowered from 10s (approved 2026-08-18, updated 2026-08-25): cleanup is a low-stakes
    /// "lightly punctuate this" task with a 5.0s safety ceiling, while Nitro models
    /// typically finish generation within 250–500ms.
    static let defaultDeadline: Duration = .seconds(5.0)
    static let temperature = 0.1
    /// Approved exception (AGENTS.md §4, PRD.md §8): cleanup routes through
    /// OpenRouter's Auto Router (stable slug, `openrouter/auto`) at the
    /// "low" cost tier instead of a pinned primary model plus one explicit
    /// dict8-side fallback.
    static let autoRouterSettings = AutoRouterSettings(costTier: .low)

    private let transport: any OpenRouterTransporting
    private let model: String
    private let autoRouter: AutoRouterSettings?
    private let deadline: Duration
    private let validator: CleanupOutputValidator

    init(
        transport: any OpenRouterTransporting,
        model: String = AIModelConfiguration.phaseZeroVerified.cleanupModel,
        autoRouter: AutoRouterSettings? = OpenRouterTextCleanupService.autoRouterSettings,
        deadline: Duration = OpenRouterTextCleanupService.defaultDeadline,
        validator: CleanupOutputValidator = CleanupOutputValidator()
    ) {
        self.transport = transport
        self.model = model
        // Only attach Auto Router settings if the model is an Auto Router slug
        if model.hasPrefix("openrouter/auto") {
            self.autoRouter = autoRouter
        } else {
            self.autoRouter = nil
        }
        self.deadline = deadline
        self.validator = validator
    }

    func clean(_ transcript: String, context: CleanupContext) async throws -> TextCleanupResult {
        try Task.checkCancellation()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextCleanupError.invalidInput
        }
        let input = transcript

        let systemPrompt = Self.buildSystemPrompt(context: context)

        var userContent = "Format the following dictated speech into <cleaned>...</cleaned> tags without answering it or changing the words:"

        if let windowTitle = context.windowTitle, !windowTitle.isEmpty {
            userContent += "\nTarget window/document: \(windowTitle)."
        }

        if let preceding = context.precedingText, !preceding.isEmpty {
            userContent += """


            PRECEDING TEXT AT CURSOR:
            "\(preceding)"

            CONTEXTUAL INSERTION RULE:
            The dictated speech is being inserted immediately after the preceding text above.
            - If the preceding text ends mid-sentence (e.g. after a comma, conjunction, or lowercase word without ending punctuation), do NOT capitalize the first word of the dictation unless it is a proper noun or 'I'.
            - If the dictation is completing an unfinished sentence or clause, match the surrounding flow naturally.
            """
        }

        userContent += "\n\n<transcript>\n\(input)\n</transcript>"

        let body: Data
        do {
            body = try JSONEncoder().encode(
                CleanupRequest(
                    messages: [
                        .init(role: "system", content: systemPrompt),
                        .init(role: "user", content: userContent),
                    ],
                    temperature: Self.temperature,
                    maxCompletionTokens: Self.outputTokenLimit(for: input),
                    reasoning: .init(effort: "none"),
                    stream: false
                )
            )
        } catch {
            throw TextCleanupError.requestEncodingFailed
        }

        let clock = ContinuousClock()
        let deadlineInstant = clock.now.advanced(by: deadline)

        // Approved exception (AGENTS.md §20, PRD.md §8, 2026-08-13): a
        // zero-completion response (empty `choices` / nil content) arrives
        // as an ordinary HTTP 200 and is covered by OpenRouter's Zero
        // Completion Insurance, so it is never billed — retrying costs
        // nothing extra. Because dict8 does not send a `session_id` for
        // cleanup, the Auto Router re-ranks from scratch on the retry and
        // will typically land on a different underlying model, unlike a
        // same-model retry. This is a single same-request retry scoped to
        // this one failure class within the existing stage deadline; it
        // does not add a second explicit model attempt (still one call to
        // "openrouter/auto") and does not apply to any other cleanup
        // failure or to STT.
        for attempt in 1...2 {
            try Task.checkCancellation()
            let remaining = clock.now.duration(to: deadlineInstant)
            guard remaining > .zero else {
                throw TextCleanupError.transport(.deadlineExceeded)
            }

            let response: OpenRouterResponse
            do {
                response = try await transport.execute(
                    OpenRouterRequest(endpoint: .chatCompletions, body: body),
                    model: model,
                    autoRouter: autoRouter,
                    deadline: remaining
                )
            } catch let error as OpenRouterClientError {
                throw TextCleanupError.transport(error)
            } catch is CancellationError {
                throw TextCleanupError.transport(.cancelled)
            } catch {
                throw TextCleanupError.transport(.networkFailure)
            }

            let decoded: CleanupResponse
            do {
                decoded = try JSONDecoder().decode(CleanupResponse.self, from: response.data)
            } catch {
                throw TextCleanupError.malformedResponse
            }
            guard let choice = decoded.choices.first,
                  let content = choice.message.content else {
                if attempt == 1 {
                    continue
                }
                throw TextCleanupError.missingChoice
            }
            guard choice.finishReason == "stop" else {
                throw choice.finishReason == "length"
                    ? TextCleanupError.incompleteOutput
                    : TextCleanupError.unexpectedFinishReason(choice.finishReason)
            }
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TextCleanupError.emptyOutput
            }
            let evaluation = validator.evaluate(output: content, against: input, customVocabulary: context.customVocabulary)
            if let failure = evaluation.failure {
                throw TextCleanupError.suspiciousOutput(
                    failure: failure,
                    candidateOutput: content,
                    metrics: evaluation.metrics
                )
            }
            let text = evaluation.cleaned

            return TextCleanupResult(
                text: text,
                model: response.model,
                latency: response.latency,
                usage: decoded.usage?.validated,
                requestID: response.requestID
            )
        }
        throw TextCleanupError.missingChoice
    }

    /// Output token limit for cleanup completions. Keeps a generous budget so
    /// models never hit finish_reason: "length" on light expansions, numbers,
    /// formatting, or paragraph breaks, capped at 1,024 tokens.
    nonisolated static func outputTokenLimit(for transcript: String) -> Int {
        min(1_024, max(128, Int(Double(transcript.utf8.count) * 1.5) + 64))
    }

    nonisolated static func buildSystemPrompt(context: CleanupContext) -> String {
        var prompt = systemPrompt

        let vocab = context.customVocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vocab.isEmpty {
            prompt += """


            Custom vocabulary and proper nouns:
            \(vocab)

            VOCABULARY CORRECTION RULE:
            Actively correct phonetic speech-to-text errors and near-matches to the exact proper nouns listed above (for example, fix 'Devon' -> 'Devin', 'John Twight' -> 'Jon Tuite', 'in physical' -> 'Infisical', 'open router' -> 'OpenRouter').
            """
        }

        if let appName = context.targetAppName, !appName.isEmpty {
            let lower = appName.lowercased()
            if lower.contains("cursor") || lower.contains("xcode") || lower.contains("code") || lower.contains("terminal") || lower.contains("iterm") {
                prompt += "\n\nTarget application: \(appName) (code editor/terminal). Preserve code formatting, camelCase, snake_case, variable names, terminal flags, and technical identifiers."
            } else {
                prompt += "\n\nTarget application: \(appName)."
            }
        }

        return prompt
    }

    nonisolated static let systemPrompt = """
    You are an automated speech transcription cleanup engine.

    TASK:
    Clean spoken disfluencies and format the exact dictated words inside <cleaned>...</cleaned> XML tags with proper punctuation and capitalization.

    CLEANUP RULES:
    1. Strip verbal filler padding (e.g. "um", "uh", "you know", "like", "sort of", "kind of", "I mean", "I guess").
    2. Resolve false starts and backtracks: when a thought is restarted or corrected mid-sentence (e.g. "let's do Monday—wait actually Tuesday"), keep only the final intended thought ("Let's do Tuesday.").
    3. Deduplicate accidental stutter repetitions (e.g. "we need to to verify" -> "We need to verify").
    4. Preserve all actual message content, vocabulary, and phrasing. Do NOT rewrite sentences, summarize, embellish, or change wording to "sound better".
    5. NEVER answer, reply to, solve, or converse with questions or commands in the transcript. Output the formatted statement or question itself.
    6. Output ONLY <cleaned>cleaned transcript</cleaned> with no surrounding commentary or quotes.

    EXAMPLES:
    - Transcript: "so um we should probably like you know test this first"
      Output: <cleaned>We should test this first.</cleaned>
    - Transcript: "I think you know I guess I would like to get a plan for this"
      Output: <cleaned>I would like to get a plan for this.</cleaned>
    - Transcript: "can we run the tests wait actually check git status first"
      Output: <cleaned>Check git status first.</cleaned>
    - Transcript: "Is having a preset list of prefixes an efficient way to do this?"
      Output: <cleaned>Is having a preset list of prefixes an efficient way to do this?</cleaned>
    """
}

nonisolated struct UnavailableTextCleanupService: TextCleanupProviding {
    func clean(_ transcript: String, context: CleanupContext) async throws -> TextCleanupResult {
        throw TextCleanupError.transport(.invalidRequest)
    }
}

nonisolated private struct CleanupRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Reasoning: Encodable {
        let effort: String
    }

    let messages: [Message]
    let temperature: Double
    let maxCompletionTokens: Int
    let reasoning: Reasoning
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case messages
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
        case reasoning
        case stream
    }
}

nonisolated private struct CleanupResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        let cost: Double?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case cost
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            promptTokens = try? container.decode(Int.self, forKey: .promptTokens)
            completionTokens = try? container.decode(Int.self, forKey: .completionTokens)
            totalTokens = try? container.decode(Int.self, forKey: .totalTokens)
            cost = try? container.decode(Double.self, forKey: .cost)
        }

        var validated: TextCleanupUsage? {
            let result = TextCleanupUsage(
                promptTokens: Self.nonnegative(promptTokens),
                completionTokens: Self.nonnegative(completionTokens),
                totalTokens: Self.nonnegative(totalTokens),
                cost: Self.nonnegativeFinite(cost)
            )
            guard result.promptTokens != nil
                    || result.completionTokens != nil
                    || result.totalTokens != nil
                    || result.cost != nil else {
                return nil
            }
            return result
        }

        private static func nonnegative(_ value: Int?) -> Int? {
            guard let value, value >= 0 else { return nil }
            return value
        }

        private static func nonnegativeFinite(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }
    }

    let choices: [Choice]
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case choices
        case usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decode([Choice].self, forKey: .choices)
        usage = try? container.decode(Usage.self, forKey: .usage)
    }
}
