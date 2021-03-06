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
    let photoStore = PhotoStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        self.populateBaseContents()
        photoStore.treeController = treeController
        let fileManager = FileManager.default
        let picsURL = fileManager.urls(for: .picturesDirectory, in: .userDomainMask)[0]//.appendingPathComponent("Brownie/")
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.syncYearTree(_:)), name: NSNotification.Name.SyncYearTree, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.periodicUpdate(_:)), name: NSNotification.Name.MorePhotosHaveArrived, object: nil)

        DispatchQueue.global(qos: .default).async {
            self.photoStore.addDirectory(picsURL, periodicUpdate: {() in
                
            })
        }
        
    }
    
    @objc func periodicUpdate(_ n: NSNotification) {
//        print("Reloading outline view")
        DispatchQueue.main.async {
            self.myOutlineView.expandItem(self.treeController!.arrangedObjects.descendant(at: IndexPath(index: 1)))
            self.myOutlineView.needsDisplay = true
            self.myOutlineView?.reloadData()
            // XXX
        }
    }

    @objc func syncYearTree(_ n: NSNotification) {
        let yeartree = PhotoStore.shared.getYearTree()
        let datesindex = IndexPath(index: 0) // XXX
        let datesnode = treeController!.arrangedObjects.descendant(at: datesindex)?.representedObject as! BaseNode
        // For now I am going to be stupid
        DispatchQueue.main.async {
            self.myOutlineView.isHidden = true
            datesnode.children = []
            for year in yeartree.keys.sorted() {
                let last = IndexPath(index: datesnode.children.count)
                let node = ChildNode()
                node.nodeTitle = String(year)
                node.count = yeartree[year]!.count
                let months = yeartree[year]!.months
                let yearindex = datesindex.appending(last)
                self.treeController.insert(node, atArrangedObjectIndexPath: yearindex)
//                var mcount = 0
//                for month in months.keys.sorted() {
//                    let node = ChildNode()
//                    node.nodeTitle = String(month)
//                    pthread_rwlock_rdlock(&(PhotoStore.shared.yeartreelock))
//                    node.count = months[month]!.count
//                    pthread_rwlock_unlock(&(PhotoStore.shared.yeartreelock))
//                    self.treeController.insert(node, atArrangedObjectIndexPath: yearindex.appending(IndexPath(index: mcount)))
//                    mcount = mcount + 1
//                }
            }
//            self.treeController.rearrangeObjects()

            self.myOutlineView.expandItem(self.treeController!.arrangedObjects.descendant(at: IndexPath(index: 0)))
            self.myOutlineView.expandItem(self.treeController!.arrangedObjects.descendant(at: IndexPath(index: 1)))
            self.myOutlineView.needsDisplay = true
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
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let selection = myOutlineView.item(atRow: myOutlineView.selectedRow) as? NSTreeNode else { return }
        let node = (selection as! NSTreeNode).representedObject as! BaseNode
        print("Selected: \(node.nodeTitle)")
        let datesindex = IndexPath(index: 0) // XXX
        let datesnode = treeController!.arrangedObjects.descendant(at: datesindex)?.representedObject as! BaseNode
        PhotoStore.shared.removeFilter(withTag: "Year")
        if (node.isDescendantOfNodes([datesnode])) {
            let f = PhotoFilter(tag: "Year") {
                if $0.isodate == nil { return false }
                let year = Calendar.current.component(.year, from: $0.isodate!)
                return String(year) == node.nodeTitle
            }
            PhotoStore.shared.addFilter(f)
        }
        // Use this to rebuild map annotations / filter table
        NotificationCenter.default.post(name: NSNotification.Name.MorePhotosHaveArrived, object: nil)
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
                if node.count > 0 {
                    label = label + " (" + String(node.count) + ")"
                }
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

