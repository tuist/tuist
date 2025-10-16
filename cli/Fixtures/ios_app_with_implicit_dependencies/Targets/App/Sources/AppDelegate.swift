import FrameworkA
import FrameworkB
import UIKit
import protocol ProtocolModule.SomeProtocol
import struct StructModule.SomeStruct
import enum EnumModule.SomeEnum
import class ClassModule.SomeClass
import func FuncModule.someFunction
import var VarModule.someVariable
import let LetModule.someConstant
import typealias TypeAliasModule.SomeTypeAlias

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        FrameworkA.frameworkA()
        FrameworkB.frameworkB()

        let structInstance = SomeStruct(value: "test")
        let enumCase = SomeEnum.case1
        let classInstance = SomeClass()
        let functionResult = someFunction()
        let variableValue = someVariable
        let constantValue = someConstant
        let typeAliasValue: SomeTypeAlias = "test"

        return true
    }
}
