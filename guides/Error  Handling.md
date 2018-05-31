# Error handling

xpm has a cli-oriented custom error handlingm echanism. It's been designed with the following two requirements in mind:

* Output should clearly describe why the execution failed.
* Errors should be reported before the execution finishes.

Although you can use Swift built-in error handling mechanism with `do/try`, errors shouldn't bubble up to the `CommandRegistry`. If at any point of the execution of your program something unexpected happens, the `ErrorHandler` should be used instead of throwing errors up. If your method takes a `Context` as one of the input arguments, you can use its `errorHandler` attribute to report a fatal error.

```swift
protocol ErrorHandling: AnyObject {
    func fatal(error: FatalError)
    func try(_ closure: () throws -> Void)
}
```

## Fatal error

A `FatalError` is an enum with the following cases:

* **bug:** Used when a bug is found and needs to be reported to be fixed.
* **bugSilent:** Same as bug but without showing any information about the error to the user.
* **abort:** Used when some conditions are not met and the execution cannot continue. These errors are not reported and the user gets a description in the console.
* **abortSilent:** Same as abort but without printing any details about the error in the console.

```swift
enum FatalError: Error {
    case abort(Error & CustomStringConvertible)
    case bug(Error & CustomStringConvertible)
    case abortSilent(Error)
    case bugSilent(Error)
}
```

Notice that `abort` and `bug` require the error to conform `CustomStringConvertible`. The description will be printed to the user so it's important that it's concise and descriptive.

```swift
// Example of a bad description
let error = SystemError.tools("Something went wrong")

//  Example of a good description
let error =  SystemError.tools("Yor version of Swift, 4.1 is  not compatible with xpm. Update xpm to use it with your current version of Swift")
```

Whenever it's possible, try to give the user details about what can be done to solve the issue.
