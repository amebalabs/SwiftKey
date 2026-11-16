import Foundation

/// The calculator of launcha: a query such as `2*(3+4)`, `1,5 × 4`, `200 + 15%` or `sqrt(2)`
/// gives its value. Pure logic: no process, no `NSExpression`.
///
/// - Numbers: digits with one `.` or `,` as the decimal separator (`1,5` is one and a half).
/// - Operators: `+`, `-` (`−`), `*` (`×`, `·`), `/` (`÷`), `^` (`**`), `mod`, parentheses.
/// - `%` after a number is a percent: `15%` is 0.15, and `a + b%` / `a - b%` add or take
///   `b` percent of `a`, as on a pocket calculator.
/// - Functions (radians): sqrt, abs, round, floor, ceil, ln, log (base 10), exp, sin, cos, tan,
///   asin, acos, atan. Constants: pi (`π`), e.
///
/// A query is a calculation only when it has a digit and at least one operation (an operator
/// or a function): `42` or `-5` alone are not.
public enum Calculator {
    /// Longer queries are not read.
    public static let maxLength = 200
    /// Deeper nesting is not read.
    static let maxDepth = 64
    /// Results are rounded to this many digits after the point.
    public static let fractionDigits: Int16 = 12

    /// The value of `query`, or `nil` when it is not a calculation or has no value (division by
    /// zero, the square root of a negative number, an overflow).
    public static func evaluate(_ query: String) -> String? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxLength, text.contains(where: \.isASCIIDigit),
              let tokens = tokenize(text) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let node = parser.parse(), node.operations > 0, let value = node.value() else { return nil }
        return format(value)
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Decimal)
        case plus, minus, times, divide, power, percent, open, close
        case name(String)
    }

    static let functions: Set<String> = ["sqrt", "abs", "round", "floor", "ceil", "ln", "log", "exp",
                                         "sin", "cos", "tan", "asin", "acos", "atan"]
    static let constants: [String: Decimal] = [
        "pi": Decimal(string: "3.14159265358979323846264338327950288")!,
        "π": Decimal(string: "3.14159265358979323846264338327950288")!,
        "e": Decimal(string: "2.71828182845904523536028747135266249")!,
    ]

    static func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isASCIIDigit || ((c == "." || c == ",") && i + 1 < chars.count && chars[i + 1].isASCIIDigit) {
                var digits = ""
                var separator = false
                while i < chars.count, chars[i].isASCIIDigit || chars[i] == "." || chars[i] == "," {
                    if chars[i] == "." || chars[i] == "," {
                        // A second separator: a version or an address, such as 1.2.3.
                        if separator { return nil }
                        separator = true
                        digits.append(".")
                    } else {
                        digits.append(chars[i])
                    }
                    i += 1
                }
                if digits.hasSuffix(".") { return nil }
                guard let value = Decimal(string: digits.hasPrefix(".") ? "0" + digits : digits, locale: Locale(identifier: "en_US_POSIX"))
                else { return nil }
                tokens.append(.number(value))
                continue
            }
            if c.isLetter {
                var word = ""
                while i < chars.count, chars[i].isLetter { word.append(chars[i]); i += 1 }
                let name = word.lowercased()
                guard functions.contains(name) || constants[name] != nil || name == "mod" else { return nil }
                tokens.append(.name(name))
                continue
            }
            switch c {
            case "+": tokens.append(.plus)
            case "-", "−", "–": tokens.append(.minus)
            case "*", "×", "·", "⋅":
                if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                    tokens.append(.power)
                    i += 1
                } else {
                    tokens.append(.times)
                }
            case "/", "÷", "∕": tokens.append(.divide)
            case "^": tokens.append(.power)
            case "%": tokens.append(.percent)
            case "(": tokens.append(.open)
            case ")": tokens.append(.close)
            default: return nil
            }
            i += 1
        }
        return tokens
    }

    // MARK: Tree

    indirect enum Node {
        case number(Decimal)
        case negate(Node)
        case percent(Node)
        case binary(Token, Node, Node)
        case mod(Node, Node)
        case function(String, Node)

        /// Operators and functions in the tree; a unary minus does not count.
        var operations: Int {
            switch self {
            case .number: 0
            case .negate(let n): n.operations
            case .percent(let n): n.operations + 1
            case .binary(_, let a, let b), .mod(let a, let b): a.operations + b.operations + 1
            case .function(_, let n): n.operations + 1
            }
        }

        func value() -> Decimal? {
            switch self {
            case .number(let v):
                return v
            case .negate(let n):
                return n.value().map { -$0 }
            case .percent(let n):
                return n.value().flatMap { Calculator.checked($0 / 100) }
            case .binary(let op, let a, let b):
                guard let x = a.value() else { return nil }
                // a + b% and a - b%: b percent of a.
                if op == .plus || op == .minus, case .percent(let p) = b {
                    guard let share = p.value().flatMap({ Calculator.checked(x * $0 / 100) }) else { return nil }
                    return Calculator.checked(op == .plus ? x + share : x - share)
                }
                guard let y = b.value() else { return nil }
                switch op {
                case .plus: return Calculator.checked(x + y)
                case .minus: return Calculator.checked(x - y)
                case .times: return Calculator.checked(x * y)
                case .divide: return y.isZero ? nil : Calculator.checked(x / y)
                case .power: return Calculator.power(x, y)
                default: return nil
                }
            case .mod(let a, let b):
                guard let x = a.value(), let y = b.value(), !y.isZero else { return nil }
                let r = fmod(Calculator.double(x), Calculator.double(y))
                return Calculator.decimal(r)
            case .function(let name, let n):
                guard let v = n.value() else { return nil }
                let d = Calculator.double(v)
                let r: Double
                switch name {
                case "sqrt": guard d >= 0 else { return nil }; r = d.squareRoot()
                case "abs": return v < 0 ? -v : v
                case "round": return Calculator.rounded(v, .plain)
                case "floor": return Calculator.rounded(v, .down)
                case "ceil": return Calculator.rounded(v, .up)
                case "ln": guard d > 0 else { return nil }; r = Foundation.log(d)
                case "log": guard d > 0 else { return nil }; r = log10(d)
                case "exp": r = Foundation.exp(d)
                case "sin": r = Foundation.sin(d)
                case "cos": r = Foundation.cos(d)
                case "tan": r = Foundation.tan(d)
                case "asin": guard abs(d) <= 1 else { return nil }; r = Foundation.asin(d)
                case "acos": guard abs(d) <= 1 else { return nil }; r = Foundation.acos(d)
                case "atan": r = Foundation.atan(d)
                default: return nil
                }
                return Calculator.decimal(r)
            }
        }
    }

    /// expression := term (("+" | "-") term)*
    /// term       := unary (("*" | "/" | "mod") unary)*
    /// unary      := ("+" | "-") unary | power
    /// power      := postfix ("^" unary)?        (right to left: 2^3^2 = 2^9)
    /// postfix    := primary "%"?
    /// primary    := number | constant | function "(" expression ")" | "(" expression ")"
    struct Parser {
        let tokens: [Token]
        var index = 0
        var depth = 0

        init(tokens: [Token]) { self.tokens = tokens }

        mutating func parse() -> Node? {
            guard let node = expression(), index == tokens.count else { return nil }
            return node
        }

        private var peek: Token? { index < tokens.count ? tokens[index] : nil }

        private mutating func expression() -> Node? {
            depth += 1
            defer { depth -= 1 }
            guard depth <= Calculator.maxDepth, var left = term() else { return nil }
            while let op = peek, op == .plus || op == .minus {
                index += 1
                guard let right = term() else { return nil }
                left = .binary(op, left, right)
            }
            return left
        }

        private mutating func term() -> Node? {
            guard var left = unary() else { return nil }
            while let op = peek {
                if op == .times || op == .divide {
                    index += 1
                    guard let right = unary() else { return nil }
                    left = .binary(op, left, right)
                } else if op == .name("mod") {
                    index += 1
                    guard let right = unary() else { return nil }
                    left = .mod(left, right)
                } else {
                    break
                }
            }
            return left
        }

        private mutating func unary() -> Node? {
            depth += 1
            defer { depth -= 1 }
            guard depth <= Calculator.maxDepth else { return nil }
            if peek == .minus {
                index += 1
                return unary().map { .negate($0) }
            }
            if peek == .plus {
                index += 1
                return unary()
            }
            return power()
        }

        private mutating func power() -> Node? {
            guard let base = postfix() else { return nil }
            if peek == .power {
                index += 1
                guard let exponent = unary() else { return nil }
                return .binary(.power, base, exponent)
            }
            return base
        }

        private mutating func postfix() -> Node? {
            guard let node = primary() else { return nil }
            if peek == .percent {
                index += 1
                return .percent(node)
            }
            return node
        }

        private mutating func primary() -> Node? {
            guard let token = peek else { return nil }
            index += 1
            switch token {
            case .number(let value):
                return .number(value)
            case .open:
                guard let inner = expression(), peek == .close else { return nil }
                index += 1
                return inner
            case .name(let name):
                if let value = Calculator.constants[name] { return .number(value) }
                guard Calculator.functions.contains(name), peek == .open else { return nil }
                index += 1
                guard let inner = expression(), peek == .close else { return nil }
                index += 1
                return .function(name, inner)
            default:
                return nil
            }
        }
    }

    // MARK: Numbers

    /// `nil` for NaN (an overflow, a division by zero).
    static func checked(_ value: Decimal) -> Decimal? { value.isNaN ? nil : value }

    static func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }

    /// A finite Double as Decimal, through its shortest text, so 0.1 stays 0.1.
    static func decimal(_ value: Double) -> Decimal? {
        guard value.isFinite else { return nil }
        return Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))
    }

    static func rounded(_ value: Decimal, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 0, mode)
        return result
    }

    /// Whole exponents up to 1000 stay exact; others go through Double.
    static func power(_ base: Decimal, _ exponent: Decimal) -> Decimal? {
        if exponent == rounded(exponent, .plain), abs(exponent) <= 1000 {
            let n = NSDecimalNumber(decimal: abs(exponent)).intValue
            guard let raised = checked(pow(base, n)) else { return nil }
            if exponent < 0 { return raised.isZero ? nil : checked(1 / raised) }
            return raised
        }
        return decimal(Foundation.pow(double(base), double(exponent)))
    }

    /// At most `fractionDigits` digits after the point, without trailing zeros; very large
    /// values in scientific notation, such as `1e+100`.
    static func format(_ value: Decimal) -> String? {
        guard !value.isNaN else { return nil }
        if abs(value) >= Decimal(string: "1e21")! { return scientific(value) }
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, Int(fractionDigits), .plain)
        if result.isZero { return "0" }
        return result.description
    }

    /// A whole number of 22 or more digits as `1.8446744073710e+19`-style text with at most
    /// 13 significant digits: `1e+30`, `-1.5e+21`.
    static func scientific(_ value: Decimal) -> String {
        var source = abs(value)
        var whole = Decimal()
        NSDecimalRound(&whole, &source, 0, .plain)
        let exponent = whole.description.count - 1
        var rounded = Decimal()
        NSDecimalRound(&rounded, &whole, -(exponent - 12), .plain)
        var digits = rounded.description
        // Rounding up can add a digit: 9.99…e+21 becomes 1e+22.
        let shift = digits.count - 1 - exponent
        digits = String(digits.prefix(13))
        while digits.count > 1, digits.hasSuffix("0") { digits.removeLast() }
        let mantissa = digits.count > 1 ? "\(digits.first!).\(digits.dropFirst())" : digits
        return (value < 0 ? "-" : "") + mantissa + "e+\(exponent + shift)"
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
