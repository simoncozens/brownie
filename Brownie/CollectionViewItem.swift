import Cocoa
import SDWebImage

class CollectionViewItem: NSCollectionViewItem {
    var item: JPEGInfo? {
        didSet {
            guard isViewLoaded else { return }
            if let item = item {
                let transformer = SDImageResizingTransformer(size: CGSize(width: 200, height: 70), scaleMode: .aspectFit)

                imageView?.sd_setImage(with: item.path, placeholderImage: nil, options: [], context: [.imageTransformer: transformer])
                self.textField?.stringValue = item.path.lastPathComponent
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.lightGray.cgColor
    }
    
    @IBAction func revealInFinder(sender: Any) {
        if let item = self.item {
            NSWorkspace.shared.activateFileViewerSelecting([item.path])
        }
    }
}
