---
{
  "title": "Previews",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "უზიარეთ iOS და Android აპლიკაციების ბილდები მყისიერად Tuist Previews-ით. მიაწოდეთ თანაგუნდელებსა და სტეიკჰოლდერებს ბმული TestFlight-ის ან Play Console-ის კონფიგურაციის გარეშე."
}
---
# პრევიუები {#previews}

Tuist Previews საშუალებას გაძლევთ შექმნათ და გააზიაროთ აპლიკაციის პრევიუები, რათა თქვენმა გუნდის წევრებმა შეძლონ ბილდების ტესტირება ლოკალურად ხელახლა აწყობის გარეშე.

აპლიკაციის აწყობისას, შესაძლოა, მოგინდეთ მისი სხვებთან გაზიარება უკუკავშირის მისაღებად. ტრადიციულად, გუნდები ამას აკეთებენ აპლიკაციების აწყობით, ხელმოწერით და Apple-ის ისეთ პლატფორმებზე, როგორიცაა [TestFlight](https://developer.apple.com/testflight/), გადატანით. თუმცა, ეს პროცესი შეიძლება იყოს რთული და ნელი, განსაკუთრებით მაშინ, როდესაც უბრალოდ ეძებთ სწრაფ უკუკავშირს კოლეგისგან ან მეგობრისგან.

ამ პროცესის უფრო გამართული შესაქმნელად, Tuist გთავაზობთ თქვენი აპლიკაციების პრევიუების შექმნის და ნებისმიერთან გაზიარების გზას.

> [!WARNING]
> **მოწყობილობისთვის აწყობილ ბილდებს სჭირდებათ ხელმოწერა**
>
> მოწყობილობისთვის აწყობისას, ამჟამად თქვენს პასუხისმგებლობაშია დარწმუნდეთ, რომ აპლიკაცია სწორად არის ხელმოწერილი. ჩვენ ვგეგმავთ ამის გამარტივებას მომავალში.

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

ბრძანება შექმნის ბმულს, რომლის გაზიარებაც შეგიძლიათ ნებისმიერთან აპლიკაციის გასაშვებად — ან სიმულატორზე, ან რეალურ მოწყობილობაზე. მათ მხოლოდ ქვემოთ მოცემული ბრძანების გაშვება დასჭირდებათ:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`.ipa` ფაილის გაზიარებისას, შეგიძლიათ აპლიკაცია პირდაპირ ჩამოტვირთოთ მობილური მოწყობილობიდან Preview ბმულის გამოყენებით. `.ipa` პრევიუების ბმულები ნაგულისხმევად _პირადია_, რაც ნიშნავს, რომ მიმღებმა უნდა გაიაროს ავტორიზაცია თავისი Tuist ანგარიშით აპლიკაციის ჩამოსატვირთად. თუ გსურთ აპლიკაციის ნებისმიერთან გაზიარება, შეგიძლიათ ეს შეცვალოთ პროექტის პარამეტრებში.

`tuist run` ასევე საშუალებას გაძლევთ გაუშვათ უახლესი პრევიუ სპეციფიკატორის მიხედვით, როგორიცაა `latest`, ბრენჩის სახელი ან კონკრეტული კომიტის ჰეში:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **უნიკალური ბილდის ნომრები CI-ში**
>
> დარწმუნდით, რომ `CFBundleVersion` (ბილდის ვერსია) უნიკალურია CI-ის გაშვების ნომრის გამოყენებით, რომელსაც უმეტესი CI პროვაიდერი აწვდის. მაგალითად, GitHub Actions-ში შეგიძლიათ `CFBundleVersion` დააყენოთ როგორც <code v-pre>${{ github.run_number }}</code> ცვლადი. 
>
> იგივე ბინარული ფაილით (ბილდი) და იგივე `CFBundleVersion`-ით პრევიუს ატვირთვა ვერ მოხერხდება.

## ტრეკები {#tracks}

ტრეკები საშუალებას გაძლევთ დააჯგუფოთ თქვენი პრევიუები სახელდარქმეულ ჯგუფებში. მაგალითად, შეიძლება გქონდეთ `beta` ტრეკი შიდა ტესტერებისთვის და `nightly` ტრეკი ავტომატური ბილდებისთვის. ტრეკები იქმნება „ზარმაცად“ — უბრალოდ მიუთითეთ ტრეკის სახელი გაზიარებისას და ის ავტომატურად შეიქმნება, თუ ჯერ არ არსებობს.

კონკრეტულ ტრეკზე პრევიუს გასაზიარებლად, გამოიყენეთ `--track` ოფცია:

```bash
tuist share App --track beta
tuist share App --track nightly
```

ეს სასარგებლოა:
- **პრევიუების დაჯგუფება**: დააჯგუფეთ პრევიუები დანიშნულების მიხედვით (მაგ., `beta`, `nightly`, `internal`)
- **აპლიკაციაში განახლებები**: Tuist SDK იყენებს ტრეკებს, რათა განსაზღვროს, რომელი განახლებების შესახებ უნდა აცნობოს მომხმარებლებს
- **ფილტრაცია**: ადვილად იპოვეთ და მართეთ პრევიუები ტრეკის მიხედვით Tuist-ის დაფაზე

> [!WARNING]
> **პრევიუების ხილვადობა**
>
> პრევიუებზე წვდომა მხოლოდ იმ ადამიანებს აქვთ, ვისაც აქვს წვდომა იმ ორგანიზაციაზე, რომელსაც პროექტი ეკუთვნის. ჩვენ ვგეგმავთ ვადიანი ბმულების მხარდაჭერის დამატებას.

## გამოშვების შენიშვნები {#release-notes}

გამოიყენეთ ტრეკები გარემოს ჯგუფებისთვის, ხოლო გამოშვების შენიშვნები — ინდივიდუალური ბილდის აღწერისთვის:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

გამოშვების შენიშვნები არის არასავალდებულო ტექსტი, 10,000 სიმბოლომდე. პირველი არაცარიელი ხაზი ჩანს ერთხაზიან ფრაგმენტად ვებ და iOS პრევიუების სიებში, რათა ბილდის ნომრები და სხვა იდენტიფიცირების ინფორმაცია ერთი შეხედვით იყოს ხილული. გრძელი ხაზები იკვეცება; სრული შენიშვნები ჩანს დეტალურ გვერდებზე. ძებნა ორივე სიაში ემთხვევა საჩვენებელ სახელებს და სრულ გამოშვების შენიშვნებს, მათ შორის იმ ხაზებსაც, რომლებიც ფრაგმენტში არ ჩანს. მრავალხაზიანი შენიშვნები მხარდაჭერილია, მაგალითად `--release-notes "$(< release-notes.txt)"`. ისინი არ ცვლიან აპლიკაციის საჩვენებელ სახელს ან მის ტრეკს.

### თავსებადობა {#preview-metadata-compatibility}

გამოშვების შენიშვნები არის დამატებითი მეტამონაცემები და არა პრევიუს იდენტობის ნაწილი. ძველი და ახალი კლიენტებიდან ატვირთვები კვლავ ჯგუფდებიან ერთსა და იმავე პრევიუში პლატფორმების მიხედვით. პირველი არაცარიელი შენიშვნები ნარჩუნდება: მოგვიანებით ატვირთვას შეუძლია შეავსოს ადრე არარსებული შენიშვნები, მაგრამ ვერ გადაწერს არსებულ შენიშვნებს. `release_notes`-ის გამოტოვება, `null`-ის გაგზავნა ან ცარიელი ან მხოლოდ თეთრი სივრცის შემცველი სტრიქონის გაგზავნა არასდროს ასუფთავებს შენიშვნებს. არსებული პრევიუები არ ივსება უკანა რიცხვით და რჩება ვალიდური შენიშვნების გარეშე.

სიის API-ის არასავალდებულო `track` კითხვის პარამეტრი ემთხვევა მთელ ტრეკის სახელს, რეგისტრის მიუხედავად, რაც შეესაბამება არსებულ ტრეკების შენახვას. გამოტოვეთ ის ან გაგზავნეთ ცარიელი მნიშვნელობა (`?track=`), რათა ჩამოთვალოთ ყველა ტრეკი. ტრეკის სახელები რჩება ღია სტრიქონებად და არა ფიქსირებული მნიშვნელობების სიად. iOS აპლიკაციის **ყველა ტრეკი** შერჩევა ტოვებს ფილტრს. iOS აპლიკაციის ტრეკის ღილაკები ტვირთავს სრულ პროექტის შეჯამებას `GET /api/projects/:account_handle/:project_handle/previews/tracks`-დან, იმავე პრევიუს კითხვის ავტორიზაციით, რაც ბილდების ჩამოთვლისას. ეს endpoint აბრუნებს `{total_count, tracks: [{name, count}]}`-ს დალაგებული, რეგისტრის მიუხედავად დაჯგუფებული სახელდარქმეული ტრეკებით. რაოდენობები მოიცავს მთელ პროექტს პაგინაციის, ძებნის და შერჩეული ტრეკისგან დამოუკიდებლად; ჯამი მოიცავს არატრეკირებულ პრევიუებს. ითვლება მხოლოდ ჩამოსათვლელი პრევიუები bundle identifier-ით. სიის API ასევე იღებს არასავალდებულო `search`-ს საჩვენებელი სახელის ან სრული გამოშვების შენიშვნების ლიტერალური, რეგისტრის მიუხედავად ქვესტრიქონისთვის, რომელიც აერთიანდება ტრეკთან პაგინაციამდე. არსებული `display_name` ფილტრაცია რჩება ზუსტი.

ძველ კლიენტებს შეუძლიათ განაგრძონ პრევიუების ატვირთვა და ჩამოთვლა ორივე ველის გაგზავნის გარეშე. ახალი კლიენტები იღებენ ძველ პასუხებს, რომლებიც ტოვებენ ტრეკს ან შენიშვნებს, და იგნორირებენ მომავალი სერვერების მიერ დამატებულ უცნობ პასუხის თვისებებს. API ინტეგრაციებმაც ასევე უნდა დაიგნორონ უცნობი პასუხის თვისებები, რათა დამატებითი მეტამონაცემები დარჩეს თავსებადი.

თვითმასპინძელ განლაგებებს სჭირდებათ სერვერის ვერსია, რომელიც მხარს უჭერს გამოშვების შენიშვნებს და ტრეკის ფილტრაციას, განახლებულ CLI-სთან და აპლიკაციასთან ერთად, ამ ფუნქციების გამოსაყენებლად. ძველმა სერვერებმა შეიძლება დაიგნორონ შენიშვნები ან უცნობი კითხვის პარამეტრები. თუ ტრეკის აღმოჩენა ხელმიუწვდომელია, iOS აპლიკაცია ინარჩუნებს გაუფილტრავ ბრაუზინგს და ხსნის, რომ ტრეკის შერჩევა განახლებულ სერვერს მოითხოვს. თუ სერვერი აბრუნებს პრევიუებს სხვა ტრეკიდან აქტიური ფილტრის მიუხედავად, iOS აპლიკაცია იუწყება, რომ ფილტრაცია არ არის მხარდაჭერილი, ნაცვლად შეცდომაში შემყვანი შედეგების წარმოდგენისა. macOS აპლიკაცია ჯერ ითხოვს უახლეს თავსებად პრევიუს თითოეული აპლიკაციისთვის; ძველ სერვერებზე, რომლებიც შერჩევენ განსხვავებულ აპლიკაციებს პლატფორმის ფილტრების გამოყენებამდე, ის გადადის პაგინირებულ ისტორიაზე ისეთი ზღვრის დაწესების გარეშე, რომელმაც შეიძლება დამალოს ხელმისაწვდომი ბილდი.

## Tuist macOS აპლიკაცია {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist Previews-ის გაშვების კიდევ უფრო გასამარტივებლად, ჩვენ შევქმენით Tuist macOS მენიუს ზოლის აპლიკაცია. Tuist CLI-ის საშუალებით Previews-ის გაშვების ნაცვლად, შეგიძლიათ [ჩამოტვირთოთ](https://tuist.dev/download) macOS აპლიკაცია. ასევე შეგიძლიათ აპლიკაციის დაყენება `brew install --cask tuist/tuist/tuist`-ის გაშვებით.

როდესაც Preview გვერდზე „Run“-ს დააჭერთ, macOS აპლიკაცია ავტომატურად გაუშვებს მას თქვენს მიმდინარე შერჩეულ მოწყობილობაზე.

## Tuist iOS აპლიკაცია {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="App Store-დან ჩამოტვირთვა" style="height: 40px;">
    </a>
</div>

macOS აპლიკაციის მსგავსად, Tuist iOS აპლიკაცია ამარტივებს თქვენი previews-ებზე წვდომას და მათ გაშვებას. თითოეული preview აჩვენებს თავის ტრეკს. გამოიყენეთ ნატიური საძიებო ველი previews-ების საპოვნელად აპლიკაციის სახელით, შემდეგ კი აირჩიეთ პილული **Tracks**-ის ქვეშ გარემოს მიხედვით ფილტრაციისთვის. შერჩეული პილული იისფერია; აირჩიეთ **All** ტრეკის ფილტრის მოსახსნელად. თითოეული პილული აჩვენებს პროექტის მასშტაბით preview-ების რაოდენობას, ხოლო All მოიცავს ბილდებს ტრეკის გარეშე. ძებნა და ტრეკის ფილტრაცია მოქმედებს ყველა გვერდზე, არა მხოლოდ უკვე ჩატვირთულ previews-ებზე. თითოეული ბილდის ტრეკის ტეგი განთავსებულია მისი commit hash-ის გვერდით.

## Pull/merge request კომენტარები {#pullmerge-request-comments}

> [!WARNING]
> **აუცილებელია Git პლატფორმასთან ინტეგრაცია**
>
> ავტომატური pull/merge request კომენტარების მისაღებად, დააკავშირეთ თქვენი <.localized_link href="/guides/server/accounts-and-projects">remote project</.localized_link> <.localized_link href="/guides/server/authentication">Git platform</.localized_link>-თან.

ახალი ფუნქციონალის ტესტირება ნებისმიერი კოდის რევიუს ნაწილი უნდა იყოს. მაგრამ აპლიკაციის ლოკალურად აშენების აუცილებლობა ზედმეტ სირთულეს ქმნის, რაც ხშირად იწვევს იმას, რომ დეველოპერები საერთოდ ტოვებენ ფუნქციონალის ტესტირებას მოწყობილობაზე. მაგრამ *რა მოხდება, თუ თითოეულ pull request-ში იქნება ბილდის ბმული, რომელიც ავტომატურად გაუშვებს აპლიკაციას თქვენს მიერ Tuist macOS აპლიკაციაში შერჩეულ მოწყობილობაზე?*

მას შემდეგ, რაც თქვენი Tuist პროექტი დაკავშირდება თქვენს Git პლატფორმასთან, როგორიცაა [GitHub](https://github.com), დაამატეთ <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link> თქვენს CI workflow-ში. Tuist შემდეგ პირდაპირ თქვენს pull requests-ში გამოაქვეყნებს Preview ბმულს: ![GitHub აპლიკაციის კომენტარი Tuist Preview ბმულით](/images/guides/features/github-app-with-preview.png)

## აპლიკაციაში განახლების შეტყობინებები {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) საშუალებას აძლევს თქვენს აპლიკაციას აღმოაჩინოს, როდესაც ხელმისაწვდომია preview-ის ახალი ვერსია და შეატყობინოს მომხმარებლებს. ეს სასარგებლოა ტესტერების უახლეს ბილდზე შესანარჩუნებლად.

SDK ამოწმებს განახლებებს იმავე **preview track**-ის ფარგლებში. როდესაც თქვენ გაზიარებთ preview-ს ცალსახა ტრეკით `--track`-ის გამოყენებით, SDK ამ ტრეკზე ეძებს განახლებებს. თუ ტრეკი მითითებული არ არის, git branch გამოიყენება როგორც ტრეკი — ასე რომ, `main` branch-დან აგებული preview მხოლოდ `main`-დან აგებულ ახალ previews-ებზე შეატყობინებს.

### დაყენება {#sdk-installation}

დაამატეთ Tuist SDK, როგორც Swift Package დამოკიდებულება:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### განახლებების მონიტორინგი {#sdk-monitor-updates}

გამოიყენეთ `monitorPreviewUpdates` preview-ების ახალი ვერსიების პერიოდულად შესამოწმებლად:

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

### განახლების ერთჯერადი შემოწმება {#sdk-single-check}

განახლების ხელით შესამოწმებლად:

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

## README ბეიჯი {#readme-badge}

იმისათვის, რომ Tuist Previews უფრო შესამჩნევი იყოს თქვენს რეპოზიტორიაში, შეგიძლიათ დაამატოთ ბეიჯი თქვენს `README` ფაილში, რომელიც მიუთითებს უახლეს Tuist Preview-ზე:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

ბეიჯის `README`-ში დასამატებლად, გამოიყენეთ შემდეგი markdown და შეცვალეთ ანგარიშისა და პროექტის handle-ები თქვენით:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

თუ თქვენი პროექტი შეიცავს რამდენიმე აპლიკაციას სხვადასხვა bundle identifier-ებით, შეგიძლიათ მიუთითოთ, თუ რომელი აპლიკაციის preview-ს ბმული გსურთ `bundle-id` query პარამეტრის დამატებით:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## ავტომატიზაციები {#automations}

შეგიძლიათ გამოიყენოთ `--json` flag, რათა მიიღოთ JSON გამოტანა `tuist share` ბრძანებიდან:
```
tuist share --json
```

JSON გამოტანა სასარგებლოა მორგებული ავტომატიზაციების შესაქმნელად, მაგალითად, Slack შეტყობინების გამოქვეყნებისთვის თქვენი CI პროვაიდერის მეშვეობით. JSON შეიცავს `url` გასაღებს სრული preview ბმულით და `qrCodeURL` გასაღებს QR კოდის გამოსახულების URL-ით, რაც ამარტივებს previews-ების ჩამოტვირთვას რეალური მოწყობილობიდან. JSON გამოტანის მაგალითი მოცემულია ქვემოთ:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
