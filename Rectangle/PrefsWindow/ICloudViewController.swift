//
//  ICloudViewController.swift
//  Rectangle
//
//  Created by OpenAI on 4/10/26.
//

import Cocoa

class ICloudViewController: NSViewController {
    private static let preferredWindowSize = NSSize(width: 850, height: 520)
    
    private let automaticSyncCheckbox = NSButton(checkboxWithTitle: "Automatically sync Rectangle settings with iCloud", target: nil, action: nil)
    private let statusValueLabel = ICloudViewController.makeValueLabel()
    private let localUpdatedValueLabel = ICloudViewController.makeValueLabel()
    private let remoteUpdatedValueLabel = ICloudViewController.makeValueLabel()
    private let lastSyncValueLabel = ICloudViewController.makeValueLabel()
    private let lastResultValueLabel = ICloudViewController.makeValueLabel()
    private let startupModePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let syncNowButton = NSButton(title: "Sync Now", target: nil, action: nil)
    private let uploadButton = NSButton(title: "Upload This Mac", target: nil, action: nil)
    private let downloadButton = NSButton(title: "Download From iCloud", target: nil, action: nil)
    private let availabilityHintLabel = ICloudViewController.makeHintLabel("Sign into iCloud in System Settings to enable syncing across Macs.")
    private var interfaceBuilt = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        preferredContentSize = Self.preferredWindowSize
        
        if let tabViewController = parent as? NSTabViewController,
           let item = tabViewController.tabViewItems.first(where: { $0.viewController === self }) {
            item.label = "iCloud"
            if #available(macOS 11.0, *) {
                item.image = NSImage(systemSymbolName: "icloud", accessibilityDescription: "iCloud")
            }
        }
        
        Notification.Name.iCloudSyncStateChanged.onPost { [weak self] _ in
            self?.updateUI()
        }
        Notification.Name.configImported.onPost { [weak self] _ in
            self?.updateUI()
        }
        Notification.Name.appWillBecomeActive.onPost { [weak self] _ in
            self?.updateUI()
        }
        
        updateUI()
    }
    
    private func buildInterface() {
        guard !interfaceBuilt else { return }
        interfaceBuilt = true
        
        automaticSyncCheckbox.target = self
        automaticSyncCheckbox.action = #selector(toggleAutomaticSync)
        
        startupModePopUpButton.addItem(withTitle: "Automatic (Use newest available copy)")
        startupModePopUpButton.lastItem?.tag = ICloudSyncStartupMode.automatic.rawValue
        startupModePopUpButton.addItem(withTitle: "Prefer This Mac")
        startupModePopUpButton.lastItem?.tag = ICloudSyncStartupMode.preferThisMac.rawValue
        startupModePopUpButton.addItem(withTitle: "Prefer iCloud")
        startupModePopUpButton.lastItem?.tag = ICloudSyncStartupMode.preferICloud.rawValue
        startupModePopUpButton.target = self
        startupModePopUpButton.action = #selector(changeStartupMode)
        
        syncNowButton.target = self
        syncNowButton.action = #selector(syncNow)
        uploadButton.target = self
        uploadButton.action = #selector(uploadCurrentMac)
        downloadButton.target = self
        downloadButton.action = #selector(downloadFromICloud)
        
        let titleLabel = ICloudViewController.makeTitleLabel("Keep Rectangle in Sync")
        let descriptionLabel = ICloudViewController.makeWrappingLabel("Sync shortcuts, snap areas, window behavior, and other Rectangle preferences through iCloud. Import and export JSON backups remain available in General.")
        let syncHeading = ICloudViewController.makeSectionLabel("Automatic Sync")
        let startupHeading = ICloudViewController.makeSectionLabel("When Turning Sync On For This Mac")
        let copiesHeading = ICloudViewController.makeSectionLabel("Current Config Versions")
        let historyHeading = ICloudViewController.makeSectionLabel("Last Sync")
        let actionsHeading = ICloudViewController.makeSectionLabel("Manual Actions")
        
        let statusRow = makeInfoRow(label: "Status", value: statusValueLabel)
        let localRow = makeInfoRow(label: "This Mac", value: localUpdatedValueLabel)
        let remoteRow = makeInfoRow(label: "iCloud", value: remoteUpdatedValueLabel)
        let lastSyncRow = makeInfoRow(label: "Checked", value: lastSyncValueLabel)
        let lastResultRow = makeInfoRow(label: "Result", value: lastResultValueLabel)
        
        let startupRow = NSStackView()
        startupRow.orientation = .horizontal
        startupRow.alignment = .centerY
        startupRow.spacing = 12
        startupRow.addArrangedSubview(ICloudViewController.makeLabel("First sync behavior"))
        startupRow.addArrangedSubview(startupModePopUpButton)
        
        let actionsRow = NSStackView(views: [syncNowButton, uploadButton, downloadButton])
        actionsRow.orientation = .horizontal
        actionsRow.alignment = .centerY
        actionsRow.spacing = 10
        
        let mainStack = NSStackView(views: [
            titleLabel,
            descriptionLabel,
            syncHeading,
            automaticSyncCheckbox,
            availabilityHintLabel,
            statusRow,
            startupHeading,
            startupRow,
            copiesHeading,
            localRow,
            remoteRow,
            historyHeading,
            lastSyncRow,
            lastResultRow,
            actionsHeading,
            actionsRow
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 26),
            mainStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mainStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 48),
            view.trailingAnchor.constraint(greaterThanOrEqualTo: mainStack.trailingAnchor, constant: 48),
            descriptionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            availabilityHintLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 560)
        ])
    }
    
    @objc private func toggleAutomaticSync(_ sender: NSButton) {
        let enabled = sender.state == .on
        ICloudConfigSyncManager.shared.setEnabled(enabled)
        updateUI()
        
        if enabled && !ICloudConfigSyncManager.shared.isICloudAvailable {
            AlertUtil.oneButtonAlert(question: "iCloud sign-in required", text: "Rectangle will start syncing automatically after you sign into iCloud in System Settings.")
        }
    }
    
    @objc private func changeStartupMode(_ sender: NSPopUpButton) {
        guard let mode = ICloudSyncStartupMode(rawValue: sender.selectedTag()) else { return }
        Defaults.iCloudSyncStartupMode.value = mode
    }
    
    @objc private func syncNow(_ sender: Any) {
        guard ICloudConfigSyncManager.shared.syncNow() else {
            AlertUtil.oneButtonAlert(question: "Unable to sync", text: "Sign into iCloud in System Settings to sync Rectangle settings.")
            return
        }
        updateUI()
    }
    
    @objc private func uploadCurrentMac(_ sender: Any) {
        let response = AlertUtil.twoButtonAlert(question: "Replace iCloud copy?", text: "This uploads the current Rectangle settings from this Mac and replaces the copy stored in iCloud.", confirmText: "Upload", cancelText: "Cancel")
        guard response == .alertFirstButtonReturn else { return }
        
        guard ICloudConfigSyncManager.shared.uploadCurrentConfig() else {
            AlertUtil.oneButtonAlert(question: "Upload unavailable", text: "Sign into iCloud in System Settings before uploading Rectangle settings.")
            return
        }
        updateUI()
    }
    
    @objc private func downloadFromICloud(_ sender: Any) {
        let response = AlertUtil.twoButtonAlert(question: "Replace local settings?", text: "This downloads the Rectangle settings stored in iCloud and replaces the current settings on this Mac.", confirmText: "Download", cancelText: "Cancel")
        guard response == .alertFirstButtonReturn else { return }
        
        guard ICloudConfigSyncManager.shared.downloadFromICloud() else {
            AlertUtil.oneButtonAlert(question: "No iCloud copy found", text: "There is no Rectangle configuration stored in iCloud yet.")
            return
        }
        updateUI()
    }
    
    private func updateUI() {
        let snapshot = currentSnapshot()
        
        automaticSyncCheckbox.state = snapshot.isEnabled ? .on : .off
        startupModePopUpButton.selectItem(withTag: Defaults.iCloudSyncStartupMode.value.rawValue)
        
        statusValueLabel.stringValue = statusText(snapshot: snapshot)
        applyTimestamp(snapshot.localUpdatedAt, to: localUpdatedValueLabel, emptyText: "Never")
        if snapshot.hasRemoteConfig {
            applyTimestamp(snapshot.remoteUpdatedAt, to: remoteUpdatedValueLabel, emptyText: "Never")
        } else {
            remoteUpdatedValueLabel.stringValue = "None"
            remoteUpdatedValueLabel.toolTip = nil
        }
        applyTimestamp(snapshot.lastSyncedAt, to: lastSyncValueLabel, emptyText: "Never")
        lastResultValueLabel.stringValue = snapshot.lastSyncResult ?? "No sync result yet"
        lastResultValueLabel.toolTip = lastResultValueLabel.stringValue
        
        availabilityHintLabel.isHidden = snapshot.isICloudAvailable
        
        let iCloudAvailable = snapshot.isICloudAvailable
        syncNowButton.isEnabled = iCloudAvailable && snapshot.isEnabled
        uploadButton.isEnabled = iCloudAvailable
        downloadButton.isEnabled = iCloudAvailable && snapshot.hasRemoteConfig
    }
    
    private func currentSnapshot() -> ICloudSyncSnapshot {
        ICloudConfigSyncManager.shared.snapshot()
    }
    
    private func statusText(snapshot: ICloudSyncSnapshot) -> String {
        if !snapshot.isEnabled {
            return snapshot.isICloudAvailable
                ? "Automatic sync is off. You can still upload or download settings manually."
                : "Automatic sync is off, and iCloud is not currently available on this Mac."
        }
        
        if !snapshot.isICloudAvailable {
            return "Waiting for iCloud sign-in."
        }
        
        if snapshot.hasPendingUpload {
            return "Local changes are queued for upload."
        }
        
        if !snapshot.hasRemoteConfig {
            return "iCloud is ready. The first synced copy will be created from this Mac."
        }
        
        if snapshot.remoteUpdatedAt == snapshot.localUpdatedAt && snapshot.localUpdatedAt > 0 {
            return "This Mac and iCloud already have the same configuration."
        }
        
        if snapshot.remoteUpdatedAt > snapshot.localUpdatedAt {
            return "iCloud has a newer copy than this Mac."
        }
        
        return "This Mac has newer changes than the iCloud copy."
    }
    
    private func applyTimestamp(_ timestamp: Int, to label: NSTextField, emptyText: String) {
        guard timestamp > 0 else {
            label.stringValue = emptyText
            label.toolTip = nil
            return
        }
        
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        label.stringValue = relativeTimestampString(for: date)
        label.toolTip = absoluteTimestampString(for: date)
    }
    
    private func relativeTimestampString(for date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 10 {
            return "Just now"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func absoluteTimestampString(for date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
    
    private func makeInfoRow(label: String, value: NSTextField) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        
        let keyLabel = ICloudViewController.makeLabel(label)
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)
        keyLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        
        row.addArrangedSubview(keyLabel)
        row.addArrangedSubview(value)
        return row
    }
    
    private static func makeTitleLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.boldSystemFont(ofSize: 20)
        return label
    }
    
    private static func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }
    
    private static func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return label
    }
    
    private static func makeValueLabel() -> NSTextField {
        let label = makeWrappingLabel("")
        label.textColor = .secondaryLabelColor
        return label
    }
    
    private static func makeHintLabel(_ text: String) -> NSTextField {
        let label = makeWrappingLabel(text)
        label.textColor = .secondaryLabelColor
        return label
    }
    
    private static func makeWrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }
}
