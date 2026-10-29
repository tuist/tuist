---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Share iOS and Android app builds instantly with Tuist Previews. Give teammates and stakeholders a link, no TestFlight or Play Console setup required."
}
---
# Previews {#previews}

Tuist Previews საშუალებას გაძლევთ შექმნათ და გააზიაროთ აპლიკაციის პრევიუები, რათა თქვენმა გუნდის წევრებმა შეძლონ ბილდების ტესტირება ლოკალურად ხელახლა აწყობის გარეშე.

როდესაც აპლიკაციას აწყობთ, შესაძლოა მოგინდეთ მისი სხვებთან გაზიარება უკუკავშირის მისაღებად. ტრადიციულად, გუნდები ამას აკეთებენ აპლიკაციების აწყობით, ხელმოწერით და Apple-ის ისეთ პლატფორმებზე, როგორიცაა [TestFlight](https://developer.apple.com/testflight/), განთავსებით. თუმცა, ეს პროცესი შეიძლება იყოს მოუხერხებელი და ნელი, განსაკუთრებით მაშინ, როდესაც უბრალოდ ეძებთ სწრაფ უკუკავშირს კოლეგისგან ან მეგობრისგან.

ამ პროცესის უფრო გამარტივების მიზნით, Tuist გთავაზობთ თქვენი აპლიკაციების პრევიუების შექმნისა და ნებისმიერთან გაზიარების გზას.

> [!WARNING]
> **მოწყობილობისთვის აწყობილი ბილდები უნდა იყოს ხელმოწერილი**
>
> მოწყობილობისთვის აწყობისას, ამჟამად თქვენს პასუხისმგებლობაშია დარწმუნდეთ, რომ აპლიკაცია სწორადაა ხელმოწერილი. ჩვენ ვგეგმავთ ამის გამარტივებას მომავალში.

::: code-group
```bash [Tuist Project (Debug)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Tuist Project (Release)]
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -sdk iphonesimulator # Build the app for the simulator
tuist xcodebuild build -scheme App -workspace App.xcworkspace -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release
```
```bash [Xcode Project (Debug)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
```bash [Xcode Project (Release)]
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release # Build the app for the simulator
tuist xcodebuild build -scheme App -project App.xcodeproj -configuration Release -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Release --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

ბრძანება შექმნის ბმულს, რომლის გაზიარებაც შეგიძლიათ ნებისმიერთან აპლიკაციის გასაშვებად — ან სიმულატორზე, ან რეალურ მოწყობილობაზე. მათ მხოლოდ ქვემოთ მოცემული ბრძანების შესრულება დასჭირდებათ:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`.ipa` ფაილის გაზიარებისას, შეგიძლიათ აპლიკაციის ჩამოტვირთვა პირდაპირ მობილური მოწყობილობიდან Preview ბმულის გამოყენებით. `.ipa` პრევიუების ბმულები ნაგულისხმევად _კერძოა_, რაც ნიშნავს, რომ მიმღებმა უნდა გაიაროს ავთენტიფიკაცია თავისი Tuist ანგარიშით აპლიკაციის ჩამოსატვირთად. თუ გსურთ აპლიკაციის ნებისმიერთან გაზიარება, შეგიძლიათ ეს შეცვალოთ პროექტის პარამეტრებში.

`tuist run` ასევე საშუალებას გაძლევთ გაუშვათ უახლესი პრევიუ სპეციფიკატორის საფუძველზე, როგორიცაა `latest`, ბრენჩის სახელი ან კონკრეტული კომიტის ჰეში:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **უნიკალური ბილდის ნომრები CI-ში**
>
> დარწმუნდით, რომ `CFBundleVersion` (ბილდის ვერსია) არის უნიკალური CI-ის გაშვების ნომრის გამოყენებით, რომელსაც უმეტესი CI პროვაიდერი აქვეყნებს. მაგალითად, GitHub Actions-ში შეგიძლიათ `CFBundleVersion` დააყენოთ როგორც <code v-pre>${{ github.run_number }}</code> ცვლადი. 
>
> იგივე ბინარული ფაილით (ბილდი) და იგივე `CFBundleVersion` პრევიუს ატვირთვა ვერ მოხერხდება.

## Tracks {#tracks}

Tracks საშუალებას გაძლევთ დააჯგუფოთ თქვენი პრევიუები დასახელებულ ჯგუფებში. მაგალითად, შეიძლება გქონდეთ `beta` track შიდა ტესტერებისთვის და `nightly` track ავტომატიზებული ბილდებისთვის. Tracks იქმნება ზარმაცად — უბრალოდ მიუთითეთ track-ის სახელი გაზიარებისას და ის ავტომატურად შეიქმნება, თუ არ არსებობს.

კონკრეტულ track-ზე პრევიუს გასაზიარებლად, გამოიყენეთ `--track` ოფცია:

```bash
tuist share App --track beta
tuist share App --track nightly
```

ეს სასარგებლოა:
- **პრევიუების ორგანიზება**: დააჯგუფეთ პრევიუები დანიშნულების მიხედვით (მაგ., `beta`, `nightly`, `internal`)
- **აპლიკაციაში განახლებები**: Tuist SDK იყენებს tracks-ს იმის დასადგენად, თუ რომელი განახლებების შესახებ უნდა აცნობოს მომხმარებლებს
- **ფილტრაცია**: მარტივად იპოვეთ და მართეთ პრევიუები track-ის მიხედვით Tuist dashboard-ში

> [!WARNING]
> **პრევიუების ხილვადობა**
>
> პრევიუებზე წვდომა მხოლოდ იმ ადამიანებს აქვთ, ვინც წვდომა აქვთ ორგანიზაციაში, რომელსაც პროექტი ეკუთვნის. ჩვენ ვგეგმავთ ვადიანი ბმულების მხარდაჭერის დამატებას.

## გამოშვების შენიშვნები {#release-notes}

გამოიყენეთ tracks გარემოს ჯგუფებისთვის და გამოშვების შენიშვნები ინდივიდუალური ბილდის მიზნისთვის:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

გამოშვების შენიშვნები არის არასავალდებულო ტექსტი, 10,000 სიმბოლომდე. პირველი არაცარიელი ხაზი ჩანს ერთხაზიან ფრაგმენტად ვებ და iOS პრევიუების სიებში, ასე რომ ბილდის ნომრები და სხვა იდენტიფიცირების ინფორმაცია ერთი შეხედვით ჩანს. გრძელი ხაზები იკვეცება; სრული შენიშვნები ჩანს დეტალურ გვერდებზე. ძებნა ორივე სიაში ემთხვევა საჩვენებელ სახელებს და სრულ გამოშვების შენიშვნებს, მათ შორის იმ ხაზებს, რომლებიც ფრაგმენტში არ ჩანს. მრავალხაზიანი შენიშვნები მხარდაჭერილია, მაგალითად `--release-notes "$(< release-notes.txt)"`. ისინი არ ცვლიან აპლიკაციის საჩვენებელ სახელს ან მის track-ს.

### თავსებადობა {#preview-metadata-compatibility}

გამოშვების შენიშვნები არის დამატებითი მეტამონაცემები, არა პრევიუს იდენტობის ნაწილი. ძველი და ახალი კლიენტებიდან ატვირთვები კვლავ ერთიანდება იმავე პრევიუში პლატფორმების მიხედვით. პირველი არაცარიელი შენიშვნები ნარჩუნდება: მოგვიანებით ატვირთვამ შეიძლება შეავსოს ადრე არარსებული შენიშვნები, მაგრამ ვერ გადაწერს არსებულ შენიშვნებს. `release_notes`-ის გამოტოვება, `null`-ის გაგზავნა ან ცარიელი ან მხოლოდ თეთრი სივრცის შემცველი სტრიქონის გაგზავნა არასდროს ასუფთავებს შენიშვნებს. არსებული პრევიუები არ ივსება უკან და რჩება ვალიდური შენიშვნების გარეშე.

სიის API-ის არასავალდებულო `track` query პარამეტრი ემთხვევა მთელ track-ის სახელს, რეგისტრის მიუხედავად, რაც თავსებადია არსებულ track-ის შენახვასთან. გამოტოვეთ ის ან გაგზავნეთ ცარიელი მნიშვნელობა (`?track=`) ყველა track-ის ჩამოსათვლელად. Track-ის სახელები რჩება ღია სტრიქონებად, არა ფიქსირებული მნიშვნელობების სიად. iOS აპლიკაციის **All Tracks** შერჩევა ტოვებს ფილტრს. iOS აპლიკაციის track pills ტვირთავს სრულ პროექტის შეჯამებას `GET /api/projects/:account_handle/:project_handle/previews/tracks`-დან, იმავე პრევიუს წაკითხვის ავტორიზაციით, რაც ბილდების ჩამოთვლისას. ეს endpoint აბრუნებს `{total_count, tracks: [{name, count}]}` დალაგებული, რეგისტრის მიუხედავად დაჯგუფებული დასახელებული track-ებით. რაოდენობები მოიცავს მთელ პროექტს დამოუკიდებლად პაგინაციის, ძებნისა და შერჩეული track-ისგან; ჯამი მოიცავს untracked პრევიუებს. ითვლება მხოლოდ ჩამოსათვლელი პრევიუები bundle identifier-ით. სიის API ასევე იღებს არასავალდებულო `search` საჩვენებელი სახელის ან სრული გამოშვების შენიშვნების literal, რეგისტრის მიუხედავად ქვესტრიქონისთვის, გაერთიანებული track-თან პაგინაციამდე. არსებული `display_name` ფილტრაცია რჩება ზუსტი.

ძველ კლიენტებს შეუძლიათ განაგრძონ პრევიუების ატვირთვა და ჩამოთვლა ორივე ველის გაგზავნის გარეშე. ახალი კლიენტები იღებენ ძველ პასუხებს, რომლებიც ტოვებენ track-ს ან შენიშვნებს და იგნორირებენ უცნობ პასუხის თვისებებს, რომლებიც დაემატა მომავალ სერვერებზე. API ინტეგრაციებმა ასევე უნდა დაიგნორონ უცნობი პასუხის თვისებები, რათა დამატებითი მეტამონაცემები დარჩეს თავსებადი.

თვითმასპინძელ განლაგებებს სჭირდებათ სერვერის ვერსია, რომელიც მხარს უჭერს გამოშვების შენიშვნებსა და track ფილტრაციას, განახლებულ CLI-სთან და აპთან ერთად, ამ ფუნქციების გამოსაყენებლად. ძველმა სერვერებმა შეიძლება დაიგნორონ შენიშვნები ან უცნობი query პარამეტრები. თუ track-ის აღმოჩენა არ არის ხელმისაწვდომი, iOS აპი ინარჩუნებს გაუფილტრავ ბრაუზინგს და ხსნის, რომ track-ის შერჩევა მოითხოვს განახლებულ სერვერს. თუ სერვერი აბრუნებს პრევიუებს სხვა track-დან აქტიური ფილტრის მიუხედავად, iOS აპი იტყობინებს, რომ ფილტრაცია არ არის მხარდაჭერილი, ვიდრე წარმოადგენს შეცდომაში შემყვან შედეგებს. macOS აპი ჯერ ითხოვს უახლეს თავსებად პრევიუს თითოეული აპისთვის; ძველ სერვერებზე, რომლებიც შერჩევენ განსხვავებულ აპებს პლატფორმის ფილტრების გამოყენებამდე, ის ბრუნდება პაგინირებულ ისტორიაზე ისეთი cutoff-ის დაწესების გარეშე, რომელმაც შეიძლება დამალოს ხელმისაწვდომი ბილდი.

## Tuist macOS აპი {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist Previews-ის გაშვების კიდევ უფრო გასამარტივებლად, შევქმენით Tuist macOS მენიუს ზოლის აპი. Previews-ის Tuist CLI-ით გაშვების ნაცვლად, შეგიძლიათ [ჩამოტვირთოთ](https://tuist.dev/download) macOS აპი. ასევე შეგიძლიათ დააინსტალიროთ აპი `brew install --cask tuist/tuist/tuist` ბრძანების გაშვებით.

როდესაც Preview გვერდზე "Run"-ს დააჭერთ, macOS აპი მას ავტომატურად გაუშვებს თქვენს მიმდინარე შერჩეულ მოწყობილობაზე.

## Tuist iOS აპი {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="App Store-დან ჩამოტვირთვა" style="height: 40px;">
    </a>
</div>

macOS აპის მსგავსად, Tuist iOS აპი ამარტივებს თქვენი პრევიუების წვდომასა და გაშვებას. თითოეული პრევიუ აჩვენებს თავის track-ს. გამოიყენეთ ნატიური ძებნის ველი პრევიუების საპოვნელად აპის სახელით, შემდეგ კი აირჩიეთ ღილაკი **Tracks**-ის ქვეშ გარემოს მიხედვით ფილტრაციისთვის. შერჩეული ღილაკი იისფერია; აირჩიეთ **All** track ფილტრის მოსახსნელად. თითოეული ღილაკი აჩვენებს პროექტის მასშტაბით პრევიუების რაოდენობას, ხოლო All მოიცავს ბილდებს track-ის გარეშე. ძებნა და track ფილტრაცია ვრცელდება ყველა გვერდზე, არა მხოლოდ უკვე ჩატვირთულ პრევიუებზე. თითოეული ბილდის track ტეგი განთავსებულია მისი commit hash-ის გვერდით.

## Pull/merge request კომენტარები {#pullmerge-request-comments}

> [!WARNING]
> **Git პლატფორმასთან ინტეგრაცია სავალდებულოა**
>
> ავტომატური pull/merge request კომენტარების მისაღებად, დააკავშირეთ თქვენი <.localized_link href="/guides/server/accounts-and-projects">remote project</.localized_link> <.localized_link href="/guides/server/authentication">Git platform</.localized_link>-თან.

ახალი ფუნქციონალის ტესტირება ნებისმიერი კოდის გადახედვის ნაწილი უნდა იყოს. მაგრამ აპის ლოკალურად აგება ზედმეტ სირთულეს ქმნის, რაც ხშირად იწვევს იმას, რომ დეველოპერები საერთოდ ტოვებენ ფუნქციონალის ტესტირებას მოწყობილობაზე. მაგრამ *რა იქნებოდა, თუ ყოველ pull request-ში იქნებოდა ბილდის ბმული, რომელიც ავტომატურად გაუშვებდა აპს Tuist macOS აპში შერჩეულ მოწყობილობაზე?*

მას შემდეგ, რაც თქვენი Tuist პროექტი დაკავშირდება თქვენს Git პლატფორმასთან, როგორიცაა [GitHub](https://github.com), დაამატეთ <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link> თქვენს CI workflow-ში. Tuist შემდეგ პირდაპირ თქვენს pull request-ებში გამოაქვეყნებს Preview ბმულს: ![GitHub აპის კომენტარი Tuist Preview ბმულით](/images/guides/features/github-app-with-preview.png)

## აპში განახლების შეტყობინებები {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) საშუალებას აძლევს თქვენს აპს აღმოაჩინოს, როდის არის ხელმისაწვდომი პრევიუს ახალი ვერსია და აცნობოს მომხმარებლებს. ეს სასარგებლოა ტესტერების უახლეს ბილდზე შესანარჩუნებლად.

SDK ამოწმებს განახლებებს იმავე **preview track**-ის ფარგლებში. როდესაც პრევიუს გაზიარებთ ცალსახა track-ით `--track`-ის გამოყენებით, SDK მოძებნის განახლებებს ამ track-ზე. თუ track მითითებული არ არის, git branch გამოიყენება როგორც track — ასე რომ, `main` branch-დან აგებული პრევიუ მხოლოდ `main`-დან აგებულ ახალ პრევიუებზე შეატყობინებს.

### ინსტალაცია {#sdk-installation}

დაამატეთ Tuist SDK Swift Package დამოკიდებულებად:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### განახლებების მონიტორინგი {#sdk-monitor-updates}

გამოიყენეთ `monitorPreviewUpdates` პრევიუს ახალი ვერსიების პერიოდულად შესამოწმებლად:

```swift
import TuistSDK

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TuistSDK(
                        fullHandle: "myorg/myapp",
                        apiKey: "your-api-key"
                    )
                    .monitorPreviewUpdates()
                }
        }
    }
}
```

### ერთჯერადი განახლების შემოწმება {#sdk-single-check}

ხელით განახლების შესამოწმებლად:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### განახლების მონიტორინგის შეჩერება {#sdk-stop-monitoring}

`monitorPreviewUpdates` აბრუნებს `Task`-ს, რომლის გაუქმებაც შესაძლებელია:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> განახლების შემოწმება ავტომატურად გამორთულია სიმულატორებზე და App Store ბილდებზე.

## README ბეჯი {#readme-badge}

იმისათვის, რომ Tuist Previews უფრო შესამჩნევი იყოს თქვენს რეპოზიტორიაში, შეგიძლიათ დაამატოთ ბეჯი თქვენს `README` ფაილში, რომელიც მიუთითებს უახლეს Tuist Preview-ზე:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

ბეჯის თქვენს `README`-ში დასამატებლად, გამოიყენეთ შემდეგი markdown და ჩაანაცვლე account და project handles თქვენით:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

თუ თქვენი პროექტი შეიცავს რამდენიმე აპს სხვადასხვა bundle identifier-ებით, შეგიძლიათ მიუთითოთ, რომელი აპის პრევიუს ბმული გსურთ `bundle-id` query პარამეტრის დამატებით:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## ავტომატიზაციები {#automations}

შეგიძლიათ გამოიყენოთ `--json` flag `tuist share` ბრძანებიდან JSON output-ის მისაღებად:
```
tuist share --json
```

JSON output სასარგებლოა მორგებული ავტომატიზაციების შესაქმნელად, მაგალითად, Slack შეტყობინების გამოქვეყნებისთვის თქვენი CI პროვაიდერის გამოყენებით. JSON შეიცავს `url` key-ს სრული preview ბმულით და `qrCodeURL` key-ს QR code გამოსახულების URL-ით, რაც ამარტივებს პრევიუების ჩამოტვირთვას რეალური მოწყობილობიდან. JSON output-ის მაგალითი მოცემულია ქვემოთ:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
