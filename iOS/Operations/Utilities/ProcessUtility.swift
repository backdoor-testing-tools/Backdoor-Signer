import Foundation

/// Utility for executing shell commands
class ProcessUtility {
    // Singleton instance
    static let shared = ProcessUtility()
    
    // Logger
    private let logger = Debug.shared
    
    // Terminal service
    private let terminalService = LocalTerminalService.shared
    
    // Private initializer for singleton
    private init() {}
    
    /// Execute a shell command and return the output
    func executeShellCommand(_ command: String, completion: @escaping (String?) -> Void) {
        var output = ""
        
        // Execute the command using the terminal service
        terminalService.executeCommand(command, outputHandler: { chunk in
            output += chunk
        }) { result in
            switch result {
            case .success:
                completion(output)
            case .failure(let error):
                self.logger.log(message: "Shell command execution failed: \(error.localizedDescription)", type: .error)
                completion(nil)
            }
        }
    }
}