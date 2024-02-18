//
//  Foo.swift
//
//
//  Created by Shahzad Majeed on 1/23/24.
//

import Foundation
import Framework
import SwiftUI

public struct ContentView: View {
    let user: Person
    init(user: Person) {
        self.user = user
    }
    
    public var body: some View {
        Text("\(user.name.capitalized) how are you? \(user.age) already?")
    }
}

#Preview {
    ContentView(user: Person(name: "Sal", age: 99))
}
