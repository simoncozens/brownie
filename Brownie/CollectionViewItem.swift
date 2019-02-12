import Cocoa
class CollectionViewItem: NSCollectionViewItem {
    var item: JPEGInfo? {
        didSet {
            guard isViewLoaded else { return }
            if let item = item {
                imageView?.image = ThumbnailCache.with(size: 250).get(item, deferable: true, oncompletion: {
                    newimage in
                    DispatchQueue.main.async { self.imageView?.image = newimage }
                })
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
