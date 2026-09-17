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
            let controller = try Controller(store: store, previewOnly: preview); self.controller = controller
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item?.button?.image = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: "Codex Dual Account Switcher")
            item?.button?.toolTip = "Codex Dual Account Switcher"
            let menu = NSMenu(); menu.delegate = self; item?.menu = menu
            controller.onChange = { [weak self, weak controller] in
                guard let controller else { return }
                self?.item?.button?.toolTip = "A: \(controller.status[.a] ?? "Unknown") · B: \(controller.status[.b] ?? "Unknown")"
            }
            if !preview { keys = HotKeys() }
            keys?.onPress = { number in Task { await controller.open(number == 1 ? .a : .b) } }
            for error in keys?.errors ?? [] { controller.log(error) }
            if !controller.settings.setupComplete { showSetup() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Switcher could not start"; alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true); alert.runModal(); NSApp.terminate(nil)
        }
    }
    private func configureMainMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); let application = NSMenu(title: "Codex Dual Account Switcher")
        application.addItem(withTitle: "Quit Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        appItem.submenu = application; bar.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit; bar.addItem(editItem); NSApp.mainMenu = bar
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let controller else { return }
        menu.removeAllItems()
        let title = NSMenuItem(title: "Codex Dual Account Switcher", action: nil, keyEquivalent: ""); menu.addItem(title)
        for id in ProfileID.allCases {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "\(id.rawValue.uppercased()) · \(controller.settings.name(id)) — \(controller.status[id] ?? "Unknown")", action: nil, keyEquivalent: ""))
            let open = add("Open / Focus \(controller.settings.name(id))", action: "open:" + id.rawValue, to: menu)
            open.keyEquivalent = id == .a ? "1" : "2"; open.keyEquivalentModifierMask = [.option, .command]
            add("Quit \(controller.settings.name(id))…", action: "quit:" + id.rawValue, to: menu)
            add("Restart \(controller.settings.name(id))…", action: "restart:" + id.rawValue, to: menu)
        }
        menu.addItem(.separator()); add("Open Both", action: "both", to: menu)
        let unmanaged = controller.unmanagedCount
        if unmanaged > 0 { menu.addItem(NSMenuItem(title: "\(unmanaged) unmanaged official instance(s) — left alone", action: nil, keyEquivalent: "")) }
        menu.addItem(.separator()); add("Setup & Compatibility…", action: "setup", to: menu)
        controller.refreshLogin(); add("Startup at Login · " + controller.loginStatus, action: "login", to: menu)
        add("Diagnostics & Log…", action: "diagnostics", to: menu)
        add("Uninstall Instructions…", action: "uninstall", to: menu)
        menu.addItem(.separator()); add("Quit Switcher (accounts keep running)", action: "exit", to: menu)
    }
    @discardableResult private func add(_ title: String, action: String, to menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        entry.target = self; entry.representedObject = action; menu.addItem(entry); return entry
    }
    @objc private func performAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String, let controller else { return }
        let parts = action.split(separator: ":")
        if parts.count == 2, let id = ProfileID(rawValue: String(parts[1])) {
            switch parts[0] {
            case "open": Task { await controller.open(id) }
            case "quit", "restart":
                let alert = NSAlert(); alert.messageText = "\(parts[0] == "quit" ? "Quit" : "Restart") \(controller.settings.name(id))?"
                alert.informativeText = "This can interrupt work in this profile. Save your work first. The other profile stays running."
                alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: parts[0] == "quit" ? "Quit profile" : "Restart profile")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertSecondButtonReturn {
                    Task { if parts[0] == "quit" { _ = await controller.quit(id) } else { await controller.restart(id) } }
                }
            default: break
            }
            return
        }
        switch action {
        case "both": Task { await controller.openBoth() }
        case "setup": showSetup()
        case "diagnostics": show("diagnostics", title: "Switcher Diagnostics", content: DiagnosticsView(controller: controller))
        case "uninstall": show("uninstall", title: "Safe Uninstall", content: UninstallView(controller: controller))
        case "login": controller.toggleLogin()
        case "exit": NSApp.terminate(nil)
        default: break
        }
    }
    private func showSetup() {
        if let controller { show("setup", title: "Setup & Compatibility", content: SetupView(controller: controller)) }
    }
    private func show<V: View>(_ key: String, title: String, content: V) {
        if let window = windows[key] { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.contentView = view; window.title = (controller?.previewOnly == true ? "UI Preview · " : "") + title; window.isReleasedWhenClosed = false
        window.center(); windows[key] = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
// Read-only CLI mode does not change switcher or official app state.
@main
struct SwitcherMain {
    @MainActor static func main() {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--check-app" {
            do { print(try Compatibility.inspect(URL(fileURLWithPath: CommandLine.arguments[2])).summary) }
            catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        } else if CommandLine.arguments.count > 1 && !(CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--preview-ui" && CommandLine.arguments[2].hasPrefix("/")) {
            fputs("Usage: DualAccountSwitcher [--check-app /path/to/ChatGPT.app | --preview-ui /absolute/scratch/path]\n", stderr); exit(2)
        } else {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate(); app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}
