import Foundation
import UsageBarCore

/// A ~100 line test harness.
///
/// Why not XCTest? XCTest is only shipped inside Xcode, and this project promises
/// to build with Command Line Tools alone. A side effect is that the tests need
/// no special runner: `swift run UsageBarSelfTest` builds, runs and reports.
///
/// Usage:
///   runner.suite("Codex parsing")
///   runner.equal(usage.plan, "prolife", "plan name")
///   ...
///   runner.finish()   // prints a summary and exits non-zero on failure
final class TestRunner {
    static let shared = TestRunner()

    private var failures: [String] = []
    private var checks = 0
    private var suite = ""
    private var suiteHeaderPrinted = false

    private init() {}

    func startSuite(_ name: String) {
        suite = name
        suiteHeaderPrinted = false
    }

    private func header() {
        guard !suiteHeaderPrinted else { return }
        print("\n▸ \(suite)")
        suiteHeaderPrinted = true
    }

    /// Core assertion. `message` is autoclosure so it costs nothing on success.
    func check(_ condition: Bool,
               _ message: @autoclosure () -> String,
               file: StaticString = #filePath,
               line: UInt = #line) {
        checks += 1
        guard !condition else { return }
        header()
        failures.append("\(file):\(line)  \(message())")
        print("  ✗ \(message())   (\(file):\(line))")
    }

    func equal<T: Equatable>(_ actual: T,
                             _ expected: T,
                             _ label: String = "",
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        checks += 1
        guard actual != expected else { return }
        header()
        let name = label.isEmpty ? "value" : label
        failures.append("\(file):\(line)  \(name): expected \(expected), got \(actual)")
        print("  ✗ \(name): expected \(expected), got \(actual)   (\(file):\(line))")
    }

    func notNil<T>(_ value: T?,
                   _ label: String = "value",
                   file: StaticString = #filePath,
                   line: UInt = #line) {
        checks += 1
        guard value == nil else { return }
        header()
        failures.append("\(file):\(line)  \(label) was nil")
        print("  ✗ \(label) was nil   (\(file):\(line))")
    }

    /// Asserts that the block throws and, optionally, that the thrown
    /// `UsageError` carries the expected stable code.
    func expectError(_ block: () throws -> Void,
                     code: String? = nil,
                     file: StaticString = #filePath,
                     line: UInt = #line) {
        checks += 1
        do {
            try block()
            header()
            failures.append("\(file):\(line)  expected an error, nothing was thrown")
            print("  ✗ expected an error, nothing was thrown   (\(file):\(line))")
        } catch let error as UsageError {
            if let code, error.code != code {
                header()
                failures.append("\(file):\(line)  expected error code \(code), got \(error.code)")
                print("  ✗ expected error code \(code), got \(error.code)   (\(file):\(line))")
            }
        } catch {
            // Any other error type is acceptable when no code is required.
        }
    }

    func finish() -> Never {
        print("\n\(checks) checks, \(failures.count) failure(s)")
        if !failures.isEmpty {
            print("FAILED")
            exit(1)
        }
        print("OK")
        exit(0)
    }
}

/// Shorthands so test bodies read like XCTest without the dependency.
let runner = TestRunner.shared

func suite(_ name: String) { runner.startSuite(name) }
func check(_ condition: Bool, _ message: @autoclosure () -> String,
           file: StaticString = #filePath, line: UInt = #line) {
    runner.check(condition, message(), file: file, line: line)
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
    runner.equal(actual, expected, label, file: file, line: line)
}
func expectNotNil<T>(_ value: T?, _ label: String = "value",
                     file: StaticString = #filePath, line: UInt = #line) {
    runner.notNil(value, label, file: file, line: line)
}
func expectError(_ block: () throws -> Void, code: String? = nil,
                 file: StaticString = #filePath, line: UInt = #line) {
    runner.expectError(block, code: code, file: file, line: line)
}

/// Loads a JSON fixture from the target's resource bundle.
func fixtureData(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
          let data = try? Data(contentsOf: url) else {
        runner.check(false, "missing fixture \(name).json", file: file, line: line)
        return Data()
    }
    return data
}
