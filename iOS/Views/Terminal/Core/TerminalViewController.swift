import UIKit

// MARK: - File System Models

struct FileItem {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date?
    
    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        
        // Get file attributes
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            self.isDirectory = isDirectory.boolValue
        } else {
            self.isDirectory = false
        }
        
        // Get file size and modification date
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            self.size = attributes[.size] as? Int64 ?? 0
            self.modificationDate = attributes[.modificationDate] as? Date
        } catch {
            self.size = 0
            self.modificationDate = nil
        }
    }
}

class TerminalViewController: UIViewController {
    // MARK: - UI Components

    private let terminalOutputTextView = TerminalTextView()
    private let commandInputView = CommandInputView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let toolbar = UIToolbar()
    private let fileSystemButton = UIButton(type: .system)

    // MARK: - Properties

    private let history = CommandHistory()
    private var isExecuting = false
    private let logger = Debug.shared
    private let terminalService = LocalTerminalService.shared
    private var currentSessionId: String?
    private var currentWorkingDirectory: URL {
        return terminalService.getCurrentWorkingDirectory()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupKeyboardNotifications()
        setupActions()

        // Load command history
        history.loadHistory()
        
        // Create a new terminal session
        createTerminalSession()

        // Set title
        title = "Terminal"

        // Welcome message
        let deviceInfo = UIDevice.current.name
        let iosVersion = UIDevice.current.systemVersion
        appendToTerminal("On-Device Terminal\n", isInput: false)
        appendToTerminal("Device: \(deviceInfo) (iOS \(iosVersion))\n", isInput: false)
        appendToTerminal("Type 'help' for available commands\n", isInput: false)
        appendToTerminal("$ ", isInput: false)

        logger.log(message: "Terminal view controller loaded", type: .info)
    }
    
    /// Create a new terminal session
    private func createTerminalSession() {
        terminalService.createSession { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let sessionId):
                self.currentSessionId = sessionId
                self.logger.log(message: "Created terminal session: \(sessionId)", type: .info)
                
            case .failure(let error):
                self.logger.log(message: "Failed to create terminal session: \(error.localizedDescription)", type: .error)
                self.appendToTerminal("Error: Failed to initialize terminal session\n", isInput: false)
            }
        }
    }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        commandInputView.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Save command history when leaving view
        history.saveHistory()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            // Notify the terminal text view about the interface style change
            NotificationCenter.default.post(name: .didChangeUserInterfaceStyle, object: nil)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        logger.log(message: "Terminal view controller deallocated", type: .info)
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = UIColor(named: "Background") ?? UIColor.systemBackground

        // Set navigation bar title and style
        title = "Terminal"
        navigationItem.largeTitleDisplayMode = .never

        // Add a close button if presented modally
        if presentingViewController != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(dismissTerminal)
            )
        }

        // Terminal output setup
        terminalOutputTextView.isEditable = false

        // Apply font size from settings
        let fontSize = UserDefaults.standard.integer(forKey: "terminal_font_size")
        terminalOutputTextView.font = UIFont.monospacedSystemFont(
            ofSize: fontSize > 0 ? CGFloat(fontSize) : 14,
            weight: .regular
        )

        // Command input setup
        commandInputView.placeholder = "Enter command..."
        commandInputView.returnKeyType = .send
        commandInputView.autocorrectionType = .no
        commandInputView.autocapitalizationType = .none
        commandInputView.delegate = self

        // Activity indicator
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = .systemBlue

        // File system button setup
        fileSystemButton.setImage(UIImage(systemName: "folder"), for: .normal)
        fileSystemButton.addTarget(self, action: #selector(showFileSystem), for: .touchUpInside)
        fileSystemButton.layer.cornerRadius = 20
        fileSystemButton.backgroundColor = .systemBlue
        fileSystemButton.tintColor = .white
        fileSystemButton.layer.shadowColor = UIColor.black.cgColor
        fileSystemButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        fileSystemButton.layer.shadowOpacity = 0.3
        fileSystemButton.layer.shadowRadius = 3

        // Toolbar setup
        setupToolbar()

        // Add subviews
        view.addSubview(terminalOutputTextView)
        view.addSubview(commandInputView)
        view.addSubview(activityIndicator)
        view.addSubview(fileSystemButton)
    }
    
    @objc private func showFileSystem() {
        // Create and present file browser
        let fileManager = FileManagerViewController(directory: currentWorkingDirectory)
        fileManager.delegate = self
        
        let navController = UINavigationController(rootViewController: fileManager)
        present(navController, animated: true)
    }

    private func setupToolbar() {
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        let clearButton = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(clearTerminal)
        )
        clearButton.accessibilityLabel = "Clear Terminal"

        let historyUpButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up"),
            style: .plain,
            target: self,
            action: #selector(historyUp)
        )
        historyUpButton.accessibilityLabel = "Previous Command"

        let historyDownButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.down"),
            style: .plain,
            target: self,
            action: #selector(historyDown)
        )
        historyDownButton.accessibilityLabel = "Next Command"

        let tabButton = UIBarButtonItem(
            title: "Tab",
            style: .plain,
            target: self,
            action: #selector(insertTab)
        )

        let ctrlCButton = UIBarButtonItem(
            title: "Ctrl+C",
            style: .plain,
            target: self,
            action: #selector(sendCtrlC)
        )
        ctrlCButton.accessibilityLabel = "Interrupt Command"
        
        // Help button
        let helpButton = UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            style: .plain,
            target: self,
            action: #selector(showHelp)
        )
        helpButton.accessibilityLabel = "Terminal Help"

        // Current directory button
        let pwdButton = UIBarButtonItem(
            image: UIImage(systemName: "location"),
            style: .plain,
            target: self,
            action: #selector(showCurrentDirectory)
        )
        pwdButton.accessibilityLabel = "Show Current Directory"

        toolbar.items = [
            clearButton,
            flexSpace,
            historyUpButton,
            historyDownButton,
            flexSpace,
            tabButton,
            flexSpace,
            ctrlCButton,
            flexSpace,
            pwdButton,
            flexSpace,
            helpButton,
        ]
        toolbar.sizeToFit()
        commandInputView.inputAccessoryView = toolbar
    }
    
    @objc private func showHelp() {
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
        
        Press the folder button to browse files visually.
        """
        
        appendToTerminal("\n\(helpText)\n\n$ ", isInput: false)
        scrollToBottom()
    }
    
    @objc private func showCurrentDirectory() {
        appendToTerminal("\n\(currentWorkingDirectory.path)\n$ ", isInput: false)
        scrollToBottom()
    }

    private func setupConstraints() {
        terminalOutputTextView.translatesAutoresizingMaskIntoConstraints = false
        commandInputView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        fileSystemButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Terminal output
            terminalOutputTextView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            terminalOutputTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalOutputTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Command input
            commandInputView.topAnchor.constraint(equalTo: terminalOutputTextView.bottomAnchor),
            commandInputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commandInputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commandInputView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            commandInputView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            // Activity indicator
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            // File system button
            fileSystemButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            fileSystemButton.bottomAnchor.constraint(equalTo: commandInputView.topAnchor, constant: -20),
            fileSystemButton.widthAnchor.constraint(equalToConstant: 40),
            fileSystemButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func setupKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func setupActions() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        terminalOutputTextView.addGestureRecognizer(tapGesture)
    }

    // MARK: - Terminal Functions

    private func executeCommand(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendToTerminal("\n$ ", isInput: false)
            return
        }

        // Add to history
        history.addCommand(command)
        appendToTerminal("\n", isInput: false)
        
        // Show activity indicator
        isExecuting = true
        activityIndicator.startAnimating()

        // Handle special commands
        if command.lowercased() == "clear" {
            // Clear the terminal
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.terminalOutputTextView.text = ""
                self.appendToTerminal("$ ", isInput: false)
                self.activityIndicator.stopAnimating()
                self.isExecuting = false
            }
            return
        } else if command.lowercased() == "help" {
            // Show help
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.showHelp()
                self.activityIndicator.stopAnimating()
                self.isExecuting = false
            }
            return
        } else if command.lowercased() == "history" {
            // Show command history
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let historyList = self.history.getHistory().enumerated().map { index, cmd in
                    return "  \(index + 1)  \(cmd)"
                }.joined(separator: "\n")
                
                self.appendToTerminal("\n\(historyList)\n\n$ ", isInput: false)
                self.scrollToBottom()
                self.activityIndicator.stopAnimating()
                self.isExecuting = false
            }
            return
        }

        // Create a stream handler to receive real-time updates
        let streamHandler: (String) -> Void = { [weak self] outputChunk in
            DispatchQueue.main.async {
                guard let self = self, self.isExecuting else { return }
                self.appendToTerminalStreaming(outputChunk)
            }
        }

        logger.log(message: "Executing command: \(command)", type: .info)

        // Execute with on-device terminal service
        terminalService.executeCommand(command, outputHandler: streamHandler) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.activityIndicator.stopAnimating()
                self.isExecuting = false

                switch result {
                case .success:
                    // Terminal output already updated incrementally via streamHandler
                    break
                case let .failure(error):
                    self.appendToTerminal("\nError: \(error.localizedDescription)", isInput: false)
                }

                self.appendToTerminal("\n$ ", isInput: false)
                self.scrollToBottom()
            }
        }
    }

    // Append streaming output to terminal
    private func appendToTerminalStreaming(_ text: String) {
        guard !text.isEmpty else { return }

        // Get the appropriate color based on text type and theme
        let colorTheme = UserDefaults.standard.integer(forKey: "terminal_color_theme")

        let outputColor: UIColor
        switch colorTheme {
        case 1: // Light theme
            outputColor = .systemGreen
        case 2: // Dark theme
            outputColor = .green
        case 3: // Solarized
            outputColor = UIColor(red: 0.52, green: 0.6, blue: 0.0, alpha: 1.0)
        default: // Default theme
            outputColor = traitCollection.userInterfaceStyle == .dark ? .green : .systemGreen
        }

        // Create attributed string for the new chunk
        let attributedString = NSMutableAttributedString(string: text)
        attributedString.addAttribute(.foregroundColor,
                                      value: outputColor,
                                      range: NSRange(location: 0, length: text.count))

        // Append to existing text
        let newAttributedText = NSMutableAttributedString(attributedString: terminalOutputTextView
            .attributedText ?? NSAttributedString())
        newAttributedText.append(attributedString)
        terminalOutputTextView.attributedText = newAttributedText

        // Scroll to bottom with each update for real-time feedback
        scrollToBottom()
    }

    private func appendToTerminal(_ text: String, isInput: Bool) {
        let attributedString = NSMutableAttributedString(string: text)

        // Get the appropriate color based on text type and theme
        let colorTheme = UserDefaults.standard.integer(forKey: "terminal_color_theme")

        if isInput {
            let userInputColor: UIColor
            switch colorTheme {
            case 1: // Light theme
                userInputColor = .systemBlue
            case 2: // Dark theme
                userInputColor = .cyan
            case 3: // Solarized
                userInputColor = UIColor(red: 0.15, green: 0.55, blue: 0.82, alpha: 1.0)
            default: // Default theme
                userInputColor = traitCollection.userInterfaceStyle == .dark ? .cyan : .systemBlue
            }

            attributedString.addAttribute(.foregroundColor,
                                          value: userInputColor,
                                          range: NSRange(location: 0, length: text.count))
        } else {
            let outputColor: UIColor
            switch colorTheme {
            case 1: // Light theme
                outputColor = .systemGreen
            case 2: // Dark theme
                outputColor = .green
            case 3: // Solarized
                outputColor = UIColor(red: 0.52, green: 0.6, blue: 0.0, alpha: 1.0)
            default: // Default theme
                outputColor = traitCollection.userInterfaceStyle == .dark ? .green : .systemGreen
            }

            attributedString.addAttribute(.foregroundColor,
                                          value: outputColor,
                                          range: NSRange(location: 0, length: text.count))
        }

        let newAttributedText = NSMutableAttributedString(attributedString: terminalOutputTextView
            .attributedText ?? NSAttributedString())
        newAttributedText.append(attributedString)
        terminalOutputTextView.attributedText = newAttributedText
        scrollToBottom()
    }

    private func scrollToBottom() {
        if !terminalOutputTextView.text.isEmpty {
            let location = terminalOutputTextView.text.count - 1
            let bottom = NSRange(location: location, length: 1)
            terminalOutputTextView.scrollRangeToVisible(bottom)
        }
    }

    // MARK: - Actions

    @objc private func clearTerminal() {
        terminalOutputTextView.text = ""
        appendToTerminal("$ ", isInput: false)
    }

    @objc private func historyUp() {
        if let previousCommand = history.getPreviousCommand() {
            commandInputView.text = previousCommand
        }
    }

    @objc private func historyDown() {
        if let nextCommand = history.getNextCommand() {
            commandInputView.text = nextCommand
        } else {
            commandInputView.text = ""
        }
    }

    @objc private func insertTab() {
        commandInputView.insertText("\t")
    }

    @objc private func sendCtrlC() {
        if isExecuting {
            // Send interrupt signal
            appendToTerminal("^C", isInput: false)
            executeCommand("\u{0003}") // Ctrl+C character
        }
    }

    @objc private func handleTap() {
        commandInputView.becomeFirstResponder()
    }

    @objc private func keyboardWillShow(_: Notification) {
        scrollToBottom()
    }

    @objc private func keyboardWillHide(_: Notification) {
        // Handle keyboard hiding if needed
    }

    @objc private func dismissTerminal() {
        // Post notification to restore floating terminal button before dismissing
        NotificationCenter.default.post(name: .showTerminalButton, object: nil)

        // Also post to a more general notification that can be observed by other components
        NotificationCenter.default.post(name: Notification.Name("TerminalDismissed"), object: nil)

        // Explicitly tell the FloatingButtonManager to show if available
        DispatchQueue.main.async {
            FloatingButtonManager.shared.show()
        }

        // Log dismissal
        logger.log(message: "Terminal dismissed, floating button restored", type: .info)

        // Dismiss the terminal view controller
        dismiss(animated: true)
    }

    // MARK: - File Manager Integration
// MARK: - File Manager View Controller

class FileManagerViewController: UITableViewController {
    // Directory being displayed
    private var directory: URL
    
    // File items in the directory
    private var items: [FileItem] = []
    
    // Delegate to notify of directory changes
    weak var delegate: TerminalViewController?
    
    // Logger
    private let logger = Debug.shared
    
    // Initialize with a directory
    init(directory: URL) {
        self.directory = directory
        super.init(style: .grouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up the table view
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FileCell")
        
        // Set up navigation bar
        title = directory.lastPathComponent
        
        // Add create directory button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(createNewItem)
        )
        
        // Load directory contents
        loadDirectoryContents()
    }
    
    // Load the contents of the current directory
    private func loadDirectoryContents() {
        do {
            // Get directory contents
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: []
            )
            
            // Create file items
            items = contents.map { FileItem(url: $0) }
            
            // Sort items: directories first, then alphabetically
            items.sort { (item1, item2) -> Bool in
                if item1.isDirectory && !item2.isDirectory {
                    return true
                } else if !item1.isDirectory && item2.isDirectory {
                    return false
                } else {
                    return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
                }
            }
            
            // Reload table view
            tableView.reloadData()
        } catch {
            logger.log(message: "Error loading directory contents: \(error.localizedDescription)", type: .error)
            
            // Show error alert
            let alert = UIAlertController(
                title: "Error",
                message: "Could not load directory contents: \(error.localizedDescription)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    
    // MARK: - Table View Data Source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath)
        let item = items[indexPath.row]
        
        // Configure cell
        cell.textLabel?.text = item.name
        
        // Set icon based on file type
        if item.isDirectory {
            cell.imageView?.image = UIImage(systemName: "folder")
            cell.accessoryType = .disclosureIndicator
        } else {
            // Choose icon based on file extension
            let fileExtension = item.url.pathExtension.lowercased()
            
            switch fileExtension {
            case "txt", "md", "rtf", "swift", "h", "m", "c", "cpp", "java", "js", "html", "css", "xml", "json", "plist":
                cell.imageView?.image = UIImage(systemName: "doc.text")
            case "jpg", "jpeg", "png", "gif", "tiff", "bmp", "heic":
                cell.imageView?.image = UIImage(systemName: "photo")
            case "mp4", "mov", "avi", "mkv":
                cell.imageView?.image = UIImage(systemName: "film")
            case "mp3", "wav", "aac", "m4a":
                cell.imageView?.image = UIImage(systemName: "music.note")
            case "pdf":
                cell.imageView?.image = UIImage(systemName: "doc.fill")
            case "zip", "rar", "tar", "gz", "7z":
                cell.imageView?.image = UIImage(systemName: "archivebox")
            default:
                cell.imageView?.image = UIImage(systemName: "doc")
            }
            
            cell.accessoryType = .none
        }
        
        // Set tint color
        cell.imageView?.tintColor = .systemBlue
        
        return cell
    }
    
    // MARK: - Table View Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        
        if item.isDirectory {
            // Navigate to directory
            let fileManager = FileManagerViewController(directory: item.url)
            fileManager.delegate = delegate
            navigationController?.pushViewController(fileManager, animated: true)
        } else {
            // Show file preview
            previewFile(item)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let item = items[indexPath.row]
        
        // Delete action
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self = self else { return }
            
            // Confirm deletion
            let alert = UIAlertController(
                title: "Delete \(item.name)",
                message: "Are you sure you want to delete this \(item.isDirectory ? "directory" : "file")?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completion(false)
            })
            
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
                do {
                    try FileManager.default.removeItem(at: item.url)
                    self.items.remove(at: indexPath.row)
                    tableView.deleteRows(at: [indexPath], with: .automatic)
                    completion(true)
                } catch {
                    self.logger.log(message: "Error deleting item: \(error.localizedDescription)", type: .error)
                    
                    // Show error alert
                    let errorAlert = UIAlertController(
                        title: "Error",
                        message: "Could not delete item: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(errorAlert, animated: true)
                    
                    completion(false)
                }
            })
            
            self.present(alert, animated: true)
        }
        
        // Rename action
        let renameAction = UIContextualAction(style: .normal, title: "Rename") { [weak self] _, _, completion in
            guard let self = self else { return }
            
            // Show rename alert
            let alert = UIAlertController(
                title: "Rename \(item.name)",
                message: "Enter a new name:",
                preferredStyle: .alert
            )
            
            alert.addTextField { textField in
                textField.text = item.name
                textField.clearButtonMode = .whileEditing
                textField.autocapitalizationType = .none
                textField.autocorrectionType = .no
            }
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completion(false)
            })
            
            alert.addAction(UIAlertAction(title: "Rename", style: .default) { _ in
                guard let newName = alert.textFields?.first?.text, !newName.isEmpty else {
                    completion(false)
                    return
                }
                
                let newURL = self.directory.appendingPathComponent(newName)
                
                do {
                    try FileManager.default.moveItem(at: item.url, to: newURL)
                    self.loadDirectoryContents()
                    completion(true)
                } catch {
                    self.logger.log(message: "Error renaming item: \(error.localizedDescription)", type: .error)
                    
                    // Show error alert
                    let errorAlert = UIAlertController(
                        title: "Error",
                        message: "Could not rename item: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(errorAlert, animated: true)
                    
                    completion(false)
                }
            })
            
            self.present(alert, animated: true)
        }
        
        renameAction.backgroundColor = .systemBlue
        
        return UISwipeActionsConfiguration(actions: [deleteAction, renameAction])
    }
    
    // MARK: - Actions
    
    @objc private func createNewItem() {
        let alert = UIAlertController(
            title: "Create New",
            message: nil,
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "Directory", style: .default) { [weak self] _ in
            self?.createNewDirectory()
        })
        
        alert.addAction(UIAlertAction(title: "Text File", style: .default) { [weak self] _ in
            self?.createNewFile()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad support
        if let popoverController = alert.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(alert, animated: true)
    }
    
    private func createNewDirectory() {
        let alert = UIAlertController(
            title: "Create Directory",
            message: "Enter a name for the new directory:",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Directory Name"
            textField.clearButtonMode = .whileEditing
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self, let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            
            let newDirectoryURL = self.directory.appendingPathComponent(name)
            
            do {
                try FileManager.default.createDirectory(
                    at: newDirectoryURL,
                    withIntermediateDirectories: false,
                    attributes: nil
                )
                self.loadDirectoryContents()
            } catch {
                self.logger.log(message: "Error creating directory: \(error.localizedDescription)", type: .error)
                
                // Show error alert
                let errorAlert = UIAlertController(
                    title: "Error",
                    message: "Could not create directory: \(error.localizedDescription)",
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func createNewFile() {
        let alert = UIAlertController(
            title: "Create Text File",
            message: "Enter a name for the new file:",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "File Name"
            textField.clearButtonMode = .whileEditing
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self, let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            
            let newFileURL = self.directory.appendingPathComponent(name)
            
            do {
                try "".write(to: newFileURL, atomically: true, encoding: .utf8)
                self.loadDirectoryContents()
            } catch {
                self.logger.log(message: "Error creating file: \(error.localizedDescription)", type: .error)
                
                // Show error alert
                let errorAlert = UIAlertController(
                    title: "Error",
                    message: "Could not create file: \(error.localizedDescription)",
                    preferredStyle: .alert
                )
                errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(errorAlert, animated: true)
            }
        })
        
        present(alert, animated: true)
    }
    
    // Preview a file
    private func previewFile(_ item: FileItem) {
        // Check if file is a text file
        let fileExtension = item.url.pathExtension.lowercased()
        let textFileExtensions = ["txt", "md", "rtf", "swift", "h", "m", "c", "cpp", "java", "js", "html", "css", "xml", "json", "plist"]
        
        if textFileExtensions.contains(fileExtension) || fileExtension.isEmpty {
            // Show text editor
            do {
                let content = try String(contentsOf: item.url, encoding: .utf8)
                showTextEditor(for: item.url, content: content)
            } catch {
                logger.log(message: "Error reading file: \(error.localizedDescription)", type: .error)
                
                // Show error alert
                let alert = UIAlertController(
                    title: "Error",
                    message: "Could not read file: \(error.localizedDescription)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        } else {
            // Use document interaction controller for other file types
            let documentInteractionController = UIDocumentInteractionController(url: item.url)
            documentInteractionController.delegate = self
            documentInteractionController.presentPreview(animated: true)
        }
    }
    
    // Show text editor for a file
    private func showTextEditor(for url: URL, content: String) {
        let textEditor = TextEditorViewController(fileURL: url, content: content)
        let navController = UINavigationController(rootViewController: textEditor)
        present(navController, animated: true)
    }
    
    // Set the current directory in the terminal
    private func setTerminalDirectory() {
        delegate?.terminalService.setCurrentWorkingDirectory(directory)
        delegate?.appendToTerminal("\nChanged directory to: \(directory.path)\n$ ", isInput: false)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // If we're going back, update the terminal's working directory
        if isMovingFromParent {
            setTerminalDirectory()
        }
    }
}

// MARK: - UIDocumentInteractionControllerDelegate

extension FileManagerViewController: UIDocumentInteractionControllerDelegate {
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
}

// MARK: - Text Editor View Controller

class TextEditorViewController: UIViewController {
    private let textView = UITextView()
    private let fileURL: URL
    private var content: String
    private let logger = Debug.shared
    
    init(fileURL: URL, content: String) {
        self.fileURL = fileURL
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up the view
        view.backgroundColor = .systemBackground
        title = fileURL.lastPathComponent
        
        // Set up the text view
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.text = content
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Add save button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveFile)
        )
        
        // Add cancel button
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
    }
    
    @objc private func saveFile() {
        do {
            try textView.text.write(to: fileURL, atomically: true, encoding: .utf8)
            logger.log(message: "File saved: \(fileURL.path)", type: .info)
            dismiss(animated: true)
        } catch {
            logger.log(message: "Error saving file: \(error.localizedDescription)", type: .error)
            
            // Show error alert
            let alert = UIAlertController(
                title: "Error",
                message: "Could not save file: \(error.localizedDescription)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    
    @objc private func cancel() {
        // Check if content has changed
        if textView.text != content {
            // Show confirmation alert
            let alert = UIAlertController(
                title: "Unsaved Changes",
                message: "You have unsaved changes. Are you sure you want to discard them?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
                self?.dismiss(animated: true)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            present(alert, animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}

    /// Fetches WebDAV credentials from the server
    private func getWebDAVCredentials(completion: @escaping (Result<WebDAVCredentials, Error>) -> Void) {
        // First ensure we have a session
        TerminalService.shared.getCurrentSessionId { [weak self] sessionId in
            guard let self = self else { return }
            guard let sessionId = sessionId else {
                completion(.failure(NSError(
                    domain: "terminal",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No active terminal session"]
                )))
                return
            }

            self.logger.log(message: "Fetching WebDAV credentials for session \(sessionId)", type: .info)

            // Get base URL from TerminalService
            let baseURL = TerminalService.shared.baseURL
            guard !baseURL.isEmpty else {
                completion(.failure(NSError(
                    domain: "terminal",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"]
                )))
                return
            }

            // Create URL for WebDAV credentials
            guard let url = URL(string: "\(baseURL)/api/webdav/credentials?session_id=\(sessionId)") else {
                completion(.failure(NSError(
                    domain: "terminal",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid URL for WebDAV credentials"]
                )))
                return
            }

            // Create request
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            // Send request
            URLSession.shared.dataTask(with: request) { data, _, error in
                if let error = error {
                    self.logger.log(
                        message: "Network error fetching WebDAV credentials: \(error.localizedDescription)",
                        type: .error
                    )
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(NSError(
                        domain: "terminal",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "No data received from server"]
                    )))
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    let webDAVResponse = try decoder.decode(WebDAVResponse.self, from: data)
                    self.logger.log(message: "Successfully fetched WebDAV credentials", type: .info)
                    completion(.success(webDAVResponse.credentials))
                } catch {
                    self.logger.log(
                        message: "Error parsing WebDAV credentials: \(error.localizedDescription)",
                        type: .error
                    )
                    completion(.failure(error))
                }
            }.resume()
        }
    }

    /// Opens the WebDAV location in Files app
    private func openWebDAVLocation(credentials: WebDAVCredentials) {
        // Create WebDAV URL with embedded credentials
        guard var urlComponents = URLComponents(string: credentials.url) else {
            showErrorAlert(title: "Invalid URL", message: "The WebDAV URL provided by the server is invalid.")
            return
        }

        // Add credentials to URL for auto-login
        urlComponents.user = credentials.username
        urlComponents.password = credentials.password

        guard let finalURL = urlComponents.url else {
            showErrorAlert(title: "Invalid URL", message: "Could not create WebDAV URL with credentials.")
            return
        }

        logger.log(message: "Opening WebDAV location: \(credentials.url) (credentials hidden)", type: .info)

        // Try to open the URL directly (iOS 13+ can handle webdav:// URLs)
        if UIApplication.shared.canOpenURL(finalURL) {
            UIApplication.shared.open(finalURL, options: [:]) { success in
                if !success {
                    self.showWebDAVInstructions(credentials: credentials)
                }
            }
        } else {
            // Try to create a WebDAV bookmark file
            createWebDAVBookmark(for: finalURL) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case let .success(bookmarkURL):
                    // Try to open the bookmark file
                    UIApplication.shared.open(bookmarkURL, options: [:]) { success in
                        if !success {
                            // If all fails, show manual instructions
                            self.showWebDAVInstructions(credentials: credentials)
                        }
                    }

                case .failure:
                    // Show manual instructions if bookmark creation fails
                    self.showWebDAVInstructions(credentials: credentials)
                }
            }
        }
    }

    /// Creates a temporary WebDAV bookmark file
    private func createWebDAVBookmark(for url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
        let bookmarkFile = tempDir.appendingPathComponent("webdav_bookmark.webdavloc")

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>URL</key>
            <string>\(url.absoluteString)</string>
        </dict>
        </plist>
        """

        do {
            try plistContent.write(to: bookmarkFile, atomically: true, encoding: .utf8)
            completion(.success(bookmarkFile))
        } catch {
            logger.log(message: "Error creating WebDAV bookmark: \(error.localizedDescription)", type: .error)
            completion(.failure(error))
        }
    }

    /// Show instructions for manually connecting to WebDAV
    private func showWebDAVInstructions(credentials: WebDAVCredentials) {
        // Create alert with instructions and credentials
        let alert = UIAlertController(
            title: "Connect to Files",
            message: """
            To access your terminal files:

            1. Open the Files app
            2. Tap Browse > Three dots (•••) > Connect to Server
            3. Enter the following:

               URL: \(credentials.url)
               Username: \(credentials.username)
               Password: \(credentials.password)
            """,
            preferredStyle: .alert
        )

        // Add copy buttons for convenience
        alert.addAction(UIAlertAction(title: "Copy URL", style: .default) { _ in
            UIPasteboard.general.string = credentials.url
            self.showToast(message: "URL copied to clipboard")
        })

        alert.addAction(UIAlertAction(title: "Copy Username", style: .default) { _ in
            UIPasteboard.general.string = credentials.username
            self.showToast(message: "Username copied to clipboard")
        })

        alert.addAction(UIAlertAction(title: "Copy Password", style: .default) { _ in
            UIPasteboard.general.string = credentials.password
            self.showToast(message: "Password copied to clipboard")
        })

        // Add option to open Files app
        alert.addAction(UIAlertAction(title: "Open Files App", style: .default) { _ in
            let filesAppURL = URL(string: "shareddocuments://")!
            if UIApplication.shared.canOpenURL(filesAppURL) {
                UIApplication.shared.open(filesAppURL, options: [:], completionHandler: nil)
            }
        })

        alert.addAction(UIAlertAction(title: "Close", style: .cancel))

        present(alert, animated: true)
    }

    // MARK: - Helper Methods

    /// Show a quick toast message
    private func showToast(message: String) {
        let toastLabel = UILabel()
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.systemFont(ofSize: 14)
        toastLabel.text = message
        toastLabel.alpha = 0
        toastLabel.layer.cornerRadius = 10
        toastLabel.clipsToBounds = true
        toastLabel.numberOfLines = 0

        view.addSubview(toastLabel)
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toastLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100),
            toastLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            toastLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            toastLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])

        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseInOut, animations: {
            toastLabel.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.5, delay: 1.5, options: .curveEaseInOut, animations: {
                toastLabel.alpha = 0
            }, completion: { _ in
                toastLabel.removeFromSuperview()
            })
        })
    }

    /// Show error alert
    private func showErrorAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITextFieldDelegate

extension TerminalViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let command = textField.text, !isExecuting {
            appendToTerminal(command, isInput: true)
            executeCommand(command)
            textField.text = ""
        }
        return false
    }
}

// MARK: - TerminalService Extensions

extension TerminalService {
    /// Get the current session ID
    func getCurrentSessionId(completion: @escaping (String?) -> Void) {
        // Get current session ID from the service
        // Use the currentSessionId getter

        if let sessionId = TerminalService.shared.currentSessionId {
            completion(sessionId)
            return
        }

        // If no current session, create one
        createSession { result in
            switch result {
            case let .success(sessionId):
                completion(sessionId)
            case .failure:
                completion(nil)
            }
        }
    }
}
