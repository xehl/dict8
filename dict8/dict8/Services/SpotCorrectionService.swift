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

        // Find single-word substitutions
        var candidatePairs: [(original: String, corrected: String)] = []

        // If the word count is identical, compare index by index
        if pastedWords.count == editedWords.count {
            for (p, e) in zip(pastedWords, editedWords) {
                if p != e {
                    candidatePairs.append((p, e))
                }
            }
        } else {
            // Check if editedText is a substring or container of the edited region
            // Simple alignment: find words in pastedText missing from editedText and vice versa
            let diffPasted = pastedWords.filter { !editedWords.contains($0) }
            let diffEdited = editedWords.filter { !pastedWords.contains($0) }

            if diffPasted.count == 1, diffEdited.count == 1,
               let orig = diffPasted.first, let corr = diffEdited.first {
                candidatePairs.append((orig, corr))
            }
        }

        // We only learn when exactly one word was corrected
        guard candidatePairs.count == 1,
              let (original, corrected) = candidatePairs.first else {
            return nil
        }

        // Clean punctuation from candidate words
        let cleanOrig = cleanWord(original)
        let cleanCorr = cleanWord(corrected)

        guard !cleanOrig.isEmpty, !cleanCorr.isEmpty,
              cleanOrig.lowercased() != cleanCorr.lowercased() || cleanOrig != cleanCorr else {
            return nil
        }

        // Check edit distance heuristic
        let distance = levenshteinDistance(cleanOrig.lowercased(), cleanCorr.lowercased())
        let maxAllowedDistance = cleanOrig.count <= 6 ? 2 : 3

        // Case difference (e.g. devin -> Devin) is distance 0 in lowercase, which is a valid capitalization correction
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
