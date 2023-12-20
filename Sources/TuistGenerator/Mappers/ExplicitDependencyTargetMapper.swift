import Foundation
import TuistCore
import TuistGraph
import TuistSupport

/// A target mapper that updates
public struct ExplicitDependencyTargetMapper: TargetMapping {
    public init() {}
    
    public func map(target: Target) throws -> (Target, [SideEffectDescriptor]) {
        let movedProductNames = target.dependencies.compactMap {
            switch $0 {
            case
                let .target(name: name, condition: _),
                let .project(target: name, path: _, condition: _):
                return name
            case .library, .framework, .package, .sdk, .xcframework, .xctest:
                return nil
            }
        }
            
        let frameworkSearchPaths = movedProductNames.map {
            "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/\($0)"
        }
        
        let copyProductsScript = movedProductNames
            .map {
                """
                #!/usr/
                
                ln -s "$CONFIGURATION_BUILD_DIR/\($0)/\($0).framework"  "$CONFIGURATION_BUILD_DIR$TARGET_BUILD_SUBPATH/$PRODUCT_NAME/\($0).framework"
                """
            }
            .joined(separator: "\n")
        
        var additionalSettings: SettingsDictionary = [
            "FRAMEWORK_SEARCH_PATHS": .array(frameworkSearchPaths)
        ]

        additionalSettings["TARGET_BUILD_DIR"] = "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)"

        additionalSettings["BUILT_PRODUCTS_DIR"] = "$(CONFIGURATION_BUILD_DIR)$(TARGET_BUILD_SUBPATH)/$(PRODUCT_NAME)"

        return (
            target.with(
                additionalSettings: additionalSettings
            )
            .with(
                scripts: [
                    TargetScript(
                        name: "Copy Build Products",
                        order: .pre,
                        script: .embedded(copyProductsScript)
                    )
                ]
            ),
            []
        )
    }
}
