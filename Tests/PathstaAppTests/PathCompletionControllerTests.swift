import AppKit
import Dispatch
import Testing

@testable import Pathsta

@Suite("Path completion controller")
struct PathCompletionControllerTests {
  @Test("Cancels detached completion work when the text changes")
  @MainActor
  func cancelsDetachedWork() async {
    let started = DispatchSemaphore(value: 0)
    let cancelled = DispatchSemaphore(value: 0)
    let controller = PathCompletionController { _, _, _ in
      started.signal()
      while !Task.isCancelled {
        Thread.sleep(forTimeInterval: 0.001)
      }
      cancelled.signal()
      return []
    }
    let editor = NSTextView()

    controller.complete(
      editor: editor,
      relativeTo: nil,
      backwards: false,
      onMissingCompletion: {}
    )
    #expect(await wait(for: started))

    controller.textDidChange()

    #expect(await wait(for: cancelled))
  }

  @Test("Cancels detached completion work when the controller is released")
  @MainActor
  func cancelsDetachedWorkOnRelease() async {
    let started = DispatchSemaphore(value: 0)
    let cancelled = DispatchSemaphore(value: 0)
    var controller: PathCompletionController? = PathCompletionController { _, _, _ in
      started.signal()
      while !Task.isCancelled {
        Thread.sleep(forTimeInterval: 0.001)
      }
      cancelled.signal()
      return []
    }
    let editor = NSTextView()

    controller?.complete(
      editor: editor,
      relativeTo: nil,
      backwards: false,
      onMissingCompletion: {}
    )
    #expect(await wait(for: started))

    controller = nil

    #expect(await wait(for: cancelled))
  }

  @Test("Falls back to jump matches when no folder name completes")
  @MainActor
  func fallsBackToJumpMatches() async {
    let controller = PathCompletionController { _, _, _ in [] }
    let editor = NSTextView()
    editor.string = "proj"
    editor.selectedRange = NSRange(location: 4, length: 0)
    let fallback: PathCompletionController.CompletionProvider = { text, _, _ in
      text == "proj" ? ["/work/project/", "/old/projects/"] : []
    }

    controller.complete(
      editor: editor,
      relativeTo: nil,
      backwards: false,
      fallbackProvider: fallback,
      onMissingCompletion: {}
    )
    #expect(await waitUntil { editor.string == "/work/project/" })

    controller.complete(
      editor: editor,
      relativeTo: nil,
      backwards: false,
      fallbackProvider: fallback,
      onMissingCompletion: {}
    )
    #expect(editor.string == "/old/projects/")
  }

  @Test("Prefers folder name completions over jump matches")
  @MainActor
  func prefersFolderCompletions() async {
    let controller = PathCompletionController { _, _, _ in ["Projects/"] }
    let editor = NSTextView()
    editor.string = "proj"
    editor.selectedRange = NSRange(location: 4, length: 0)

    controller.complete(
      editor: editor,
      relativeTo: nil,
      backwards: false,
      fallbackProvider: { _, _, _ in ["/work/project/"] },
      onMissingCompletion: {}
    )

    #expect(await waitUntil { editor.string == "Projects/" })
  }
}

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
  for _ in 0..<200 {
    if condition() {
      return true
    }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return condition()
}

private func wait(for semaphore: DispatchSemaphore) async -> Bool {
  await withCheckedContinuation { continuation in
    DispatchQueue.global().async {
      continuation.resume(returning: semaphore.wait(timeout: .now() + 1) == .success)
    }
  }
}
