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
    @State private var showsReceipt = false
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
            Button("Show receipt") { showsReceipt = true }
            if showsReceipt {
                Text(Receipt.lines(for: cart.items, discountPercent: cart.discountPercent).joined(separator: "\n"))
                    .accessibilityIdentifier("receipt")
            }
        }
        .padding()
        .tint(Color("Brand"))
    }
}
