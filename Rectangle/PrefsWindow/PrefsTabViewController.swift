//
//  PrefsTabViewController.swift
//  Rectangle
//
//  Created by OpenAI on 4/10/26.
//

import Cocoa

class PrefsTabViewController: NSTabViewController {
    private var appliedInitialWindowSize = false
    
    override func viewDidAppear() {
        super.viewDidAppear()
        resizeWindowToSelectedTab(animated: appliedInitialWindowSize)
        appliedInitialWindowSize = true
    }
    
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        resizeWindowToSelectedTab(animated: true)
    }
    
    private func resizeWindowToSelectedTab(animated: Bool) {
        guard
            let window = view.window,
            let viewController = currentViewController
        else {
            return
        }
        
        let targetSize = preferredSize(for: viewController)
        let currentContentRect = window.contentRect(forFrameRect: window.frame)
        guard currentContentRect.size != targetSize else { return }
        
        let targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize))
        let currentFrame = window.frame
        let newOrigin = NSPoint(x: currentFrame.origin.x,
                                y: currentFrame.maxY - targetFrame.height)
        let newFrame = NSRect(origin: newOrigin, size: targetFrame.size)
        window.setFrame(newFrame, display: true, animate: animated)
    }
    
    private var currentViewController: NSViewController? {
        if let viewController = tabView.selectedTabViewItem?.viewController {
            return viewController
        }
        
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return tabViewItems[selectedTabViewItemIndex].viewController
    }
    
    private func preferredSize(for viewController: NSViewController) -> NSSize {
        if viewController.preferredContentSize != .zero {
            return viewController.preferredContentSize
        }
        
        viewController.view.layoutSubtreeIfNeeded()
        let fittingSize = viewController.view.fittingSize
        if fittingSize.width > 0, fittingSize.height > 0 {
            return fittingSize
        }
        
        return viewController.view.frame.size
    }
}
