import Foundation

/// LanguageInterpreter integrates the BackdoorLanguage with the terminal
class LanguageInterpreter {
    // Singleton instance
    static let shared = LanguageInterpreter()
    
    // Logger
    private let logger = Debug.shared
    
    // Language instance
    private let language = BackdoorLanguage.shared
    
    // Terminal service
    private let terminalService = LocalTerminalService.shared
    
    // Private initializer for singleton
    private init() {
        // Register language commands with the terminal
        registerLanguageCommands()
    }
    
    /// Register language commands with the terminal
    private func registerLanguageCommands() {
        // Register the language with the terminal service
        terminalService.registerBuiltInCommand("run") { [weak self] args, outputHandler, completion in
            guard let self = self else {
                completion(.failure(.executionFailed("Interpreter not available")))
                return
            }
            
            if args.isEmpty {
                outputHandler("Usage: run <filename> or run -e \"<code>\"")
                completion(.success(()))
                return
            }
            
            if args[0] == "-e" && args.count > 1 {
                // Execute code directly
                let code = args[1...].joined(separator: " ")
                self.executeCode(code, outputHandler: outputHandler, completion: completion)
            } else {
                // Execute code from file
                let filename = args[0]
                self.executeFile(filename, outputHandler: outputHandler, completion: completion)
            }
        }
        
        // Register the language help command
        terminalService.registerBuiltInCommand("lang-help") { _, outputHandler, completion in
            let helpText = """
            Backdoor Language Commands:
            
            run <filename>     - Execute a script file
            run -e "<code>"    - Execute code directly
            lang-help          - Show this help message
            
            Language Syntax:
            
            # Comments start with a hash
            
            # Variable assignment
            x = 10
            name = "John"
            
            # Function calls
            print("Hello, " + name)
            result = add(5, 10)
            
            # Built-in functions:
            print(...)         - Print values
            shell("command")   - Execute shell command
            add(a, b)          - Addition
            subtract(a, b)     - Subtraction
            multiply(a, b)     - Multiplication
            divide(a, b)       - Division
            read_file(path)    - Read file contents
            write_file(path, content) - Write to file
            length(str)        - Get string length
            substring(str, start, end) - Get substring
            array(...)         - Create array
            array_get(arr, index) - Get array element
            array_length(arr)  - Get array length
            """
            
            outputHandler(helpText)
            completion(.success(()))
        }
        
        logger.log(message: "Language commands registered with terminal", type: .info)
    }
    
    /// Execute code directly
    private func executeCode(_ code: String, outputHandler: @escaping (String) -> Void, completion: @escaping (LocalTerminalResult<Void>) -> Void) {
        // Execute the code
        language.executeScript(code, outputHandler: outputHandler)
        completion(.success(()))
    }
    
    /// Execute code from a file
    private func executeFile(_ filename: String, outputHandler: @escaping (String) -> Void, completion: @escaping (LocalTerminalResult<Void>) -> Void) {
        // Resolve the file path
        let fileURL: URL
        if filename.hasPrefix("/") {
            // Absolute path
            fileURL = URL(fileURLWithPath: filename)
        } else {
            // Relative path
            fileURL = terminalService.getCurrentWorkingDirectory().appendingPathComponent(filename)
        }
        
        // Read the file
        do {
            let code = try String(contentsOf: fileURL, encoding: .utf8)
            executeCode(code, outputHandler: outputHandler, completion: completion)
        } catch {
            outputHandler("Error: Could not read file: \(error.localizedDescription)")
            completion(.failure(.ioError("Could not read file: \(error.localizedDescription)")))
        }
    }
    
    /// Execute a single line of code
    func executeLine(_ line: String, outputHandler: @escaping (String) -> Void) -> Any? {
        return language.executeLine(line, outputHandler: outputHandler)
    }
    
    /// Register a custom function
    func registerFunction(_ name: String, function: @escaping ([Any]) -> Any?) {
        language.registerFunction(name, function: function)
    }
}