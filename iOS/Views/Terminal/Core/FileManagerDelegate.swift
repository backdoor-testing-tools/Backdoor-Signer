import Foundation
import UIKit

// Protocol for FileManagerViewController delegate
protocol FileManagerViewControllerDelegate: AnyObject {
    func fileManager(_ fileManager: FileManagerViewController, didSelectDirectory directory: URL)
    func fileManager(_ fileManager: FileManagerViewController, didSelectFile file: URL)
    var terminalService: LocalTerminalService { get }
}

// Terminal View Controller extension for FileManagerViewController
extension TerminalViewController: FileManagerViewControllerDelegate {
    func fileManager(_ fileManager: FileManagerViewController, didSelectDirectory directory: URL) {
        // Update terminal's working directory
        terminalService.setCurrentWorkingDirectory(directory)
        appendToTerminal("\nChanged directory to: \(directory.path)\n$ ", isInput: false)
    }
    
    func fileManager(_ fileManager: FileManagerViewController, didSelectFile file: URL) {
        // Show file contents in terminal
        do {
            let content = try String(contentsOf: file, encoding: .utf8)
            appendToTerminal("\n\(content)\n$ ", isInput: false)
        } catch {
            appendToTerminal("\nError reading file: \(error.localizedDescription)\n$ ", isInput: false)
        }
    }
}