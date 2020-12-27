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

class TextFile {
    let filepath : URL
    private var _contents : String

    // Reads the file and stores the contents 
    init(filepath:URL) throws {
        self.filepath = filepath
        _contents = try String(contentsOf:filepath, encoding: .utf8)
    }

    // Creates an object storing the filepath and contents
    init(filepath:URL, contents:String) {
        self.filepath = filepath
        _contents = contents
    }

    var contents : String {
        get {
            return _contents
        }
        set {
            _contents = newValue
        }
    }

    // Writes the contents to the specified filepath
    func write(targetFilepath:URL? = nil) throws {
        let finalTargetFilepath = targetFilepath ?? self.filepath
        try _contents.write(to: finalTargetFilepath, atomically: true, encoding: .utf8)
    }
    
}
