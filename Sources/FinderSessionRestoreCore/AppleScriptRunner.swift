import Foundation

public protocol AppleScriptRunning {
    func run(_ source: String) throws -> String
}

public enum AppleScriptRunnerError: Error, LocalizedError {
    case executionFailed(String)
    case missingOutput

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return message
        case .missingOutput:
            return "AppleScript did not return a value."
        }
    }
}

public final class AppleScriptRunner: AppleScriptRunning {
    private let timeout: TimeInterval

    public convenience init() {
        self.init(timeout: 12)
    }

    public init(timeout: TimeInterval = 12) {
        self.timeout = timeout
    }

    public func run(_ source: String) throws -> String {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<String, Error>?

        DispatchQueue.global(qos: .userInitiated).async {
            let scriptResult: Result<String, Error>
            do {
                guard let script = NSAppleScript(source: source) else {
                    throw AppleScriptRunnerError.executionFailed("AppleScript could not be compiled.")
                }

                var error: NSDictionary?
                let descriptor = script.executeAndReturnError(&error)
                if let error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed."
                    throw AppleScriptRunnerError.executionFailed(message)
                }

                scriptResult = .success(descriptor.stringValue ?? "")
            } catch {
                scriptResult = .failure(error)
            }

            lock.lock()
            result = scriptResult
            lock.unlock()
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw AppleScriptRunnerError.executionFailed("AppleScript timed out after \(Int(timeout)) seconds.")
        }

        lock.lock()
        let finishedResult = result
        lock.unlock()

        switch finishedResult {
        case .success(let output):
            return output
        case .failure(let error):
            throw error
        case .none:
            throw AppleScriptRunnerError.missingOutput
        }
    }
}

public enum AppleScriptEscaper {
    public static func quotedString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
}
