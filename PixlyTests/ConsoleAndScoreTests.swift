import Foundation
import Testing
@testable import Pixly

struct ConsoleBufferTests {
    @Test func writesAtTheCursorWithColours() {
        var console = ConsoleBuffer()
        console.textcolor(.black, .white)
        console.gotoxy(10, 3)
        console.write("Hi")
        #expect(console[10, 3] == .init(character: "H", foreground: .black, background: .white))
        #expect(console[11, 3].character == "i")
        #expect(console.cursorX == 12)
    }

    @Test func tabsAndNewlinesMoveLikePrintf() {
        var console = ConsoleBuffer()
        console.write("\t\t   X\nY")
        #expect(console[20, 1].character == "X")
        #expect(console[1, 2].character == "Y")
    }

    @Test func clipsOutsideTheScreen() {
        var console = ConsoleBuffer()
        console.gotoxy(0, 0)
        console.write("A")
        console.gotoxy(80, 25)
        console.write("BC")
        #expect(console[80, 25].character == "B")
        #expect(console.cells.filter { $0.character != " " }.count == 1)
    }

    @Test func clearScreenUsesTheCurrentColours() {
        var console = ConsoleBuffer()
        console.textcolor(.black, .white)
        console.clrscr()
        #expect(console.cells.allSatisfy { $0.background == .white })
    }
}

struct ScoreStoreTests {
    @Test func keepsScoresSortedAndPersists() throws {
        let defaults = try #require(UserDefaults(suiteName: "pixly-scores-\(UUID().uuidString)"))
        var store = ScoreStore(defaults: defaults)
        store.add(name: "Pascal", score: 854)
        store.add(name: "  ", score: 1084)
        store.add(name: "Jan", score: 202)
        #expect(store.entries.map(\.score) == [1084, 854, 202])
        #expect(store.entries.first?.name == "No Name")
        #expect(ScoreStore(defaults: defaults).entries == store.entries)
        #expect(store.highscore(900) == 1084)
        #expect(store.highscore(2000) == 2000)
    }
}
