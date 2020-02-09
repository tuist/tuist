extension String.StringInterpolation {

    public mutating func appendInterpolation(_ value: String, _ token: ConsoleToken) {
        
        guard Environment.shared.shouldOutputBeColoured else {
            return appendLiteral(value)
        }
        
        let message = token.elements().reduce(value) { $1.ƒ($0) }
        
        appendLiteral(message)

    }
    
}
