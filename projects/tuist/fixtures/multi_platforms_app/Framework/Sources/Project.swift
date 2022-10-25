import ZIPFoundation

public enum Printer {
    public static func printInfo() {
        let archive = Archive(accessMode: .create)
        print(archive.debugDescription)
    }
}
