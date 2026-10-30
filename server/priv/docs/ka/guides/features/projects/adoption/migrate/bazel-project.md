---
{
  "title": "Bazel-ის პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გადაიტანოთ თქვენი პროექტები Bazel-იდან Tuist-ზე."
}
---
# Bazel-პროექტის მიგრაცია {#migrate-a-bazel-project}

[Bazel](https://bazel.build) არის ბილდის სისტემა, რომელიც Google-მა 2015 წელს ღია კოდად გამოაქვეყნა. ეს არის მძლავრი ინსტრუმენტი, რომელიც საშუალებას გაძლევთ ნებისმიერი ზომის პროგრამული უზრუნველყოფა სწრაფად და საიმედოდ ააწყოთ და დატესტოთ. მას იყენებენ ისეთი დიდი ორგანიზაციები, როგორიცაა [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/), [Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae) ან [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel), თუმცა მისი внедрება და შენარჩუნება მოითხოვს საწყის (ანუ ტექნოლოგიის შესწავლა) და გრძელვადიან ინვესტიციას (ანუ Xcode-ის განახლებებთან თავის შესაბამისობაში ყოლა). მიუხედავად იმისა, რომ ეს ზოგიერთი ორგანიზაციისთვის, რომელიც მას გადაკვეთილი საკითხად მიიჩნევს, მუშაობს, სხვებისთვის, რომლებიც პროდუქტის განვითარებაზე ფოკუსირებას აპირებენ, შესაძლოა საუკეთესო ვარიანტი არ იყოს. მაგალითად, ჩვენ ვნახეთ ორგანიზაციები, სადაც iOS პლატფორმის გუნდმა Bazel внедрила, მაგრამ ძალისხმევის ხელმძღვანელი ინჟინრების კომპანიიდან წასვლის შემდეგ მისი გამოყენება შეწყვიტა. Apple-ის პოზიცია Xcode-სა და ბილდის სისტემას შორის მჭიდრო კავშირზე კიდევ ერთი ფაქტორია, რაც Bazel-პროექტების გრძელვადიან შენარჩუნებას ართულებს.

> [!TIP]
> **Tuist-ის უნიკალურობა მის დახვეწილობაშია**
>
> Xcode-თან და Xcode-პროექტებთან ბრძოლის ნაცვლად, Tuist მას ეთანხმება. იგივე კონცეფციები (მაგ., ტარგეტები, სქემები, ბილდის პარამეტრები), ნაცნობი ენა (ანუ Swift) და მარტივი, სასიამოვნო გამოცდილება, რაც პროექტების შენარჩუნებასა და მასშტაბირებას ყველას საქმედ აქცევს და არა მხოლოდ iOS პლატფორმის გუნდის.


## წესები {#rules}

Bazel იყენებს წესებს, რათა განსაზღვროს, თუ როგორ უნდა აიწყოს და დაიტესტოს პროგრამული უზრუნველყოფა. წესები იწერება [Starlark](https://github.com/bazelbuild/starlark)-ში, Python-ის მსგავს ენაში. Tuist იყენებს Swift-ს კონფიგურაციის ენად, რაც დეველოპერებს Xcode-ის ავტოშევსების, ტიპების შემოწმებისა და ვალიდაციის ფუნქციების გამოყენების კომფორტს ანიჭებს. მაგალითად, ქვემოთ მოცემული წესი აღწერს, თუ როგორ უნდა აიწყოს Swift-ბიბლიოთეკა Bazel-ში:

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
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
<!-- -->
:::

აქ არის კიდევ ერთი მაგალითი, რომელიც ადარებს ერთეულოვანი ტესტების განსაზღვრას Bazel-ში და Tuist-ში:

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

Bazel-ში შეგიძლიათ გამოიყენოთ [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) პლაგინი Swift-პაკეტების დამოკიდებულებად გამოსაყენებლად. პლაგინი მოითხოვს `Package.swift`-ს, როგორც დამოკიდებულებების ჭეშმარიტ წყაროს. ამ თვალსაზრისით Tuist-ის ინტერფეისი Bazel-ის მსგავსია. შეგიძლიათ გამოიყენოთ `tuist install` ბრძანება პაკეტის დამოკიდებულებების გასაშლელად და ჩამოსატვირთად. გაშლის დასრულების შემდეგ შეგიძლიათ პროექტი `tuist generate` ბრძანებით გენერირება.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## პროექტის გენერაცია {#project-generation}

საზოგადოება უზრუნველყოფს წესების ნაკრებს, [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj), რათა Bazel-ში აღწერილი პროექტებიდან Xcode-პროექტები გენერირდეს. Bazel-ისგან განსხვავებით, სადაც `BUILD` ფაილში გარკვეული კონფიგურაციის დამატებაა საჭირო, Tuist საერთოდ არ მოითხოვს კონფიგურაციას. შეგიძლიათ გაუშვათ `tuist generate` თქვენი პროექტის ფესვური დირექტორიიდან და Tuist თქვენთვის Xcode-პროექტს გენერირებს.
