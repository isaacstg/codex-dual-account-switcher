import AppKit
import SwiftUI
import SwitcherCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: Controller?
    private var keys: HotKeys?
    private var item: NSStatusItem?
    private var windows: [String: NSWindow] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        do {
            let preview = CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--preview-ui"
            let store = try PrivateStore(root: preview ? URL(fileURLWithPath: CommandLine.arguments[2]) : PrivateStore.defaultRoot)
            try store.acquireLock()
            let controller = try Controller(store: store, previewOnly: preview)
            self.controller = controller

            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item?.button?.image = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: "Codex Account Switcher")
            item?.button?.toolTip = "Codex Account Switcher"
            let menu = NSMenu(); menu.delegate = self; item?.menu = menu

            controller.onChange = { [weak self, weak controller] in
                guard let controller else { return }
                self?.item?.button?.toolTip = "Current: \(controller.currentState.displayText) · Second: \(controller.secondaryState.displayText)"
            }

            if !preview { keys = HotKeys() }
            keys?.onPress = { [weak controller] number in
                guard let controller else { return }
                Task { await controller.open(number == 1 ? .a : .b) }
            }
            for error in keys?.errors ?? [] { controller.log(error) }
            if !controller.settings.setupComplete { showSetup() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Switcher could not start"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func configureMainMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let application = NSMenu(title: "Codex Account Switcher")
        application.addItem(withTitle: "Quit Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        appItem.submenu = application
        bar.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }

    private func symbol(for state: CurrentAccountState) -> String {
        switch state {
        case .running: return "●"
        case .stopped: return "○"
        case .launching: return "◐"
        case .ambiguous: return "⚠"
        }
    }

    private func symbol(for state: SecondaryAccountState) -> String {
        switch state {
        case .runningVerified: return "●"
        case .stopped: return "○"
        case .launching, .quitting: return "◐"
        case .ownershipUncertain, .unverifiedLiveProcess: return "⚠"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let controller else { return }
        controller.refresh()
        let capabilities = controller.capabilities
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "Codex Account Switcher", action: nil, keyEquivalent: ""))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "\(symbol(for: controller.currentState)) \(controller.settings.name(.a)) — \(controller.currentState.displayText)",
            action: nil, keyEquivalent: ""
        ))
        let current = add("Open / Focus Current Account", action: "open:a", to: menu)
        current.keyEquivalent = "1"
        current.keyEquivalentModifierMask = [.option, .command]
        current.isEnabled = capabilities.canOpenCurrent
        menu.addItem(NSMenuItem(title: "Existing ChatGPT profile · lifecycle stays with ChatGPT", action: nil, keyEquivalent: ""))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "\(symbol(for: controller.secondaryState)) \(controller.settings.name(.b)) — \(controller.secondaryState.displayText)",
            action: nil, keyEquivalent: ""
        ))
        let second = add("Open / Focus Second Account", action: "open:b", to: menu)
        second.keyEquivalent = "2"
        second.keyEquivalentModifierMask = [.option, .command]
        second.isEnabled = capabilities.canOpenSecond
        let restart = add("Restart Second Account…", action: "restart:b", to: menu)
        restart.isEnabled = capabilities.canRestartSecond
        let quit = add("Quit Second Account…", action: "quit:b", to: menu)
        quit.isEnabled = capabilities.canQuitSecond

        if capabilities.canRecoverSecond {
            let recover = add("Recover Second Account…", action: "recover", to: menu)
            recover.isEnabled = true
        }

        menu.addItem(.separator())
        let both = add("Open Both", action: "both", to: menu)
        both.isEnabled = capabilities.canOpenBoth
        if controller.currentState.isAmbiguous {
            menu.addItem(NSMenuItem(title: "⚠ Multiple default ChatGPT instances · Current focus disabled", action: nil, keyEquivalent: ""))
        }
        if controller.secondaryState.needsRecovery {
            menu.addItem(NSMenuItem(title: "⚠ Second Account needs safe recovery before relaunch", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        add("Settings & Compatibility…", action: "setup", to: menu)
        controller.refreshLogin()
        add("Startup at Login · " + controller.loginStatus, action: "login", to: menu)
        add("Diagnostics & Recovery…", action: "diagnostics", to: menu)
        add("Uninstall Instructions…", action: "uninstall", to: menu)
        menu.addItem(.separator())
        add("Quit Switcher (accounts keep running)", action: "exit", to: menu)
    }

    @discardableResult
    private func add(_ title: String, action: String, to menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        entry.target = self
        entry.representedObject = action
        menu.addItem(entry)
        return entry
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String, let controller else { return }
        let parts = action.split(separator: ":")
        if parts.count == 2, let id = ProfileID(rawValue: String(parts[1])) {
            switch parts[0] {
            case "open":
                Task { await controller.open(id) }
            case "quit", "restart":
                guard id == .b else { return }
                let isQuit = parts[0] == "quit"
                let alert = NSAlert()
                alert.messageText = "\(isQuit ? "Quit" : "Restart") Second Account?"
                alert.informativeText = "Save any work in the isolated account first. Your Current Account is not affected."
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: isQuit ? "Quit Second Account" : "Restart Second Account")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertSecondButtonReturn {
                    Task {
                        if isQuit { _ = await controller.quit(.b) }
                        else { await controller.restart(.b) }
                    }
                }
            default:
                break
            }
            return
        }

        switch action {
        case "both":
            Task { await controller.openBoth() }
        case "recover":
            confirmRecovery(controller)
        case "setup":
            showSetup()
        case "diagnostics":
            show("diagnostics", title: "Switcher Diagnostics & Recovery", content: DiagnosticsView(controller: controller))
        case "uninstall":
            show("uninstall", title: "Safe Uninstall", content: UninstallView(controller: controller))
        case "login":
            controller.toggleLogin()
        case "exit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    private func confirmRecovery(_ controller: Controller) {
        let alert = NSAlert()
        alert.messageText = "Recover Second Account?"
        alert.informativeText = "If a verified Second Account receipt exists, recovery is automatic and does not close anything. Otherwise recovery will only proceed after all official ChatGPT instances are closed, so the switcher never guesses process ownership."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Try Safe Recovery")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { controller.resolveInterruptedLaunches() }
    }

    private func showSetup() {
        if let controller { show("setup", title: "Settings & Compatibility", content: SetupView(controller: controller)) }
    }

    private func show<V: View>(_ key: String, title: String, content: V) {
        if let window = windows[key] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: view.fittingSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.title = (controller?.previewOnly == true ? "UI Preview · " : "") + title
        window.isReleasedWhenClosed = false
        window.center()
        windows[key] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct SwitcherMain {
    @MainActor static func main() {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--check-app" {
            do { print(try Compatibility.inspect(URL(fileURLWithPath: CommandLine.arguments[2])).summary) }
            catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        } else if CommandLine.arguments.count > 1 && !(CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--preview-ui" && CommandLine.arguments[2].hasPrefix("/")) {
            fputs("Usage: DualAccountSwitcher [--check-app /path/to/ChatGPT.app | --preview-ui /absolute/scratch/path]\n", stderr)
            exit(2)
        } else {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate()
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}
