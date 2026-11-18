---
{
  "title": "Swift",
  "titleTemplate": ":title · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "დააჩქარეთ Swift Package Manager-ის დამოკიდებულებების ამოხსნა წუთებიდან წამებამდე Tuist-ის Swift-პაკეტების რეესტრით, რომელიც ეყრდნობა Tuist-ის გლობალურ ქეშის ქსელს."
}
---
# Swift Package Registry {#swift-package-registry}

დამოკიდებულებების რაოდენობის ზრდასთან ერთად იზრდება მათი ამოხსნისთვის საჭირო დროც. სხვა პაკეტების მენეჯერები, როგორიცაა [CocoaPods](https://cocoapods.org/) ან [npm](https://www.npmjs.com/), ცენტრალიზებულია, ხოლო Swift Package Manager — არა. ამის გამო, SwiftPM-მა თითოეული რეპოზიტორიის სრული კლონირებით უნდა ამოხსნას დამოკიდებულებები, რაც დროს მოითხოვს და უფრო მეტ მეხსიერებას იკავებს, ვიდრე ცენტრალიზებული მიდგომა. ამ პრობლემის გადასაჭრელად, Tuist გთავაზობთ [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)-ის იმპლემენტაციას, რათა ჩამოტვირთოთ მხოლოდ ის კომიტები, რომლებიც _ნამდვილად გჭირდებათ_. რეესტრში არსებული პაკეტები ეფუძნება [Swift Package Index](https://swiftpackageindex.com/)-ს — თუ პაკეტს იქ იპოვით, ის Tuist Registry-შიც ხელმისაწვდომია. გარდა ამისა, პაკეტები მსოფლიოს მასშტაბით ნაწილდება edge storage-ის გამოყენებით, რაც ამოხსნისას მინიმალურ დაყოვნებას უზრუნველყოფს.

## გამოყენება {#usage}

რეესტრის დაყენების ორი გზა არსებობს:

### ვარიანტი 1: ავტომატური დაყენება გენერაციის დროს (რეკომენდებული) {#automatic-setup}

თუ Tuist-ს იყენებთ თქვენი პროექტის გენერაციისთვის, შეგიძლიათ ჩართოთ რეესტრი `registryEnabled` პარამეტრის მითითებით თქვენს `Tuist.swift` კონფიგურაციაში:

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

ამ პარამეტრით, `tuist generate` ავტომატურად შექმნის რეესტრის კონფიგურაციის ფაილს თქვენს სამუშაო სივრცეში. ეს აღმოფხვრის `tuist registry setup` ცალკე გაშვების საჭიროებას.

> [!TIP]
> `registryEnabled` ასევე აკონფიგურირებს რეესტრს იმ პროექტებისთვის, რომლებიც დამოკიდებულებებს აინტეგრირებენ Xcode-ის ნაგულისხმევი Swift Package Manager ინტეგრაციის მეშვეობით და არა Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით. ის არ აკონფიგურირებს Xcode-ს იმ პაკეტების ამოსახსნელად, რომლებიც რეესტრიდან source control URL-ით არის განსაზღვრული. ამის გასაკეთებლად, გაუშვით `tuist registry setup` თითოეულ მანქანაზე ერთხელ, როგორც ეს აღწერილია <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Resolving source control packages</.localized_link>-ში.


### ვარიანტი 2: ხელით დაყენება {#manual-setup}

რეესტრის ხელით დასაყენებლად, გაუშვით შემდეგი ბრძანება თქვენი პროექტის დირექტორიაში:

```bash
tuist registry setup
```

ეს ბრძანება ქმნის რეესტრის კონფიგურაციის ფაილს, რომელიც რეესტრს თქვენი პროექტისთვის ააქტიურებს. დარწმუნდით, რომ ეს ფაილი კომიტებულია, რათა თქვენმა გუნდმა ასევე მიიღოს სარგებელი რეესტრისგან.

### ავთენტიკაცია (არასავალდებულო) {#authentication}

ავთენტიკაცია **არასავალდებულოა**. ავთენტიკაციის გარეშე, შეგიძლიათ გამოიყენოთ რეესტრი შეზღუდვით **1,000 მოთხოვნა წუთში** თითოეული IP მისამართისთვის. მაღალი ლიმიტის, **20,000 მოთხოვნა წუთში**, მისაღებად, შეგიძლიათ გაიაროთ ავთენტიკაცია შემდეგი ბრძანების გაშვებით:

```bash
tuist registry login
```

> [!NOTE]
> ავთენტიკაცია მოითხოვს <.localized_link href="/guides/server/accounts-and-projects">Tuist ანგარიშს და პროექტს</.localized_link>.


### დამოკიდებულებების ამოხსნა {#resolving-dependencies}

დამოკიდებულებების რეესტრიდან ამოსახსნელად source control-ის ნაცვლად, გააგრძელეთ კითხვა თქვენი პროექტის კონფიგურაციის შესაბამისად:
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

CI-ზე რეესტრის დასაყენებლად, მიჰყევით ამ სახელმძღვანელოს: <.localized_link href="/guides/features/package-registries/swift/continuous-integration">Continuous integration</.localized_link>.

### პაკეტის რეესტრის იდენტიფიკატორები {#package-registry-identifiers}

როდესაც იყენებთ პაკეტის რეესტრის იდენტიფიკატორებს `Package.swift` ან `Project.swift` ფაილში, პაკეტის URL უნდა გადაიყვანოთ რეესტრის კონვენციის შესაბამისად. რეესტრის იდენტიფიკატორი ყოველთვის არის `{organization}.{repository}` ფორმატში. მაგალითად, `https://github.com/pointfreeco/swift-composable-architecture` პაკეტისთვის რეესტრის იდენტიფიკატორი იქნება `pointfreeco.swift-composable-architecture`.

> [!NOTE]
> იდენტიფიკატორი არ შეიძლება შეიცავდეს ერთზე მეტ წერტილს. თუ რეპოზიტორიის სახელი შეიცავს წერტილს, ის იცვლება underscore-ით. მაგალითად, `https://github.com/groue/GRDB.swift` პაკეტს ექნება რეესტრის იდენტიფიკატორი `groue.GRDB_swift`.
