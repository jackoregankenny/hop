import Foundation

// Small recursive-descent calculator: + - * / % ^, parentheses, functions, constants.
struct Calc {
    private var t: [Character]
    private var i = 0

    static func eval(_ s: String) -> Double? {
        let src = s.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "")
        // Only treat it as math if there is an operator or a function call; bare numbers are not answers.
        guard src.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/%^(")) != nil,
              src.rangeOfCharacter(from: .decimalDigits) != nil || src.contains("pi"),
              Double(src.trimmingCharacters(in: .whitespaces)) == nil else { return nil }
        var c = Calc(t: Array(src.lowercased()))
        guard let v = c.expr(), c.skip() == nil, v.isFinite else { return nil }
        return v
    }

    @discardableResult private mutating func skip() -> Character? {
        while i < t.count && t[i] == " " { i += 1 }
        return i < t.count ? t[i] : nil
    }

    private mutating func expr() -> Double? {
        guard var v = term() else { return nil }
        while let c = skip(), c == "+" || c == "-" {
            i += 1
            guard let r = term() else { return nil }
            v = c == "+" ? v + r : v - r
        }
        return v
    }

    private mutating func term() -> Double? {
        guard var v = unary() else { return nil }
        while let c = skip(), c == "*" || c == "/" || c == "%" {
            i += 1
            guard let r = unary() else { return nil }
            v = c == "*" ? v * r : c == "/" ? v / r : v.truncatingRemainder(dividingBy: r)
        }
        return v
    }

    private mutating func unary() -> Double? {
        if skip() == "-" { i += 1; return unary().map { -$0 } }
        if skip() == "+" { i += 1; return unary() }
        return power()
    }

    private mutating func power() -> Double? {
        guard let b = primary() else { return nil }
        if skip() == "^" {
            i += 1
            guard let e = unary() else { return nil }
            return pow(b, e)
        }
        return b
    }

    private mutating func primary() -> Double? {
        guard let c = skip() else { return nil }
        if c == "(" {
            i += 1
            let v = expr()
            guard skip() == ")" else { return nil }
            i += 1
            return v
        }
        if c.isNumber || c == "." {
            let start = i
            while i < t.count && (t[i].isNumber || t[i] == ".") { i += 1 }
            return Double(String(t[start..<i]))
        }
        if c.isLetter {
            let start = i
            while i < t.count && t[i].isLetter { i += 1 }
            let name = String(t[start..<i])
            switch name {
            case "pi": return .pi
            case "e": return M_E
            default: break
            }
            guard let f = Calc.funcs[name], skip() == "(" else { return nil }
            i += 1
            guard let a = expr(), skip() == ")" else { return nil }
            i += 1
            return f(a)
        }
        return nil
    }

    private static let funcs: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "abs": { abs($0) }, "ln": { log($0) }, "log": { log10($0) },
        "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
        "round": { $0.rounded() }, "floor": { floor($0) }, "ceil": { ceil($0) },
    ]

    static func format(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e15 { return String(format: "%.0f", v) }
        let s = String(format: "%.10g", v)
        return s
    }
}

// "5 km to mi", "70f in c", "3.5 gb to mb"
enum Units {
    private static let table: [(dim: String, names: [String], factor: Double)] = [
        ("len", ["mm"], 0.001), ("len", ["cm"], 0.01), ("len", ["m", "meter", "meters"], 1),
        ("len", ["km"], 1000), ("len", ["in", "inch", "inches"], 0.0254), ("len", ["ft", "feet", "foot"], 0.3048),
        ("len", ["yd", "yard", "yards"], 0.9144), ("len", ["mi", "mile", "miles"], 1609.344),
        ("mass", ["mg"], 0.001), ("mass", ["g", "gram", "grams"], 1), ("mass", ["kg"], 1000),
        ("mass", ["oz", "ounce", "ounces"], 28.349523125), ("mass", ["lb", "lbs", "pound", "pounds"], 453.59237),
        ("mass", ["st", "stone"], 6350.29318),
        ("vol", ["ml"], 0.001), ("vol", ["l", "liter", "litre", "liters", "litres"], 1),
        ("vol", ["cup", "cups"], 0.2365882365), ("vol", ["floz"], 0.0295735295625),
        ("vol", ["gal", "gallon", "gallons"], 3.785411784), ("vol", ["pt", "pint", "pints"], 0.473176473),
        ("data", ["b", "byte", "bytes"], 1), ("data", ["kb"], 1e3), ("data", ["mb"], 1e6),
        ("data", ["gb"], 1e9), ("data", ["tb"], 1e12), ("data", ["kib"], 1024), ("data", ["mib"], 1048576),
        ("data", ["gib"], 1073741824),
        ("time", ["ms"], 0.001), ("time", ["s", "sec", "secs", "seconds"], 1), ("time", ["min", "mins", "minutes"], 60),
        ("time", ["h", "hr", "hrs", "hour", "hours"], 3600), ("time", ["d", "day", "days"], 86400),
        ("time", ["wk", "week", "weeks"], 604800), ("time", ["yr", "year", "years"], 31557600),
        ("speed", ["kmh", "kph"], 1 / 3.6), ("speed", ["mph"], 0.44704), ("speed", ["mps"], 1),
    ]

    static func parse(_ s: String) -> (value: Double, from: String, to: String)? {
        let pattern = #"^\s*(-?[\d.,]+)\s*([a-zA-Z°]+)\s+(?:to|in|as|=)\s+([a-zA-Z°]+)\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r1 = Range(m.range(at: 1), in: s), let r2 = Range(m.range(at: 2), in: s),
              let r3 = Range(m.range(at: 3), in: s),
              let v = Double(s[r1].replacingOccurrences(of: ",", with: "")) else { return nil }
        return (v, s[r2].lowercased().replacingOccurrences(of: "°", with: ""),
                s[r3].lowercased().replacingOccurrences(of: "°", with: ""))
    }

    static func convert(_ s: String) -> String? {
        guard let (v, from, to) = parse(s) else { return nil }
        let temps = ["c": "°C", "f": "°F", "k": "K"]
        if temps[from] != nil, let tt = temps[to] {
            let c = from == "c" ? v : from == "f" ? (v - 32) * 5 / 9 : v - 273.15
            let out = to == "c" ? c : to == "f" ? c * 9 / 5 + 32 : c + 273.15
            return "\(Calc.format(roundTo(out))) \(tt)"
        }
        guard let a = table.first(where: { $0.names.contains(from) }),
              let b = table.first(where: { $0.names.contains(to) }), a.dim == b.dim else { return nil }
        return "\(Calc.format(roundTo(v * a.factor / b.factor))) \(to)"
    }

    static func roundTo(_ v: Double) -> Double { (v * 1e6).rounded() / 1e6 }

    /// "100 usd to eur" -> (100, "USD", "EUR"); resolved asynchronously.
    static func currency(_ s: String) -> (Double, String, String)? {
        guard let (v, from, to) = parse(s), from.count == 3, to.count == 3,
              table.first(where: { $0.names.contains(from) || $0.names.contains(to) }) == nil else { return nil }
        return (v, from.uppercased(), to.uppercased())
    }
}
