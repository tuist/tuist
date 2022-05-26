import SlothCreator
import SwiftUI

struct CustomizedSlothView: View {
    @State var sloth: Sloth

    var body: some View {
        Text("Hello, World!")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        CustomizedSlothView()
    }
}
