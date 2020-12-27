/*
merlin-journal-verification - Interacts with Merlin Mission Manager to
verify compliance of journal formatting, tagging, and pushing to GitHub
Copyright (C) 2020,2021 CoderMerlin.com
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
import Foundation

let gitExecutableURL = URL(fileURLWithPath: "/usr/bin/git", isDirectory: false)
let configurationURL = URL(fileURLWithPath: "journalVerification.config")
let gitCredentialsFilename = ".git-credentials"
let localJournalURL =  FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Journals")

enum VerificationError : Error {
    case requiredLocalTagNotPresent(tagName: String, errorMessage: String?)
    case gitCredentialFileMissing
    case gitCredentialFileLacksExactlyOneJournal(actualCount: Int)
    case repositoryURLUnparseable
    case repositoryURLLacksUserName
    case repositoryURLLacksPassword

    case cloneProcessFailed(errorMessage: String?)
    case checkoutProcessFailed(tagName: String, errorMessage: String?)
    case requiredLocalFileNotPresent(filePathname: String)
    case requiredRemoteFileNotPresent(filePathname: String)
}

infix operator =~
func =~(string:String, regex:String) -> Bool {
    let notFoundRange = NSRange(location: NSNotFound, length: 0)
    return string.range(of: regex, options: [.regularExpression]) != notFoundRange
}

infix operator !=~
func !=~(string:String, regex:String) -> Bool {
    return !(string =~ regex)
}

func printError(_ message: String) {
    fputs("\(message)\n", stderr)
}

func getLine(prompt: String) -> String? {
    print(prompt, terminator:"-> ")
    let line = readLine()
    if line?.isEmpty == true {
        return nil
    } else {
        return line
    }
}

func gatherInput() -> JournalRequirement {
    var tagRequirements = [TagRequirement]()
    while let tagName = getLine(prompt: "Enter tag name (or <RETURN> to end)") {
        var fileRequirements = [FileRequirement]()
        while let filePathname = getLine(prompt: "Enter filePathname (or <RETURN> to end)") {
            var regexMessages = [RegexMessage]()
            while let regex = getLine(prompt: "Enter regex (or <RETURN> to end)") {
                let message = getLine(prompt: "Enter message for regex (or <RETURN> to end)")
                if let message = message {
                    regexMessages.append(RegexMessage(regex: regex, message: message))
                }
            }
            fileRequirements.append(FileRequirement(filePathname: filePathname, regexMessages: regexMessages))
        }
        tagRequirements.append(TagRequirement(tagName: tagName, fileRequirements: fileRequirements))
    }
    return JournalRequirement(tagRequirements: tagRequirements)
}

func persistConfiguration(journalRequirement:JournalRequirement) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(journalRequirement)
    guard let contents = String(data: data, encoding: .utf8) else {
        fatalError("Failed to encode configuration using utf8")
    }
    let textFile = TextFile(filepath:configurationURL, contents: contents)
    try textFile.write()
}

func restoreConfiguration() throws -> JournalRequirement {
    let textFile = try TextFile(filepath: configurationURL)
    guard let data = textFile.contents.data(using: .utf8) else {
        fatalError("Failed to decode configuration using utf8")
    }
    let decoder = JSONDecoder()
    let journalRequirement = try decoder.decode(JournalRequirement.self, from: data)
    return journalRequirement
}

/// Clones the Journal repository to the current directory
/// Returns the URL to the cloned directory
func clone() throws -> URL {
    // Begin by opening the .git-credentials file and looking for a journal entry
    let homeDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    let gitCredentialsPathnameURL = homeDirectoryURL.appendingPathComponent(gitCredentialsFilename)

    // Verify that the file exists
    guard FileManager.default.fileExists(atPath: gitCredentialsPathnameURL.path) else {
        throw VerificationError.gitCredentialFileMissing
    }

    // Read the file
    let gitCredentialsText = try TextFile(filepath: gitCredentialsPathnameURL)

    // Find exactly one line that references 'journals', case insensitive
    var journalLines = [String]()
    for line in gitCredentialsText.contents.components(separatedBy: "\n") {
        if line.range(of: "journal", options: .caseInsensitive) != nil {
            journalLines.append(line)
        }
    }
    guard journalLines.count == 1 else {
        throw VerificationError.gitCredentialFileLacksExactlyOneJournal(actualCount: journalLines.count)
    }

    // Treat the line as a URL for easier parsing
    guard let repositoryURL = URL(string: journalLines[0]) else {
        throw VerificationError.repositoryURLUnparseable
    }

    // Verify that username and password are specified
    guard repositoryURL.user != nil else {
        throw VerificationError.repositoryURLLacksUserName
    }

    guard repositoryURL.password != nil else {
        throw VerificationError.repositoryURLLacksPassword
    }

    // Next, get the final path component which will be used for the
    // directory name
    // It may or may not contain an extension of (.git)
    // If so, we remove it
    let targetDirectoryName = repositoryURL.deletingPathExtension().lastPathComponent

    // Clone the repository
    let cloneTaskArguments = ["clone", repositoryURL.absoluteString, targetDirectoryName]
    let cloneTaskExecutor = TaskExecutor(executableURL: gitExecutableURL,
                                         arguments: cloneTaskArguments)
    let cloneTaskResult = cloneTaskExecutor.launchTaskAndWait()
    guard cloneTaskResult.terminationStatus == 0 else {
        throw VerificationError.cloneProcessFailed(errorMessage: cloneTaskResult.standardError)
    }

    return URL(fileURLWithPath: targetDirectoryName, isDirectory: true)
}

// When checking locally, we FIRST check the local file for expected content
// In this way, we can assist students to ensure that the content is correct BEFORE they tag 
func verifyLocalRepository(with journalRequirement: JournalRequirement) throws -> Bool {
    var success = true
    for tagRequirement in journalRequirement.tagRequirements {
        // Ignore the tag initially and begin checking directory contents

        for fileRequirement in tagRequirement.fileRequirements {
            // Verify the existance of each file
            let fileURL = localJournalURL.appendingPathComponent(fileRequirement.filePathname)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw VerificationError.requiredLocalFileNotPresent(filePathname: fileRequirement.filePathname) // Intentionally provide relative URL
            }
            let textFile = try TextFile(filepath: fileURL)
            let contents = textFile.contents 
            
            // Verify any regexes specified within the file
            // We simply print the error messages to standard output in this case
            // so we can collect all of the output at once
            for regexMessage in fileRequirement.regexMessages {
                if contents !=~ regexMessage.regex {
                    print("Required text is not present: \(regexMessage.message) in LOCAL file \(fileRequirement.filePathname)")
                    success = false
                }
            }
        }
        
        // After verifying content, if we're successful up to this point, we check for the tag
        // We check only to verify that it exists
        let tagTaskArguments = ["rev-list", "-n", "1", tagRequirement.tagName]
        let tagTaskExecutor = TaskExecutor(executableURL: gitExecutableURL,
                                           arguments: tagTaskArguments,
                                           workingDirectory: localJournalURL)
        let tagResult = tagTaskExecutor.launchTaskAndWait()
        guard tagResult.terminationStatus == 0 else {
            throw VerificationError.requiredLocalTagNotPresent(tagName: tagRequirement.tagName, errorMessage: tagResult.standardError)
        }
    }

    return success
}

func verifyRemoteRepository(at repositoryURL:URL, with journalRequirement: JournalRequirement) throws -> Bool {
    var success = true
    for tagRequirement in journalRequirement.tagRequirements {
        // Verify that we're able to check out the specified tag
        let checkoutTaskArguments = ["checkout", tagRequirement.tagName]
        let checkoutTaskExecutor = TaskExecutor(executableURL: gitExecutableURL,
                                                arguments: checkoutTaskArguments,
                                                workingDirectory: repositoryURL)
        let checkoutTaskResult = checkoutTaskExecutor.launchTaskAndWait()
        guard checkoutTaskResult.terminationStatus == 0 else {
            throw VerificationError.checkoutProcessFailed(tagName: tagRequirement.tagName, errorMessage: checkoutTaskResult.standardError)
        }

        for fileRequirement in tagRequirement.fileRequirements {
            // Verify the existance of each file
            let fileURL = repositoryURL.appendingPathComponent(fileRequirement.filePathname)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw VerificationError.requiredRemoteFileNotPresent(filePathname: fileRequirement.filePathname) // Intentionally provide relative URL
            }
            let textFile = try TextFile(filepath: fileURL)
            let contents = textFile.contents 
            
            // Verify any regexes specified within the file
            // We simply print the error messages to standard output in this case
            // so we can collect all of the output at once
            for regexMessage in fileRequirement.regexMessages {
                if contents !=~ regexMessage.regex {
                    print("Required text is not present: \(regexMessage.message) in REMOTE file \(fileRequirement.filePathname)")
                    success = false
                }
            }
        }
    }
    return success
}

do {
    // If a configuration file is present in the current directory, we use that for verification,
    // otherwise, we gather input, persist the configuration, and exit
    var success: Bool
    if FileManager.default.fileExists(atPath: configurationURL.path) {
        let journalRequirement = try restoreConfiguration()
        let repositoryURL = try clone()
        defer {
            try? FileManager.default.removeItem(at: repositoryURL)
        }
        success = try verifyLocalRepository(with: journalRequirement)
        success = try verifyRemoteRepository(at: repositoryURL, with: journalRequirement)
    } else {
        let journalRequirement = gatherInput()
        try persistConfiguration(journalRequirement: journalRequirement)
        success = false
    }
    if success {
        print("Conformance requirements fulfilled.")
    }
} catch VerificationError.requiredLocalTagNotPresent(let tagName, let errorMessage) {
    print("The required LOCAL tag \(tagName) was not found")
    if let errorMessage = errorMessage {
        print(errorMessage)
    }
} catch VerificationError.gitCredentialFileMissing {
    print("The git credentials file was not found")
} catch VerificationError.gitCredentialFileLacksExactlyOneJournal(let actualCount) {
    print("Failed to find exactly one journal entry in git credential file; found \(actualCount) instead")
} catch VerificationError.repositoryURLLacksUserName {
    print("Failed to find the username in the git credential entry")
} catch VerificationError.repositoryURLLacksPassword {
    print("Failed to find the password in the git credential entry")
} catch VerificationError.cloneProcessFailed(let errorMessage) {
    print("Failed to clone repository")
    if let errorMessage = errorMessage {
        print(errorMessage)
    }
} catch VerificationError.checkoutProcessFailed(let tagName, let errorMessage) {
    print("Failed to checkout repository at tag \(tagName)")
    if let errorMessage = errorMessage {
        print(errorMessage)
    }
} catch VerificationError.requiredLocalFileNotPresent(let filePathname) {
    print("Required LOCAL file not present: \(filePathname)")
} catch VerificationError.requiredRemoteFileNotPresent(let filePathname) {
    print("Required REMOTE file not present: \(filePathname)")
} catch {
    printError("An unexpected error occurred: \(error)")
    exit(1)
}

