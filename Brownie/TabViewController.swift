//
//  TabViewController.swift
//  Brownie
//
//  Created by Simon Cozens on 25/02/2019.
//  Copyright © 2019 Simon Cozens. All rights reserved.
//

import Cocoa

class TabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        if tabViewItem?.label == "Table" {
            PhotoStore.shared.removeFilter(withTag: "Map")
        }
    }
}
