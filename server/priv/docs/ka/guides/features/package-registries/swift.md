---
{
  "title": "Swift",
  "titleTemplate": ":title · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "დააჩქარეთ Swift Package Manager-ის დამოკიდებულებების ამოცნობა წუთებიდან წამებამდე Tuist-ის Swift-პაკეტების რეესტრით, რომელიც ეყრდნობა Tuist-ის გლობალურ ქეშის ქსელს."
}
---
# Swift Package Registry {#swift-package-registry}

დამოკიდებულებების რაოდენობის ზრდასთან ერთად იზრდება მათი ამოხსნისთვის საჭირო დროც. სხვა პაკეტების მენეჯერები, როგორიცაა [CocoaPods](https://cocoapods.org/) ან [npm](https://www.npmjs.com/), ცენტრალიზებულია, ხოლო Swift Package Manager — არა. ამიტომ SwiftPM-ს დამოკიდებულებების ამოსახსნელად თითოეული რეპოზიტორიის სრული კლონირება სჭირდება, რაც დროს მოითხოვს და უფრო მეტ მეხსიერებას იკავებს, ვიდრე ცენტრალიზებული მიდგომა. ამ პრობლემის გადასაჭრელად Tuist გთავაზობთ [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)-ის იმპლემენტაციას, რათა ჩამოტვირთოთ მხოლოდ ის კომიტები, რომლებიც _ნამდვილად გჭირდებათ_. რეესტრში არსებული პაკეტები ეფუძნება [Swift Package Index](https://swiftpackageindex.com/)-ს — თუ პაკეტს იქ იპოვით, ის Tuist Registry-შიც ხელმისაწვდომია. გარდა ამისა, პაკეტები მსოფლიოს მასშტაბით ნაწილდება edge storage-ის გამოყენებით, რაც მინიმალურ დაყოვნებას უზრუნველყოფს მათი ამოხსნისას.

## გამოყენება {#usage}

რეესტრის დასაყენებლად ორი გზა არსებობს:

### ვარიანტი 1: ავტომატური დაყენება გენერაციის დროს (რეკომენდებული) {#automatic-setup}

თუ Tuist-ს იყენებთ პროექტის გენერირებისთვის, შეგიძლიათ ჩართოთ რეესტრი `registryEnabled` პარამეტრის მითითებით თქვენს `Tuist.swift` კონფიგურაციაში:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

ამ პარამეტრით `tuist generate` ავტომატურად შექმნის რეესტრის კონფიგურაციის ფაილს თქვენს სამუშაო სივრცეში. ეს აღმოფხვრის საჭიროებას, ცალკე გაუშვათ `tuist registry setup`.

> [!TIP]
> `registryEnabled` ასევე აკონფიგურირებს რეესტრს პროექტებისთვის, რომლებიც დამოკიდებულებებს აინტეგრირებენ Xcode-ის ნაგულისხმევი Swift Package Manager ინტეგრაციით და არა Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით. ის არ აკონფიგურირებს Xcode-ს ისეთი პაკეტების ამოსახსნელად, რომლებიც რეესტრიდან source control URL-ით არის განსაზღვრული. ამის გასაკეთებლად, თითოეულ მანქანაზე ერთხელ გაუშვით `tuist registry setup`, როგორც აღწერილია <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Source control პაკეტების ამოხსნა</.localized_link>-ში.


### ვარიანტი 2: ხელით დაყენება {#manual-setup}

რეესტრის ხელით დასაყენებლად, გაუშვით შემდეგი ბრძანება თქვენი პროექტის დირექტორიაში:

```bash
tuist registry setup
```

ეს ბრძანება ქმნის რეესტრის კონფიგურაციის ფაილს, რომელიც რთავს რეესტრს თქვენი პროექტისთვის. დარწმუნდით, რომ ეს ფაილი შეტანილია ვერსიების კონტროლის სისტემაში, რათა თქვენმა გუნდმაც ისარგებლოს რეესტრით.

### ავთენტიკაცია (არასავალდებულო) {#authentication}

ავთენტიკაცია **არასავალდებულოა**. ავთენტიკაციის გარეშე შეგიძლიათ გამოიყენოთ რეესტრი **1,000 მოთხოვნა წუთში** შეზღუდვით თითოეულ IP მისამართზე. უფრო მაღალი ლიმიტის, **20,000 მოთხოვნა წუთში**, მისაღებად შეგიძლიათ გაიაროთ ავთენტიკაცია შემდეგი ბრძანების გაშვებით:

```bash
tuist registry login
```

> [!NOTE]
> ავთენტიკაცია მოითხოვს <.localized_link href="/guides/server/accounts-and-projects">Tuist ანგარიშს და პროექტს</.localized_link>.


### დამოკიდებულებების ამოხსნა {#resolving-dependencies}

დამოკიდებულებების რეესტრიდან ამოსახსნელად source control-ის ნაცვლად, განაგრძეთ კითხვა თქვენი პროექტის კონფიგურაციის მიხედვით:
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

CI-ზე რეესტრის დასაყენებლად მიჰყევით ამ სახელმძღვანელოს: <.localized_link href="/guides/features/package-registries/swift/continuous-integration">უწყვეტი ინტეგრაცია</.localized_link>.

### პაკეტის რეესტრის იდენტიფიკატორები {#package-registry-identifiers}

როდესაც `Package.swift` ან `Project.swift` ფაილში იყენებთ პაკეტის რეესტრის იდენტიფიკატორებს, პაკეტის URL უნდა გადაიყვანოთ რეესტრის შეთანხმების შესაბამისად. რეესტრის იდენტიფიკატორი ყოველთვის `{organization}.{repository}` ფორმატშია. მაგალითად, `https://github.com/pointfreeco/swift-composable-architecture` პაკეტისთვის რეესტრის იდენტიფიკატორი იქნება `pointfreeco.swift-composable-architecture`.

> [!NOTE]
> იდენტიფიკატორი არ შეიძლება შეიცავდეს ერთზე მეტ წერტილს. თუ რეპოზიტორიის სახელი შეიცავს წერტილს, ის იცვლება underscore-ით. მაგალითად, `https://github.com/groue/GRDB.swift` პაკეტს ექნება რეესტრის იდენტიფიკატორი `groue.GRDB_swift`.
