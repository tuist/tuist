---
{
  "title": "Swift",
  "titleTemplate": ":title · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "აჩქარეთ Swift Package Manager-ის გარჩევა წუთებიდან წამებამდე Tuist-ის Swift პაკეტების რეესტრით, რომელიც ეყრდნობა Tuist-ის გლობალურ ქეშის ქსელს."
}
---
# Swift Package Registry {#swift-package-registry}

დამოკიდებულებების რაოდენობის ზრდასთან ერთად იზრდება მათი გარჩევისთვის საჭირო დროც. სხვა პაკეტების მენეჯერები, როგორიცაა [CocoaPods](https://cocoapods.org/) ან [npm](https://www.npmjs.com/), ცენტრალიზებულია, ხოლო Swift Package Manager — არა. ამის გამო, SwiftPM-მა თითოეული რეპოზიტორიის სრული კლონირებით უნდა გაარჩიოს დამოკიდებულებები, რაც დროს მოითხოვს და უფრო მეტ მეხსიერებას იკავებს, ვიდრე ცენტრალიზებული მიდგომა. ამ პრობლემის გადასაჭრელად, Tuist გთავაზობთ [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md)-ის იმპლემენტაციას, რათა ჩამოტვირთოთ მხოლოდ ის კომიტები, რომლებიც _ნამდვილად გჭირდებათ_. რეესტრში არსებული პაკეტები ეყრდნობა [Swift Package Index](https://swiftpackageindex.com/)-ს — თუ პაკეტს იქ იპოვით, ის Tuist Registry-შიც ხელმისაწვდომია. გარდა ამისა, პაკეტები მსოფლიოს მასშტაბით ნაწილდება edge storage-ის გამოყენებით, რაც უზრუნველყოფს მინიმალურ დაყოვნებას მათი გარჩევისას.

## გამოყენება {#usage}

რეესტრის კონფიგურირების ორი გზა არსებობს:

### ვარიანტი 1: ავტომატური კონფიგურაცია გენერაციის დროს (რეკომენდებული) {#automatic-setup}

თუ პროექტის გენერაციისთვის Tuist-ს იყენებთ, შეგიძლიათ ჩართოთ რეესტრი `registryEnabled` პარამეტრის მითითებით თქვენს `Tuist.swift` კონფიგურაციაში:

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

ამ პარამეტრით `tuist generate` ავტომატურად შექმნის რეესტრის კონფიგურაციის ფაილს თქვენს სამუშაო სივრცეში. ეს აღმოფხვრის `tuist registry setup` ცალკე გაშვების საჭიროებას.

> [!TIP]
> `registryEnabled` ასევე აკონფიგურირებს რეესტრს პროექტებისთვის, რომლებიც დამოკიდებულებებს აერთიანებენ Xcode-ის ნაგულისხმევი Swift Package Manager ინტეგრაციით და არა Tuist-ის XcodeProj-ზე დაფუძნებული ინტეგრაციით. ის არ აკონფიგურირებს Xcode-ს ისეთი პაკეტების გარჩევისთვის, რომლებიც რეესტრიდან წყაროს კონტროლის URL-ით არის განსაზღვრული. ამისთვის გაუშვით `tuist registry setup` თითოეულ მანქანაზე ერთხელ, როგორც აღწერილია <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">წყაროს კონტროლის პაკეტების გარჩევა</.localized_link> განყოფილებაში.


### ვარიანტი 2: ხელით კონფიგურაცია {#manual-setup}

რეესტრის ხელით კონფიგურაციისთვის, გაუშვით შემდეგი ბრძანება თქვენი პროექტის დირექტორიაში:

```bash
tuist registry setup
```

ეს ბრძანება ქმნის რეესტრის კონფიგურაციის ფაილს, რომელიც რთავს რეესტრს თქვენი პროექტისთვის. დარწმუნდით, რომ ეს ფაილი დააკომიტეთ, რათა თქვენმა გუნდმა ასევე მიიღოს სარგებელი რეესტრისგან.

### ავთენტიკაცია (არასავალდებულო) {#authentication}

ავთენტიკაცია **არასავალდებულოა**. ავთენტიკაციის გარეშე, შეგიძლიათ გამოიყენოთ რეესტრი **1,000 მოთხოვნა წუთში** ლიმიტით თითოეულ IP მისამართზე. უფრო მაღალი ლიმიტის, **20,000 მოთხოვნა წუთში**, მისაღებად, შეგიძლიათ გაიაროთ ავთენტიკაცია შემდეგი ბრძანების გაშვებით:

```bash
tuist registry login
```

> [!NOTE]
> ავთენტიკაცია მოითხოვს <.localized_link href="/guides/server/accounts-and-projects">Tuist ანგარიშს და პროექტს</.localized_link>.


### დამოკიდებულებების გარჩევა {#resolving-dependencies}

დამოკიდებულებების რეესტრიდან გარჩევისთვის წყაროს კონტროლის ნაცვლად, განაგრძეთ კითხვა თქვენი პროექტის კონფიგურაციის მიხედვით:
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

CI-ზე რეესტრის კონფიგურაციისთვის, მიჰყევით ამ სახელმძღვანელოს: <.localized_link href="/guides/features/package-registries/swift/continuous-integration">უწყვეტი ინტეგრაცია</.localized_link>.

### პაკეტის რეესტრის იდენტიფიკატორები {#package-registry-identifiers}

როდესაც პაკეტის რეესტრის იდენტიფიკატორებს იყენებთ `Package.swift` ან `Project.swift` ფაილში, პაკეტის URL უნდა გადაიყვანოთ რეესტრის შეთანხმების შესაბამისად. რეესტრის იდენტიფიკატორი ყოველთვის არის `{organization}.{repository}` ფორმატში. მაგალითად, `https://github.com/pointfreeco/swift-composable-architecture` პაკეტისთვის რეესტრის გამოყენებისას, პაკეტის რეესტრის იდენტიფიკატორი იქნება `pointfreeco.swift-composable-architecture`.

> [!NOTE]
> იდენტიფიკატორი არ შეიძლება შეიცავდეს ერთზე მეტ წერტილს. თუ რეპოზიტორიის სახელი შეიცავს წერტილს, ის იცვლება ქვედა ტირეთი. მაგალითად, `https://github.com/groue/GRDB.swift` პაკეტს ექნება რეესტრის იდენტიფიკატორი `groue.GRDB_swift`.
