//
//  Config.swift
//  Rectangle
//
//  Created by Ryan Hanson on 12/15/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation
import MASShortcut

extension Defaults {
    static func encoded() -> String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return nil }
        let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))
        
        var shortcuts = [String: Shortcut]()
        for action in WindowAction.active {
            if let shortcut = currentShortcut(for: action, dictTransformer: dictTransformer) {
                shortcuts[action.name] = shortcut
            }
        }
        for defaultsKey in TodoManager.defaultsKeys {
            if let masShortcut = storedShortcut(forKey: defaultsKey, dictTransformer: dictTransformer) {
                shortcuts[defaultsKey] = Shortcut(masShortcut: masShortcut)
            }
        }
        
        var codableDefaults = [String: CodableDefault]()
        for exportableDefault in Defaults.array {
            codableDefaults[exportableDefault.key] = exportableDefault.toCodable()
        }
                
        let config = Config(bundleId: Bundle.main.bundleIdentifier ?? "app.cmdspace.rectangle",
                            version: version,
                            shortcuts: shortcuts,
                            defaults: codableDefaults)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if #available(macOS 10.13, *) {
            encoder.outputFormatting.update(with: .sortedKeys)
        }
        if let encodedJson = try? encoder.encode(config) {
            if let jsonString = String(data: encodedJson, encoding: .utf8) {
                return jsonString
            }
        }
        return nil
    }
    
    static func convert(jsonString: String) -> Config? {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(Config.self, from: jsonData)
    }
    
    @discardableResult
    static func load(jsonString: String, trackAsLocalChange: Bool = true) -> Bool {
        guard let config = convert(jsonString: jsonString) else { return false }
        return load(config: config, trackAsLocalChange: trackAsLocalChange)
    }
    
    static func load(fileUrl: URL) {
        guard let jsonString = try? String(contentsOf: fileUrl, encoding: .utf8) else { return }
        _ = load(jsonString: jsonString)
    }
    
    @discardableResult
    private static func load(config: Config, trackAsLocalChange: Bool) -> Bool {
        guard let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) else { return false }

        for availableDefault in Defaults.array {
            if let codedDefault = config.defaults[availableDefault.key] {
                availableDefault.load(from: codedDefault)
            }
        }
        
        for action in WindowAction.active {
            if let shortcut = config.shortcuts[action.name]?.toMASSHortcut() {
                let dictValue = dictTransformer.reverseTransformedValue(shortcut)
                UserDefaults.standard.setValue(dictValue, forKey: action.name)
            }
        }
        for defaultsKey in TodoManager.defaultsKeys {
            if let shortcut = config.shortcuts[defaultsKey]?.toMASSHortcut() {
                let dictValue = dictTransformer.reverseTransformedValue(shortcut)
                UserDefaults.standard.setValue(dictValue, forKey: defaultsKey)
            }
        }

        if trackAsLocalChange {
            Defaults.iCloudConfigTimestamp.value = ICloudConfigSyncManager.currentTimestamp()
        }
        
        Notification.Name.configImported.post()
        return true
    }
    
    static func loadFromSupportDir() {
        if let rectangleSupportURL = getSupportDir()?
            .appendingPathComponent("Rectangle", isDirectory: true) {
            
            let configURL = rectangleSupportURL.appendingPathComponent("RectangleConfig.json")
                        
            let exists = try? configURL.checkResourceIsReachable()
            if exists == true {
                load(fileUrl: configURL)
                do {
                    let newFilename = "RectangleConfig\(timestamp()).json"
                    
                    try FileManager.default.moveItem(atPath: configURL.path, toPath: rectangleSupportURL.appendingPathComponent(newFilename).path)
                } catch {
                    do {
                        try FileManager.default.removeItem(at: configURL)
                    } catch {
                        AlertUtil.oneButtonAlert(question: "Error after loading from Support Dir", text: "Unable to rename/remove RectangleConfig.json from \(rectangleSupportURL) after loading.")
                    }
                }
            }
        }
    }
    
    private static func getSupportDir() -> URL? {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths.isEmpty ? nil : paths[0]
    }
    
    private static func timestamp() -> String {
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "y-MM-dd_H-mm-ss-SSSS"
        return formatter.string(from: date)
    }
    
    private static func currentShortcut(for action: WindowAction, dictTransformer: ValueTransformer?) -> Shortcut? {
        if let masShortcut = storedShortcut(forKey: action.name, dictTransformer: dictTransformer) {
            return Shortcut(masShortcut: masShortcut)
        }
        
        return alternateDefaultShortcuts.enabled ? action.alternateDefault : action.spectacleDefault
    }
    
    private static func storedShortcut(forKey key: String, dictTransformer: ValueTransformer?) -> MASShortcut? {
        guard
            let shortcutDict = UserDefaults.standard.dictionary(forKey: key),
            let dictTransformer,
            let shortcut = dictTransformer.transformedValue(shortcutDict) as? MASShortcut
        else {
            return nil
        }
        return shortcut
    }
}

struct Config: Codable {
    let bundleId: String
    let version: String
    let shortcuts: [String: Shortcut]
    let defaults: [String: CodableDefault]
}

enum ICloudSyncStartupMode: Int {
    case automatic = 0
    case preferThisMac = 1
    case preferICloud = 2
}

struct ICloudSyncSnapshot {
    let isEnabled: Bool
    let isICloudAvailable: Bool
    let hasRemoteConfig: Bool
    let hasPendingUpload: Bool
    let localUpdatedAt: Int
    let remoteUpdatedAt: Int
    let lastSyncedAt: Int
    let lastSyncResult: String?
}

class ICloudConfigSyncManager {
    private struct PendingUpload {
        let payload: String
        let updatedAt: Int
    }
    
    private static let configKey = "rectangleICloudConfig"
    private static let timestampKey = "rectangleICloudConfigTimestamp"
    
    private enum SyncOutcome {
        case uploaded
        case downloaded
        case noChanges
        case unavailable
        
        var description: String {
            switch self {
            case .uploaded:
                return "Uploaded this Mac's configuration to iCloud."
            case .downloaded:
                return "Downloaded the newer iCloud configuration."
            case .noChanges:
                return "Checked iCloud. No configuration changes were needed."
            case .unavailable:
                return "iCloud is unavailable on this Mac."
            }
        }
    }
    
    static let shared = ICloudConfigSyncManager()
    
    private let notificationCenter = NotificationCenter.default
    private lazy var store = NSUbiquitousKeyValueStore.default
    
    private var started = false
    private var isApplyingRemoteConfig = false
    private var lastKnownLocalPayload: String?
    private var pendingUpload: PendingUpload?
    
    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
    
    private init() {}
    
    func start() {
        guard !started else { return }
        started = true
        lastKnownLocalPayload = Defaults.encoded()
        
        notificationCenter.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { [weak self] _ in
            self?.handleLocalDefaultsChange()
        }
        notificationCenter.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reconcileWithICloud(syncReason: .manual)
        }
        notificationCenter.addObserver(forName: NSNotification.Name.NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.handleICloudIdentityChange()
        }
        
        postStateChanged()
        reconcileWithICloud(syncReason: .startup)
    }
    
    func setEnabled(_ enabled: Bool) {
        Defaults.iCloudSync.enabled = enabled
        if !enabled {
            pendingUpload = nil
        }
        postStateChanged()
        if enabled {
            reconcileWithICloud(syncReason: .startup)
        }
    }
    
    static func currentTimestamp() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }
    
    func snapshot() -> ICloudSyncSnapshot {
        let remote = remoteState()
        return ICloudSyncSnapshot(isEnabled: Defaults.iCloudSync.enabled,
                                  isICloudAvailable: isICloudAvailable,
                                  hasRemoteConfig: remote.payload?.isEmpty == false && remote.updatedAt > 0,
                                  hasPendingUpload: pendingUpload != nil,
                                  localUpdatedAt: Defaults.iCloudConfigTimestamp.value,
                                  remoteUpdatedAt: remote.updatedAt,
                                  lastSyncedAt: Defaults.iCloudLastSyncTimestamp.value,
                                  lastSyncResult: Defaults.iCloudLastSyncResult.value)
    }
    
    @discardableResult
    func syncNow() -> Bool {
        guard isICloudAvailable else {
            recordSyncOutcome(.unavailable)
            postStateChanged()
            return false
        }
        _ = reconcileWithICloud(syncReason: .manual)
        return true
    }
    
    @discardableResult
    func uploadCurrentConfig() -> Bool {
        guard isICloudAvailable, let payload = Defaults.encoded(), !payload.isEmpty else {
            recordSyncOutcome(.unavailable)
            postStateChanged()
            return false
        }
        
        upload(payload: payload, updatedAt: Self.currentTimestamp(), requireEnabled: false)
        recordSyncOutcome(.uploaded)
        return true
    }
    
    @discardableResult
    func downloadFromICloud() -> Bool {
        let remote = remoteState()
        guard isICloudAvailable, let payload = remote.payload, !payload.isEmpty, remote.updatedAt > 0 else {
            recordSyncOutcome(.unavailable)
            postStateChanged()
            return false
        }
        
        applyRemote(payload: payload, updatedAt: remote.updatedAt)
        recordSyncOutcome(.downloaded)
        return true
    }
    
    private func handleLocalDefaultsChange() {
        guard !isApplyingRemoteConfig, let payload = Defaults.encoded() else { return }
        guard payload != lastKnownLocalPayload else { return }
        
        lastKnownLocalPayload = payload
        let updatedAt = Self.currentTimestamp()
        Defaults.iCloudConfigTimestamp.value = updatedAt
        scheduleUpload(payload: payload, updatedAt: updatedAt)
        postStateChanged()
    }
    
    private func handleICloudIdentityChange() {
        postStateChanged()
        if Defaults.iCloudSync.enabled {
            reconcileWithICloud(syncReason: .startup)
        }
    }
    
    private func scheduleUpload(payload: String, updatedAt: Int) {
        guard Defaults.iCloudSync.enabled, isICloudAvailable else { return }
        
        pendingUpload = PendingUpload(payload: payload, updatedAt: updatedAt)
        postStateChanged()
        Debounce<String>.input(payload, comparedAgainst: self.pendingUpload?.payload ?? "") { [weak self] payload in
            guard let self, let pendingUpload = self.pendingUpload, pendingUpload.payload == payload else { return }
            self.upload(payload: payload, updatedAt: pendingUpload.updatedAt, requireEnabled: true)
        }
    }
    
    private enum SyncReason: Equatable {
        case startup
        case manual
    }
    
    @discardableResult
    private func reconcileWithICloud(syncReason: SyncReason) -> SyncOutcome? {
        guard Defaults.iCloudSync.enabled, isICloudAvailable else { return nil }
        
        let remote = remoteState()
        let remotePayload = remote.payload
        let remoteUpdatedAt = remote.updatedAt
        let localPayload = Defaults.encoded()
        let localUpdatedAt = Defaults.iCloudConfigTimestamp.value
        
        if let remotePayload, !remotePayload.isEmpty, remoteUpdatedAt > 0 {
            if localUpdatedAt == 0 {
                switch startupResolution(localPayload: localPayload, remotePayload: remotePayload) {
                case .local:
                    if let localPayload, !localPayload.isEmpty {
                        upload(payload: localPayload, updatedAt: Self.currentTimestamp(), requireEnabled: true)
                        if syncReason == .manual {
                            recordSyncOutcome(.uploaded)
                        }
                        return .uploaded
                    }
                case .remote:
                    applyRemote(payload: remotePayload, updatedAt: remoteUpdatedAt)
                    if syncReason == .manual {
                        recordSyncOutcome(.downloaded)
                    }
                    return .downloaded
                case .automatic:
                    if remotePayload == localPayload {
                        Defaults.iCloudConfigTimestamp.value = remoteUpdatedAt
                        postStateChanged()
                        if syncReason == .manual {
                            recordSyncOutcome(.noChanges)
                        }
                        return .noChanges
                    } else if syncReason == .startup {
                        applyRemote(payload: remotePayload, updatedAt: remoteUpdatedAt)
                        return .downloaded
                    } else if let localPayload, !localPayload.isEmpty {
                        upload(payload: localPayload, updatedAt: Self.currentTimestamp(), requireEnabled: true)
                        recordSyncOutcome(.uploaded)
                        return .uploaded
                    } else {
                        applyRemote(payload: remotePayload, updatedAt: remoteUpdatedAt)
                        if syncReason == .manual {
                            recordSyncOutcome(.downloaded)
                        }
                        return .downloaded
                    }
                }
                return nil
            }
            
            if remoteUpdatedAt > localUpdatedAt {
                if remotePayload == localPayload {
                    Defaults.iCloudConfigTimestamp.value = remoteUpdatedAt
                    postStateChanged()
                    if syncReason == .manual {
                        recordSyncOutcome(.noChanges)
                    }
                    return .noChanges
                } else {
                    applyRemote(payload: remotePayload, updatedAt: remoteUpdatedAt)
                    if syncReason == .manual {
                        recordSyncOutcome(.downloaded)
                    }
                    return .downloaded
                }
            }
        }
        
        guard let localPayload, !localPayload.isEmpty else {
            if syncReason == .manual {
                recordSyncOutcome(.noChanges)
            }
            return .noChanges
        }
        let updatedAt = localUpdatedAt == 0 ? Self.currentTimestamp() : localUpdatedAt
        let previousRemotePayload = remotePayload
        let previousRemoteUpdatedAt = remoteUpdatedAt
        upload(payload: localPayload, updatedAt: updatedAt, requireEnabled: true)
        let uploaded = previousRemotePayload != localPayload || previousRemoteUpdatedAt != updatedAt
        if syncReason == .manual {
            recordSyncOutcome(uploaded ? .uploaded : .noChanges)
        }
        return uploaded ? .uploaded : .noChanges
    }
    
    private func upload(payload: String, updatedAt: Int, requireEnabled: Bool) {
        guard isICloudAvailable else { return }
        guard !requireEnabled || Defaults.iCloudSync.enabled else { return }
        guard store.string(forKey: Self.configKey) != payload || Int(store.double(forKey: Self.timestampKey)) != updatedAt else { return }
        
        pendingUpload = nil
        lastKnownLocalPayload = payload
        Defaults.iCloudConfigTimestamp.value = updatedAt
        store.set(payload, forKey: Self.configKey)
        store.set(Double(updatedAt), forKey: Self.timestampKey)
        store.synchronize()
        postStateChanged()
    }
    
    private func applyRemote(payload: String, updatedAt: Int) {
        isApplyingRemoteConfig = true
        defer { isApplyingRemoteConfig = false }
        
        guard Defaults.load(jsonString: payload, trackAsLocalChange: false) else { return }
        
        lastKnownLocalPayload = payload
        Defaults.iCloudConfigTimestamp.value = updatedAt
        postStateChanged()
    }
    
    private func remoteState() -> (payload: String?, updatedAt: Int) {
        guard isICloudAvailable else {
            return (nil, 0)
        }
        
        store.synchronize()
        return (store.string(forKey: Self.configKey), Int(store.double(forKey: Self.timestampKey)))
    }
    
    private enum StartupResolution {
        case automatic
        case local
        case remote
    }
    
    private func startupResolution(localPayload: String?, remotePayload: String) -> StartupResolution {
        switch Defaults.iCloudSyncStartupMode.value {
        case .preferThisMac:
            return .local
        case .preferICloud:
            return .remote
        case .automatic:
            if localPayload == nil || localPayload?.isEmpty == true {
                return .remote
            }
            return .automatic
        }
    }
    
    private func postStateChanged() {
        Notification.Name.iCloudSyncAvailabilityChanged.post()
        Notification.Name.iCloudSyncStateChanged.post()
    }
    
    private func recordSyncOutcome(_ outcome: SyncOutcome) {
        Defaults.iCloudLastSyncTimestamp.value = Self.currentTimestamp()
        Defaults.iCloudLastSyncResult.value = outcome.description
        postStateChanged()
    }
}
