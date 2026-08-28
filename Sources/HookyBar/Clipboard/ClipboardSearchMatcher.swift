import Foundation

/// Лёгкий локальный fuzzy-поиск: без сети, индексации диска и фоновых моделей.
enum ClipboardSearchMatcher {
    static func score(query: String, candidate: String) -> Int? {
        let rawQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawQuery.isEmpty, !candidate.isEmpty else { return nil }

        if candidate.compare(rawQuery, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return 1_000
        }
        if candidate.range(
            of: rawQuery,
            options: [.anchored, .caseInsensitive, .diacriticInsensitive]
        ) != nil {
            return 900
        }
        if candidate.range(of: rawQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return 760
        }

        // Fuzzy-часть ограничена, чтобы огромный кусок кода не тормозил UI на каждом символе.
        let candidateIndex = normalize(String(candidate.prefix(12_000)))
        guard !candidateIndex.isEmpty else { return nil }

        return queryVariants(query)
            .compactMap { scoreNormalized(query: $0, candidate: candidateIndex) }
            .max()
    }

    private static func scoreNormalized(query: String, candidate: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        if candidate == query { return 1_000 }
        if candidate.hasPrefix(query) { return 900 }
        if candidate.contains(query) { return 760 }

        let queryWords = words(in: query, limit: 8)
        let candidateWords = words(in: candidate, limit: 160)
        guard !queryWords.isEmpty, !candidateWords.isEmpty else { return nil }

        var total = 160
        for queryWord in queryWords {
            guard let wordScore = bestWordScore(for: queryWord, in: candidateWords) else { return nil }
            total += wordScore
        }
        return total
    }

    private static func bestWordScore(for query: String, in candidates: [String]) -> Int? {
        var best = 0
        for word in candidates {
            if word == query { return 90 }
            if word.hasPrefix(query) { best = max(best, 76); continue }
            if query.count >= 3, word.contains(query) { best = max(best, 64); continue }

            let tolerance = query.count <= 4 ? 1 : query.count <= 8 ? 2 : 3
            guard query.count >= 3,
                  word.count <= 48,
                  abs(word.count - query.count) <= tolerance else { continue }
            let distance = damerauLevenshtein(query, word)
            if distance <= tolerance {
                best = max(best, 58 - distance * 9)
            }
        }
        return best > 0 ? best : nil
    }

    private static func queryVariants(_ text: String) -> [String] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }
        let swapped = swapKeyboardLayout(normalized)
        return swapped == normalized ? [normalized] : [normalized, swapped]
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(in text: String, limit: Int) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }
            .prefix(limit)
            .map(String.init)
    }

    private static func swapKeyboardLayout(_ text: String) -> String {
        let english = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.")
        let russian = Array("йцукенгшщзхъфывапролджэячсмитьбю")
        var mapping: [Character: Character] = [:]
        for (left, right) in zip(english, russian) {
            mapping[left] = right
            mapping[right] = left
        }
        return String(text.map { mapping[$0] ?? $0 })
    }

    /// Damerau–Levenshtein также считает соседнюю перестановку одной опечаткой.
    private static func damerauLevenshtein(_ left: String, _ right: String) -> Int {
        let left = Array(left)
        let right = Array(right)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var matrix = Array(
            repeating: Array(repeating: 0, count: right.count + 1),
            count: left.count + 1
        )
        for index in 0...left.count { matrix[index][0] = index }
        for index in 0...right.count { matrix[0][index] = index }

        for leftIndex in 1...left.count {
            for rightIndex in 1...right.count {
                let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                matrix[leftIndex][rightIndex] = min(
                    matrix[leftIndex - 1][rightIndex] + 1,
                    matrix[leftIndex][rightIndex - 1] + 1,
                    matrix[leftIndex - 1][rightIndex - 1] + substitutionCost
                )
                if leftIndex > 1, rightIndex > 1,
                   left[leftIndex - 1] == right[rightIndex - 2],
                   left[leftIndex - 2] == right[rightIndex - 1] {
                    matrix[leftIndex][rightIndex] = min(
                        matrix[leftIndex][rightIndex],
                        matrix[leftIndex - 2][rightIndex - 2] + 1
                    )
                }
            }
        }
        return matrix[left.count][right.count]
    }
}
