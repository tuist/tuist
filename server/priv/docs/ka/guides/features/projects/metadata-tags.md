---
{
  "title": "მეტამონაცემების ტეგები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ სამიზნის მეტამონაცემების ტეგები თქვენი პროექტის კონკრეტული ნაწილების ორგანიზებისა და მათზე ფოკუსირებისთვის"
}
---
# მეტამონაცემების ტეგები {#metadata-tags}

როდესაც პროექტები ზომაში და სირთულეში იზრდება, მთლიან კოდბაზასთან ერთდროულად მუშაობა შეიძლება არაეფექტური გახდეს. Tuist გთავაზობთ **მეტამონაცემების ტეგებს**, როგორც საშუალებას, დაალაგოთ target-ები ლოგიკურ ჯგუფებად და განვითარების დროს ყურადღება გაამახვილოთ თქვენი პროექტის კონკრეტულ ნაწილებზე.

## რა არის მეტამონაცემების ტეგები? {#what-are-metadata-tags}

მეტამონაცემების ტეგები არის სტრიქონული ლეიბლები, რომლებიც შეგიძლიათ მიამაგროთ თქვენი პროექტის target-ებს. ისინი ემსახურებიან როგორც მარკერები, რომლებიც საშუალებას გაძლევთ:

- **დააჯგუფოთ დაკავშირებული target-ები** - მონიშნეთ target-ები, რომლებიც ერთსა და იმავე ფუნქციას, გუნდს ან არქიტექტურულ შრეს ეკუთვნის
- **გაამახვილოთ ყურადღება სამუშაო სივრცეზე** - შექმენით პროექტები, რომლებიც მოიცავს მხოლოდ კონკრეტული ტეგების მქონე target-ებს
- **ოპტიმიზაცია გაუკეთოთ თქვენ სამუშაო პროცესს** - იმუშავეთ კონკრეტულ ფუნქციებზე კოდბაზის შეუღებელი ნაწილების ჩატვირთვის გარეშე
- **აირჩიეთ target-ები წყაროებად შესანარჩუნებლად** - აირჩიეთ, target-ების რომელი ჯგუფი გსურთ შეინარჩუნოთ წყაროებად ქეშირების დროს

ტეგები განისაზღვრება target-ებზე `metadata` თვისების გამოყენებით და ინახება სტრიქონების მასივის სახით.

## მეტამონაცემების ტეგების განსაზღვრა {#defining-metadata-tags}

შეგიძლიათ დაამატოთ ტეგები ნებისმიერ target-ს თქვენს პროექტის მანიფესტში:

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

## ტეგირებულ target-ებზე ფოკუსირება {#focusing-on-tagged-targets}

მას შემდეგ, რაც მონიშნავთ თქვენს target-ებს, შეგიძლიათ გამოიყენოთ `tuist generate` ბრძანება ფოკუსირებული პროექტის შესაქმნელად, რომელიც მოიცავს მხოლოდ კონკრეტულ target-ებს:

### ფოკუსირება ტეგით

გამოიყენეთ `tag:` პრეფიქსი პროექტის შესაქმნელად ყველა იმ target-ით, რომელიც შეესაბამება კონკრეტულ ტეგს:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### ფოკუსირება სახელით

ასევე შეგიძლიათ ფოკუსირება მოახდინოთ კონკრეტულ target-ებზე სახელის მიხედვით:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### როგორ მუშაობს ფოკუსირება

როდესაც ფოკუსირდებით target-ებზე:

1. **ჩართული target-ები** - თქვენს მოთხოვნას შესაბამისი target-ები შედიან შექმნილ პროექტში
2. **დამოკიდებულებები** - ფოკუსირებული target-ების ყველა დამოკიდებულება ავტომატურად შედის
3. **ტესტების target-ები** - ფოკუსირებული target-ების ტესტების target-ები შედის
4. **გამორიცხვა** - ყველა სხვა target გამორიცხულია სამუშაო სივრციდან

ეს ნიშნავს, რომ მიიღებთ უფრო მცირე და მართვად სამუშაო სივრცეს, რომელიც შეიცავს მხოლოდ იმას, რაც საჭიროა თქვენს ფუნქციაზე მუშაობისთვის.

## ტეგების სახელდების კონვენციები {#tag-naming-conventions}

მიუხედავად იმისა, რომ ტეგად ნებისმიერი სტრიქონის გამოყენება შეგიძლიათ, თანმიმდევრული სახელდების კონვენციის დაცვა დაგეხმარებათ ტეგების დალაგებაში:

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

Tuist იყენებს `tuist:` პრეფიქსს სისტემის მიერ მართული ტეგებისთვის. ეს ტეგები ავტომატურად ენიჭება Tuist-ის მიერ და შეიძლება გამოყენებულ იქნას ქეშის პროფილებში გენერირებული კონტენტის კონკრეტული ტიპების სამიზნედ.

### ხელმისაწვდომი სისტემური ტეგები

| ტეგი | აღწერა |
| --- | --- |
| `tuist:synthesized` | გამოიყენება სინთეზირებული bundle target-ებისთვის, რომლებსაც Tuist ქმნის რესურსების დამუშავებისთვის სტატიკურ ბიბლიოთეკებსა და სტატიკურ ფრეიმვორქებში. ეს bundles არსებობს ისტორიული მიზეზების გამო რესურსებზე წვდომის API-ების უზრუნველსაყოფად. |

### სისტემური ტეგების გამოყენება ქეშის პროფილებთან

შეგიძლიათ გამოიყენოთ სისტემური ტეგები ქეშის პროფილებში სინთეზირებული target-ების ჩასართავად ან გამოსარიცხად:

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
> **სინთეზირებული bundles მშობლის ტეგებს იღებენ**
>
> სინთეზირებული bundle target-ები იღებენ ყველა ტეგს თავიანთი მშობელი target-ისგან `tuist:synthesized` ტეგის მიღების გარდა. ეს ნიშნავს, რომ თუ სტატიკურ ბიბლიოთეკას მონიშნავთ `feature:auth`-ით, მის სინთეზირებულ რესურსების bundle-ს ექნება როგორც `feature:auth`, ასევე `tuist:synthesized` ტეგები.


## ტეგების გამოყენება პროექტის აღწერის დამხმარე საშუალებებთან {#using-tags-with-helpers}

შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარე საშუალებები</.localized_link>, რათა სტანდარტიზაცია მოახდინოთ იმისა, თუ როგორ გამოიყენება ტეგები თქვენს პროექტში:

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

პროექტის კონკრეტულ ნაწილებზე ფოკუსირებით შეგიძლიათ:

- **Xcode პროექტის ზომის შემცირება** - იმუშავეთ უფრო მცირე პროექტებთან, რომლებიც უფრო სწრაფად იხსნება და ნავიგაციაში მოსახერხებელია
- **ბილდების დაჩქარება** - ააწყეთ მხოლოდ ის, რაც თქვენი მიმდინარე სამუშაოსთვის გჭირდებათ
- **ფოკუსის გაუმჯობესება** - თავიდან აიცილეთ შეუსაბამო კოდისგან გამოწვეული ყურადღების გაფანტვა
- **ინდექსაციის ოპტიმიზაცია** - Xcode ნაკლებ კოდს აინდექსებს, რაც ავტომატურ შევსებას აჩქარებს

### პროექტის უკეთესი ორგანიზება

ტეგები უზრუნველყოფენ თქვენი კოდბაზის ორგანიზების მოქნილ გზას:

- **მრავალგანზომილებიანობა** - მონიშნეთ target-ები ფუნქციის, გუნდის, შრის, პლატფორმის ან ნებისმიერი სხვა განზომილების მიხედვით
- **სტრუქტურული ცვლილებების გარეშე** - დაამატეთ ორგანიზაციული სტრუქტურა დირექტორიების განლაგების შეცვლის გარეშე
- **გადამკვეთი საკითხები** - ერთი target-ი შეიძლება ეკუთვნოდეს რამდენიმე ლოგიკურ ჯგუფს

### ინტეგრაცია ქეშთან

მეტამონაცემთა ტეგები უპრობლემოდ მუშაობს <.localized_link href="/guides/features/cache">Tuist-ის ქეშის ფუნქციებთან</.localized_link>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## საუკეთესო პრაქტიკა {#best-practices}

1. **დაიწყეთ მარტივად** - დაიწყეთ ერთი ტეგირების განზომილებით (მაგ., ფუნქციები) და გააფართოეთ საჭიროებისამებრ
2. **იყავით თანმიმდევრული** - გამოიყენეთ იგივე სახელდების კონვენციები ყველა თქვენს მანიფესტში
3. **დაადოკუმენტეთ თქვენი ტეგები** - შეინახეთ ხელმისაწვდომი ტეგებისა და მათი მნიშვნელობების სია თქვენი პროექტის დოკუმენტაციაში
4. **გამოიყენეთ დამხმარე საშუალებები** - გამოიყენეთ პროექტის აღწერის დამხმარე საშუალებები ტეგების გამოყენების სტანდარტიზაციისთვის
5. **პერიოდულად გადახედეთ** - როგორც კი თქვენი პროექტი ვითარდება, გადახედეთ და განაახლეთ თქვენი ტეგირების სტრატეგია

## დაკავშირებული ფუნქციები {#related-features}

- <.localized_link href="/guides/features/projects/code-sharing">კოდის გაზიარება</.localized_link> - გამოიყენეთ პროექტის აღწერის დამხმარე საშუალებები ტეგების გამოყენების სტანდარტიზაციისთვის
- <.localized_link href="/guides/features/cache">ქეში</.localized_link> - გააერთიანეთ ტეგები ქეშთან ბილდის ოპტიმალური შესრულებისთვის
- <.localized_link href="/guides/features/selective-testing">შერჩევითი ტესტირება</.localized_link> - გაუშვით ტესტები მხოლოდ შეცვლილი target-ებისთვის
