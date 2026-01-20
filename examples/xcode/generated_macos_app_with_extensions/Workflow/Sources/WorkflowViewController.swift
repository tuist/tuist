import Cocoa
import ProExtensionHost

class WorkflowViewController: NSViewController {
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override var nibName: NSNib.Name? {
        NSNib.Name("WorkflowViewController")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    var hostInfoString: String {
        let host = ProExtensionHostSingleton() as! FCPXHost
        return String(format: "%@ %@", host.name, host.versionString)
    }
}
