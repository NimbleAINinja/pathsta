import AppKit
import PathstaCore
import Testing

@testable import Pathsta

@Suite("zoxide jumps")
struct ZoxideJumpsTests {
  @Test("Offers jump completions only while enabled")
  @MainActor
  func followsPreference() throws {
    try withJumps(executable: "/usr/bin/true") { jumps, editor in
      #expect(jumps.isAvailable)
      #expect(jumps.isEnabled)
      #expect(jumps.activeClient != nil)
      #expect(editor.jumpCompletionProvider != nil)

      jumps.isEnabled = false

      #expect(jumps.activeClient == nil)
      #expect(editor.jumpCompletionProvider == nil)
    }
  }

  @Test("Stays inactive when zoxide isn't installed")
  @MainActor
  func inactiveWithoutZoxide() throws {
    try withJumps(executable: "/pathsta/no/such/zoxide") { jumps, editor in
      #expect(!jumps.isAvailable)
      #expect(jumps.isEnabled)
      #expect(jumps.activeClient == nil)
      #expect(editor.jumpCompletionProvider == nil)
    }
  }

  @Test("Resolves real folders without consulting zoxide")
  @MainActor
  func resolvesRealFolders() throws {
    try withJumps(executable: "/usr/bin/true") { jumps, _ in
      let resolved = try jumps.resolve("/tmp", relativeTo: nil).get()
      #expect(resolved.path == URL(filePath: "/tmp").resolvingSymlinksInPath().path)
    }
  }
}

@MainActor
private func withJumps(
  executable: String,
  _ operation: @MainActor (ZoxideJumps, PathEditorView) throws -> Void
) throws {
  _ = NSApplication.shared
  let suiteName = "ZoxideJumpsTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let editor = PathEditorView(frame: NSRect(x: 0, y: 0, width: 720, height: 28))
  let jumps = ZoxideJumps(
    client: ZoxideClient(executableCandidates: [URL(filePath: executable)]),
    preferences: PathstaPreferences(defaults: defaults)
  )
  jumps.attach(to: editor)
  try operation(jumps, editor)
}
