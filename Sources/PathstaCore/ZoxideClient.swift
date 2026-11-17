import Foundation

/// Queries and updates the user's zoxide directory database through the zoxide command.
public struct ZoxideClient: Sendable {
  /// The locations searched for zoxide, because apps don't inherit the shell's `PATH`.
  public static let defaultExecutableCandidates: [URL] = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
      URL(filePath: "/opt/homebrew/bin/zoxide"),
      URL(filePath: "/usr/local/bin/zoxide"),
      home.appending(path: ".cargo/bin/zoxide"),
      home.appending(path: ".local/bin/zoxide"),
      home.appending(path: ".nix-profile/bin/zoxide"),
      URL(filePath: "/run/current-system/sw/bin/zoxide"),
    ]
  }()

  private static let explicitPathPrefixes = ["/", "~", "./", "../", "file:"]

  private let executable: URL?
  private let timeout: TimeInterval

  /// Creates a client that uses the first executable candidate present on disk.
  public init(
    executableCandidates: [URL] = ZoxideClient.defaultExecutableCandidates,
    timeout: TimeInterval = 2
  ) {
    self.executable = executableCandidates.first {
      FileManager.default.isExecutableFile(atPath: $0.path)
    }
    self.timeout = timeout
  }

  /// Whether a zoxide executable was found.
  public var isAvailable: Bool {
    executable != nil
  }

  /// Splits text into zoxide keywords, or returns `nil` when the text is an explicit path.
  public static func keywords(from text: String) -> [String]? {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty, trimmedText != ".", trimmedText != ".." else {
      return nil
    }
    let lowercasedText = trimmedText.lowercased()
    guard !explicitPathPrefixes.contains(where: lowercasedText.hasPrefix) else {
      return nil
    }
    return trimmedText.split(whereSeparator: \.isWhitespace).map(String.init)
  }

  /// Returns zoxide's ranked matches for keyword text, keeping only folders that exist.
  public func matches(
    for text: String,
    excluding currentDirectory: URL?,
    maximumResults: Int = 20,
    fileManager: FileManager = .default
  ) -> [URL] {
    guard maximumResults > 0, let keywords = Self.keywords(from: text) else {
      return []
    }

    var arguments = ["query", "--list"]
    if let currentDirectory {
      arguments += ["--exclude", currentDirectory.path]
    }
    arguments.append("--")
    arguments += keywords
    guard let output = run(arguments) else {
      return []
    }

    var matches: [URL] = []
    for line in output.split(whereSeparator: \.isNewline) {
      var isDirectory = ObjCBool(false)
      guard
        fileManager.fileExists(atPath: String(line), isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        continue
      }
      matches.append(URL(filePath: String(line), directoryHint: .isDirectory))
      if matches.count == maximumResults {
        break
      }
    }
    return matches
  }

  /// Returns zoxide matches as replacement text for Tab completion.
  public func completions(
    for text: String,
    selection: NSRange,
    relativeTo currentDirectory: URL?,
    maximumResults: Int = 20
  ) -> [String] {
    guard selection.location == (text as NSString).length else {
      return []
    }
    return matches(
      for: text,
      excluding: currentDirectory,
      maximumResults: maximumResults
    ).map { directory in
      directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
    }
  }

  /// Records a visit so the folder ranks higher in later queries.
  @discardableResult
  public func add(_ directory: URL) -> Bool {
    run(["add", "--", directory.path]) != nil
  }

  private func run(_ arguments: [String]) -> String? {
    guard let executable, !Task.isCancelled else {
      return nil
    }

    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }

    // A database on a stalled volume must not hang the caller.
    let watchdog = ProcessWatchdog(process)
    let expiry = DispatchWorkItem { watchdog.terminate() }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: expiry)
    // Drain the pipe before waiting so a long result list can't fill it and block zoxide.
    let data = try? output.fileHandleForReading.readToEnd()
    process.waitUntilExit()
    expiry.cancel()

    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      return nil
    }
    return String(data: data ?? Data(), encoding: .utf8)
  }
}

/// Resolves editable text to a folder, falling back to zoxide for text that isn't a path.
public enum JumpResolver {
  /// Resolves a path first and asks zoxide only when no folder matches the text.
  public static func resolve(
    _ input: String,
    relativeTo currentDirectory: URL?,
    zoxide: ZoxideClient?,
    fileManager: FileManager = .default
  ) -> Result<URL, PathResolverError> {
    let pathResult = PathResolver.resolve(
      input,
      relativeTo: currentDirectory,
      fileManager: fileManager
    )
    guard case .failure(.notDirectory) = pathResult, let zoxide else {
      return pathResult
    }
    guard
      let match = zoxide.matches(
        for: input,
        excluding: currentDirectory,
        maximumResults: 1,
        fileManager: fileManager
      ).first
    else {
      return pathResult
    }
    return .success(match.standardizedFileURL.resolvingSymlinksInPath())
  }
}

/// Lets the timeout queue stop a process that the calling thread is still waiting on.
private final class ProcessWatchdog: @unchecked Sendable {
  private let process: Process

  init(_ process: Process) {
    self.process = process
  }

  func terminate() {
    if process.isRunning {
      process.terminate()
    }
  }
}
