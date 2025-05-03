import Foundation

/// BackdoorLanguage is a simple programming language implementation for the Backdoor-Signer app
class BackdoorLanguage {
    // Singleton instance
    static let shared = BackdoorLanguage()
    
    // Logger
    private let logger = Debug.shared
    
    // Terminal service for executing shell commands
    private let terminalService = LocalTerminalService.shared
    
    // Variables storage
    private var variables: [String: Any] = [:]
    
    // Functions storage
    private var functions: [String: ([Any]) -> Any?] = [:]
    
    // Private initializer for singleton
    private init() {
        // Register built-in functions
        registerBuiltInFunctions()
    }
    
    /// Register built-in functions
    private func registerBuiltInFunctions() {
        // print function
        functions["print"] = { args in
            let output = args.map { "\($0)" }.joined(separator: " ")
            print(output)
            return output
        }
        
        // shell function
        functions["shell"] = { [weak self] args in
            guard let self = self else { return nil }
            
            if let command = args.first as? String {
                // Create a semaphore to wait for the result
                let semaphore = DispatchSemaphore(value: 0)
                var result: String?
                
                // Execute the command
                var output = ""
                self.terminalService.executeCommand(command, outputHandler: { chunk in
                    output += chunk
                }) { cmdResult in
                    switch cmdResult {
                    case .success:
                        result = output
                    case .failure:
                        result = nil
                    }
                    semaphore.signal()
                }
                
                // Wait for the command to complete (with timeout)
                _ = semaphore.wait(timeout: .now() + 30)
                return result
            }
            return nil
        }
        
        // math functions
        functions["add"] = { args in
            guard args.count >= 2 else { return nil }
            
            if let a = args[0] as? Int, let b = args[1] as? Int {
                return a + b
            } else if let a = args[0] as? Double, let b = args[1] as? Double {
                return a + b
            } else if let a = args[0] as? String, let b = args[1] as? String {
                return a + b
            }
            return nil
        }
        
        functions["subtract"] = { args in
            guard args.count >= 2 else { return nil }
            
            if let a = args[0] as? Int, let b = args[1] as? Int {
                return a - b
            } else if let a = args[0] as? Double, let b = args[1] as? Double {
                return a - b
            }
            return nil
        }
        
        functions["multiply"] = { args in
            guard args.count >= 2 else { return nil }
            
            if let a = args[0] as? Int, let b = args[1] as? Int {
                return a * b
            } else if let a = args[0] as? Double, let b = args[1] as? Double {
                return a * b
            }
            return nil
        }
        
        functions["divide"] = { args in
            guard args.count >= 2 else { return nil }
            
            if let a = args[0] as? Int, let b = args[1] as? Int, b != 0 {
                return a / b
            } else if let a = args[0] as? Double, let b = args[1] as? Double, b != 0 {
                return a / b
            }
            return nil
        }
        
        // file operations
        functions["read_file"] = { args in
            guard let path = args.first as? String else { return nil }
            
            do {
                let fileURL = URL(fileURLWithPath: path)
                return try String(contentsOf: fileURL, encoding: .utf8)
            } catch {
                return nil
            }
        }
        
        functions["write_file"] = { args in
            guard args.count >= 2,
                  let path = args[0] as? String,
                  let content = args[1] as? String else { return nil }
            
            do {
                let fileURL = URL(fileURLWithPath: path)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        }
        
        // string operations
        functions["length"] = { args in
            guard let str = args.first as? String else { return nil }
            return str.count
        }
        
        functions["substring"] = { args in
            guard args.count >= 3,
                  let str = args[0] as? String,
                  let start = args[1] as? Int,
                  let end = args[2] as? Int else { return nil }
            
            let startIndex = str.index(str.startIndex, offsetBy: max(0, start))
            let endIndex = str.index(str.startIndex, offsetBy: min(str.count, end))
            
            if startIndex <= endIndex {
                return String(str[startIndex..<endIndex])
            }
            return ""
        }
        
        // array operations
        functions["array"] = { args in
            return args
        }
        
        functions["array_get"] = { args in
            guard args.count >= 2,
                  let array = args[0] as? [Any],
                  let index = args[1] as? Int else { return nil }
            
            if index >= 0 && index < array.count {
                return array[index]
            }
            return nil
        }
        
        functions["array_length"] = { args in
            guard let array = args.first as? [Any] else { return nil }
            return array.count
        }
    }
    
    /// Execute a script
    func executeScript(_ script: String, outputHandler: @escaping (String) -> Void) -> Any? {
        let lines = script.components(separatedBy: .newlines)
        var result: Any?
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            
            // Execute the line
            result = executeLine(trimmedLine, outputHandler: outputHandler)
        }
        
        return result
    }
    
    /// Execute a single line of code
    func executeLine(_ line: String, outputHandler: @escaping (String) -> Void) -> Any? {
        // Variable assignment
        if line.contains("=") {
            return handleVariableAssignment(line, outputHandler: outputHandler)
        }
        
        // Function call
        if line.contains("(") && line.contains(")") {
            return handleFunctionCall(line, outputHandler: outputHandler)
        }
        
        // Variable reference
        if !line.contains(" ") {
            return variables[line]
        }
        
        outputHandler("Error: Invalid syntax: \(line)")
        return nil
    }
    
    /// Handle variable assignment
    private func handleVariableAssignment(_ line: String, outputHandler: @escaping (String) -> Void) -> Any? {
        let components = line.components(separatedBy: "=")
        guard components.count >= 2 else {
            outputHandler("Error: Invalid assignment: \(line)")
            return nil
        }
        
        let variableName = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let valueExpression = components[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Evaluate the right-hand side
        let value = evaluateExpression(valueExpression, outputHandler: outputHandler)
        
        // Store the variable
        variables[variableName] = value
        
        return value
    }
    
    /// Handle function call
    private func handleFunctionCall(_ line: String, outputHandler: @escaping (String) -> Void) -> Any? {
        guard let openParenIndex = line.firstIndex(of: "(") else {
            outputHandler("Error: Invalid function call: \(line)")
            return nil
        }
        
        let functionName = line[..<openParenIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let function = functions[functionName] else {
            outputHandler("Error: Unknown function: \(functionName)")
            return nil
        }
        
        // Extract arguments
        guard let closeParenIndex = line.lastIndex(of: ")") else {
            outputHandler("Error: Missing closing parenthesis: \(line)")
            return nil
        }
        
        let argsString = line[line.index(after: openParenIndex)..<closeParenIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let args = parseArguments(argsString, outputHandler: outputHandler)
        
        // Call the function
        let result = function(args)
        
        // If it's a print function, output the result
        if functionName == "print", let output = result as? String {
            outputHandler(output)
        }
        
        return result
    }
    
    /// Parse function arguments
    private func parseArguments(_ argsString: String, outputHandler: @escaping (String) -> Void) -> [Any] {
        if argsString.isEmpty {
            return []
        }
        
        var args: [Any] = []
        var currentArg = ""
        var inString = false
        var parenLevel = 0
        
        for char in argsString {
            if char == "\"" {
                inString = !inString
                currentArg.append(char)
            } else if char == "," && !inString && parenLevel == 0 {
                // End of argument
                let arg = evaluateExpression(currentArg.trimmingCharacters(in: .whitespacesAndNewlines), outputHandler: outputHandler)
                args.append(arg ?? NSNull())
                currentArg = ""
            } else if char == "(" {
                parenLevel += 1
                currentArg.append(char)
            } else if char == ")" {
                parenLevel -= 1
                currentArg.append(char)
            } else {
                currentArg.append(char)
            }
        }
        
        // Add the last argument
        if !currentArg.isEmpty {
            let arg = evaluateExpression(currentArg.trimmingCharacters(in: .whitespacesAndNewlines), outputHandler: outputHandler)
            args.append(arg ?? NSNull())
        }
        
        return args
    }
    
    /// Evaluate an expression
    private func evaluateExpression(_ expression: String, outputHandler: @escaping (String) -> Void) -> Any? {
        // String literal
        if expression.hasPrefix("\"") && expression.hasSuffix("\"") {
            let startIndex = expression.index(after: expression.startIndex)
            let endIndex = expression.index(before: expression.endIndex)
            return String(expression[startIndex..<endIndex])
        }
        
        // Number literal
        if let intValue = Int(expression) {
            return intValue
        }
        
        if let doubleValue = Double(expression) {
            return doubleValue
        }
        
        // Boolean literal
        if expression == "true" {
            return true
        }
        
        if expression == "false" {
            return false
        }
        
        // Function call
        if expression.contains("(") && expression.contains(")") {
            return handleFunctionCall(expression, outputHandler: outputHandler)
        }
        
        // Variable reference
        if !expression.contains(" ") {
            return variables[expression]
        }
        
        return nil
    }
    
    /// Register a custom function
    func registerFunction(_ name: String, function: @escaping ([Any]) -> Any?) {
        functions[name] = function
    }
    
    /// Set a variable
    func setVariable(_ name: String, value: Any) {
        variables[name] = value
    }
    
    /// Get a variable
    func getVariable(_ name: String) -> Any? {
        return variables[name]
    }
    
    /// Clear all variables
    func clearVariables() {
        variables.removeAll()
    }
}