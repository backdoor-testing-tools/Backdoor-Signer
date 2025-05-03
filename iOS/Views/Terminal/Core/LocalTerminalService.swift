import Foundation
import UIKit

/// Error types for the local terminal service
enum LocalTerminalError: Error {
    case processCreationFailed
    case executionFailed(String)
    case invalidCommand
    case permissionDenied
    case ioError(String)
    case timeout
    
    var localizedDescription: String {
        switch self {
        case .processCreationFailed:
            return "Failed to create process"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .invalidCommand:
            return "Invalid command"
        case .permissionDenied:
            return "Permission denied"
        case .ioError(let message):
            return "I/O error: \(message)"
        case .timeout:
            return "Command execution timed out"
        }
    }
}

typealias LocalTerminalResult<T> = Result<T, LocalTerminalError>

/// A service that provides terminal functionality using on-device process execution
class LocalTerminalService {
    // Singleton instance
    static let shared = LocalTerminalService()
    
    // Logger
    private let logger = Debug.shared
    
    // Current working directory
    private var currentWorkingDirectory: URL
    
    // Environment variables
    private var environmentVariables: [String: String]
    
    // Active processes
    private var activeProcesses: [UUID: Process] = [:]
    
    // Command history
    private var commandHistory: [String] = []
    private let maxHistoryItems = 100
    
    // Session ID for the current terminal session
    private var sessionId = UUID()
    
    // Initialization
    private init() {
        // Set initial working directory to Documents
        currentWorkingDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Set up environment variables
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
        env["HOME"] = NSHomeDirectory()
        env["USER"] = UIDevice.current.name
        env["TMPDIR"] = NSTemporaryDirectory()
        environmentVariables = env
        
        logger.log(message: "LocalTerminalService initialized", type: .info)
        
        // Load command history
        loadCommandHistory()
    }
    
    // MARK: - Public Methods
    
    /// Get the current session ID
    func getCurrentSessionId(completion: @escaping (String?) -> Void) {
        completion(sessionId.uuidString)
    }
    
    /// Create a new terminal session
    func createSession(completion: @escaping (LocalTerminalResult<String>) -> Void) {
        // Generate a new session ID
        sessionId = UUID()
        
        // Reset working directory to Documents
        currentWorkingDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        logger.log(message: "Created new terminal session: \(sessionId.uuidString)", type: .info)
        completion(.success(sessionId.uuidString))
    }
    
    /// Execute a command in the terminal
    func executeCommand(
        _ command: String,
        outputHandler: @escaping (String) -> Void,
        completion: @escaping (LocalTerminalResult<Void>) -> Void
    ) {
        // Trim the command
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip empty commands
        guard !trimmedCommand.isEmpty else {
            completion(.success(()))
            return
        }
        
        // Add to history
        addToHistory(command: trimmedCommand)
        
        // Check for built-in commands
        if handleBuiltInCommand(trimmedCommand, outputHandler: outputHandler) {
            completion(.success(()))
            return
        }
        
        // Execute the command
        executeShellCommand(trimmedCommand, outputHandler: outputHandler, completion: completion)
    }
    
    /// Get the command history
    func getCommandHistory() -> [String] {
        return commandHistory
    }
    
    /// Clear the command history
    func clearCommandHistory() {
        commandHistory.removeAll()
        saveCommandHistory()
    }
    
    /// Get the current working directory
    func getCurrentWorkingDirectory() -> URL {
        return currentWorkingDirectory
    }
    
    /// Set the current working directory
    func setCurrentWorkingDirectory(_ url: URL) {
        currentWorkingDirectory = url
    }
    
    // MARK: - Private Methods
    
    // Custom built-in command handler type
    typealias BuiltInCommandHandler = ([String], @escaping (String) -> Void, @escaping (LocalTerminalResult<Void>) -> Void) -> Void
    
    // Dictionary of custom built-in commands
    private var customBuiltInCommands: [String: BuiltInCommandHandler] = [:]
    
    /// Register a built-in command
    func registerBuiltInCommand(_ name: String, handler: @escaping BuiltInCommandHandler) {
        customBuiltInCommands[name] = handler
    }
    
    /// Handle built-in commands
    private func handleBuiltInCommand(_ command: String, outputHandler: @escaping (String) -> Void) -> Bool {
        // Split the command into components
        let components = command.components(separatedBy: .whitespaces)
        guard let firstComponent = components.first else { return false }
        
        // Check for custom built-in commands
        if let handler = customBuiltInCommands[firstComponent] {
            let args = Array(components.dropFirst())
            handler(args, outputHandler) { _ in }
            return true
        }
        
        // Handle standard built-in commands
        switch firstComponent {
        case "cd":
            // Change directory command
            if components.count > 1 {
                let path = components.dropFirst().joined(separator: " ")
                return changeDirectory(path, outputHandler: outputHandler)
            } else {
                // cd without arguments goes to home directory
                return changeDirectory("~", outputHandler: outputHandler)
            }
            
        case "clear":
            // Clear command - handled by the view controller
            outputHandler("\u{001B}[2J\u{001B}[H") // ANSI escape sequence to clear screen
            return true
            
        case "pwd":
            // Print working directory
            outputHandler(currentWorkingDirectory.path)
            return true
            
        case "exit":
            // Exit command - handled by the view controller
            outputHandler("exit")
            return true
            
        case "help":
            // Help command
            showHelp(outputHandler: outputHandler)
            return true
            
        default:
            return false
        }
    }
    
    /// Show help information
    private func showHelp(outputHandler: @escaping (String) -> Void) {
        let helpText = """
        Available Commands:
        
        File System:
        - ls: List directory contents
        - cd <dir>: Change directory
        - pwd: Print working directory
        - mkdir <dir>: Create directory
        - rm <file/dir>: Remove file or directory
        - touch <file>: Create empty file
        - cat <file>: Display file contents
        
        Terminal:
        - clear: Clear terminal screen
        - history: Show command history
        - help: Show this help message
        
        System:
        - uname: Print system information
        - whoami: Print current user
        - date: Show current date and time
        - env: Show environment variables
        
        Language:
        - run <file>: Run a script file
        - run -e "<code>": Execute code directly
        - lang-help: Show language help
        
        Press the folder button to browse files visually.
        """
        
        outputHandler(helpText)
    }
    
    /// Change the current working directory
    private func changeDirectory(_ path: String, outputHandler: @escaping (String) -> Void) -> Bool {
        var targetPath = path
        
        // Handle home directory shorthand
        if targetPath.hasPrefix("~") {
            targetPath = (targetPath as NSString).replacingOccurrences(
                of: "~",
                with: NSHomeDirectory(),
                options: .anchored
            )
        }
        
        // Handle relative paths
        var targetURL: URL
        if targetPath.hasPrefix("/") {
            // Absolute path
            targetURL = URL(fileURLWithPath: targetPath)
        } else {
            // Relative path
            targetURL = currentWorkingDirectory.appendingPathComponent(targetPath)
        }
        
        // Resolve any symbolic links and standardize the path
        targetURL = targetURL.standardized
        
        // Check if directory exists
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            // Update working directory
            currentWorkingDirectory = targetURL
            return true
        } else {
            // Directory doesn't exist
            outputHandler("cd: \(path): No such file or directory")
            return true
        }
    }
    
    /// Execute a shell command
    private func executeShellCommand(
        _ command: String,
        outputHandler: @escaping (String) -> Void,
        completion: @escaping (LocalTerminalResult<Void>) -> Void
    ) {
        // Create a unique ID for this process
        let processId = UUID()
        
        // Create a process
        let process = Process()
        
        // Set up the process
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = currentWorkingDirectory
        process.environment = environmentVariables
        
        // Set up pipes for stdout and stderr
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Set up a pipe for stdin if needed
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        
        // Store the process
        activeProcesses[processId] = process
        
        // Set up output handling
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        // Set up asynchronous reading from stdout
        outputHandle.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            
            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        outputHandler(output)
                    }
                }
            }
        }
        
        // Set up asynchronous reading from stderr
        errorHandle.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            
            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        outputHandler(output)
                    }
                }
            }
        }
        
        // Set up termination handler
        process.terminationHandler = { [weak self] process in
            guard let self = self else { return }
            
            // Clean up file handles
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            
            // Remove process from active processes
            self.activeProcesses.removeValue(forKey: processId)
            
            // Check termination status
            if process.terminationStatus == 0 {
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(.executionFailed("Process terminated with status \(process.terminationStatus)")))
                }
            }
        }
        
        // Start the process
        do {
            try process.run()
            logger.log(message: "Started process for command: \(command)", type: .info)
        } catch {
            logger.log(message: "Failed to start process: \(error.localizedDescription)", type: .error)
            completion(.failure(.processCreationFailed))
        }
    }
    
    /// Send input to a running process
    func sendInput(_ input: String, to processId: UUID) -> Bool {
        guard let process = activeProcesses[processId],
              process.isRunning,
              let inputPipe = process.standardInput as? Pipe else {
            return false
        }
        
        // Send input to the process
        if let data = (input + "\n").data(using: .utf8) {
            do {
                try inputPipe.fileHandleForWriting.write(contentsOf: data)
                return true
            } catch {
                logger.log(message: "Failed to send input to process: \(error.localizedDescription)", type: .error)
                return false
            }
        }
        
        return false
    }
    
    /// Terminate a running process
    func terminateProcess(_ processId: UUID) -> Bool {
        guard let process = activeProcesses[processId], process.isRunning else {
            return false
        }
        
        process.terminate()
        return true
    }
    
    // MARK: - Command History Management
    
    /// Add a command to the history
    private func addToHistory(command: String) {
        // Don't add duplicates consecutively
        if let lastCommand = commandHistory.first, lastCommand == command {
            return
        }
        
        // Add to the beginning of the array
        commandHistory.insert(command, at: 0)
        
        // Trim history if needed
        if commandHistory.count > maxHistoryItems {
            commandHistory = Array(commandHistory.prefix(maxHistoryItems))
        }
        
        // Save history
        saveCommandHistory()
    }
    
    /// Save command history to UserDefaults
    private func saveCommandHistory() {
        UserDefaults.standard.set(commandHistory, forKey: "terminal_command_history")
    }
    
    /// Load command history from UserDefaults
    private func loadCommandHistory() {
        if let history = UserDefaults.standard.stringArray(forKey: "terminal_command_history") {
            commandHistory = history
        }
    }
}

// MARK: - File System Operations

extension LocalTerminalService {
    /// Get the contents of a directory
    func getDirectoryContents(path: String? = nil) -> [URL]? {
        let directoryURL: URL
        
        if let path = path {
            if path.hasPrefix("/") {
                // Absolute path
                directoryURL = URL(fileURLWithPath: path)
            } else {
                // Relative path
                directoryURL = currentWorkingDirectory.appendingPathComponent(path)
            }
        } else {
            // Current directory
            directoryURL = currentWorkingDirectory
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return contents
        } catch {
            logger.log(message: "Failed to get directory contents: \(error.localizedDescription)", type: .error)
            return nil
        }
    }
    
    /// Get file information
    func getFileInfo(for url: URL) -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            logger.log(message: "Failed to get file info: \(error.localizedDescription)", type: .error)
            return nil
        }
    }
    
    /// Create a directory
    func createDirectory(at path: String) -> Bool {
        let directoryURL: URL
        
        if path.hasPrefix("/") {
            // Absolute path
            directoryURL = URL(fileURLWithPath: path)
        } else {
            // Relative path
            directoryURL = currentWorkingDirectory.appendingPathComponent(path)
        }
        
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            return true
        } catch {
            logger.log(message: "Failed to create directory: \(error.localizedDescription)", type: .error)
            return false
        }
    }
    
    /// Delete a file or directory
    func deleteItem(at path: String) -> Bool {
        let itemURL: URL
        
        if path.hasPrefix("/") {
            // Absolute path
            itemURL = URL(fileURLWithPath: path)
        } else {
            // Relative path
            itemURL = currentWorkingDirectory.appendingPathComponent(path)
        }
        
        do {
            try FileManager.default.removeItem(at: itemURL)
            return true
        } catch {
            logger.log(message: "Failed to delete item: \(error.localizedDescription)", type: .error)
            return false
        }
    }
}