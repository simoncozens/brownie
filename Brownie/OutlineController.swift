//
//  OutlineController.swift
//  Brownie
//
//  Created by Simon Cozens on 09/02/2019.
//  Copyright © 2019 Simon Cozens. All rights reserved.
//

import Foundation
import AppKit

@objc(TreeAdditionObj)
class TreeAdditionObj: NSObject {
    private(set) var nodeURL: URL?
    private(set) var nodeName: String?
    private(set) var selectItsParent: Bool
    init(URL url: URL?, withName name: String?, selectItsParent select: Bool) {
        nodeName = name
        nodeURL = url
        selectItsParent = select
        super.init()
        
    }
}

class OutlineController: NSViewController, NSOutlineViewDelegate, NSOutlineViewDataSource {
    @IBOutlet weak var myOutlineView: NSOutlineView!
    @IBOutlet var treeController: NSTreeController!
    @objc dynamic var contents: [AnyObject] = []
    let pendingOperations = PendingOperations()
    let photoStore = PhotoStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        self.populateBaseContents()
        photoStore.treeController = treeController
        let fileManager = FileManager.default
        let picsURL = fileManager.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.syncYearTree(_:)), name: NSNotification.Name.SyncYearTree, object: nil)

        DispatchQueue.global(qos: .default).async {
            self.photoStore.addDirectory(picsURL, periodicUpdate: {() in
                DispatchQueue.main.async { self.myOutlineView?.reloadData() }
                NotificationCenter.default.post(name: NSNotification.Name.MorePhotosHaveArrived, object: nil)
                
            })
        }
        
    }

    @objc func syncYearTree(_ n: NSNotification) {
        guard let yeartree = n.userInfo?["yeartree"] as? Dictionary<Int,YearTree> else { return }
        let datesindex = IndexPath(index: 0) // XXX
        let datesnode = treeController!.arrangedObjects.descendant(at: datesindex)?.representedObject as! BaseNode
        // For now I am going to be stupid
        DispatchQueue.main.sync {
            self.myOutlineView.isHidden = true
            datesnode.children = []
            for year in yeartree.keys.sorted() {
                let last = IndexPath(index: datesnode.children.count)
                let node = ChildNode()
                node.nodeTitle = String(year)
                node.count = yeartree[year]!.count
                    self.treeController.insert(node, atArrangedObjectIndexPath: datesindex.appending(last))
            }
            self.myOutlineView.isHidden = false
        }
    }

    func populateBaseContents() {
        var treeObjInfo = TreeAdditionObj(URL: nil, withName: BaseNode.DATES_NAME, selectItsParent: false)
        self.performAddFolder(treeObjInfo)
        treeObjInfo = TreeAdditionObj(URL: nil, withName: BaseNode.SOURCES_NAME, selectItsParent: false)
        self.performAddFolder(treeObjInfo)

    }
    
    private func performAddFolder(_ treeAddition: TreeAdditionObj) {
        var indexPath: IndexPath
        indexPath = IndexPath(index: self.contents.count)
        let node = ChildNode()
        node.nodeTitle = treeAddition.nodeName ?? ""
        // the user is adding a child node, tell the controller directly
        self.treeController.insert(node, atArrangedObjectIndexPath: indexPath)
    }
    
    //MARK: - NSOutlineViewDelegate
    
    // -------------------------------------------------------------------------------
    //    shouldSelectItem:item
    // -------------------------------------------------------------------------------
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        // don't allow special group nodes (Places and Bookmarks) to be selected
        let node = (item as! NSTreeNode).representedObject as! BaseNode
        return !node.isSpecialGroup && !node.isSeparator
    }
    
    // -------------------------------------------------------------------------------
    //    viewForTableColumn:tableColumn:item
    // -------------------------------------------------------------------------------
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var result = outlineView.makeView(withIdentifier: tableColumn?.identifier ?? NSUserInterfaceItemIdentifier(rawValue: ""), owner: self)
        
        if let node = (item as! NSTreeNode).representedObject as? BaseNode {
            if self.outlineView(outlineView, isGroupItem: item) {    // is it a special group (not a folder)?
                // Group items are sections of our outline that can be hidden/shown (i.e. PLACES/BOOKMARKS).
                let identifier = outlineView.tableColumns[0].identifier
                result = outlineView.makeView(withIdentifier: identifier, owner: self) as! NSTableCellView?
                var value = node.nodeTitle.uppercased()
                if node.count > 0 {
                    value = value + " (" + String(node.count) + ")"
                }
                (result as! NSTableCellView).textField!.stringValue = value
            } else if node.isSeparator {
                // Separators have no title or icon, just use the custom view to draw it.
                result = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "Separator"), owner: self)
            } else {
                var label = node.nodeTitle
                // I'm on the main thread anyway, right?
//                pthread_rwlock_rdlock(&(photoStore.treelock))
                if node.count > 0 {
                    label = label + " (" + String(node.count) + ")"
                }
//                pthread_rwlock_unlock(&(photoStore.treelock))

                (result as! NSTableCellView).textField!.stringValue = label
                (result as! NSTableCellView).imageView!.image = node.nodeIcon
            }
        }
        
        return result
    }
    
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        let node = (item as! NSTreeNode).representedObject as! BaseNode
        return node.isSpecialGroup
    }
}

