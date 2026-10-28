import AppKit
import WinwayCore

@main
struct WinwayMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--check-disk-access") {
            if let data = try? JSONEncoder().encode(FullDiskAccess.current()) { FileHandle.standardOutput.write(data) }
            return
        }
        if CommandLine.arguments.contains("--check-resources") {
            let bundle = ExplorerStyle.resourceBundle
            let appRoot = Bundle.main.bundleURL.resolvingSymlinksInPath().path + "/"
            guard bundle.bundleURL.resolvingSymlinksInPath().path.hasPrefix(appRoot),
                  ExplorerStyle.image("folder") != nil,
                  ExplorerStyle.sortImage(ascending: true) != nil else {
                FileHandle.standardError.write(Data("Packaged resource lookup failed\n".utf8))
                exit(1)
            }
            print("Packaged resource lookup passed: \(bundle.bundleURL.path)")
            return
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var model: AppModel!
    var commandItems: [NSMenuItem] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        func argument(_ key: String) -> String? {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        let directory = argument("--directory").map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = argument("--settings-path").map { URL(fileURLWithPath: $0) }
        model = AppModel(directory: directory, settingsURL: settingsURL)
        configureMenus()
        model.onRender = { [weak self] in self?.refreshMenus() }
        model.start()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdownSearch()
    }
    func configureMenus() {
        let main = NSMenu()
        let app = NSMenu(title: "Winway")
        let appItem = NSMenuItem(); appItem.submenu = app; main.addItem(appItem)
        app.addItem(withTitle: "关于 Winway", action: #selector(about), keyEquivalent: "").target = self
        add(.settings, to: app)
        app.addItem(.separator())
        let services = NSMenu(title: "服务")
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        servicesItem.submenu = services; app.addItem(servicesItem)
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(withTitle: "隐藏 Winway", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "退出 Winway", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for (title, commands): (String, [CommandID]) in [
            ("文件", [.newTab, .closeTab, .newFolder, .open, .rename, .trash]),
            ("编辑", [.copy, .cut, .paste, .moveHere, .selectAll]),
            ("显示", [.back, .forward, .up, .refresh, .toggleHidden, .toggleDetails])
        ] {
            let menu = NSMenu(title: title)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = menu
            main.addItem(item)
            commands.forEach { add($0, to: menu) }
        }
        NSApp.mainMenu = main
    }
    func add(_ command: CommandID, to menu: NSMenu) {
        let item = NSMenuItem(title: command.title, action: #selector(command(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = command.rawValue; menu.addItem(item); commandItems.append(item)
    }
    @objc func command(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let command = CommandID(rawValue: raw) else { return }
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            switch command {
            case .copy: editor.copy(nil)
            case .cut: editor.cut(nil)
            case .paste: editor.paste(nil)
            case .selectAll: editor.selectAll(nil)
            default: break
            }
            return
        }
        guard !model.keyboard.isRecording, NSApp.keyWindow === model.controller.window, model.controller.window?.attachedSheet == nil else { return }
        model.execute(command)
    }
    func refreshMenus() {
        for item in commandItems {
            guard let raw = item.representedObject as? String, let command = CommandID(rawValue: raw) else { continue }
            item.title = command.title
            if let binding = model.keyboard.bindings(for: command).first {
                let equivalent = KeyboardEventAdapter.menuEquivalent(for: binding)
                item.keyEquivalent = equivalent.key
                item.keyEquivalentModifierMask = equivalent.modifiers
            } else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }
        }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let raw = menuItem.representedObject as? String, let command = CommandID(rawValue: raw) else { return true }
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            switch command {
            case .copy: return editor.selectedRange().length > 0
            case .cut: return editor.isEditable && editor.selectedRange().length > 0
            case .paste: return editor.isEditable
            case .selectAll: return true
            default: return false
            }
        }
        guard let model, !model.keyboard.isRecording, NSApp.keyWindow === model.controller.window, model.controller.window?.attachedSheet == nil else { return false }
        return model.enabledCommands.contains(command)
    }
    @objc func about() {
        model.showSettings(page: .about)
    }
}
