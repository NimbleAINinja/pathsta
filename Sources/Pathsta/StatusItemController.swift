import AppKit

@MainActor
protocol StatusItemControllerDelegate: AnyObject {
  func statusItemDidRequestAutomationSettings()
  func statusItemDidSetErrorSoundEnabled(_ isEnabled: Bool)
  func statusItemDidSetDirectoryCreationEnabled(_ isEnabled: Bool)
  func statusItemDidSetLaunchAtLoginEnabled(_ isEnabled: Bool) -> Bool
  func statusItemDidSetZoxideEnabled(_ isEnabled: Bool)
}

@MainActor
final class StatusItemController: NSObject {
  weak var delegate: StatusItemControllerDelegate?

  private let statusItem = NSStatusBar.system.statusItem(
    withLength: NSStatusItem.squareLength
  )
  private let errorSoundMenuItem = NSMenuItem()
  private let directoryCreationMenuItem = NSMenuItem()
  private let launchAtLoginMenuItem = NSMenuItem()
  private let zoxideMenuItem = NSMenuItem()

  var menu: NSMenu? {
    statusItem.menu
  }

  init(
    delegate: StatusItemControllerDelegate,
    errorSoundEnabled: Bool,
    directoryCreationEnabled: Bool,
    launchAtLoginEnabled: Bool,
    zoxideEnabled: Bool,
    zoxideAvailable: Bool,
    checkForUpdatesTarget: AnyObject,
    checkForUpdatesAction: Selector
  ) {
    self.delegate = delegate
    super.init()
    configureButton()
    configureZoxideItem(isEnabled: zoxideEnabled, isAvailable: zoxideAvailable)
    configureMenu(
      errorSoundEnabled: errorSoundEnabled,
      directoryCreationEnabled: directoryCreationEnabled,
      launchAtLoginEnabled: launchAtLoginEnabled,
      checkForUpdatesTarget: checkForUpdatesTarget,
      checkForUpdatesAction: checkForUpdatesAction
    )
  }

  @objc private func toggleZoxide() {
    zoxideMenuItem.state = zoxideMenuItem.state == .on ? .off : .on
    delegate?.statusItemDidSetZoxideEnabled(zoxideMenuItem.state == .on)
  }

  @objc private func toggleErrorSound() {
    errorSoundMenuItem.state = errorSoundMenuItem.state == .on ? .off : .on
    delegate?.statusItemDidSetErrorSoundEnabled(errorSoundMenuItem.state == .on)
  }

  @objc private func toggleDirectoryCreation() {
    directoryCreationMenuItem.state = directoryCreationMenuItem.state == .on ? .off : .on
    delegate?.statusItemDidSetDirectoryCreationEnabled(
      directoryCreationMenuItem.state == .on
    )
  }

  @objc private func openAutomationSettings() {
    delegate?.statusItemDidRequestAutomationSettings()
  }

  @objc private func toggleLaunchAtLogin() {
    let requestedState = launchAtLoginMenuItem.state != .on
    let enabled = delegate?.statusItemDidSetLaunchAtLoginEnabled(requestedState) ?? false
    launchAtLoginMenuItem.state = enabled ? .on : .off
  }

  private func configureButton() {
    let image =
      NSImage(named: "MenuBarIcon")
      ?? NSImage(
        systemSymbolName: "folder.badge.gearshape",
        accessibilityDescription: "Pathsta"
      )
    image?.isTemplate = true
    statusItem.button?.image = image
    statusItem.button?.setAccessibilityLabel("Pathsta")
  }

  private func configureMenu(
    errorSoundEnabled: Bool,
    directoryCreationEnabled: Bool,
    launchAtLoginEnabled: Bool,
    checkForUpdatesTarget: AnyObject,
    checkForUpdatesAction: Selector
  ) {
    let menu = NSMenu()
    let heading = NSMenuItem(title: "Pathsta", action: nil, keyEquivalent: "")
    heading.isEnabled = false
    menu.addItem(heading)
    menu.addItem(.separator())

    configureToggleItem(
      errorSoundMenuItem,
      title: "Play Error Sound",
      action: #selector(toggleErrorSound),
      isEnabled: errorSoundEnabled
    )
    menu.addItem(errorSoundMenuItem)

    configureToggleItem(
      directoryCreationMenuItem,
      title: "Allow Shift-Return Folder Creation",
      action: #selector(toggleDirectoryCreation),
      isEnabled: directoryCreationEnabled
    )
    menu.addItem(directoryCreationMenuItem)
    menu.addItem(zoxideMenuItem)
    configureToggleItem(
      launchAtLoginMenuItem,
      title: "Launch at Login",
      action: #selector(toggleLaunchAtLogin),
      isEnabled: launchAtLoginEnabled
    )
    menu.addItem(launchAtLoginMenuItem)
    menu.addItem(
      menuItem(title: "Automation Settings…", action: #selector(openAutomationSettings))
    )
    let checkForUpdatesItem = NSMenuItem(
      title: "Check for Updates…",
      action: checkForUpdatesAction,
      keyEquivalent: ""
    )
    checkForUpdatesItem.target = checkForUpdatesTarget
    menu.addItem(checkForUpdatesItem)
    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit Pathsta",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = NSApp
    menu.addItem(quitItem)
    statusItem.menu = menu
  }

  private func configureZoxideItem(isEnabled: Bool, isAvailable: Bool) {
    guard isAvailable else {
      // An item without an action is drawn disabled, which explains why jumps do nothing.
      zoxideMenuItem.title = "Jump with zoxide (Not Installed)"
      return
    }
    configureToggleItem(
      zoxideMenuItem,
      title: "Jump with zoxide",
      action: #selector(toggleZoxide),
      isEnabled: isEnabled
    )
  }

  private func configureToggleItem(
    _ item: NSMenuItem,
    title: String,
    action: Selector,
    isEnabled: Bool
  ) {
    item.title = title
    item.action = action
    item.target = self
    item.state = isEnabled ? .on : .off
  }

  private func menuItem(title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }
}
