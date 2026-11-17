import AppKit
import Testing

@testable import Pathsta

@Suite("Status item")
struct StatusItemControllerTests {
  @Test("Offers a user-initiated update check")
  @MainActor
  func offersUserInitiatedUpdateCheck() throws {
    _ = NSApplication.shared
    let delegate = StatusItemDelegateSpy()
    let updateTarget = UpdateCheckTarget()
    let controller = StatusItemController(
      delegate: delegate,
      errorSoundEnabled: true,
      directoryCreationEnabled: false,
      launchAtLoginEnabled: true,
      zoxideEnabled: true,
      zoxideAvailable: true,
      checkForUpdatesTarget: updateTarget,
      checkForUpdatesAction: #selector(UpdateCheckTarget.checkForUpdates(_:))
    )

    let menu = try #require(controller.menu)
    let updateItem = try #require(
      menu.items.first { $0.title == "Check for Updates…" }
    )

    #expect(updateItem.target === updateTarget)
    #expect(updateItem.action == #selector(UpdateCheckTarget.checkForUpdates(_:)))
    let updateIndex = try #require(menu.items.firstIndex(of: updateItem))
    let quitIndex = try #require(menu.items.firstIndex { $0.title == "Quit Pathsta" })
    #expect(menu.items[updateIndex + 1].isSeparatorItem)
    #expect(updateIndex + 2 == quitIndex)

    let launchAtLoginItem = try #require(
      menu.items.first { $0.title == "Launch at Login" }
    )
    #expect(launchAtLoginItem.state == .on)
  }

  @Test("Toggles zoxide jumps from the menu")
  @MainActor
  func togglesZoxideJumps() throws {
    _ = NSApplication.shared
    let delegate = StatusItemDelegateSpy()
    let controller = makeController(delegate: delegate, zoxideAvailable: true)

    let item = try #require(controller.menu?.items.first { $0.title == "Jump with zoxide" })
    #expect(item.state == .on)
    let action = try #require(item.action)
    #expect(NSApp.sendAction(action, to: item.target, from: item))

    #expect(item.state == .off)
    #expect(delegate.zoxideEnabledValues == [false])
  }

  @Test("Disables the zoxide toggle when zoxide isn't installed")
  @MainActor
  func disablesZoxideToggleWithoutZoxide() throws {
    _ = NSApplication.shared
    let controller = makeController(delegate: StatusItemDelegateSpy(), zoxideAvailable: false)

    let item = try #require(
      controller.menu?.items.first { $0.title == "Jump with zoxide (Not Installed)" }
    )
    #expect(item.action == nil)
    #expect(item.state == .off)
  }
}

@MainActor
private func makeController(
  delegate: StatusItemDelegateSpy,
  zoxideAvailable: Bool
) -> StatusItemController {
  StatusItemController(
    delegate: delegate,
    errorSoundEnabled: true,
    directoryCreationEnabled: true,
    launchAtLoginEnabled: false,
    zoxideEnabled: true,
    zoxideAvailable: zoxideAvailable,
    checkForUpdatesTarget: delegate,
    checkForUpdatesAction: #selector(NSObject.copy)
  )
}

@MainActor
private final class StatusItemDelegateSpy: StatusItemControllerDelegate {
  private(set) var zoxideEnabledValues: [Bool] = []

  func statusItemDidRequestAutomationSettings() {}

  func statusItemDidSetZoxideEnabled(_ isEnabled: Bool) {
    zoxideEnabledValues.append(isEnabled)
  }

  func statusItemDidSetErrorSoundEnabled(_ isEnabled: Bool) {}

  func statusItemDidSetDirectoryCreationEnabled(_ isEnabled: Bool) {}

  func statusItemDidSetLaunchAtLoginEnabled(_ isEnabled: Bool) -> Bool {
    isEnabled
  }
}

@MainActor
private final class UpdateCheckTarget: NSObject {
  @objc func checkForUpdates(_ sender: Any?) {}
}
