---
{
  "title": "გენერირებული პროექტი XcodeProj-ზე დაფუძნებული პაკეტის ინტეგრაციით",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "გამოიყენეთ Tuist Registry გენერირებულ პროექტებში XcodeProj-ზე დაფუძნებული პაკეტის ინტეგრაციით."
}
---
# გენერირებული პროექტი XcodeProj-ზე დაფუძნებული პაკეტის ინტეგრაციით {#generated-project-with-xcodeproj-based-integration}

<.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj-ზე დაფუძნებული ინტეგრაციის</.localized_link> გამოყენებისას, შეგიძლიათ გამოიყენოთ `--replace-scm-with-registry` ფლაგი რეესტრიდან დამოკიდებულებების ამოსაცნობად, თუ ისინი ხელმისაწვდომია. დაამატეთ ის თქვენს `Tuist.swift` ფაილში `installOptions`-ში:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

თუ გსურთ უზრუნველყოთ, რომ რეესტრი ყოველთვის გამოიყენებოდეს დამოკიდებულებების ამოცნობისას, საჭიროა განაახლოთ `dependencies` თქვენს `Tuist/Package.swift` ფაილში ისე, რომ გამოიყენოთ რეესტრის იდენტიფიკატორი URL-ის ნაცვლად.

<!-- @snippet: ./_registry-identifier -->
