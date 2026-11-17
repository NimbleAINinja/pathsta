import Foundation
import PathstaCore

/// Connects the path editor to zoxide while honoring the user's preference.
@MainActor
final class ZoxideJumps {
  private let client: ZoxideClient
  private let preferences: PathstaPreferences
  private weak var pathEditor: PathEditorView?

  init(
    client: ZoxideClient = ZoxideClient(),
    preferences: PathstaPreferences = PathstaPreferences()
  ) {
    self.client = client
    self.preferences = preferences
  }

  var isAvailable: Bool {
    client.isAvailable
  }

  var isEnabled: Bool {
    get { preferences.usesZoxide }
    set {
      preferences.usesZoxide = newValue
      applyPreference()
    }
  }

  /// The client to consult, or `nil` when jumps are off or zoxide isn't installed.
  var activeClient: ZoxideClient? {
    isEnabled && isAvailable ? client : nil
  }

  func attach(to pathEditor: PathEditorView) {
    self.pathEditor = pathEditor
    applyPreference()
  }

  func resolve(
    _ text: String,
    relativeTo currentDirectory: URL?
  ) -> Result<URL, PathResolverError> {
    JumpResolver.resolve(text, relativeTo: currentDirectory, zoxide: activeClient)
  }

  /// Tells zoxide about a visited folder so Finder and shell navigation share one ranking.
  func record(_ directory: URL) {
    guard let client = activeClient else {
      return
    }
    // zoxide may wait on a slow volume, so keep it off the main thread.
    DispatchQueue.global(qos: .utility).async {
      client.add(directory)
    }
  }

  private func applyPreference() {
    guard let client = activeClient else {
      pathEditor?.jumpCompletionProvider = nil
      return
    }
    pathEditor?.jumpCompletionProvider = { text, selection, currentDirectory in
      client.completions(for: text, selection: selection, relativeTo: currentDirectory)
    }
  }
}
