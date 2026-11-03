---
{
  "title": "Swift",
  "titleTemplate": ":title · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "დააჩქარეთ Swift Package Manager-ის დამოკიდებულებების გარჩევა წუთებიდან წამებამდე Tuist-ის Swift პაკეტების რეესტრით, რომელიც ეყრდნობა Tuist-ის გლობალურ ქეშის ქსელს."
}
---
# Swift Package Registry {#swift-package-registry}

დამოკიდებულობების რაოდენობის ზრდასთან ერთად იზრდება მათი ამოხსნისთვის საჭირო დროც. სხვა პაკეტების მენეჯერები, როგორიცაა [CocoaPods](https://cocoapods.org/) ან [npm](https://www.npmjs.com/), ცენტრალიზებულია, Swift Package Manager კი — არა. ამის გამო, SwiftPM-მა დამოკიდებულობების ამოსახსნელად თითოეული რეპოზიტორიის სრული კლონი უნდა გააკეთოს, რაც დროს მოითხოვს და უფრო მეტ მეხსიერებას იკავებს, ვიდრე ცენტრალიზებული მიდგომა. ამ პრობლემის გადასაჭრელად, Tuist გთავაზობთ [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)-ის იმპლემენტაციას, რათა ჩამოტვირთოთ მხოლოდ ის კომიტები, რომლებიც _ნამდვილად გჭირდებათ_. რეესტრში არსებული პაკეტები ეყრდნობა [Swift Package Index](https://swiftpackageindex.com/)-ს — თუ პაკეტს იქ იპოვით, ის Tuist Registry-შიც ხელმისაწვდომია. გარდა ამისა, პაკეტები მსოფლიოს მასშტაბით ნაწილდება edge storage-ის საშუალებით, რაც მინიმალურ დაყოვნებას უზრუნველყოფს მათი ამოხსნისას.

## გამოყენება {#usage}

რეესტრის კონფიგურაციის ორი გზა არსებობს:

### ვარიანტი 1: ავტომატური კონფიგურაცია გენერაციის დროს (რეკომენდებული) {#automatic-setup}

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

ამ პარამეტრით, `tuist generate` ავტომატურად შექმნის რეესტრის კონფიგურაციის ფაილს თქვენს სამუშაო სივრცეში. ეს აღმოფხვრის `tuist registry setup`-ის ცალკე გაშვების საჭიროებას.

> [!TIP]
> `registryEnabled` ასევე აკონფიგურირებს რეესტრს იმ პროექტებისთვის, რომლებიც დამოკიდებულობებს ინტეგრირებენ Xcode-ის ნაგულისხმევი Swift Package Manager ინტეგრაციის საშუალებით და არა Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით. ის არ აკონფიგურირებს Xcode-ს იმ პაკეტების ამოსახსნელად, რომლებიც რეესტრიდან source control URL-ით არის განსაზღვრული. ამის გასაკეთებლად, თითოეულ მანქანაზე ერთხელ გაუშვით `tuist registry setup`, როგორც ეს აღწერილია <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">წყაროს კონტროლის პაკეტების ამოხსნა</.localized_link>-ში.


### ვარიანტი 2: ხელით კონფიგურაცია {#manual-setup}

რეესტრის ხელით კონფიგურაციისთვის, გაუშვით შემდეგი ბრძანება თქვენი პროექტის დირექტორიაში:

```bash
tuist registry setup
```

ეს ბრძანება ქმნის რეესტრის კონფიგურაციის ფაილს, რომელიც რეესტრს თქვენი პროექტისთვის ააქტიურებს. დარწმუნდით, რომ ეს ფაილი კომიტებულია, რათა თქვენმა გუნდმაც ისარგებლოს რეესტრით.

### ავთენტიკაცია (არასავალდებულო) {#authentication}

ავთენტიკაცია **არასავალდებულოა**. ავთენტიკაციის გარეშე, რეესტრის გამოყენება შეგიძლიათ **წუთში 1,000 მოთხოვნის** ლიმიტით თითოეული IP მისამართისთვის. **წუთში 20,000 მოთხოვნის** უფრო მაღალი ლიმიტის მისაღებად, შეგიძლიათ გაიაროთ ავთენტიკაცია შემდეგი ბრძანების გაშვებით:

```bash
tuist registry login
```

> [!NOTE]
> ავთენტიკაცია მოითხოვს <.localized_link href="/guides/server/accounts-and-projects">Tuist ანგარიშს და პროექტს</.localized_link>.


### დამოკიდებულობების ამოხსნა {#resolving-dependencies}

დამოკიდებულობების რეესტრიდან ამოსახსნელად წყაროს კონტროლის ნაცვლად, გააგრძელეთ კითხვა თქვენი პროექტის კონფიგურაციის მიხედვით:
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

CI-ზე რეესტრის კონფიგურაციისთვის, მიჰყევით ამ სახელმძღვანელოს: <.localized_link href="/guides/features/package-registries/swift/continuous-integration">უწყვეტი ინტეგრაცია</.localized_link>.

### პაკეტის რეესტრის იდენტიფიკატორები {#package-registry-identifiers}

როდესაც პაკეტის რეესტრის იდენტიფიკატორებს იყენებთ `Package.swift` ან `Project.swift` ფაილში, პაკეტის URL უნდა გადაიყვანოთ რეესტრის შეთანხმების შესაბამისად. რეესტრის იდენტიფიკატორი ყოველთვის არის `{organization}.{repository}` ფორმატში. მაგალითად, `https://github.com/pointfreeco/swift-composable-architecture` პაკეტისთვის რეესტრის გამოყენებისას, პაკეტის რეესტრის იდენტიფიკატორი იქნება `pointfreeco.swift-composable-architecture`.

> [!NOTE]
> იდენტიფიკატორი არ შეიძლება შეიცავდეს ერთზე მეტ წერტილს. თუ რეპოზიტორიის სახელი შეიცავს წერტილს, ის იცვლება ქვედა ტირეთი. მაგალითად, `https://github.com/groue/GRDB.swift` პაკეტს ექნება რეესტრის იდენტიფიკატორი `groue.GRDB_swift`.
