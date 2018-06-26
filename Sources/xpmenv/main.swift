import Foundation

do {
    let environmentController = LocalEnvironmentController()
    try environmentController.setup()
    let localVersionsController = LocalVersionsController(environmentController: environmentController)

} catch {
    let stringConvertibleError = error as CustomStringConvertible
    let message = """
    An internal error happened: \(stringConvertibleError.description)
        
    Try again and if the problem persists, create an issue on https://github.com/xcode-project-manager/support
    """
    print(message)
    exit(1)
}
