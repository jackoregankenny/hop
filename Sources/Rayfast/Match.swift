import Foundation

// Fuzzy matching: exact > prefix > initials > word prefix > substring > subsequence > typo.
enum Match {
    static func words(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var prev: Character = " "
        for ch in s {
            if ch == " " || ch == "-" || ch == "_" || ch == "." || ch == "/" {
                if !cur.isEmpty { out.append(cur); cur = "" }
            } else if ch.isUppercase && prev.isLowercase && !cur.isEmpty {
                out.append(cur); cur = String(ch)
            } else {
                cur.append(ch)
            }
            prev = ch
        }
        if !cur.isEmpty { out.append(cur) }
        return out.map { $0.lowercased() }
    }

    static func initials(_ s: String) -> String {
        String(words(s).compactMap(\.first))
    }

    /// Returns nil when there is no match. Higher is better. `loose` allows scattered-letter
    /// (subsequence) matches, which suit short app names but are noise on long command or menu titles.
    static func score(_ query: String, _ name: String, loose: Bool = true) -> Double? {
        let q = query.lowercased()
        let n = name.lowercased()
        if q.isEmpty { return nil }
        if n == q { return 1000 }
        if n.hasPrefix(q) { return 900 - Double(n.count - q.count) }
        let ws = words(name)
        let ini = String(ws.compactMap(\.first))
        if q.count >= 2 && ini.hasPrefix(q) { return 820 - Double(ini.count - q.count) }
        if ws.dropFirst().contains(where: { $0.hasPrefix(q) }) { return 760 - Double(n.count) * 0.5 }
        if n.contains(q) { return 650 - Double(n.count) * 0.5 }
        if loose, let s = subsequence(q, n, ws) { return s }
        let allowed = q.count <= 3 ? 0 : (q.count <= 6 ? 1 : 2)
        if allowed > 0 {
            var best = Int.max
            for cand in [n] + ws {
                let prefix = String(cand.prefix(q.count))
                best = min(best, osa(q, prefix))
                if cand.count > q.count { best = min(best, osa(q, String(cand.prefix(q.count + 1)))) }
            }
            if best <= allowed { return 300 - Double(best) * 60 - Double(n.count) * 0.3 }
        }
        return nil
    }

    private static func subsequence(_ q: String, _ n: String, _ ws: [String]) -> Double? {
        let qa = Array(q), na = Array(n)
        let starts = Set(wordStarts(na))
        var i = 0, score = 400.0, last = -2
        for (j, ch) in na.enumerated() where i < qa.count && ch == qa[i] {
            if j == last + 1 { score += 6 }
            if starts.contains(j) { score += 10 }
            last = j
            i += 1
        }
        guard i == qa.count else { return nil }
        return score - Double(na.count) * 0.5
    }

    private static func wordStarts(_ a: [Character]) -> [Int] {
        var out = [0]
        for i in 1..<max(a.count, 1) where !a[i - 1].isLetter && !a[i - 1].isNumber { out.append(i) }
        return out
    }

    /// Optimal string alignment distance (Damerau-Levenshtein with adjacent transpositions).
    static func osa(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}

/// What a query is for. Light rules, no model: questions go to the web first; anything that
/// matched well on this Mac keeps the web row last.
enum Intent {
    static let questionWords: Set<String> = ["how", "what", "why", "when", "where", "who", "which", "whats", "is", "are",
                                             "can", "does", "do", "should", "will", "best", "vs", "versus"]

    static func isQuestion(_ q: String) -> Bool {
        let words = q.lowercased().split(separator: " ")
        if q.hasSuffix("?") { return true }
        if words.count >= 2, let first = words.first, questionWords.contains(String(first)) { return true }
        return words.count >= 4
    }

    /// `bestLocal` is the top score among apps, commands, settings, files…; nil when nothing matched.
    static func webFirst(_ q: String, bestLocal: Double?, hasAnswer: Bool) -> Bool {
        if hasAnswer { return false }
        if isQuestion(q) { return true }
        guard let best = bestLocal else { return true }
        return best < 600
    }
}
