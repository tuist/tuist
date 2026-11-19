---
{
  "title": "Bazel-ის პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადაიტანოთ თქვენი პროექტები Bazel-დან Tuist-ზე."
}
---
# Bazel-ის პროექტის მიგრაცია {#migrate-a-bazel-project}

[Bazel](https://bazel.build) არის ბილდის სისტემა, რომელიც Google-მა 2015 წელს ღია კოდად გამოაქვეყნა. ეს არის მძლავრი ინსტრუმენტი, რომელიც საშუალებას გაძლევთ ნებისმიერი ზომის პროგრამული უზრუნველყოფა სწრაფად და საიმედოდ ააწყოთ და შეამოწმოთ. მას იყენებენ ისეთი დიდი ორგანიზაციები, როგორიცაა [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/), [Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae) ან [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel), თუმცა მისი внедрение და შენარჩუნება მოითხოვს საწყის (ანუ ტექნოლოგიის შესწავლა) და გრძელვადიან ინვესტიციას (ანუ Xcode-ის განახლებებთან თანხვედრას). მიუხედავად იმისა, რომ ეს მუშაობს ზოგიერთი ორგანიზაციისთვის, რომლებიც მას ჯვარედინ ამოცანად განიხილავენ, შეიძლება არ იყოს საუკეთესო გადაწყვეტა სხვებისთვის, რომლებიც პროდუქტის განვითარებაზე ფოკუსირებას აპირებენ. მაგალითად, ჩვენ ვნახეთ ორგანიზაციები, სადაც iOS პლატფორმის გუნდმა Bazel внедриა, მაგრამ ძალისხმევის ხელმძღვანელი ინჟინრების კომპანიიდან წასვლის შემდეგ მისი გამოყენება შეწყვიტა. Apple-ის პოზიცია Xcode-სა და ბილდის სისტემას შორის მჭიდრო კავშირზე კიდევ ერთი ფაქტორია, რაც Bazel-ის პროექტების გრძელვადიან შენარჩუნებას ართულებს.

> [!TIP]
> **Tuist-ის უნიკალურობა მის დახვეწილობაშია**
>
> Xcode-თან და Xcode-ის პროექტებთან ბრძოლის ნაცვლად, Tuist მას იღებს. იგივე კონცეფციები (მაგ., სამიზნეები, სქემები, ბილდის პარამეტრები), ნაცნობი ენა (ანუ Swift) და მარტივი, სასიამოვნო გამოცდილება, რაც პროექტების შენარჩუნებას და მასშტაბირებას ყველას საქმედ ხდის და არა მხოლოდ iOS პლატფორმის გუნდის.


## წესები {#rules}

Bazel იყენებს წესებს პროგრამული უზრუნველყოფის აწყობისა და ტესტირების განსაზღვრისთვის. წესები იწერება [Starlark](https://github.com/bazelbuild/starlark)-ში, Python-ის მსგავს ენაში. Tuist იყენებს Swift-ს კონფიგურაციის ენად, რაც დეველოპერებს Xcode-ის ავტოშევსების, ტიპების შემოწმებისა და ვალიდაციის ფუნქციების გამოყენების კომფორტს სთავაზობს. მაგალითად, შემდეგი წესი აღწერს, თუ როგორ ავაწყოთ Swift-ის ბიბლიოთეკა Bazel-ში:

::: code-group
```txt [BUILD (Bazel)]
swift_library(
    name = "MyLibrary.library",
    srcs = glob(["**/*.swift"]),
    module_name = "MyLibrary"
)
```

```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .staticLibrary,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["**/*.swift"]
        )
    ]
)
```
<!-- -->
:::

აქ არის კიდევ ერთი მაგალითი, რომელიც ადარებს ერთეულური ტესტების განსაზღვრას Bazel-ში და Tuist-ში:

::: code-group
```txt [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "dev.tuist.MyLibraryTests",
    minimum_os_version = "16.0",
    test_host = "//MyApp:MyLibrary",
    deps = [":MyLibraryTests.library"],
)

```
```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```
<!-- -->
:::


## Swift Package Manager დამოკიდებულებები {#swift-package-manager-dependencies}

Bazel-ში შეგიძლიათ გამოიყენოთ [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) პლაგინი Swift პაკეტების დამოკიდებულებებად გამოსაყენებლად. პლაგინი მოითხოვს `Package.swift`-ს, როგორც დამოკიდებულებების სანდო წყაროს. Tuist-ის ინტერფეისი ამ მხრივ Bazel-ის მსგავსია. შეგიძლიათ გამოიყენოთ `tuist install` ბრძანება პაკეტის დამოკიდებულებების გასაწყვეტად და ჩამოსატვირთად. გარჩევის დასრულების შემდეგ, შეგიძლიათ პროექტი `tuist generate` ბრძანებით დააგენერიროთ.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## პროექტის გენერაცია {#project-generation}

საზოგადოება გთავაზობთ წესების ნაკრებს, [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj), Bazel-ში აღწერილი პროექტებიდან Xcode-ის პროექტების გენერირებისთვის. Bazel-ისგან განსხვავებით, სადაც `BUILD` ფაილში კონფიგურაციის დამატებაა საჭირო, Tuist არავითარ კონფიგურაციას არ მოითხოვს. შეგიძლიათ გაუშვათ `tuist generate` თქვენი პროექტის ფესვურ დირექტორიაში და Tuist თქვენთვის Xcode-ის პროექტს დააგენერირებს.
