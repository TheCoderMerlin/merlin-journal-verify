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
struct TagRequirement: Codable {
    let tagName: String // The tag to (attempt) to retrieve from the repository
    let fileRequirements: [FileRequirement]
}

