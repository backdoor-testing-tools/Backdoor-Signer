# Terminal Implementation

This directory contains the implementation of the on-device terminal for the Backdoor-Signer app.

## Features

- Fully on-device terminal implementation (no external dependencies)
- Built-in shell command execution
- File system navigation and management
- Custom programming language support
- Visual file browser

## Components

### Core Terminal

- `LocalTerminalService.swift`: Core service for executing commands on-device
- `TerminalViewController.swift`: UI controller for the terminal
- `TerminalTextView.swift`: Custom text view for terminal output
- `CommandInputView.swift`: Input view for entering commands
- `CommandHistory.swift`: Manages command history

### File Management

- `FileManagerViewController.swift`: Visual file browser
- `TextEditorViewController.swift`: Text editor for files
- `FileManagerDelegate.swift`: Protocol for file manager integration

### Custom Language

- `BackdoorLanguage.swift`: Custom programming language implementation
- `LanguageInterpreter.swift`: Integrates the language with the terminal

## Usage

### Basic Commands

- `ls`: List directory contents
- `cd <dir>`: Change directory
- `pwd`: Print working directory
- `mkdir <dir>`: Create directory
- `rm <file/dir>`: Remove file or directory
- `touch <file>`: Create empty file
- `cat <file>`: Display file contents
- `clear`: Clear terminal screen
- `help`: Show help message

### Language Commands

- `run <file>`: Run a script file
- `run -e "<code>"`: Execute code directly
- `lang-help`: Show language help

### Language Syntax

```
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
```

## Implementation Details

The terminal implementation uses Swift's Process API to execute shell commands on-device. It provides a secure, sandboxed environment for running commands within the app's container.

The custom programming language is a simple interpreter that supports variables, function calls, and basic operations. It integrates with the terminal to provide a scripting capability for automating tasks.

The file browser provides a visual way to navigate the file system, create and edit files, and manage directories. It integrates with the terminal to provide a seamless experience.