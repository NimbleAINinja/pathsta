import Foundation
import PathstaCore
import Testing

@Suite("zoxide client")
struct ZoxideClientTests {
  @Test("Treats plain words as zoxide keywords")
  func keywordsFromPlainWords() {
    #expect(ZoxideClient.keywords(from: "  ffm   wt ") == ["ffm", "wt"])
    #expect(ZoxideClient.keywords(from: "src/pathsta") == ["src/pathsta"])
  }

  @Test(
    "Never sends explicit paths to zoxide",
    arguments: [
      "", "   ", "/Users/nobody", "~", "~/Documents", ".", "..", "./build", "../other",
      "file:///tmp", "FILE:///tmp",
    ])
  func explicitPathsAreNotKeywords(text: String) {
    #expect(ZoxideClient.keywords(from: text) == nil)
  }

  @Test("Lists ranked matches that still exist as folders")
  func listsExistingMatches() throws {
    try withFakeZoxide { fake in
      let first = try fake.makeDirectory("first")
      let second = try fake.makeDirectory("second")
      let file = fake.root.appending(path: "plain-file")
      try Data().write(to: file)
      try fake.setOutput([first.path, "/pathsta/missing/folder", file.path, second.path])

      let matches = fake.client.matches(for: "fi se", excluding: nil)

      #expect(matches.map(\.path) == [first.path, second.path])
      #expect(try fake.recordedArguments() == ["query", "--list", "--", "fi", "se"])
    }
  }

  @Test("Excludes the current Finder folder and caps the result count")
  func excludesCurrentFolderAndCapsResults() throws {
    try withFakeZoxide { fake in
      let folders = try (1...4).map { try fake.makeDirectory("folder\($0)") }
      try fake.setOutput(folders.map(\.path))

      let matches = fake.client.matches(
        for: "folder",
        excluding: URL(filePath: "/tmp/current", directoryHint: .isDirectory),
        maximumResults: 2
      )

      #expect(matches.map(\.path) == [folders[0].path, folders[1].path])
      #expect(
        try fake.recordedArguments() == [
          "query", "--list", "--exclude", "/tmp/current", "--", "folder",
        ]
      )
    }
  }

  @Test("Keeps option-like keywords behind the argument terminator")
  func optionLikeKeywords() throws {
    try withFakeZoxide { fake in
      try fake.setOutput([])
      _ = fake.client.matches(for: "--interactive", excluding: nil)
      #expect(try fake.recordedArguments() == ["query", "--list", "--", "--interactive"])
    }
  }

  @Test("Does not run zoxide for explicit paths")
  func explicitPathSkipsQuery() throws {
    try withFakeZoxide { fake in
      let folder = try fake.makeDirectory("folder")
      try fake.setOutput([folder.path])

      #expect(fake.client.matches(for: "/not/a/keyword", excluding: nil).isEmpty)
      #expect(try fake.recordedArguments() == nil)
    }
  }

  @Test("Returns nothing when zoxide fails")
  func failingExecutable() throws {
    try withFakeZoxide(exitCode: 1) { fake in
      let folder = try fake.makeDirectory("folder")
      try fake.setOutput([folder.path])
      #expect(fake.client.matches(for: "folder", excluding: nil).isEmpty)
    }
  }

  @Test("Reports zoxide as unavailable when no executable exists")
  func missingExecutable() {
    let client = ZoxideClient(
      executableCandidates: [URL(filePath: "/pathsta/no/such/zoxide")]
    )
    #expect(!client.isAvailable)
    #expect(client.matches(for: "anything", excluding: nil).isEmpty)
    #expect(!client.add(URL(filePath: "/tmp", directoryHint: .isDirectory)))
  }

  @Test("Stops a zoxide process that exceeds the timeout")
  func timesOut() throws {
    try withFakeZoxide(body: "exec sleep 30", timeout: 0.2) { fake in
      let started = Date()
      #expect(fake.client.matches(for: "slow", excluding: nil).isEmpty)
      #expect(Date().timeIntervalSince(started) < 5)
    }
  }

  @Test("Records a visited folder")
  func addsDirectory() throws {
    try withFakeZoxide { fake in
      let folder = try fake.makeDirectory("visited")
      #expect(fake.client.add(folder))
      #expect(try fake.recordedArguments() == ["add", "--", folder.path])
    }
  }

  @Test("Offers matches as Tab completions that end with a slash")
  func completions() throws {
    try withFakeZoxide { fake in
      let first = try fake.makeDirectory("first")
      let second = try fake.makeDirectory("second")
      try fake.setOutput([first.path, second.path])

      let text = "fi"
      let completions = fake.client.completions(
        for: text,
        selection: NSRange(location: 2, length: 0),
        relativeTo: nil
      )

      #expect(completions == [first.path + "/", second.path + "/"])
    }
  }

  @Test("Offers no completions while the insertion point is inside the text")
  func completionsNeedTrailingInsertionPoint() throws {
    try withFakeZoxide { fake in
      let first = try fake.makeDirectory("first")
      try fake.setOutput([first.path])

      let completions = fake.client.completions(
        for: "first",
        selection: NSRange(location: 2, length: 0),
        relativeTo: nil
      )

      #expect(completions.isEmpty)
      #expect(try fake.recordedArguments() == nil)
    }
  }
}

@Suite("Jump resolution")
struct JumpResolverTests {
  @Test("Prefers a real folder over a zoxide match")
  func prefersRealFolder() throws {
    try withFakeZoxide { fake in
      let real = try fake.makeDirectory("real")
      let other = try fake.makeDirectory("other")
      try fake.setOutput([other.path])

      let resolved = try JumpResolver.resolve(
        "real",
        relativeTo: fake.root,
        zoxide: fake.client
      ).get()

      #expect(resolved.path == real.resolvingSymlinksInPath().path)
      #expect(try fake.recordedArguments() == nil)
    }
  }

  @Test("Falls back to the best zoxide match when no folder has that name")
  func fallsBackToZoxide() throws {
    try withFakeZoxide { fake in
      let target = try fake.makeDirectory("deep/target")
      try fake.setOutput([target.path])

      let resolved = try JumpResolver.resolve(
        "tar",
        relativeTo: fake.root,
        zoxide: fake.client
      ).get()

      #expect(resolved.path == target.resolvingSymlinksInPath().path)
      #expect(
        try fake.recordedArguments() == [
          "query", "--list", "--exclude", fake.root.path, "--", "tar",
        ]
      )
    }
  }

  @Test("Keeps the original error when zoxide has no match")
  func keepsErrorWithoutMatch() throws {
    try withFakeZoxide { fake in
      try fake.setOutput([])
      let result = JumpResolver.resolve("nothing", relativeTo: fake.root, zoxide: fake.client)
      guard case .failure(.notDirectory) = result else {
        Issue.record("A missing folder was accepted: \(result)")
        return
      }
    }
  }

  @Test("Behaves like plain path resolution without zoxide")
  func worksWithoutZoxide() throws {
    try withFakeZoxide { fake in
      let result = JumpResolver.resolve("nothing", relativeTo: fake.root, zoxide: nil)
      guard case .failure(.notDirectory) = result else {
        Issue.record("A missing folder was accepted: \(result)")
        return
      }
      let recordedArguments = try fake.recordedArguments()
      #expect(recordedArguments == nil)
    }
  }

  @Test("Does not fall back for an explicit path that is missing")
  func explicitMissingPath() throws {
    try withFakeZoxide { fake in
      let target = try fake.makeDirectory("target")
      try fake.setOutput([target.path])
      let result = JumpResolver.resolve(
        "/pathsta/missing/target",
        relativeTo: fake.root,
        zoxide: fake.client
      )
      guard case .failure(.notDirectory) = result else {
        Issue.record("An explicit missing path jumped elsewhere: \(result)")
        return
      }
    }
  }
}

/// A stand-in zoxide executable that records its arguments and prints canned output.
private struct FakeZoxide {
  let root: URL
  let client: ZoxideClient

  private var outputFile: URL { root.appending(path: "output.txt") }
  private var argumentsFile: URL { root.appending(path: "arguments.txt") }

  func makeDirectory(_ name: String) throws -> URL {
    let directory = root.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return URL(filePath: directory.path, directoryHint: .isDirectory)
  }

  func setOutput(_ lines: [String]) throws {
    let text = lines.map { $0 + "\n" }.joined()
    try text.write(to: outputFile, atomically: true, encoding: .utf8)
  }

  func recordedArguments() throws -> [String]? {
    guard FileManager.default.fileExists(atPath: argumentsFile.path) else {
      return nil
    }
    let text = try String(contentsOf: argumentsFile, encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
  }
}

private func withFakeZoxide(
  exitCode: Int = 0,
  body: String? = nil,
  timeout: TimeInterval = 5,
  _ operation: (FakeZoxide) throws -> Void
) throws {
  let fileManager = FileManager.default
  let root = fileManager.temporaryDirectory
    .appending(path: "pathsta-zoxide-\(UUID().uuidString)", directoryHint: .isDirectory)
    .resolvingSymlinksInPath()
  try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
  defer { try? fileManager.removeItem(at: root) }

  let executable = root.appending(path: "zoxide")
  let defaultBody = """
    printf '%s\\n' "$@" > '\(root.path)/arguments.txt'
    [ -f '\(root.path)/output.txt' ] && cat '\(root.path)/output.txt'
    exit \(exitCode)
    """
  let script = "#!/bin/sh\n\(body ?? defaultBody)\n"
  try script.write(to: executable, atomically: true, encoding: .utf8)
  try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

  try operation(
    FakeZoxide(
      root: root,
      client: ZoxideClient(executableCandidates: [executable], timeout: timeout)
    )
  )
}
