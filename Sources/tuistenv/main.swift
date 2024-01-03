import Foundation
import TuistEnvKit
import TuistSupport

try TuistSupport.Environment.shared.bootstrap()
LogOutput.bootstrap()

WarningController.shared.append(warning: """
The method used to install this version of Tuist is deprecated and will be deleted soon.
Please, uninstall it by running:

    curl -Ls https://uninstall.tuist.io | bash

And follow the new installation instructions at https://docs.next.tuist.io/documentation/tuist/installation

Read more about the rationale at https://tuist.io/blog/2023/12/15/rtx-default/
""")

TuistCommand.main()
