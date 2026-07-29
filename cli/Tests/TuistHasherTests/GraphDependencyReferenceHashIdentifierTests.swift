import Path
import Testing
import TuistCore
import XcodeGraph

@testable import TuistHasher

struct GraphDependencyReferenceHashIdentifierTests {
    @Test func product_reference_identifier_uses_target_and_product_name() {
        // Given
        let reference = GraphDependencyReference.product(
            target: "Resources",
            productName: "Resources.bundle"
        )

        // Then
        #expect(reference.hashIdentifier == "product:Resources:Resources.bundle")
    }

    @Test func bundle_reference_identifier_is_independent_of_the_absolute_path() throws {
        // Given
        let a = GraphDependencyReference.bundle(path: try AbsolutePath(validating: "/checkout-a/Foo.bundle"))
        let b = GraphDependencyReference.bundle(path: try AbsolutePath(validating: "/another/machine/Foo.bundle"))

        // Then
        #expect(a.hashIdentifier == "bundle:Foo.bundle")
        #expect(a.hashIdentifier == b.hashIdentifier)
    }
}
