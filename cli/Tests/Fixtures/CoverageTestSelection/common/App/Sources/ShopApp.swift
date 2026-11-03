import Catalog
import Core
import SwiftUI

@main
struct ShopApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var cart = Cart()
    private let products = (try? Catalog.bundled().products) ?? []

    var body: some View {
        VStack(spacing: 16) {
            ForEach(products, id: \.sku) { product in
                HStack {
                    Text(product.name)
                    Spacer()
                    Text(Money(cents: product.priceCents).formatted)
                    Button("Add \(product.name)") { cart.add(product) }
                }
            }
            Button("Apply 10% off") { cart.discountPercent = 10 }
            Text("Total: \(cart.total.formatted)")
                .accessibilityIdentifier("total")
        }
        .padding()
        .tint(Color("Brand"))
    }
}
