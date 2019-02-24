//
//  TableController.swift
//  Brownie
//
//  Created by Simon Cozens on 09/02/2019.
//  Copyright © 2019 Simon Cozens. All rights reserved.
//

import Foundation
import AppKit
import SDWebImage

class TableController: NSViewController {
    @IBOutlet weak var tableView: NSTableView!
    override func viewDidLoad() {
        NotificationCenter.default.addObserver(self, selector: #selector(reloadTable), name: NSNotification.Name.MorePhotosHaveArrived, object: nil)
    }
    @objc func reloadTable () {
        DispatchQueue.main.async { self.tableView.reloadData() }
    }
}

extension TableController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return PhotoStore.shared.countFilteredItems
    }
}

extension TableController: NSTableViewDelegate {
    
    fileprivate enum CellIdentifiers {
        static let ThumbnailCell = "ThumbnailCellID"
        
        static let PathCell = "PathCellID"
        static let LocationCell = "LocationCellID"
        static let DateCell = "DateCellID"
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        var text: String = ""
        var cellIdentifier: String = ""
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        //        let rect = tableView.visibleRect
        //        let visiblerows = tableView.rows(in: rect)
        pthread_rwlock_rdlock(&PhotoStore.shared.databaselock)
        let item = PhotoStore.shared.filteredItems[row]
        pthread_rwlock_unlock(&PhotoStore.shared.databaselock)
        if tableColumn == tableView.tableColumns[0] {
            cellIdentifier = CellIdentifiers.ThumbnailCell
        } else if tableColumn == tableView.tableColumns[1] {
            text = item.path.lastPathComponent
            cellIdentifier = CellIdentifiers.PathCell
        } else if tableColumn == tableView.tableColumns[2] {
            if item.location != nil { text = item.location!.dms.latitude + " " + item.location!.dms.longitude }
            cellIdentifier = CellIdentifiers.LocationCell
        } else if tableColumn == tableView.tableColumns[3] {
            if item.date != nil { text = item.date! }
            cellIdentifier = CellIdentifiers.DateCell
        }
        
        // 3
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(cellIdentifier), owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = text
            if tableColumn == tableView.tableColumns[0] {
                let transformer = SDImageResizingTransformer(size: CGSize(width: 200, height: 200), scaleMode: .aspectFit)
                cell.imageView?.sd_setImage(with: item.path, placeholderImage: nil, options: [], context: [.imageTransformer: transformer])
            }
            return cell
        }
        return nil
    }
    
    @IBAction func revealInFinder(sender: Any) {
        print(self.tableView.clickedRow)
        NSWorkspace.shared.activateFileViewerSelecting([PhotoStore.shared.filteredItems[self.tableView.clickedRow].path])
    }
    
}
