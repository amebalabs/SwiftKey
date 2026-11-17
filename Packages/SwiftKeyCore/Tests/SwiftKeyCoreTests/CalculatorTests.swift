import Foundation
import Testing
@testable import SwiftKeyCore

@Suite struct CalculatorTests {
    @Test(arguments: [
        ("2+2", "4"),
        ("2 * (3 + 4)", "14"),
        ("1,5 × 4", "6"),
        ("1.5*4", "6"),
        (".5 + .25", "0.75"),
        ("0.1 + 0.2", "0.3"),
        ("10 / 4", "2.5"),
        ("1/3", "0.333333333333"),
        ("2/3", "0.666666666667"),
        ("7 ÷ 2", "3.5"),
        ("10 − 3", "7"),
        ("-5 + 2", "-3"),
        ("-(2+3)*2", "-10"),
        ("-2^2", "-4"),
        ("2^10", "1024"),
        ("2**3", "8"),
        ("2^3^2", "512"),
        ("2^-2", "0.25"),
        ("2^64", "18446744073709551616"),
        ("2^0.5", "1.414213562373"),
        ("10^30", "1e+30"),
        ("-3 * 10^25", "-3e+25"),
        ("2^100", "1.267650600228e+30"),
        ("999999999999999999999 + 1", "1e+21"),
        ("200 + 15%", "230"),
        ("200 - 10%", "180"),
        ("200 * 15%", "30"),
        ("50%", "0.5"),
        ("17 mod 5", "2"),
        ("sqrt(16)", "4"),
        ("sqrt(2)", "1.414213562373"),
        ("SQRT(9)+1", "4"),
        ("abs(-3.5)", "3.5"),
        ("round(2.5)", "3"),
        ("floor(-1.5)", "-2"),
        ("ceil(1.2)", "2"),
        ("2 * pi", "6.28318530718"),
        ("2π", nil),
        ("sin(pi) + 1", "1"),
        ("cos(0)", "1"),
        ("ln(e) * 2", "2"),
        ("log(1000)", "3"),
        ("exp(1)", "2.718281828459"),
        ("1000000 * 1000000", "1000000000000"),
    ] as [(String, String?)])
    func values(query: String, expected: String?) {
        #expect(Calculator.evaluate(query) == expected, "\(query)")
    }

    @Test(arguments: [
        "", "42", "-5", "+7", "(3)", "pi", "pi*e", "ln(e)", "sin(pi)", "Notes", "1Password", "c++", "2fa", "3d",
        "1.2.3", "192.168.1.1", "2.", "2+", "*2", "(2+3", "2+3)", "2 3", "1/0", "5 mod 0", "sqrt(-1)",
        "log(0)", "asin(2)", "0^-1", "foo(2)", "sqrt 4", "2 + x", "10^5000",
    ])
    func notCalculations(query: String) {
        #expect(Calculator.evaluate(query) == nil, "\(query)")
    }

    @Test func limits() {
        #expect(Calculator.evaluate(String(repeating: "1+", count: 100) + "1") == nil, "longer than 200 characters")
        #expect(Calculator.evaluate(String(repeating: "1+", count: 99) + "1") == "100")
        #expect(Calculator.evaluate(String(repeating: "(", count: 70) + "1+1" + String(repeating: ")", count: 70)) == nil, "too deep")
        #expect(Calculator.evaluate(String(repeating: "(", count: 20) + "1+1" + String(repeating: ")", count: 20)) == "2")
        #expect(Calculator.evaluate(String(repeating: "-", count: 150) + "1+1") == nil, "too deep")
    }
}
