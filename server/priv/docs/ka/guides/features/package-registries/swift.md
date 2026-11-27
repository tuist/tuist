---
{
  "title": "Swift",
  "titleTemplate": ":title · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "აჩქარეთ Swift Package Manager-ის დამოკიდებულებების გადმოწერა წუთებიდან წამებამდე Tuist-ის Swift პაკეტების რეესტრით, რომელიც ეყრდნობა Tuist-ის გლობალურ ქეშის ქსელს."
}
---
# Swift Package Registry {#swift-package-registry}

დამოკიდებულებების რაოდენობის ზრდასთან ერთად იზრდება მათი გარჩევისთვის საჭირო დროც. სხვა პაკეტების მენეჯერები, როგორიცაა [CocoaPods](https://cocoapods.org/) ან [npm](https://www.npmjs.com/), ცენტრალიზებულია, ხოლო Swift Package Manager — არა. ამის გამო, SwiftPM-მა დამოკიდებულებების გარჩევა თითოეული რეპოზიტორიის სრული კლონირებით უნდა მოახდინოს, რაც დროს მოითხოვს და ცენტრალიზებულ მიდგომასთან შედარებით მეტ მეხსიერებას იკავებს. ამ პრობლემის გადასაჭრელად, Tuist გთავაზობთ [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)-ის იმპლემენტაციას, რათა ჩამოტვირთოთ მხოლოდ ის კომიტები, რომლებიც _ნამდვილად გჭირდებათ_. რეესტრში არსებული პაკეტები ეფუძნება [Swift Package Index](https://swiftpackageindex.com/)-ს — თუ პაკეტს იქ იპოვით, ის ასევე ხელმისაწვდომია Tuist Registry-ში. გარდა ამის, პაკეტები მსოფლიოს მასშტაბით ნაწილდება edge storage-ის გამოყენებით, რაც მინიმალურ დაყოვნებას უზრუნველყოფს მათი გარჩევისას.

## გამოყენება {#usage}

რეესტრის დაყენების ორი გზა არსებობს:

### ვარიანტი 1: ავტომატური დაყენება გენერაციის დროს (რეკომენდებული) {#automatic-setup}

თუ პროექტის გენერაციისთვის Tuist-ს იყენებთ, რეესტრის ჩართვა შეგიძლიათ `registryEnabled` პარამეტრის მითითებით თქვენს `Tuist.swift` კონფიგურაციაში:

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

ამ პარამეტრით `tuist generate` ავტომატურად შექმნის რეესტრის კონფიგურაციის ფაილს თქვენს სამუშაო სივრცეში. ეს აღმოფხვრის `tuist registry setup`-ის ცალკე გაშვების საჭიროებას.

> [!TIP]
> `registryEnabled` ასევე აკონფიგურირებს რეესტრს პროექტებისთვის, რომლებიც დამოკიდებულებებს ინტეგრირებენ Xcode-ის ნაგულისხმევი Swift Package Manager-ის მეშვეობით და არა Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით. ის არ აკონფიგურირებს Xcode-ს პაკეტების ამოსაცნობად, რომლებიც რეესტრიდან წყაროს კონტროლის URL-ითაა განცხადებული. ამის გასაკეთებლად, თითოეულ მანქანაზე ერთხელ შეასრულეთ `tuist registry setup`, როგორც აღწერილია <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">წყაროს კონტროლის პაკეტების ამოცნობა</.localized_link>-ში.


### ვარიანტი 2: ხელით დაყენება {#manual-setup}

რეესტრის ხელით დასაყენებლად, გაუშვით შემდეგი ბრძანება თქვენი პროექტის დირექტორიაში:

```bash
tuist registry setup
```

ეს ბრძანება ქმნის რეესტრის კონფიგურაციის ფაილს, რომელიც რეესტრს თქვენი პროექტისთვის ააქტიურებს. დარწმუნდით, რომ ეს ფაილი კომიტებულია, რათა თქვენმა გუნდმაც ისარგებლოს რეესტრით.

### ავთენტიკაცია (არასავალდებულო) {#authentication}

ავთენტიკაცია **არასავალდებულოა**. ავთენტიკაციის გარეშე, რეესტრის გამოყენება შესაძლებელია შეზღუდვით **1,000 მოთხოვნა წუთში** თითოეული IP მისამართისთვის. მაღალი ლიმიტის, **20,000 მოთხოვნა წუთში**, მისაღებად, შეგიძლიათ ავთენტიფიცირდეთ შემდეგი ბრძანების გაშვებით:

```bash
tuist registry login
```

> [!NOTE]
> ავთენტიკაცია მოითხოვს <.localized_link href="/guides/server/accounts-and-projects">Tuist ანგარიშსა და პროექტს</.localized_link>.


### დამოკიდებულებების გარჩევა {#resolving-dependencies}

დამოკიდებულებების რეესტრიდან გარჩევისთვის წყაროს კონტროლის ნაცვლად, გააგრძელეთ კითხვა თქვენი პროექტის კონფიგურაციის მიხედვით:
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

CI-ზე რეესტრის დასაყენებლად, მიჰყევით ამ სახელმძღვანელოს: <.localized_link href="/guides/features/package-registries/swift/continuous-integration">უწყვეტი ინტეგრაცია</.localized_link>.

### პაკეტის რეესტრის იდენტიფიკატორები {#package-registry-identifiers}

როდესაც პაკეტის რეესტრის იდენტიფიკატორებს იყენებთ `Package.swift` ან `Project.swift` ფაილში, პაკეტის URL უნდა გადაიყვანოთ რეესტრის კონვენციის შესაბამისად. რეესტრის იდენტიფიკატორი ყოველთვის არის `{organization}.{repository}` ფორმატში. მაგალითად, `https://github.com/pointfreeco/swift-composable-architecture` პაკეტისთვის რეესტრის იდენტიფიკატორი იქნება `pointfreeco.swift-composable-architecture`.

> [!NOTE]
> იდენტიფიკატორი ვერ შეიცავს ერთზე მეტ წერტილს. თუ რეპოზიტორიის სახელი შეიცავს წერტილს, ის იცვლება ქვედა ტირეთი. მაგალითად, `https://github.com/groue/GRDB.swift` პაკეტს ექნება რეესტრის იდენტიფიკატორი `groue.GRDB_swift`.
