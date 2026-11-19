---
{
  "title": "Bazel-ის პროექტის მიგრაცია",
  "titleTemplate": ":title · მიგრაცია · დანერგვა · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ისწავლეთ, როგორ გადაიტანოთ თქვენი პროექტები Bazel-იდან Tuist-ზე."
}
---
# Bazel-ის პროექტის მიგრაცია {#migrate-a-bazel-project}

[Bazel](https://bazel.build) არის ბილდის სისტემა, რომელიც Google-მა 2015 წელს გახადა ღია კოდის პროექტად. ეს არის მძლავრი ინსტრუმენტი, რომელიც საშუალებას გაძლევთ სწრაფად და საიმედოდ ააგოთ და შეამოწმოთ ნებისმიერი ზომის პროგრამული უზრუნველყოფა. მას იყენებენ ისეთი დიდი ორგანიზაციები, როგორიცაა [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/), [Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae) ან [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel), თუმცა მისი внедрება და შენარჩუნება მოითხოვს საწყის (ანუ ტექნოლოგიის შესწავლა) და გრძელვადიან ინვესტიციას (ანუ Xcode-ის განახლებებთან თანმხვედრობას). მიუხედავად იმისა, რომ ეს მუშაობს ზოგიერთი ორგანიზაციისთვის, რომლებიც მას ჯვარედინ ამოცანად განიხილავენ, შეიძლება არ იყოს საუკეთესო გადაწყვეტა სხვებისთვის, რომლებიც პროდუქტის განვითარებაზე ფოკუსირებას აპირებენ. მაგალითად, ჩვენ ვნახეთ ორგანიზაციები, სადაც iOS პლატფორმის გუნდმა внедрила Bazel, მაგრამ იძულებული გახდა უარი ეთქვა მასზე, მას შემდეგ, რაც ინიციატივის ხელმძღვანელი ინჟინრები კომპანიიდან წავიდნენ. Apple-ის პოზიცია Xcode-სა და ბილდის სისტემას შორის მჭიდრო კავშირის შესახებ კიდევ ერთი ფაქტორია, რაც Bazel-ის პროექტების გრძელვადიან შენარჩუნებას ართულებს.

> [!TIP]
> **Tuist-ის უნიკალურობა მის დახვეწილობაშია**
>
> Xcode-თან და Xcode-ის პროექტებთან ბრძოლის ნაცვლად, Tuist მათ იღებს. იგივე კონცეფციები (მაგ., სამიზნეები, სქემები, ბილდის პარამეტრები), ნაცნობი ენა (ანუ Swift) და მარტივი, სასიამოვნო გამოცდილება, რაც პროექტების შენარჩუნებას და მასშტაბირებას ყველას საქმედ აქცევს და არა მხოლოდ iOS პლატფორმის გუნდის.


## წესები {#rules}

Bazel იყენებს წესებს, რათა განსაზღვროს, თუ როგორ უნდა აიგოს და შემოწმდეს პროგრამული უზრუნველყოფა. წესები იწერება [Starlark](https://github.com/bazelbuild/starlark)-ში, Python-ის მსგავს ენაში. Tuist იყენებს Swift-ს, როგორც კონფიგურაციის ენას, რაც დეველოპერებს აძლევს Xcode-ის ავტოშევსების, ტიპების შემოწმებისა და ვალიდაციის ფუნქციების გამოყენების მოხერხებულობას. მაგალითად, შემდეგი წესი აღწერს, თუ როგორ უნდა აიგოს Swift ბიბლიოთეკა Bazel-ში:

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


## Swift Package Manager-ის დამოკიდებულებები {#swift-package-manager-dependencies}

Bazel-ში შეგიძლიათ გამოიყენოთ [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) პლაგინი, რათა Swift Packages გამოიყენოთ, როგორც დამოკიდებულებები. პლაგინს სჭირდება `Package.swift`, როგორც დამოკიდებულებების სანდო წყარო. Tuist-ის ინტერფეისი ამ მხრივ Bazel-ის მსგავსია. შეგიძლიათ გამოიყენოთ `tuist install` ბრძანება პაკეტის დამოკიდებულებების გასაწევად და ჩამოსატვირთად. რეზოლუციის დასრულების შემდეგ, შეგიძლიათ პროექტის გენერირება `tuist generate` ბრძანებით.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## პროექტის გენერირება {#project-generation}

საზოგადოება უზრუნველყოფს წესების ნაკრებს, [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj), რათა Bazel-ში განსაზღვრული პროექტებიდან Xcode-ის პროექტები გენერირდეს. Bazel-ისგან განსხვავებით, სადაც თქვენს `BUILD` ფაილში კონფიგურაციის დამატებაა საჭირო, Tuist საერთოდ არ მოითხოვს კონფიგურაციას. შეგიძლიათ გაუშვათ `tuist generate` თქვენი პროექტის ფესვური დირექტორიიდან და Tuist თქვენთვის Xcode-ის პროექტს შექმნის.
