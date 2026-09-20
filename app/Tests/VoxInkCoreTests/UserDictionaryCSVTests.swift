import Foundation
import Testing
@testable import VoxInkCore

struct UserDictionaryCSVTests {
    @Test func roundTripWithBOMAndQuotedFields() throws {
        let entry = try UserDictionaryEntry(source: "雨落", replacement: "语落")
        let rows = try UserDictionaryCSV.decode(UserDictionaryCSV.encode([entry]))
        #expect(rows.count == 1 && rows[0].source == entry.source && rows[0].replacement == entry.replacement)
        let quoted = try UserDictionaryCSV.decode(Data("source,replacement\r\n\"a,b\",\"c\"\"d\"\r\n".utf8))
        #expect(quoted[0].source == "a,b" && quoted[0].replacement == "c\"d")
    }
    @Test func rejectsMalformedAndOversizedFiles() {
        for text in ["a,b\nx,y", "source,replacement\na,b,c", "source,replacement\n\"a,b", "source,replacement\n\"a\"x,b"] {
            #expect(throws: UserDictionaryCSV.FormatError.self) { try UserDictionaryCSV.decode(Data(text.utf8)) }
        }
        #expect(throws: UserDictionaryCSV.FormatError.self) { try UserDictionaryCSV.decode(Data(repeating: 65, count: 131073)) }
        #expect(throws: UserDictionaryCSV.FormatError.self) { try UserDictionaryCSV.decode(Data([0xff])) }
    }
}
