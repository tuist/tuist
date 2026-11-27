---
{
  "title": "მეტამონაცემების ტეგები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ისწავლეთ, როგორ გამოიყენოთ სამიზნე მეტამონაცემების ტეგები თქვენი პროექტის კონკრეტული ნაწილების ორგანიზებისა და მათზე ფოკუსირებისთვის"
}
---
# მეტამონაცემების ტეგები {#metadata-tags}

როგორც კი პროექტები ზომითა და სირთულით იზრდება, მთელ კოდბაზასთან ერთდროულად მუშაობა შეიძლება არაეფექტური გახდეს. Tuist გთავაზობთ **მეტამონაცემების ტეგებს**, როგორც მიზნების ლოგიკურ ჯგუფებად ორგანიზების საშუალებას და განვითარების დროს თქვენი პროექტის კონკრეტულ ნაწილებზე ფოკუსირების შესაძლებლობას.

## რა არის მეტამონაცემების ტეგები? {#what-are-metadata-tags}

მეტამონაცემების ტეგები არის სტრიქონული ჭდეები, რომლებიც შეგიძლიათ მიუმაგრეთ თქვენს პროექტში არსებულ მიზნებს. ისინი ემსახურებიან მარკერებს, რომლებიც საშუალებას გაძლევთ:

- **დააჯგუფოთ დაკავშირებული მიზნები** - მონიშნეთ მიზნები, რომლებიც ერთსა და იმავე ფუნქციას, გუნდს ან არქიტექტურულ შრეს ეკუთვნის
- **მოახდინეთ თქვენი სამუშაო სივრცის ფოკუსირება** - შექმენით პროექტები, რომლებიც მხოლოდ კონკრეტული ტეგების მქონე მიზნებს შეიცავს
- **ოპტიმიზაცია გაუკეთეთ თქვენს სამუშაო პროცესს** - იმუშავეთ კონკრეტულ ფუნქციებზე კოდბაზის შეუერთებელი ნაწილების ჩატვირთვის გარეშე
- **აირჩიეთ მიზნები, რომლებიც წყაროდ შეინარჩუნოთ** - აირჩიეთ, მიზნების რომელი ჯგუფი გსურთ შეინარჩუნოთ წყაროდ ქეშირების დროს

ტეგები განისაზღვრება მიზნებზე `metadata` თვისების გამოყენებით და ინახება როგორც სტრიქონების მასივი.

## მეტამონაცემების ტეგების განსაზღვრა {#defining-metadata-tags}

შეგიძლიათ დაამატოთ ტეგები ნებისმიერ მიზანს თქვენს პროექტის მანიფესტში:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "Authentication",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.authentication",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:auth", "team:identity"])
        ),
        .target(
            name: "Payment",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.payment",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:payment", "team:commerce"])
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.app",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "Authentication"),
                .target(name: "Payment")
            ]
        )
    ]
)
```

## მონიშნულ მიზნებზე ფოკუსირება {#focusing-on-tagged-targets}

მას შემდეგ, რაც მონიშნავთ თქვენს მიზნებს, შეგიძლიათ გამოიყენოთ ბრძანება `tuist generate`, რათა შექმნათ ფოკუსირებული პროექტი, რომელიც მხოლოდ კონკრეტულ მიზნებს შეიცავს:

### ფოკუსირება ტეგის მიხედვით

გამოიყენეთ პრეფიქსი `tag:`, რათა შექმნათ პროექტი ყველა იმ მიზნით, რომელიც შეესაბამება კონკრეტულ ტეგს:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### ფოკუსირება სახელის მიხედვით

ასევე შეგიძლიათ ფოკუსირდეთ კონკრეტულ მიზნებზე სახელის მიხედვით:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### როგორ მუშაობს ფოკუსირება

როდესაც ფოკუსირდებით მიზნებზე:

1. **ჩართული მიზნები** - თქვენს მოთხოვნას შესაბამისი მიზნები შედის შექმნილ პროექტში
2. **დამოკიდებულებები** - ფოკუსირებული მიზნების ყველა დამოკიდებულება ავტომატურად შედის
3. **ტესტების მიზნები** - ფოკუსირებული მიზნებისთვის განკუთვნილი ტესტების მიზნები შედის
4. **გამორიცხვა** - ყველა სხვა მიზანი გამორიცხულია სამუშაო სივრციდან

ეს ნიშნავს, რომ მიიღებთ უფრო მცირე, უფრო მართვად სამუშაო სივრცეს, რომელიც მხოლოდ იმას შეიცავს, რაც თქვენს ფუნქციაზე მუშაობისთვის გჭირდებათ.

## ტეგების სახელდების კონვენციები {#tag-naming-conventions}

მიუხედავად იმისა, რომ ნებისმიერი სტრიქონის გამოყენება შეგიძლიათ ტეგად, თანმიმდევრული სახელდების კონვენციის დაცვა გეხმარებათ ტეგების ორგანიზებულად შენარჩუნებაში:

```swift
// Organize by feature
metadata: .metadata(tags: ["feature:authentication", "feature:payment"])

// Organize by team ownership
metadata: .metadata(tags: ["team:identity", "team:commerce"])

// Organize by architectural layer
metadata: .metadata(tags: ["layer:ui", "layer:business", "layer:data"])

// Organize by platform
metadata: .metadata(tags: ["platform:ios", "platform:macos"])

// Combine multiple dimensions
metadata: .metadata(tags: ["feature:auth", "team:identity", "layer:ui"])
```

პრეფიქსების, როგორიცაა `feature:`, `team:` ან `layer:`, გამოყენება ამარტივებს თითოეული ტეგის დანიშნულების გაგებას და სახელდების კონფლიქტების თავიდან აცილებას.

## სისტემური ტეგები {#system-tags}

Tuist იყენებს პრეფიქსს `tuist:` სისტემის მიერ მართული ტეგებისთვის. ეს ტეგები ავტომატურად ენიჭება Tuist-ის მიერ და შეიძლება გამოყენებულ იქნას ქეშის პროფილებში გენერირებული კონტენტის კონკრეტული ტიპების სამიზნედ.

### ხელმისაწვდომი სისტემური ტეგები

| ტეგი | აღწერა |
| --- | --- |
| `tuist:synthesized` | ეკუთვნის სინთეზირებულ ბანდლის მიზნებს, რომლებსაც Tuist ქმნის რესურსების დამუშავებისთვის სტატიკურ ბიბლიოთეკებსა და სტატიკურ ფრეიმვორქებში. ეს ბანდლები არსებობს ისტორიული მიზეზების გამო, რათა უზრუნველყონ რესურსებზე წვდომის API-ები. |

### სისტემური ტეგების გამოყენება ქეშის პროფილებთან

შეგიძლიათ გამოიყენოთ სისტემური ტეგები ქეშის პროფილებში სინთეზირებული მიზნების ჩასართავად ან გამოსარიცხად:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                [
                    "development": .profile(
                        .onlyExternal,
                        and: ["tag:tuist:synthesized"]  // Also cache synthesized bundles
                    )
                ],
                default: .onlyExternal
            )
        )
    )
)
```

> [!TIP]
> **სინთეზირებული ბანდლები მშობლის ტეგებს იღებენ**
>
> სინთეზირებული ბანდლის მიზნები იღებენ ყველა ტეგს თავიანთი მშობელი მიზნიდან `tuist:synthesized` ტეგის მიღების გარდა. ეს ნიშნავს, რომ თუ სტატიკურ ბიბლიოთეკას მონიშნავთ `feature:auth`-ით, მის სინთეზირებულ რესურსების ბანდლს ექნება როგორც `feature:auth`, ასევე `tuist:synthesized` ტეგები.


## ტეგების გამოყენება პროექტის აღწერის დამხმარე საშუალებებთან {#using-tags-with-helpers}

შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარე საშუალებები</.localized_link>, რათა სტანდარტიზაცია გაუკეთოთ ტეგების გამოყენების წესს თქვენს პროექტში:

```swift
// Tuist/ProjectDescriptionHelpers/Project+Templates.swift
import ProjectDescription

extension Target {
    public static func feature(
        name: String,
        team: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.\(name.lowercased())",
            sources: ["Sources/**"],
            dependencies: dependencies,
            metadata: .metadata(tags: [
                "feature:\(name.lowercased())",
                "team:\(team.lowercased())"
            ])
        )
    }
}
```

შემდეგ გამოიყენეთ ის თქვენს მანიფესტებში:

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Features",
    targets: [
        .feature(name: "Authentication", team: "Identity"),
        .feature(name: "Payment", team: "Commerce"),
    ]
)
```

## მეტამონაცემთა ტეგების გამოყენების სარგებელი {#benefits}

### განვითარების გაუმჯობესებული გამოცდილება

თქვენი პროექტის კონკრეტულ ნაწილებზე ფოკუსირებით შეგიძლიათ:

- **Xcode-ის პროექტის ზომის შემცირება** - იმუშავეთ უფრო მცირე პროექტებთან, რომლებიც უფრო სწრაფად იხსნება და ნავიგაციაში მოსახერხებელია
- **აწყობის დაჩქარება** - ააწყეთ მხოლოდ ის, რაც თქვენი მიმდინარე სამუშაოსთვის გჭირდებათ
- **ფოკუსის გაუმჯობესება** - თავიდან აიცილეთ შეფერხებები არარელევანტური კოდიდან
- **ინდექსაციის ოპტიმიზაცია** - Xcode ნაკლებ კოდს ინდექსავს, რაც ავტომატურ შევსებას უფრო სწრაფს ხდის

### პროექტის უკეთესი ორგანიზაცია

ტეგები უზრუნველყოფენ თქვენი კოდბაზის ორგანიზების მოქნილ გზას:

- **მრავალი განზომილება** - მონიშნეთ მიზნები ფუნქციის, გუნდის, შრის, პლატფორმის ან ნებისმიერი სხვა განზომილების მიხედვით
- **სტრუქტურული ცვლილებების გარეშე** - დაამატეთ ორგანიზაციული სტრუქტურა დირექტორიების განლაგების შეცვლის გარეშე
- **გადაკვეთილი საკითხები** - ერთ მიზანს შეუძლია ეკუთვნოდეს რამდენიმე ლოგიკურ ჯგუფს

### ინტეგრაცია ქეშინგთან

მეტამონაცემთა ტეგები უპრობლემოდ მუშაობს <.localized_link href="/guides/features/cache">Tuist-ის ქეშინგის ფუნქციებთან</.localized_link>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## საუკეთესო პრაქტიკა {#best-practices}

1. **დაიწყეთ მარტივად** - დაიწყეთ ერთი ტეგირების განზომილებით (მაგ., ფუნქციები) და გააფართოვეთ საჭიროებისამებრ
2. **იყავით თანმიმდევრული** - გამოიყენეთ იგივე სახელდების კონვენციები ყველა თქვენს მანიფესტში
3. **დაადოკუმენტეთ თქვენი ტეგები** - შეინახეთ ხელმისაწვდომი ტეგების სია და მათი მნიშვნელობები თქვენი პროექტის დოკუმენტაციაში
4. **გამოიყენეთ დამხმარე საშუალებები** - გამოიყენეთ პროექტის აღწერის დამხმარე საშუალებები ტეგების გამოყენების სტანდარტიზაციისთვის
5. **პერიოდულად გადახედეთ** - როგორც კი თქვენი პროექტი ვითარდება, გადახედეთ და განაახლეთ თქვენი ტეგირების სტრატეგია

## დაკავშირებული ფუნქციები {#related-features}

- <.localized_link href="/guides/features/projects/code-sharing">კოდის გაზიარება</.localized_link> - გამოიყენეთ პროექტის აღწერის დამხმარე საშუალებები ტეგების გამოყენების სტანდარტიზაციისთვის
- <.localized_link href="/guides/features/cache">ქეში</.localized_link> - გააერთიანეთ ტეგები ქეშინგთან აწყობის ოპტიმალური შესრულებისთვის
- <.localized_link href="/guides/features/selective-testing">შერჩევითი ტესტირება</.localized_link> - ჩაატარეთ ტესტები მხოლოდ შეცვლილი მიზნებისთვის
