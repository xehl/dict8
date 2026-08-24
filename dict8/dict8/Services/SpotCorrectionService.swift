import Foundation

nonisolated struct SpotCorrectionPair: Equatable, Sendable {
    let originalWord: String
    let correctedWord: String
}

nonisolated struct SpotCorrectionDiffEngine: Sendable {
    /// Minimum similarity threshold to distinguish a typo/spelling fix from an unrelated rewrite.
    /// Uses Levenshtein edit distance: max distance 2 for short words (<=6 chars) and 3 for longer words.
    func findCorrection(
        pastedText: String,
        editedText: String
    ) -> SpotCorrectionPair? {
        let pastedWords = tokenize(pastedText)
        let editedWords = tokenize(editedText)

        guard !pastedWords.isEmpty, !editedWords.isEmpty else { return nil }
        guard pastedWords != editedWords else { return nil }

        // 1. Direct same-length substitution check
        if pastedWords.count == editedWords.count {
            var diffs: [(original: String, corrected: String)] = []
            for (p, e) in zip(pastedWords, editedWords) {
                if cleanWord(p) != cleanWord(e) {
                    diffs.append((p, e))
                }
            }
            if diffs.count == 1, let (orig, corr) = diffs.first {
                return validatePair(original: orig, corrected: corr)
            }
        }

        // 2. Sliding window sub-slice check:
        // When editedText contains the full pastedText (plus or minus surrounding buffer words)
        // Check windows of size pastedWords.count in editedWords
        let pLen = pastedWords.count
        if editedWords.count >= pLen {
            for start in 0...(editedWords.count - pLen) {
                let window = Array(editedWords[start..<(start + pLen)])
                var diffs: [(original: String, corrected: String)] = []
                for (p, e) in zip(pastedWords, window) {
                    if cleanWord(p) != cleanWord(e) {
                        diffs.append((p, e))
                    }
                }
                if diffs.count == 1, let (orig, corr) = diffs.first {
                    if let pair = validatePair(original: orig, corrected: corr) {
                        return pair
                    }
                }
            }
        }

        // 3. Multi-word phrase substitution (e.g. 2-to-1: "in physical" -> "Infisical" or "open router" -> "OpenRouter")
        if editedWords.count >= (pLen - 1) && pLen >= 2 {
            for start in 0...(editedWords.count - (pLen - 1)) {
                let window = Array(editedWords[start..<(start + pLen - 1)])
                // Find where the 2 words merged into 1
                for splitIdx in 0..<(pLen - 1) {
                    let pBefore = Array(pastedWords[0..<splitIdx])
                    let pPair = Array(pastedWords[splitIdx..<(splitIdx + 2)])
                    let pAfter = Array(pastedWords[(splitIdx + 2)..<pLen])

                    let wBefore = Array(window[0..<splitIdx])
                    let wCandidate = window[splitIdx]
                    let wAfter = Array(window[(splitIdx + 1)..<window.count])

                    if pBefore.map(cleanWord) == wBefore.map(cleanWord) &&
                       pAfter.map(cleanWord) == wAfter.map(cleanWord) {
                        let combinedOrig = pPair.joined(separator: " ")
                        let cleanCorr = cleanWord(wCandidate)
                        let cleanOrigNoSpace = cleanWord(pPair.joined())
                        if levenshteinDistance(cleanOrigNoSpace.lowercased(), cleanCorr.lowercased()) <= 3 {
                            return SpotCorrectionPair(originalWord: combinedOrig, correctedWord: cleanCorr)
                        }
                    }
                }
            }
        }

        // 4. Fallback set difference for loose cursor placement
        let diffPasted = pastedWords.filter { p in !editedWords.contains(where: { cleanWord($0).lowercased() == cleanWord(p).lowercased() }) }
        let diffEdited = editedWords.filter { e in !pastedWords.contains(where: { cleanWord($0).lowercased() == cleanWord(e).lowercased() }) }

        if diffPasted.count == 1 && diffEdited.count == 1 {
            return validatePair(original: diffPasted[0], corrected: diffEdited[0])
        }

        return nil
    }

    private func validatePair(original: String, corrected: String) -> SpotCorrectionPair? {
        let cleanOrig = cleanWord(original)
        let cleanCorr = cleanWord(corrected)

        guard !cleanOrig.isEmpty, !cleanCorr.isEmpty,
              cleanOrig.lowercased() != cleanCorr.lowercased() || cleanOrig != cleanCorr else {
            return nil
        }

        let distance = levenshteinDistance(cleanOrig.lowercased(), cleanCorr.lowercased())
        let maxAllowedDistance = cleanOrig.count <= 6 ? 2 : 3

        if distance <= maxAllowedDistance {
            return SpotCorrectionPair(originalWord: cleanOrig, correctedWord: cleanCorr)
        }
        return nil
    }

    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }

    private func cleanWord(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = min(
                        matrix[i - 1][j] + 1,     // deletion
                        matrix[i][j - 1] + 1,     // insertion
                        matrix[i - 1][j - 1] + 1  // substitution
                    )
                }
            }
        }

        return matrix[m][n]
    }
}
