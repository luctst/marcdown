import AppKit
import Testing

@testable import MarcdownEditor

@Suite("EditorCommand chord table")
struct EditorCommandTests {
    @Test func commandBoldAndShiftCommandQuote() {
        #expect(EditorCommand.command(forKey: "b", keyCode: 11, modifiers: [.command]) == .bold)
        #expect(EditorCommand.command(forKey: "B", keyCode: 11, modifiers: [.command, .shift]) == .quote)
    }

    @Test func extraModifiersDoNotMatch() {
        #expect(EditorCommand.command(forKey: "b", keyCode: 11, modifiers: [.command, .option]) == nil)
        #expect(EditorCommand.command(forKey: "b", keyCode: 11, modifiers: [.command, .control]) == nil)
    }

    @Test func capsLockIsIgnored() {
        #expect(EditorCommand.command(forKey: "B", keyCode: 11, modifiers: [.command, .capsLock]) == .bold)
    }

    @Test func headingsMatchPhysicalDigitKeys() {
        #expect(EditorCommand.command(forKey: "&", keyCode: 18, modifiers: [.command, .option]) == .heading(1))
        #expect(EditorCommand.command(forKey: "6", keyCode: 22, modifiers: [.command, .option]) == .heading(6))
        #expect(EditorCommand.command(forKey: "0", keyCode: 29, modifiers: [.command, .option]) == .heading(0))
        #expect(EditorCommand.command(forKey: "1", keyCode: 18, modifiers: [.command]) == nil)
    }

    @Test func remainingChords() {
        #expect(EditorCommand.command(forKey: "i", keyCode: 34, modifiers: [.command]) == .italic)
        #expect(EditorCommand.command(forKey: "e", keyCode: 14, modifiers: [.command]) == .inlineCode)
        #expect(EditorCommand.command(forKey: "x", keyCode: 7, modifiers: [.command, .shift]) == .strikethrough)
        #expect(EditorCommand.command(forKey: "h", keyCode: 4, modifiers: [.command, .shift]) == .highlight)
        #expect(EditorCommand.command(forKey: "k", keyCode: 40, modifiers: [.command, .shift]) == .link)
        #expect(EditorCommand.command(forKey: "l", keyCode: 37, modifiers: [.command, .shift]) == .bulletList)
        #expect(EditorCommand.command(forKey: "n", keyCode: 45, modifiers: [.command, .shift]) == .orderedList)
        #expect(EditorCommand.command(forKey: "t", keyCode: 17, modifiers: [.command, .shift]) == .taskList)
    }
}
