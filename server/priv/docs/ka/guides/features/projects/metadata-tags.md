---
{
  "title": "მეტამონაცემთა ტეგები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ სამიზნის მეტამონაცემთა ტეგები თქვენი პროექტის კონკრეტული ნაწილების ორგანიზებისა და მათზე ფოკუსირებისთვის"
}
---
# მეტამონაცემების ტეგები {#metadata-tags}

როგორც პროექტები იზრდება ზომითა და სირთულით, მთელ კოდბაზასთან ერთდროულად მუშაობა შეიძლება არაეფექტური გახდეს. Tuist გთავაზობთ **მეტამონაცემების ტეგებს**, როგორც საშუალებას სამიზნეების ლოგიკურ ჯგუფებად დასაჯგუფებლად და განვითარების დროს პროექტის კონკრეტულ ნაწილებზე ფოკუსირებისთვის.

## რა არის მეტამონაცემების ტეგები? {#what-are-metadata-tags}

მეტამონაცემების ტეგები არის სტრიქონული იარლიყები, რომლებიც შეგიძლიათ მიამაგროთ თქვენი პროექტის სამიზნეებს. ისინი ემსახურებიან მარკერებს, რომლებიც საშუალებას გაძლევთ:

- **დააჯგუფეთ დაკავშირებული სამიზნეები** - მონიშნეთ სამიზნეები, რომლებიც ეკუთვნის ერთსა და იმავე ფუნქციას, გუნდს ან არქიტექტურულ შრეს
- **მოახდინეთ ფოკუსირება თქვენს სამუშაო სივრცეზე** - შექმენით პროექტები, რომლებიც მოიცავს მხოლოდ კონკრეტული ტეგების მქონე სამიზნეებს
- **ოპტიმიზაცია გაუკეთეთ თქვენს სამუშაო პროცესს** - იმუშავეთ კონკრეტულ ფუნქციებზე კოდბაზის არარელევანტური ნაწილების ჩატვირთვის გარეშე
- **აირჩიეთ სამიზნეები წყაროებად შესანახად** - აირჩიეთ, სამიზნეების რომელი ჯგუფი გსურთ შეინარჩუნოთ წყაროებად ქეშირების დროს

ტეგები განისაზღვრება სამიზნეებზე `metadata` თვისების გამოყენებით და ინახება სტრიქონების მასივის სახით.

## მეტამონაცემების ტეგების განსაზღვრა {#defining-metadata-tags}

შეგიძლიათ დაამატოთ ტეგები ნებისმიერ სამიზნეს თქვენს პროექტის მანიფესტში:

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

## ფოკუსირება მონიშნულ სამიზნეებზე {#focusing-on-tagged-targets}

მას შემდეგ, რაც მონიშნავთ თქვენს სამიზნეებს, შეგიძლიათ გამოიყენოთ ბრძანება `tuist generate`, რათა შექმნათ ფოკუსირებული პროექტი, რომელიც მოიცავს მხოლოდ კონკრეტულ სამიზნეებს:

### ფოკუსირება ტეგით

გამოიყენეთ პრეფიქსი `tag:`, რათა შექმნათ პროექტი ყველა იმ სამიზნით, რომელიც შეესაბამება კონკრეტულ ტეგს:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### ფოკუსირება სახელით

ასევე შეგიძლიათ ფოკუსირება მოახდინოთ კონკრეტულ სამიზნეებზე სახელის მიხედვით:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### როგორ მუშაობს ფოკუსირება

როდესაც ფოკუსირდებით სამიზნეებზე:

1. **ჩართული სამიზნეები** - თქვენს მოთხოვნასთან შესაბამისი სამიზნეები შედიან შექმნილ პროექტში
2. **დამოკიდებულებები** - ფოკუსირებული სამიზნეების ყველა დამოკიდებულება ავტომატურად შედის
3. **ტესტების სამიზნეები** - ფოკუსირებული სამიზნეების ტესტების სამიზნეები შედის
4. **გამორიცხვა** - ყველა სხვა სამიზნე გამორიცხულია სამუშაო სივრციდან

ეს ნიშნავს, რომ მიიღებთ უფრო მცირე, უკეთესად მართვად სამუშაო სივრცეს, რომელიც შეიცავს მხოლოდ იმას, რაც გჭირდებათ თქვენს ფუნქციაზე მუშაობისთვის.

## ტეგების სახელდების კონვენციები {#tag-naming-conventions}

მიუხედავად იმისა, რომ ნებისმიერი სტრიქონის გამოყენება შეგიძლიათ ტეგად, თანმიმდევრული სახელდების კონვენციის დაცვა გეხმარებათ ტეგების მოწესრიგებულად შენარჩუნებაში:

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

Tuist იყენებს პრეფიქსს `tuist:` სისტემის მიერ მართული ტეგებისთვის. ეს ტეგები ავტომატურად ვრცელდება Tuist-ის მიერ და შეიძლება გამოყენებულ იქნას ქეშის პროფილებში გენერირებული შინაარსის კონკრეტული ტიპების სამიზნედ.

### ხელმისაწვდომი სისტემური ტეგები

| ტეგი | აღწერა |
| --- | --- |
| `tuist:synthesized` | ვრცელდება სინთეზირებულ ბანდლების სამიზნეებზე, რომლებსაც Tuist ქმნის რესურსების დამუშავებისთვის სტატიკურ ბიბლიოთეკებსა და სტატიკურ ფრეიმვორქებში. ეს ბანდლები არსებობს ისტორიული მიზეზების გამო, რათა უზრუნველყონ რესურსებზე წვდომის API-ები. |

### სისტემური ტეგების გამოყენება ქეშის პროფილებთან

შეგიძლიათ გამოიყენოთ სისტემური ტეგები ქეშის პროფილებში სინთეზირებული სამიზნეების ჩასართავად ან გამოსარიცხად:

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
> **სინთეზირებული ბანდლები იღებენ მშობლის ტეგებს**
>
> სინთეზირებული ბანდლების სამიზნეები იღებენ ყველა ტეგს თავიანთი მშობელი სამიზნიდან `tuist:synthesized` ტეგის მიღების დამატებით. ეს ნიშნავს, რომ თუ სტატიკურ ბიბლიოთეკას მონიშნავთ `feature:auth`-ით, მის სინთეზირებულ რესურსების ბანდლს ექნება როგორც `feature:auth`, ასევე `tuist:synthesized` ტეგები.


## ტეგების გამოყენება პროექტის აღწერის დამხმარე საშუალებებთან {#using-tags-with-helpers}

შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარე საშუალებები</.localized_link>, რათა სტანდარტიზაცია მოახდინოთ ტეგების გამოყენების თქვენს პროექტში:

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

## მეტამონაცემების ტეგების გამოყენების სარგებელი {#benefits}

### განვითარების გაუმჯობესებული გამოცდილება

პროექტის კონკრეტულ ნაწილებზე ფოკუსირებით შეგიძლიათ:

- **Xcode-ის პროექტის ზომის შემცირება** - იმუშავეთ უფრო მცირე პროექტებთან, რომლებიც უფრო სწრაფად იხსნება და ნავიგაციაში ადვილია
- **ბილდების დაჩქარება** - ააწყეთ მხოლოდ ის, რაც თქვენი მიმდინარე სამუშაოსთვის გჭირდებათ
- **ფოკუსის გაუმჯობესება** - თავიდან აიცილეთ ყურადღების გადატანა არარელევანტურ კოდზე
- **ინდექსაციის ოპტიმიზაცია** - Xcode ნაკლებ კოდს ინდექსავს, რაც ავტომატურ შევსებას უფრო სწრაფს ხდის

### პროექტის უკეთესი ორგანიზაცია

ტეგები უზრუნველყოფენ თქვენი კოდბაზის ორგანიზების მოქნილ გზას:

- **მრავალი განზომილება** - მონიშნეთ სამიზნეები ფუნქციის, გუნდის, შრის, პლატფორმის ან ნებისმიერი სხვა განზომილების მიხედვით
- **სტრუქტურული ცვლილებების გარეშე** - დაამატეთ ორგანიზაციული სტრუქტურა დირექტორიების განლაგების შეცვლის გარეშე
- **გადაკვეთილი საკითხები** - ერთ სამიზნეს შეუძლია ეკუთვნოდეს რამდენიმე ლოგიკურ ჯგუფს

### ინტეგრაცია ქეშთან

მეტამონაცემების ტეგები უპრობლემოდ მუშაობს <.localized_link href="/guides/features/cache">Tuist-ის ქეშის ფუნქციებთან</.localized_link>:

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
- <.localized_link href="/guides/features/cache">ქეში</.localized_link> - გააერთიანეთ ტეგები ქეშთან ბილდის ოპტიმალური შესრულებისთვის
- <.localized_link href="/guides/features/selective-testing">შერჩევითი ტესტირება</.localized_link> - ჩაუშვით ტესტები მხოლოდ შეცვლილი სამიზნეებისთვის
