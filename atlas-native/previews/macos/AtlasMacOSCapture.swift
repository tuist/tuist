import AppKit
import ScreenCaptureKit

/// Captures only this isolated fixture window, without screen-recording access.
@MainActor
enum AtlasMacOSCapture {
    static func schedule() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--capture"), arguments.indices.contains(index + 1) else { return }
        Task {
            try await Task.sleep(for: .seconds(4))
            guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
                fatalError("The fixture window was not available")
            }
            let updates = arguments.contains("--updates")
            let settings = arguments.contains("--settings")
            window.setContentSize(NSSize(width: settings ? 660 : (updates ? 420 : (arguments.contains("--compact") ? 820 : 1180)),
                                         height: settings ? 640 : (updates ? 220 : 800)))
            window.center()
            if arguments.contains("orbit-environment"), let screen = window.screen {
                // Keep the menu over this window, not uncaptured desktop pixels.
                window.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - window.frame.width, y: window.frame.minY))
            }
            NSApplication.shared.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(300))
            try await prepareTable(arguments)
            try await prepareInbox(arguments, window: window)
            let verified = try await prepareAction(arguments, window: window)
            try await prepareScroll(arguments, window: window)
            if let index = arguments.firstIndex(of: "--measure-interactions"), arguments.indices.contains(index + 1) {
                try await measureInteractions(window: window, output: arguments[index + 1])
            }
            if !arguments.contains("orbit-environment") {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            try await Task.sleep(for: .milliseconds(300))
            guard #available(macOS 14.4, *),
                  let target = try await SCShareableContent.currentProcess.windows.first(where: {
                      $0.windowID == CGWindowID(window.windowNumber)
                  }) else {
                fatalError("The fixture window was not available for capture")
            }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * window.backingScaleFactor)
            configuration.height = Int(window.frame.height * window.backingScaleFactor)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.includeChildWindows = true
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration
            )
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Could not encode the fixture capture")
            }
            try png.write(to: URL(fileURLWithPath: arguments[index + 1]))
            exit(verified ? 0 : 1)
        }
    }

    private static func measureInteractions(window: NSWindow, output: String) async throws {
        var samples: [[String: Any]] = []
        func measure(_ name: String, action: () -> Void) async throws {
            guard let items = window.toolbar?.items, !items.isEmpty else { fatalError("No native toolbar to measure") }
            let toolbar = window.toolbar?.items.map { ObjectIdentifier($0) } ?? []
            let start = ProcessInfo.processInfo.systemUptime
            action()
            let event = ProcessInfo.processInfo.systemUptime
            try await Task.sleep(for: .milliseconds(16))
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let end = ProcessInfo.processInfo.systemUptime
            let replaced = toolbar != (window.toolbar?.items.map { ObjectIdentifier($0) } ?? [])
            samples.append(["interaction": name, "event_ms": (event - start) * 1000,
                            "settle_ms": (end - start) * 1000, "toolbar_replaced": replaced,
                            "toolbar_item_ids": items.map { $0.itemIdentifier.rawValue }])
        }
        try await prepareInbox(["--select-thread", "1"], window: window)
        for _ in 0..<8 {
            for (character, code) in [("\u{f701}", UInt16(125)), ("\u{f700}", UInt16(126))] {
                guard let root = window.contentView, let inbox = findInbox(in: root), window.makeFirstResponder(inbox) else {
                    fatalError("No inbox for responsiveness measurement")
                }
                let previousRow = inbox.selectedRow
                try await measure("thread-selection") { window.sendEvent(key(character, code: code, window: window)) }
                guard inbox.selectedRow != previousRow else { fatalError("Measured selection did not change the conversation") }
            }
        }
        guard let root = window.contentView, let editor = findEditor(in: root) else {
            fatalError("No composer for responsiveness measurement")
        }
        for character in "A fixture draft for measuring native typing." {
            try await measure("typing") { editor.insertText(String(character), replacementRange: editor.selectedRange()) }
        }
        guard editor.string == "A fixture draft for measuring native typing." else { fatalError("Measured typing lost draft text") }
        editor.selectAll(nil)
        editor.insertText("", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(300))
        for index in 0..<20 {
            try await measure("resize") {
                window.setContentSize(NSSize(width: index.isMultiple(of: 2) ? 900 : 1180, height: 800))
            }
        }
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: output))
        print("Measured \(samples.count) native interactions: \(output)")
    }

    private static func prepareAction(_ arguments: [String], window: NSWindow) async throws -> Bool {
        guard let action = arguments.firstIndex(of: "--press"), arguments.indices.contains(action + 1) else { return true }
        switch arguments[action + 1] {
        case "business-create", "orbit-create":
            guard window.performKeyEquivalent(with: key("n", code: 45, window: window, modifiers: .command)) else {
                fatalError("The fixture New shortcut was not available")
            }
        case "business-open-selection": window.sendEvent(key("\r", code: 36, window: window))
        case "business-open-command": window.sendEvent(key("o", code: 31, window: window, modifiers: .command))
        case "orbit-draft-switch": return try await verifyDraftProtection(window: window)
        case "orbit-info", "orbit-environment", "settings-this-mac", "environment-stop":
            let labels = ["orbit-info": "Thread details", "orbit-environment": "Tool environment", "settings-this-mac": "This Mac",
                          "environment-stop": "Stop command"]
            let label = labels[arguments[action + 1]]!
            let root = window.contentView?.superview ?? window.contentView
            let toolbarId = ["orbit-info": "thread-info", "orbit-environment": "orbit-environment"][arguments[action + 1]]
            let pressed = toolbarId.map { pressToolbar($0, window: window) } == true
                || root.map { pressControl(label, in: $0) } == true || pressElement(label, in: window)
            guard pressed else {
                fatalError("The fixture \(label) action was not available")
            }
            try await Task.sleep(for: .seconds(1))
            if arguments[action + 1] == "orbit-info" { return window.attachedSheet != nil }
        case "workspace-round-trip":
            guard let root = window.contentView, let sidebar = findSidebar(in: root), window.makeFirstResponder(sidebar) else {
                fatalError("The fixture workspace sidebar was not available")
            }
            window.sendEvent(key("\u{f701}", code: 125, window: window))
            try await Task.sleep(for: .seconds(1))
            guard let root = window.contentView, findTable(in: root) != nil else { fatalError("Accounts did not open") }
            guard window.makeFirstResponder(sidebar) else { fatalError("Could not refocus workspace sidebar") }
            window.sendEvent(key("\u{f700}", code: 126, window: window))
            try await Task.sleep(for: .seconds(1))
            guard let root = window.contentView, let inbox = findInbox(in: root), inbox !== sidebar,
                  inbox.numberOfRows > 1 else { fatalError("Orbit lost its loaded conversations on section return") }
        case "orbit-archived":
            guard let root = window.contentView?.superview, let picker = findStatusPicker(in: root) else {
                fatalError("The fixture conversation status picker was not available")
            }
            picker.selectedSegment = 1
            guard picker.sendAction(picker.action, to: picker.target) else {
                fatalError("The fixture Archived action was not available")
            }
        default: fatalError("Unsupported fixture action")
        }
        try await Task.sleep(for: .seconds(1))
        return true
    }

    private static func verifyDraftProtection(window: NSWindow) async throws -> Bool {
        guard let root = window.contentView, let table = findInbox(in: root), table.selectedRow >= 0,
              let editor = findEditor(in: root), window.makeFirstResponder(editor) else {
            fatalError("No selected conversation and native composer for draft verification")
        }
        let row = table.selectedRow
        editor.insertText("Unsent fixture draft", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(500))
        guard window.makeFirstResponder(table) else { fatalError("Could not focus fixture inbox") }
        var showedAlert = false
        let dismissal = Timer(timeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                if let alert = NSApplication.shared.modalWindow ?? window.attachedSheet,
                   let root = alert.contentView, let button = findAlertButton(in: root) {
                    showedAlert = true
                    button.performClick(nil)
                }
            }
        }
        RunLoop.main.add(dismissal, forMode: .common)
        defer { dismissal.invalidate() }
        window.sendEvent(key("\u{f701}", code: 125, window: window))
        try await Task.sleep(for: .seconds(1))
        let retained = table.selectedRow == row
        let draftRetained = findEditor(in: root)?.string.contains("Unsent fixture draft") == true
        print("Draft switch: alert=\(showedAlert), original row retained=\(retained), draft retained=\(draftRetained)")
        return showedAlert && retained && draftRetained
    }

    private static func prepareTable(_ arguments: [String]) async throws {
        for option in ["--sort-column", "--scroll-column", "--scroll-row", "--select-row"] {
            guard let index = arguments.firstIndex(of: option) else { continue }
            guard arguments.indices.contains(index + 1),
                  let position = Int(arguments[index + 1]),
                  let table = NSApplication.shared.windows.lazy.compactMap({ $0.contentView.flatMap(findTable) }).first else {
                fatalError("No table or valid position for \(option)")
            }
            if option.hasSuffix("-column") {
                prepareColumn(option, position: position, table: table)
            } else if option == "--scroll-row" {
                guard (0..<table.numberOfRows).contains(position) else { fatalError("No fixture row at \(position)") }
                let before = table.numberOfRows
                table.scrollRowToVisible(position)
                try await Task.sleep(for: .seconds(1))
                print("Scrolled native table to row \(position); loaded rows: \(before) → \(table.numberOfRows)")
            } else {
                guard (0..<table.numberOfRows).contains(position), let window = table.window,
                      window.makeFirstResponder(table) else { fatalError("No fixture row at \(position)") }
                table.deselectAll(nil)
                for _ in 0...position { window.sendEvent(key("\u{f701}", code: 125, window: window)) }
                try await Task.sleep(for: .milliseconds(300))
                guard table.selectedRow == position else { fatalError("Fixture row selection failed") }
            }
            try await Task.sleep(for: .milliseconds(300))
        }
    }

    private static func prepareColumn(_ option: String, position: Int, table: NSTableView) {
        guard table.tableColumns.indices.contains(position) else { fatalError("No fixture column at \(position)") }
        if option == "--sort-column" {
            guard let descriptor = table.tableColumns[position].sortDescriptorPrototype else {
                fatalError("No sortable fixture column at \(position)")
            }
            table.sortDescriptors = [descriptor]
        } else {
            guard let scroll = table.enclosingScrollView else { fatalError("No scrollable fixture table") }
            table.scrollColumnToVisible(position)
            print("Native horizontal scrolling: enabled=\(scroll.hasHorizontalScroller), offset=\(scroll.contentView.bounds.minX)")
        }
    }

    private static func prepareScroll(_ arguments: [String], window: NSWindow) async throws {
        guard let index = arguments.firstIndex(of: "--scroll-content") else { return }
        let root = window.attachedSheet?.contentView ?? window.contentView
        guard arguments.indices.contains(index + 1), ["top", "bottom"].contains(arguments[index + 1]),
              let root, let scroll = findContentScroll(in: root), let document = scroll.documentView else {
            fatalError("Expected --scroll-content top|bottom and scrollable fixture content")
        }
        let atEnd = arguments[index + 1] == "bottom"
        let offset = atEnd == document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
        scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(500))
    }

    private static func prepareInbox(_ arguments: [String], window: NSWindow) async throws {
        guard let index = arguments.firstIndex(of: "--select-thread") else { return }
        guard arguments.indices.contains(index + 1), let position = Int(arguments[index + 1]),
              let root = window.contentView, let table = findInbox(in: root),
              (0..<table.numberOfRows).contains(position), window.makeFirstResponder(table) else {
            fatalError("No inbox or valid row for --select-thread")
        }
        table.deselectAll(nil)
        await Task.yield()
        for _ in 0..<table.numberOfRows {
            window.makeFirstResponder(table)
            window.sendEvent(key("\u{f701}", code: 125, window: window))
            try await Task.sleep(for: .milliseconds(16))
            if table.selectedRow == position { break }
        }
        guard table.selectedRow == position else {
            fatalError("Fixture inbox selection failed: expected \(position), got \(table.selectedRow)")
        }
        print("Selected native inbox row \(position)")
        try await Task.sleep(for: .seconds(1))
    }

    private static func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView, table.tableColumns.count > 1 { return table }
        for child in view.subviews {
            if let table = findTable(in: child) { return table }
        }
        return nil
    }

    private static func findInbox(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView, table.tableColumns.count == 1 { return table }
        return view.subviews.compactMap { findInbox(in: $0) }.max {
            $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX
        }
    }

    private static func findEditor(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView, editor.isEditable { return editor }
        if let field = view as? NSTextField, field.isEditable, field.isEnabled,
           let window = field.window, window.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView {
            return editor
        }
        for child in view.subviews {
            if let editor = findEditor(in: child) { return editor }
        }
        return nil
    }

    private static func findAlertButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.title == "OK" { return button }
        for child in view.subviews {
            if let button = findAlertButton(in: child) { return button }
        }
        return nil
    }

    private static func pressToolbar(_ identifier: String, window: NSWindow) -> Bool {
        guard let item = window.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == identifier }),
              item.isEnabled, let view = item.view, view.window === window else { return false }
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return false }
            NSApplication.shared.postEvent(event, atStart: false)
        }
        return true
    }

    private static func pressControl(_ label: String, in view: NSView) -> Bool {
        if let button = view as? NSButton, button.title == label || button.toolTip == label {
            button.performClick(nil)
            return true
        }
        if let picker = view as? NSSegmentedControl,
           let index = (0..<picker.segmentCount).first(where: { picker.label(forSegment: $0) == label }) {
            picker.selectedSegment = index
            return picker.sendAction(picker.action, to: picker.target)
        }
        return view.subviews.contains { pressControl(label, in: $0) }
    }

    private static func pressElement(_ label: String, in value: Any) -> Bool {
        let element = value as AnyObject
        let identifier = ["Stop command": "environment-stop"][label]
        if element.accessibilityLabel?() == label || element.accessibilityTitle?() == label || element.accessibilityHelp?() == label
            || identifier.map({ element.accessibilityIdentifier?() == $0 }) == true,
           element.accessibilityPerformPress?() == true { return true }
        return (element.accessibilityChildren?() ?? []).contains { pressElement(label, in: $0) }
    }

    private static func findSidebar(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView, table.tableColumns.count == 1 { return table }
        return view.subviews.compactMap { findSidebar(in: $0) }.min {
            $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX
        }
    }

    private static func findStatusPicker(in view: NSView) -> NSSegmentedControl? {
        if let picker = view as? NSSegmentedControl, picker.segmentCount == 2,
           picker.label(forSegment: 0) == "Active", picker.label(forSegment: 1) == "Archived" { return picker }
        for child in view.subviews {
            if let picker = findStatusPicker(in: child) { return picker }
        }
        return nil
    }

    private static func findContentScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, let document = scroll.documentView,
           !(document is NSTableView), document.bounds.height > scroll.contentView.bounds.height {
            return scroll
        }
        for child in view.subviews {
            if let scroll = findContentScroll(in: child) { return scroll }
        }
        return nil
    }

    private static func key(_ characters: String, code: UInt16, window: NSWindow,
                            modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          characters: characters, charactersIgnoringModifiers: characters,
                                          isARepeat: false, keyCode: code) else { fatalError("Could not create fixture input") }
        return event
    }
}
