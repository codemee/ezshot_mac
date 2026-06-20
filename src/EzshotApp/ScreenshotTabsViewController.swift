import AppKit
import Carbon.HIToolbox
import EzshotCore

@MainActor
final class ScreenshotTabsViewController: NSObject, NSWindowDelegate {
    private let preferences: PreferencesStore
    private var documentsByWindow: [NSWindow: ScreenshotDocument] = [:]
    private var editorsByWindow: [NSWindow: ScreenshotEditorView] = [:]
    private var toolbarsByWindow: [NSWindow: ScreenshotEditorToolbarDelegate] = [:]
    private var orderedWindows: [NSWindow] = []
    private var emptyWindow: NSWindow?
    private var emptyToolbarDelegate: ScreenshotEditorToolbarDelegate?
    private var retiredEmptyWindows: [NSWindow] = []
    private var keyMonitor: Any?

    init(preferences: PreferencesStore) {
        self.preferences = preferences
        super.init()
        NSWindow.allowsAutomaticWindowTabbing = true
        installKeyMonitor()
    }

    func showWindow() {
        if let window = NSApp.keyWindow, documentsByWindow[window] != nil {
            window.makeKeyAndOrderFront(nil)
        } else if let window = orderedWindows.last {
            window.makeKeyAndOrderFront(nil)
        } else {
            showEmptyWindow()
        }
    }

    func addDocument(_ document: ScreenshotDocument) {
        let windowToClose = emptyWindow
        windowToClose?.orderOut(nil)
        emptyWindow = nil
        emptyToolbarDelegate = nil

        let window = makeDocumentWindow(for: document)
        documentsByWindow[window] = document
        orderedWindows.append(window)

        if let existingWindow = orderedWindows.dropLast().last {
            existingWindow.addTabbedWindow(window, ordered: .above)
        }

        selectDocumentWindow(window)

        // Keep the empty drag source window alive after importing. Closing a
        // window shortly after an AppKit drag session can crash while drag
        // bookkeeping is still unwinding.
        if let windowToClose {
            retiredEmptyWindows.append(windowToClose)
        }
    }

    private func addDroppedImageURLs(_ urls: [URL]) {
        let images = urls.compactMap { materializedImage(from: $0) }
        guard !images.isEmpty else {
            NSSound.beep()
            return
        }

        images.forEach { image in
            addDocument(ScreenshotDocument(image: image))
        }
    }

    func refreshChrome() {
        let localizer = AppLocalizer(preferences: preferences)
        emptyWindow?.title = localizer.text(.emptyTitle)
        if let contentView = emptyWindow?.contentView, let label = firstTextField(in: contentView) {
            label.stringValue = localizer.text(.emptyMessage)
        }
        emptyToolbarDelegate?.refreshChrome()
        toolbarsByWindow.values.forEach { $0.refreshChrome() }
        if !documentsByWindow.isEmpty {
            let saveItem = NSMenuItem(title: localizer.text(.save), action: #selector(saveCurrentDocument), keyEquivalent: "s")
            saveItem.target = self
            NSApp.mainMenu = makeMainMenu(saveItem: saveItem)
        }
    }

    private func selectDocumentWindow(_ window: NSWindow) {
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            window.tabGroup?.selectedWindow = window
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc func saveCurrentDocument() {
        guard
            let window = NSApp.keyWindow,
            let document = documentsByWindow[window]
        else {
            NSSound.beep()
            return
        }

        do {
            if document.fileURL == nil {
                try showSavePanel(for: document, window: window)
            } else {
                try document.overwrite()
            }
            window.title = title(for: document)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func undoCurrentEdit() {
        guard let editor = currentEditor() else {
            NSSound.beep()
            return
        }

        editor.undo()
        currentToolbar()?.refreshUndo()
    }

    @objc func copyCurrentImage() {
        guard let editor = currentEditor() else {
            NSSound.beep()
            return
        }

        editor.copyImageToPasteboard()
    }

    @objc func selectLineTool() {
        selectTool(.line)
    }

    @objc func selectArrowTool() {
        selectTool(.arrow)
    }

    @objc func selectMosaicTool() {
        selectTool(.mosaic)
    }

    @objc func showLineStyleSettings() {
        guard let toolbar = currentToolbar() else {
            NSSound.beep()
            return
        }

        toolbar.showStylePopoverFromToolbar()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let document = documentsByWindow[sender], document.isDirty else {
            return true
        }

        return confirmCloseUnsavedDocuments([document])
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        documentsByWindow.removeValue(forKey: window)
        editorsByWindow.removeValue(forKey: window)
        toolbarsByWindow.removeValue(forKey: window)
        orderedWindows.removeAll { $0 === window }
        if window === emptyWindow {
            emptyWindow = nil
            emptyToolbarDelegate = nil
        }
    }

    private func makeDocumentWindow(for document: ScreenshotDocument) -> NSWindow {
        let editorView = ScreenshotEditorView(document: document)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title(for: document)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "EzshotScreenshots"
        window.delegate = self
        window.contentView = makeDropContainer(contentView: editorView)
        window.center()
        editorView.onDocumentChanged = { [weak window, weak self] in
        guard
            let self,
            let window,
            let document = self.documentsByWindow[window]
            else {
                return
            }
            window.title = self.title(for: document)
            self.toolbarsByWindow[window]?.refreshUndo()
        }

        let toolbarDelegate = ScreenshotEditorToolbarDelegate(editor: editorView, preferences: preferences) { [weak self] in
            self?.refreshChrome()
        }
        let toolbar = NSToolbar(identifier: "EzshotEditorToolbar")
        toolbar.delegate = toolbarDelegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        editorView.onModeChanged = { [weak toolbarDelegate] mode in
            toolbarDelegate?.syncSelectedMode(mode)
        }
        editorsByWindow[window] = editorView
        toolbarsByWindow[window] = toolbarDelegate

        let saveItem = NSMenuItem(title: AppLocalizer(preferences: preferences).text(.save), action: #selector(saveCurrentDocument), keyEquivalent: "s")
        saveItem.target = self
        NSApp.mainMenu = makeMainMenu(saveItem: saveItem)

        return window
    }

    private func showEmptyWindow() {
        if let emptyWindow {
            emptyWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let localizer = AppLocalizer(preferences: preferences)
        let contentView = makeDropContainer(contentView: NSView())
        let label = NSTextField(labelWithString: localizer.text(.emptyMessage))
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = localizer.text(.emptyTitle)
        window.delegate = self
        window.contentView = contentView
        window.center()

        let toolbarDelegate = ScreenshotEditorToolbarDelegate(editor: nil, preferences: preferences) { [weak self] in
            self?.refreshChrome()
        }
        let toolbar = NSToolbar(identifier: "EzshotEmptyToolbar")
        toolbar.delegate = toolbarDelegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        emptyToolbarDelegate = toolbarDelegate
        emptyWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeDropContainer(contentView: NSView) -> ImageDropView {
        let container = ImageDropView { [weak self] urls in
            self?.addDroppedImageURLs(urls)
        }
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func firstTextField(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField {
            return textField
        }

        for subview in view.subviews {
            if let textField = firstTextField(in: subview) {
                return textField
            }
        }

        return nil
    }

    private func materializedImage(from url: URL) -> NSImage? {
        guard
            let sourceImage = NSImage(contentsOf: url),
            let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func makeMainMenu(saveItem: NSMenuItem) -> NSMenu {
        let localizer = AppLocalizer(preferences: preferences)
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let fileMenuItem = NSMenuItem()
        let windowMenuItem = NSMenuItem()

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: localizer.text(.quit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let fileMenu = NSMenu(title: localizer.text(.file))
        fileMenu.addItem(saveItem)
        fileMenu.addItem(NSMenuItem(title: localizer.text(.copyEditedImage), action: #selector(copyCurrentImage), keyEquivalent: "c"))
        fileMenu.items.last?.target = self
        fileMenuItem.submenu = fileMenu

        let windowMenu = NSMenu(title: localizer.text(.window))
        windowMenu.addItem(NSMenuItem(title: localizer.text(.showPreviousTab), action: #selector(NSWindow.selectPreviousTab(_:)), keyEquivalent: "{"))
        windowMenu.addItem(NSMenuItem(title: localizer.text(.showNextTab), action: #selector(NSWindow.selectNextTab(_:)), keyEquivalent: "}"))
        windowMenu.addItem(.separator())
        let undoItem = NSMenuItem(title: localizer.text(.undo), action: #selector(undoCurrentEdit), keyEquivalent: "z")
        undoItem.target = self
        windowMenu.addItem(undoItem)
        let lineItem = NSMenuItem(title: localizer.text(.line), action: #selector(selectLineTool), keyEquivalent: "l")
        lineItem.keyEquivalentModifierMask = []
        lineItem.target = self
        windowMenu.addItem(lineItem)
        let arrowItem = NSMenuItem(title: localizer.text(.arrow), action: #selector(selectArrowTool), keyEquivalent: "a")
        arrowItem.keyEquivalentModifierMask = []
        arrowItem.target = self
        windowMenu.addItem(arrowItem)
        let mosaicItem = NSMenuItem(title: localizer.text(.mosaic), action: #selector(selectMosaicTool), keyEquivalent: "m")
        mosaicItem.keyEquivalentModifierMask = []
        mosaicItem.target = self
        windowMenu.addItem(mosaicItem)
        let styleItem = NSMenuItem(title: localizer.text(.lineStyle), action: #selector(showLineStyleSettings), keyEquivalent: "l")
        styleItem.keyEquivalentModifierMask = [.command, .shift]
        styleItem.target = self
        windowMenu.addItem(styleItem)
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(fileMenuItem)
        mainMenu.addItem(windowMenuItem)
        return mainMenu
    }

    private func showSavePanel(for document: ScreenshotDocument, window: NSWindow) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = document.defaultFileName
        panel.canCreateDirectories = true

        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            try document.save(to: url)
        }
    }

    private func title(for document: ScreenshotDocument) -> String {
        document.isDirty ? "\(document.tabTitle) *" : document.tabTitle
    }

    private func confirmCloseUnsavedDocuments(_ documents: [ScreenshotDocument]) -> Bool {
        let unsavedCount = documents.filter(\.isDirty).count
        guard unsavedCount > 0 else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Close \(unsavedCount) Unsaved Screenshot\(unsavedCount == 1 ? "" : "s")?"
        alert.informativeText = "Unsaved screenshots will be discarded."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func currentEditor() -> ScreenshotEditorView? {
        guard let window = currentDocumentWindow() else {
            return nil
        }

        return editorsByWindow[window]
    }

    private func currentToolbar() -> ScreenshotEditorToolbarDelegate? {
        guard let window = currentDocumentWindow() else {
            return nil
        }

        return toolbarsByWindow[window]
    }

    private func currentDocumentWindow() -> NSWindow? {
        if let keyWindow = NSApp.keyWindow {
            if documentsByWindow[keyWindow] != nil {
                return keyWindow
            }

            if
                let selectedWindow = keyWindow.tabGroup?.selectedWindow,
                documentsByWindow[selectedWindow] != nil
            {
                return selectedWindow
            }
        }

        if let mainWindow = NSApp.mainWindow {
            if documentsByWindow[mainWindow] != nil {
                return mainWindow
            }

            if
                let selectedWindow = mainWindow.tabGroup?.selectedWindow,
                documentsByWindow[selectedWindow] != nil
            {
                return selectedWindow
            }
        }

        return orderedWindows.reversed().first { window in
            window.isVisible && documentsByWindow[window] != nil
        }
    }

    private func selectTool(_ mode: ScreenshotEditMode) {
        guard let editor = currentEditor() else {
            NSSound.beep()
            return
        }

        editor.mode = mode
        currentToolbar()?.syncSelectedMode(mode)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handleEditorShortcut(event)
        }
    }

    private func handleEditorShortcut(_ event: NSEvent) -> NSEvent? {
        guard
            currentDocumentWindow() != nil,
            event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        else {
            return event
        }

        switch Int(event.keyCode) {
        case kVK_ANSI_L:
            selectTool(.line)
            return nil
        case kVK_ANSI_A:
            selectTool(.arrow)
            return nil
        case kVK_ANSI_M:
            selectTool(.mosaic)
            return nil
        default:
            return event
        }
    }
}

@MainActor
private final class ScreenshotEditorToolbarDelegate: NSObject, NSToolbarDelegate {
    private enum Item {
        static let undo = NSToolbarItem.Identifier("EzshotUndo")
        static let copy = NSToolbarItem.Identifier("EzshotCopy")
        static let delay = NSToolbarItem.Identifier("EzshotDelay")
        static let style = NSToolbarItem.Identifier("EzshotLineStyle")
        static let tools = NSToolbarItem.Identifier("EzshotTools")
        static let language = NSToolbarItem.Identifier("EzshotLanguage")
        static let appearance = NSToolbarItem.Identifier("EzshotAppearance")
    }

    private weak var editor: ScreenshotEditorView?
    private let preferences: PreferencesStore
    private let onSettingsChange: () -> Void
    private lazy var settingsMenuController = AppSettingsMenuController(preferences: preferences) { [weak self] in
        guard let self else {
            return
        }
        AppSettingsMenuController.applyAppearance(preferences: self.preferences)
        self.onSettingsChange()
        self.refreshChrome()
    }
    private lazy var delayMenuController = CaptureDelayMenuController(preferences: preferences) { [weak self] in
        self?.refreshDelay()
    }
    private var segmentedControl: NSSegmentedControl?
    private var undoItem: NSToolbarItem?
    private var delayItem: NSToolbarItem?
    private var styleItem: NSToolbarItem?
    private var toolsItem: NSToolbarItem?
    private var languageItem: NSToolbarItem?
    private var appearanceItem: NSToolbarItem?
    private weak var styleButton: NSButton?
    private weak var delayButton: NSButton?
    private weak var languageButton: NSButton?
    private weak var appearanceButton: NSButton?
    private var delayPopover: NSPopover?

    init(editor: ScreenshotEditorView?, preferences: PreferencesStore, onSettingsChange: @escaping () -> Void) {
        self.editor = editor
        self.preferences = preferences
        self.onSettingsChange = onSettingsChange
        super.init()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.undo, Item.copy, Item.delay, .space, Item.tools, Item.style, .flexibleSpace, Item.language, Item.appearance]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.undo, Item.copy, Item.delay, .space, Item.tools, Item.style, .flexibleSpace, Item.language, Item.appearance]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == Item.undo {
            let localizer = AppLocalizer(preferences: preferences)
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = localizer.text(.undo)
            item.paletteLabel = localizer.text(.undo)
            item.toolTip = tooltip(localizer.text(.undo), shortcut: "Cmd+Z")
            item.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: localizer.text(.undo))
            item.target = self
            item.action = #selector(undo)
            item.isEnabled = editor?.canUndo == true
            undoItem = item
            return item
        }

        if itemIdentifier == Item.copy {
            let localizer = AppLocalizer(preferences: preferences)
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = localizer.text(.copyEditedImage)
            item.paletteLabel = localizer.text(.copyEditedImage)
            item.toolTip = tooltip(localizer.text(.copyEditedImage), shortcut: "Cmd+C")
            item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: localizer.text(.copyEditedImage))
            item.target = self
            item.action = #selector(copyImage)
            item.isEnabled = editor != nil
            return item
        }

        if itemIdentifier == Item.delay {
            let localizer = AppLocalizer(preferences: preferences)
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = localizer.text(.delay)
            item.paletteLabel = localizer.text(.delay)
            item.toolTip = CaptureDelayMenuController.localizedLabel(for: preferences.captureDelaySeconds, preferences: preferences)
            item.view = makeDelayButton()
            delayItem = item
            return item
        }

        if itemIdentifier == Item.style {
            let localizer = AppLocalizer(preferences: preferences)
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = localizer.text(.style)
            item.paletteLabel = localizer.text(.lineStyle)
            item.toolTip = tooltip(localizer.text(.lineStyle), shortcut: "Cmd+Shift+L")
            item.view = makeStyleButton()
            item.isEnabled = editor != nil
            styleItem = item
            return item
        }

        if itemIdentifier == Item.language {
            let localizer = AppLocalizer(preferences: preferences)
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = localizer.text(.language)
            item.paletteLabel = localizer.text(.language)
            item.toolTip = localizer.text(.language)
            item.view = makeToolbarButton(
                symbolName: "globe",
                tooltip: localizer.text(.language),
                action: #selector(showLanguageMenu(_:))
            ) { [weak self] button in
                self?.languageButton = button
            }
            languageItem = item
            return item
        }

        if itemIdentifier == Item.appearance {
            let localizer = AppLocalizer(preferences: preferences)
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = localizer.text(.appearance)
            item.paletteLabel = localizer.text(.appearance)
            item.toolTip = localizer.text(.appearance)
            item.view = makeToolbarButton(
                symbolName: "circle.lefthalf.filled",
                tooltip: localizer.text(.appearance),
                action: #selector(showAppearanceMenu(_:))
            ) { [weak self] button in
                self?.appearanceButton = button
            }
            appearanceItem = item
            return item
        }

        guard itemIdentifier == Item.tools else {
            return nil
        }

        let localizer = AppLocalizer(preferences: preferences)
        let control = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: self, action: #selector(selectModeFromSegment(_:)))
        control.segmentCount = ScreenshotEditMode.allCases.count
        control.segmentStyle = NSSegmentedControl.Style.texturedRounded
        control.selectedSegment = 0
        control.isEnabled = editor != nil

        for (index, mode) in ScreenshotEditMode.allCases.enumerated() {
            let title = title(for: mode, localizer: localizer)
            control.setImage(NSImage(systemSymbolName: symbolName(for: mode), accessibilityDescription: title), forSegment: index)
            control.setToolTip(tooltip(title, shortcut: shortcut(for: mode)), forSegment: index)
            control.setWidth(34, forSegment: index)
        }

        segmentedControl = control

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = localizer.text(.tools)
        item.paletteLabel = localizer.text(.tools)
        item.view = control
        toolsItem = item
        return item
    }

    private func title(for mode: ScreenshotEditMode, localizer: AppLocalizer) -> String {
        switch mode {
        case .line:
            localizer.text(.line)
        case .arrow:
            localizer.text(.arrow)
        case .mosaic:
            localizer.text(.mosaic)
        }
    }

    private func symbolName(for mode: ScreenshotEditMode) -> String {
        switch mode {
        case .line:
            "line.diagonal"
        case .arrow:
            "arrow.up.right"
        case .mosaic:
            "checkerboard.rectangle"
        }
    }

    @objc private func selectModeFromSegment(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard ScreenshotEditMode.allCases.indices.contains(index) else {
            return
        }

        let mode = ScreenshotEditMode.allCases[index]

        editor?.mode = mode
        segmentedControl?.selectedSegment = index
    }

    func syncSelectedMode(_ mode: ScreenshotEditMode) {
        guard let index = ScreenshotEditMode.allCases.firstIndex(of: mode) else {
            return
        }

        segmentedControl?.selectedSegment = index
    }

    @objc private func undo() {
        editor?.undo()
        refreshUndo()
    }

    @objc private func copyImage() {
        editor?.copyImageToPasteboard()
    }

    @objc private func showDelaySettings(_ sender: NSButton) {
        let content = CaptureDelayPopoverViewController(preferences: preferences) { [weak self] in
            self?.refreshDelay()
            self?.delayMenuController.updateMenuItems()
        }
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 268, height: 118)
        popover.behavior = .transient
        popover.contentViewController = content
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        delayPopover = popover
    }

    @objc private func showLanguageMenu(_ sender: NSButton) {
        let localizer = AppLocalizer(preferences: preferences)
        let menu = settingsMenuController.makeLanguageMenu(localizer: localizer)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func showAppearanceMenu(_ sender: NSButton) {
        let localizer = AppLocalizer(preferences: preferences)
        let menu = settingsMenuController.makeAppearanceMenu(localizer: localizer)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func showStylePopover(_ sender: NSButton) {
        showStylePopover(relativeTo: sender)
    }

    func showStylePopoverFromToolbar() {
        guard let styleButton else {
            NSSound.beep()
            return
        }

        showStylePopover(relativeTo: styleButton)
    }

    private func showStylePopover(relativeTo sender: NSButton) {
        guard let editor else {
            return
        }

        let content = LineStylePopoverViewController(editor: editor) { [weak self] in
            self?.refreshStyle()
        }
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 260, height: 92)
        popover.behavior = .transient
        popover.contentViewController = content
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    func refreshUndo() {
        undoItem?.isEnabled = editor?.canUndo == true
    }

    func refreshChrome() {
        let localizer = AppLocalizer(preferences: preferences)
        undoItem?.label = localizer.text(.undo)
        undoItem?.paletteLabel = localizer.text(.undo)
        undoItem?.toolTip = tooltip(localizer.text(.undo), shortcut: "Cmd+Z")
        delayItem?.label = localizer.text(.delay)
        delayItem?.paletteLabel = localizer.text(.delay)
        styleItem?.label = localizer.text(.style)
        styleItem?.paletteLabel = localizer.text(.lineStyle)
        styleItem?.toolTip = tooltip(localizer.text(.lineStyle), shortcut: "Cmd+Shift+L")
        toolsItem?.label = localizer.text(.tools)
        toolsItem?.paletteLabel = localizer.text(.tools)
        languageItem?.label = localizer.text(.language)
        languageItem?.paletteLabel = localizer.text(.language)
        languageItem?.toolTip = localizer.text(.language)
        appearanceItem?.label = localizer.text(.appearance)
        appearanceItem?.paletteLabel = localizer.text(.appearance)
        appearanceItem?.toolTip = localizer.text(.appearance)
        languageButton?.toolTip = localizer.text(.language)
        appearanceButton?.toolTip = localizer.text(.appearance)
        styleButton?.toolTip = tooltip(localizer.text(.lineStyle), shortcut: "Cmd+Shift+L")

        if let segmentedControl {
            for (index, mode) in ScreenshotEditMode.allCases.enumerated() {
                segmentedControl.setToolTip(
                    tooltip(title(for: mode, localizer: localizer), shortcut: shortcut(for: mode)),
                    forSegment: index
                )
            }
        }
        refreshDelay()
        refreshStyle()
    }

    private func refreshStyle() {
        guard let button = styleItem?.view as? NSButton else {
            return
        }

        button.image = makeStylePreviewImage()
    }

    private func refreshDelay() {
        let label = CaptureDelayMenuController.localizedLabel(for: preferences.captureDelaySeconds, preferences: preferences)
        delayItem?.toolTip = label
        delayButton?.toolTip = label
        delayButton?.image = makeDelayImage()
    }

    private func makeDelayButton() -> NSButton {
        let button = NSButton(image: makeDelayImage(), target: self, action: #selector(showDelaySettings(_:)))
        button.bezelStyle = .texturedRounded
        button.toolTip = CaptureDelayMenuController.localizedLabel(for: preferences.captureDelaySeconds, preferences: preferences)
        button.imagePosition = .imageOnly
        delayButton = button
        return button
    }

    private func makeToolbarButton(
        symbolName: String,
        tooltip: String,
        action: Selector,
        store: (NSButton) -> Void
    ) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.toolTip = tooltip
        button.imagePosition = .imageOnly
        store(button)
        return button
    }

    private func makeDelayImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 40, height: 20))
        image.lockFocus()

        NSColor.labelColor.setStroke()
        let clock = NSBezierPath(ovalIn: NSRect(x: 2, y: 3, width: 14, height: 14))
        clock.lineWidth = 1.5
        clock.stroke()

        let hand = NSBezierPath()
        hand.lineWidth = 1.4
        hand.move(to: NSPoint(x: 9, y: 10))
        hand.line(to: NSPoint(x: 9, y: 14))
        hand.move(to: NSPoint(x: 9, y: 10))
        hand.line(to: NSPoint(x: 12, y: 10))
        hand.stroke()

        let delay = preferences.captureDelaySeconds
        let suffix: String
        if delay <= 0 {
            suffix = "off"
        } else if delay.rounded() == delay {
            suffix = "\(Int(delay))"
        } else {
            suffix = String(format: "%.1f", delay)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        (suffix as NSString).draw(in: NSRect(x: 19, y: 5, width: 20, height: 11), withAttributes: attributes)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func makeStyleButton() -> NSButton {
        let button = NSButton(image: makeStylePreviewImage(), target: self, action: #selector(showStylePopover(_:)))
        button.bezelStyle = .texturedRounded
        button.toolTip = tooltip(AppLocalizer(preferences: preferences).text(.lineStyle), shortcut: "Cmd+Shift+L")
        button.imagePosition = .imageOnly
        styleButton = button
        return button
    }

    private func makeStylePreviewImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 34, height: 18))
        image.lockFocus()
        let color = editor?.lineColor ?? .systemRed
        let width = editor?.lineWidth ?? 4
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: 5, y: 9))
        path.line(to: NSPoint(x: 29, y: 9))
        path.stroke()
        image.unlockFocus()
        return image
    }

    private func shortcut(for mode: ScreenshotEditMode) -> String {
        switch mode {
        case .line:
            "L"
        case .arrow:
            "A"
        case .mosaic:
            "M"
        }
    }

    private func tooltip(_ title: String, shortcut: String) -> String {
        "\(title) (\(shortcut))"
    }
}

@MainActor
private final class LineStylePopoverViewController: NSViewController {
    private weak var editor: ScreenshotEditorView?
    private let onChange: () -> Void
    private let colorWell = NSColorWell(frame: .zero)
    private let slider = NSSlider(value: 4, minValue: 1, maxValue: 14, target: nil, action: nil)
    private let widthLabel = NSTextField(labelWithString: "4 pt")

    init(editor: ScreenshotEditorView, onChange: @escaping () -> Void) {
        self.editor = editor
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 92))

        let colorLabel = NSTextField(labelWithString: "Color")
        let widthTextLabel = NSTextField(labelWithString: "Width")
        colorWell.color = editor?.lineColor ?? .systemRed
        colorWell.target = self
        colorWell.action = #selector(updateStyle)
        slider.doubleValue = Double(editor?.lineWidth ?? 4)
        slider.target = self
        slider.action = #selector(updateStyle)
        widthLabel.alignment = .right

        for subview in [colorLabel, colorWell, widthTextLabel, slider, widthLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            colorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            colorLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            colorWell.leadingAnchor.constraint(equalTo: colorLabel.trailingAnchor, constant: 16),
            colorWell.centerYAnchor.constraint(equalTo: colorLabel.centerYAnchor),
            colorWell.widthAnchor.constraint(equalToConstant: 44),

            widthTextLabel.leadingAnchor.constraint(equalTo: colorLabel.leadingAnchor),
            widthTextLabel.topAnchor.constraint(equalTo: colorLabel.bottomAnchor, constant: 22),
            slider.leadingAnchor.constraint(equalTo: colorWell.leadingAnchor),
            slider.centerYAnchor.constraint(equalTo: widthTextLabel.centerYAnchor),
            slider.widthAnchor.constraint(equalToConstant: 120),
            widthLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            widthLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            widthLabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor)
        ])

        updateWidthLabel()
    }

    @objc private func updateStyle() {
        editor?.lineColor = colorWell.color
        editor?.lineWidth = CGFloat(slider.doubleValue.rounded())
        updateWidthLabel()
        onChange()
    }

    private func updateWidthLabel() {
        widthLabel.stringValue = "\(Int(slider.doubleValue.rounded())) pt"
    }
}
