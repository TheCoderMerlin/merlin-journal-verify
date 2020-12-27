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

class TaskExecutor {

    static let waitTimeoutMicrosecondsDefault : UInt32 = 5_000_000 // 5 seconds

    /// Set upon initilization
    let executableURL : URL
    let arguments : [String]?
    let standardInput : String?
    let waitTimeoutMicroseconds : UInt32
    let workingDirectory : URL?

    struct CompletionStatus {
        let timedOut : Bool

        // The following may be nil if the process was terminated because of timing out
        // That is, the following will be nil unless timedOut is false
        let terminationStatus : Int32?
        let terminationReason : Process.TerminationReason? 
        let standardOutput : String? 
        let standardError : String?

        func didExitSuccessfully(ignoreTerminationStatus:Bool = false) -> Bool {
            return (!timedOut &&
                    (ignoreTerminationStatus || terminationStatus == 0) &&
                    terminationReason == Process.TerminationReason.exit &&
                    (standardError == nil || standardError!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
    }


    init(executableURL:URL, arguments:[String]? = nil, standardInput:String? = nil, waitTimeoutMicroseconds:UInt32 = TaskExecutor.waitTimeoutMicrosecondsDefault, workingDirectory:URL? = nil) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.standardInput = standardInput
        self.waitTimeoutMicroseconds = waitTimeoutMicroseconds
        self.workingDirectory = workingDirectory
    }


    /// Launches and executes the task, waiting for it to either complete or timeout
    func launchTaskAndWait() -> CompletionStatus {
        let microSecondsBetweenChecks : UInt32 = 100_000 // 100ms
        
        // Create and initialize the task
        let task = Process()
        task.executableURL = executableURL
        task.arguments = arguments

        // Set working directory if specified
        if let workingDirectory = workingDirectory {
            task.currentDirectoryURL = workingDirectory
        }

        // Allocate and assign pipes
        var standardInputPipe : Pipe? = nil
        if standardInput != nil {
            standardInputPipe = Pipe()
            task.standardInput = standardInputPipe
        }
        
        let standardOutputPipe = Pipe()
        task.standardOutput = standardOutputPipe
        
        let standardErrorPipe = Pipe()
        task.standardError = standardErrorPipe

        // Assume we did not timeout at this point
        var timedOut = false

        // Launch the task
        do {
            try task.run()
        } catch {
            return CompletionStatus(timedOut:true, terminationStatus:nil, terminationReason:nil, standardOutput:nil, standardError:error.localizedDescription) 
        }

        // If an input pipe has been specified, push the input into the pipe
        // Reference: https://gist.github.com/profburke/c6a39a034077584f8dbafe591bcb526d
        if let standardInputPipe = standardInputPipe,
           let standardInput = standardInput {
            let bytes : [UInt8] = Array(standardInput.utf8)
            let fileHandle = standardInputPipe.fileHandleForWriting
            fileHandle.write(Data(bytes))
            fileHandle.closeFile()
        }

        // Monitor the task for completion or timeout
        var elapsedUS : UInt32 = 0
        while task.isRunning {
            elapsedUS += microSecondsBetweenChecks
            usleep(microSecondsBetweenChecks)


            // If we've timed out, note this and exit the loop
            if (elapsedUS >= waitTimeoutMicroseconds) {
                timedOut = true
                break
            }
        }

        // If the task is still running, terminate it
        if task.isRunning {
            task.terminate()
        }

        // Wait for the task to complete execution
        task.waitUntilExit()
        

        // Obtain the string data from the pipes (only if we didn't time out, otherwise this will block)
        if (!timedOut) {
            return CompletionStatus(timedOut:false, terminationStatus: task.terminationStatus, terminationReason:task.terminationReason,
                                    standardOutput:obtainPipeContents(pipe:standardOutputPipe),
                                    standardError:obtainPipeContents(pipe:standardErrorPipe))
        } else {
            return CompletionStatus(timedOut:true, terminationStatus:nil, terminationReason:nil, standardOutput:nil, standardError:nil)
        }
    } // func launchTaskAndWait

    /// Reads from the pipe and returns a string 
    private func obtainPipeContents(pipe:Pipe) -> String? {
        var returnString : String? = nil
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: String.Encoding.utf8) {
            let string = output.trimmingCharacters(in:.whitespaces)
            if string.count > 0 {
                returnString = string
            }
        }

        return returnString
    }

} // class TaskExecutor

