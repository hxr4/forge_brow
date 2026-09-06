import AppKit

@objc(ForgeAppDelegate)
final class ForgeAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var windowControllers: [BrowserWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        FGBrowserView.documentStartScript =
            (ContentDefuse.isEnabled ? ContentDefuse.script : "") + AudioProbeScript.script
        buildMainMenu()
        openNewWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let minimised = windowControllers.first(where: { $0.window?.isMiniaturized == true }) {
            minimised.window?.deminiaturize(nil)
        } else if !windowControllers.contains(where: { $0.window?.isVisible == true }) {
            openNewWindow()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let addresses = urls.map { $0.absoluteString }.filter { !$0.isEmpty }
        guard !addresses.isEmpty else { return }
        if activeController == nil { openNewWindow() }
        guard let controller = activeController else { return }
        for address in addresses {
            controller.newTab(url: address)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        HistoryStore.shared.flush()
        FGEngine.quitMessageLoop()
        return .terminateCancel
    }

    @objc func ensureWindow() {
        if windowControllers.isEmpty {
            openNewWindow()
        }
    }

    @objc func openNewWindow() {
        let controller = BrowserWindowController()
        controller.showWindow(nil)
        windowControllers.append(controller)
    }

    @objc func openPrivateWindow() {
        let controller = BrowserWindowController(isPrivate: true)
        controller.showWindow(nil)
        windowControllers.append(controller)
        NSApp.activate(ignoringOtherApps: true)
    }

    func presentPrivateWindow(with url: String) {
        let controller = BrowserWindowController(isPrivate: true)
        controller.showWindow(nil)
        windowControllers.append(controller)
        controller.newTab(url: url)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var activeController: BrowserWindowController? {
        if let keyed = NSApp.keyWindow?.windowController as? BrowserWindowController { return keyed }
        if let main = NSApp.mainWindow?.windowController as? BrowserWindowController { return main }
        return windowControllers.last
    }

    @objc private func forwardToBrowser(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let selector = NSSelectorFromString(name)
        if let controller = activeController, controller.responds(to: selector) {
            controller.perform(selector)
        } else if responds(to: selector) {
            perform(selector)
        }
    }

    @objc private func moveToGroupFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        activeController?.addSelectedTabToGroup(id)
    }

    @objc private func addShortcutFromMenu(_ sender: NSMenuItem) {
        activeController?.addCurrentTabToTray(sender.representedObject as? String)
    }

    @objc private func openURLFromMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        if let controller = activeController {
            controller.newTab(url: url)
        } else {
            openNewWindow()
            activeController?.newTab(url: url)
        }
    }

    private func item(_ title: String,
                      _ action: Selector?,
                      _ key: String = "",
                      _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { entry.keyEquivalentModifierMask = modifiers }
        return entry
    }

    private func browserItem(_ title: String,
                             _ selectorName: String,
                             _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: #selector(forwardToBrowser(_:)), keyEquivalent: key)
        if !key.isEmpty { entry.keyEquivalentModifierMask = modifiers }
        entry.target = self
        entry.representedObject = selectorName
        return entry
    }

    private func linkItem(_ title: String, _ url: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: #selector(openURLFromMenu(_:)), keyEquivalent: "")
        entry.target = self
        entry.representedObject = url
        return entry
    }

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(item("About Forge", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        app.addItem(.separator())
        app.addItem(browserItem("Settings…", "handleShowSettings", ","))
        app.addItem(.separator())
        let services = NSMenu()
        let servicesItem = item("Services", nil)
        servicesItem.submenu = services
        NSApp.servicesMenu = services
        app.addItem(servicesItem)
        app.addItem(.separator())
        app.addItem(item("Hide Forge", #selector(NSApplication.hide(_:)), "h"))
        app.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit Forge", #selector(NSApplication.terminate(_:)), "q"))
        appItem.submenu = app
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let file = NSMenu(title: "File")
        file.addItem(browserItem("New Tab", "handleNewTab", "t"))
        file.addItem(item("New Window", #selector(openNewWindow), "n"))
        file.addItem(item("New Private Window", #selector(openPrivateWindow), "n", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(browserItem("Open Location…", "handleFocusAddress", "l"))
        file.addItem(.separator())
        file.addItem(browserItem("Close Tab", "handleCloseTab", "w"))
        file.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(browserItem("Print…", "handlePrint", "p"))
        fileItem.submenu = file
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(browserItem("Undo", "handleUndo", "z"))
        edit.addItem(browserItem("Redo", "handleRedo", "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(browserItem("Cut", "handleCut", "x"))
        edit.addItem(browserItem("Copy", "handleCopy", "c"))
        edit.addItem(browserItem("Paste", "handlePaste", "v"))
        edit.addItem(browserItem("Select All", "handleSelectAll", "a"))
        edit.addItem(.separator())
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(browserItem("Find…", "handleFind", "f"))
        findMenu.addItem(browserItem("Find Next", "handleFindNext", "g"))
        findMenu.addItem(browserItem("Find Previous", "handleFindPrevious", "g", [.command, .shift]))
        let findItem = item("Find", nil)
        findItem.submenu = findMenu
        edit.addItem(findItem)
        editItem.submenu = edit
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let view = NSMenu(title: "View")
        view.addItem(browserItem("Stop", "handleStop", "."))
        view.addItem(browserItem("Reload", "handleReload", "r"))
        view.addItem(browserItem("Force Reload", "handleForceReload", "r", [.command, .shift]))
        view.addItem(.separator())
        view.addItem(browserItem("Actual Size", "handleActualSize", "0"))
        view.addItem(browserItem("Zoom In", "handleZoomIn", "+"))
        view.addItem(browserItem("Zoom Out", "handleZoomOut", "-"))
        view.addItem(.separator())
        view.addItem(browserItem("Toggle Sidebar", "handleToggleSidebar", "s", [.command, .control]))
        view.addItem(browserItem("Enter Full Screen", "handleToggleFullScreen", "f", [.command, .control]))
        view.addItem(.separator())
        let devMenu = NSMenu(title: "Developer")
        devMenu.addItem(browserItem("Developer Tools", "handleShowDevTools", "i", [.command, .option]))
        devMenu.addItem(browserItem("View Source", "handleViewSource", "u", [.command, .option]))
        devMenu.addItem(browserItem("Stats for Nerds", "handleToggleStats", "s", [.command, .option]))
        let devItem = item("Developer", nil)
        devItem.submenu = devMenu
        view.addItem(devItem)
        viewItem.submenu = view
        main.addItem(viewItem)

        let historyItem = NSMenuItem()
        let history = NSMenu(title: "History")
        history.delegate = self
        historyItem.submenu = history
        main.addItem(historyItem)

        let bookmarksItem = NSMenuItem()
        let bookmarks = NSMenu(title: "Bookmarks")
        bookmarks.delegate = self
        bookmarksItem.submenu = bookmarks
        main.addItem(bookmarksItem)

        let toolsItem = NSMenuItem()
        let tools = NSMenu(title: "Tools")
        tools.addItem(browserItem("Command Palette", "handleTogglePalette", "k"))
        tools.addItem(.separator())
        let beltMenu = NSMenu(title: "Utility Belt")
        for tool in DevTools.all {
            beltMenu.addItem(linkItem(tool.name, tool.url))
        }
        let beltItem = item("Utility Belt", nil)
        beltItem.submenu = beltMenu
        tools.addItem(beltItem)
        tools.addItem(browserItem("Downloads", "handleShowDownloads", "j", [.command, .shift]))
        tools.addItem(.separator())
        tools.addItem(browserItem("Toggle Vertical Tabs", "handleToggleOrientation", "e", [.command, .shift]))
        tools.addItem(.separator())
        tools.addItem(browserItem("Ignore Certificate Errors (this tab)", "handleToggleCertBypass"))
        toolsItem.submenu = tools
        main.addItem(toolsItem)

        let tabItem = NSMenuItem()
        let tab = NSMenu(title: "Tab")
        tab.delegate = self
        tabItem.submenu = tab
        main.addItem(tabItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        main.addItem(windowItem)

        let helpItem = NSMenuItem()
        let help = NSMenu(title: "Help")
        help.addItem(browserItem("Forge Help", "handleShowHelp"))
        helpItem.submenu = help
        NSApp.helpMenu = help
        main.addItem(helpItem)

        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        switch menu.title {
        case "History":
            menu.removeAllItems()
            menu.addItem(browserItem("Home", "handleHome", "H", [.command, .shift]))
            menu.addItem(browserItem("Back", "handleBack", "[", [.command]))
            menu.addItem(browserItem("Forward", "handleForward", "]", [.command]))
            menu.addItem(.separator())
            menu.addItem(browserItem("Reopen Closed Tab", "handleReopenClosedTab", "t", [.command, .shift]))
            menu.addItem(browserItem("Show Full History", "handleShowHistory", "y"))
            let recent = HistoryStore.shared.recent(12)
            if !recent.isEmpty {
                menu.addItem(.separator())
                let header = NSMenuItem(title: "Recently Visited", action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
                for entry in recent {
                    let title = entry.title.isEmpty ? entry.url : entry.title
                    let display = title.count > 60 ? String(title.prefix(60)) + "…" : title
                    menu.addItem(linkItem(display, entry.url))
                }
            }
        case "Tab":
            menu.removeAllItems()
            menu.addItem(browserItem("Show Next Tab", "handleNextTab", "\t", [.control]))
            menu.addItem(browserItem("Show Previous Tab", "handlePreviousTab", "\t", [.control, .shift]))
            menu.addItem(.separator())
            menu.addItem(browserItem("New Group with This Tab", "handleNewTabGroup", "g", [.command, .shift]))
            menu.addItem(.separator())
            menu.addItem(browserItem("Duplicate Tab", "handleDuplicateTab"))
            menu.addItem(browserItem("Mute Tab", "handleToggleMuteTab"))
            menu.addItem(.separator())
            menu.addItem(browserItem("Close Other Tabs", "handleCloseOtherTabs"))
            menu.addItem(browserItem("Close Tabs to the Left", "handleCloseTabsToTheLeft"))
            menu.addItem(browserItem("Close Tabs to the Right", "handleCloseTabsToTheRight"))
            menu.addItem(.separator())

            let controller = activeController
            let groups = controller?.tabGroups ?? []
            let currentGroup = controller?.selectedTabGroupID
            let others = groups.filter { $0.id != currentGroup }
            if !others.isEmpty {
                let moveItem = NSMenuItem(title: "Move to Group", action: nil, keyEquivalent: "")
                let moveMenu = NSMenu(title: "Move to Group")
                for group in others {
                    let entry = NSMenuItem(title: group.name,
                                           action: #selector(moveToGroupFromMenu(_:)),
                                           keyEquivalent: "")
                    entry.target = self
                    entry.representedObject = group.id.uuidString
                    moveMenu.addItem(entry)
                }
                moveItem.submenu = moveMenu
                menu.addItem(moveItem)
            }
            if currentGroup != nil {
                menu.addItem(browserItem("Remove Tab from Group", "handleUngroupTab"))
                menu.addItem(browserItem("Collapse or Expand Group", "handleToggleGroupCollapsed"))
                menu.addItem(browserItem("Close Group", "handleCloseGroup"))
            }
        case "Bookmarks":
            menu.removeAllItems()
            menu.addItem(browserItem("Bookmark This Tab", "handleBookmarkTab", "d"))
            menu.addItem(browserItem("Show All Bookmarks", "handleShowBookmarks", "b", [.command, .option]))
            let shortcutItem = NSMenuItem(title: "Add to Shortcuts", action: nil, keyEquivalent: "")
            let shortcutMenu = NSMenu(title: "Add to Shortcuts")
            for tray in Trays.all {
                let entry = NSMenuItem(title: tray.name,
                                       action: #selector(addShortcutFromMenu(_:)),
                                       keyEquivalent: "")
                entry.target = self
                entry.representedObject = tray.name
                shortcutMenu.addItem(entry)
            }
            shortcutItem.submenu = shortcutMenu
            menu.addItem(shortcutItem)
            let saved = BookmarkStore.shared.all
            if !saved.isEmpty {
                menu.addItem(.separator())
                for mark in saved.prefix(25) {
                    let display = mark.title.count > 60 ? String(mark.title.prefix(60)) + "…" : mark.title
                    menu.addItem(linkItem(display, mark.url))
                }
            }
        default:
            break
        }
    }
}
