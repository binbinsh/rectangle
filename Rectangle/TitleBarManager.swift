//
//  TitleBarManager.swift
//  Rectangle
//
//  Copyright © 2023 Ryan Hanson. All rights reserved.
//

import Foundation

class TitleBarManager {
    private var titleBarMonitor: EventMonitor!
    private var greenButtonMonitor: EventMonitor!
    private var lastTitleBarEventNumber: Int?
    private var pendingGreenButtonClick: PendingGreenButtonClick?

    init() {
        titleBarMonitor = PassiveEventMonitor(mask: .leftMouseUp, handler: handleTitleBar)
        greenButtonMonitor = ActiveEventMonitor(mask: [.leftMouseDown, .leftMouseUp], filterer: filterGreenButton, handler: {_ in })
        toggleTitleBarListening()
        toggleGreenButtonListening()
        Notification.Name.windowTitleBar.onPost { notification in
            self.toggleTitleBarListening()
        }
        Notification.Name.greenButtonZoom.onPost { notification in
            self.toggleGreenButtonListening()
        }
        Notification.Name.configImported.onPost { notification in
            self.toggleTitleBarListening()
            self.toggleGreenButtonListening()
        }
    }
    
    private func toggleTitleBarListening() {
        let shouldListen = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1) != nil
        if shouldListen {
            if !titleBarMonitor.running {
                titleBarMonitor.start()
            }
        } else if titleBarMonitor.running {
            titleBarMonitor.stop()
        }
    }

    private func toggleGreenButtonListening() {
        pendingGreenButtonClick = nil
        if Defaults.greenButtonMaximize.enabled {
            if !greenButtonMonitor.running {
                greenButtonMonitor.start()
            }
        } else if greenButtonMonitor.running {
            greenButtonMonitor.stop()
        }
    }

    private func eventLocation(_ event: NSEvent) -> CGPoint? {
        event.cgEvent?.location.screenFlipped ?? NSEvent.mouseLocation.screenFlipped
    }

    private func plainLeftClick(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty && event.clickCount == 1
    }

    private func greenButtonTarget(at location: CGPoint) -> PendingGreenButtonClick? {
        guard
            let element = AccessibilityElement(location)?.getSelfOrChildElementRecursively(location),
            let windowElement = element.windowElement,
            let buttonFrame = windowElement.fullScreenButtonFrame,
            buttonFrame.contains(location)
        else {
            return nil
        }
        return PendingGreenButtonClick(windowElement: windowElement, buttonFrame: buttonFrame)
    }
    
    private func filterGreenButton(_ event: NSEvent) -> Bool {
        guard Defaults.greenButtonMaximize.enabled, let location = eventLocation(event) else {
            pendingGreenButtonClick = nil
            return false
        }

        switch event.type {
        case .leftMouseDown:
            guard plainLeftClick(event), let target = greenButtonTarget(at: location) else {
                pendingGreenButtonClick = nil
                return false
            }
            pendingGreenButtonClick = target
            return true
        case .leftMouseUp:
            guard let pending = pendingGreenButtonClick else { return false }
            pendingGreenButtonClick = nil
            if pending.buttonFrame.contains(location) {
                DispatchQueue.main.async {
                    WindowAction.maximize.postTitleBar(windowElement: pending.windowElement)
                }
            }
            return true
        default:
            pendingGreenButtonClick = nil
            return false
        }
    }

    private func handleTitleBar(_ event: NSEvent) {
        guard
            event.type == .leftMouseUp,
            event.clickCount == 2,
            event.eventNumber != lastTitleBarEventNumber,
            TitleBarManager.systemSettingDisabled,
            let action = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1),
            case let location = NSEvent.mouseLocation.screenFlipped,
            let element = AccessibilityElement(location)?.getSelfOrChildElementRecursively(location),
            let windowElement = element.windowElement,
            var titleBarFrame = windowElement.titleBarFrame
        else {
            return
        }
        lastTitleBarEventNumber = event.eventNumber
        
        var bundleIdentifier: String?
        if let pid = element.pid {
            bundleIdentifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        
        if let toolbarFrame = windowElement.getChildElement(.toolbar)?.frame, toolbarFrame != .null {
            if let bundleIdentifier,
               let toolbarIgnoredIds = Defaults.doubleClickToolBarIgnoredApps.typedValue,
               toolbarIgnoredIds.contains(bundleIdentifier) {
               // don't add the toolbar frame to the title bar
            } else {
                titleBarFrame = titleBarFrame.union(toolbarFrame)
            }
        }
        guard
            titleBarFrame.contains(location),
            element.isWindow == true || element.isToolbar == true || element.isGroup == true || element.isTabGroup == true || element.isStaticText == true
        else {
            return
        }
        if let bundleIdentifier,
            let ignoredApps = Defaults.doubleClickTitleBarIgnoredApps.typedValue,
            ignoredApps.contains(bundleIdentifier) {
            return
        }
        if Defaults.doubleClickTitleBarRestore.enabled != false,
           let windowId = windowElement.windowId,
           case let windowFrame = windowElement.frame,
           windowFrame != .null,
           let historyAction = AppDelegate.windowHistory.lastRectangleActions[windowId],
           historyAction.action == action,
           historyAction.rect == windowFrame {
            WindowAction.restore.postTitleBar(windowElement: windowElement)
            return
        }
        action.postTitleBar(windowElement: windowElement)
    }
}

private struct PendingGreenButtonClick {
    let windowElement: AccessibilityElement
    let buttonFrame: CGRect
}

extension TitleBarManager {
    static var systemSettingDisabled: Bool {
        UserDefaults(suiteName: ".GlobalPreferences")?.string(forKey: "AppleActionOnDoubleClick") == "None"
    }
}
