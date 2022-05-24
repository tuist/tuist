import SlothCreator
import SwiftUI

struct CustomizedSlothView: View {
    @State var sloth: Sloth

    var body: some View {
        VStack {
            SlothView(sloth: $sloth)
            PowerPicker(power: $sloth.power)
        }.padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        CustomizedSlothView()
    }
}
