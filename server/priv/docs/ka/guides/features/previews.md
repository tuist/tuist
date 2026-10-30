---
{
  "title": "პრივიუები",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუზიარეთ iOS და Android აპლიკაციების ბილდები მყისიერად Tuist Previews-ით. მიაწოდეთ თანამშრომლებსა და სტეიკჰოლდერებს ბმული TestFlight-ის ან Play Console-ის კონფიგურაციის გარეშე."
}
---
# Previews {#previews}

Tuist Previews საშუალებას გაძლევთ შექმნათ და გააზიაროთ აპლიკაციის პრევიუები, რათა გუნდის წევრებმა შეძლონ ბილდების ტესტირება ლოკალურად ხელახლა აწყობის გარეშე.

აპლიკაციის აწყობისას, შესაძლოა, გსურთ მისი სხვებთან გაზიარება უკუკავშირის მისაღებად. ტრადიციულად, გუნდები ამას აკეთებენ აპლიკაციების აწყობით, ხელმოწერით და ისეთ პლატფორმებზე გაგზავნით, როგორიცაა Apple-ის [TestFlight](https://developer.apple.com/testflight/). თუმცა, ეს პროცესი შეიძლება იყოს მოუხერხებელი და ნელი, განსაკუთრებით მაშინ, როცა უბრალოდ ეძებთ სწრაფ უკუკავშირს კოლეგისგან ან მეგობრისგან.

ამ პროცესის უფრო გამართული გასახდელად, Tuist გთავაზობთ თქვენი აპლიკაციების პრევიუების შექმნისა და ნებისმიერთან გაზიარების გზას.

> [!WARNING]
> **მოწყობილობისთვის აწყობილი ბილდები უნდა იყოს ხელმოწერილი**
>
> მოწყობილობისთვის აწყობისას, ამჟამად თქვენს პასუხისმგებლობაში შედის აპლიკაციის სწორად ხელმოწერის უზრუნველყოფა. ჩვენ ვგეგმავთ ამის გამარტივებას მომავალში.

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

ბრძანება შექმნის ბმულს, რომლის გაზიარებაც ნებისმიერთან შეგიძლიათ აპლიკაციის გასაშვებად — იქნება ეს სიმულატორი თუ რეალური მოწყობილობა. მათ მხოლოდ ქვემოთ მოცემული ბრძანების შესრულება დასჭირდებათ:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`.ipa` ფაილის გაზიარებისას, აპლიკაციის ჩამოტვირთვა პირდაპირ მობილური მოწყობილობიდან შეგიძლიათ Preview ბმულის გამოყენებით. `.ipa` პრევიუების ბმულები ნაგულისხმევად _პირადია_, რაც ნიშნავს, რომ მიმღებს აპლიკაციის ჩამოტვირთვისთვის Tuist ანგარიშით ავტორიზაცია უნდა გაიაროს. პროექტის პარამეტრებში შეგიძლიათ ეს საჯაროდ შეცვალოთ, თუ გსურთ აპლიკაციის ნებისმიერთან გაზიარება.

`tuist run` ასევე საშუალებას გაძლევთ გაუშვათ უახლესი პრევიუ სპეციფიკატორის მიხედვით, როგორიცაა `latest`, ბრენჩის სახელი ან კონკრეტული კომიტის ჰეში:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [!WARNING]
> **უნიკალური ბილდის ნომრები CI-ში**
>
> დარწმუნდით, რომ `CFBundleVersion` (ბილდის ვერსია) არის უნიკალური CI-ის გაშვების ნომრის გამოყენებით, რომელსაც უმეტესი CI პროვაიდერი წარმოადგენს. მაგალითად, GitHub Actions-ში შეგიძლიათ `CFBundleVersion` დააყენოთ <code v-pre>${{ github.run_number }}</code> ცვლადზე. 
>
> იგივე ბინარული ფაილით (ბილდი) და იგივე `CFBundleVersion`-ით პრევიუს ატვირთვა ვერ მოხერხდება.

## ტრეკები {#tracks}

ტრეკები საშუალებას გაძლევთ დააჯგუფოთ თქვენი პრევიუები სახელიანი ჯგუფებად. მაგალითად, შეიძლება გქონდეთ `beta` ტრეკი შიდა ტესტერებისთვის და `nightly` ტრეკი ავტომატური ბილდებისთვის. ტრეკები იქმნება ზარმაცად — უბრალოდ მიუთითეთ ტრეკის სახელი გაზიარებისას და ის ავტომატურად შეიქმნება, თუ არ არსებობს.

კონკრეტულ ტრეკზე პრევიუს გასაზიარებლად, გამოიყენეთ `--track` ოფცია:

```bash
tuist share App --track beta
tuist share App --track nightly
```

ეს სასარგებლოა:
- **პრევიუების დაჯგუფება**: პრევიუების დაჯგუფება დანიშნულების მიხედვით (მაგ., `beta`, `nightly`, `internal`)
- **აპლიკაციაში განახლებები**: Tuist SDK იყენებს ტრეკებს იმის დასადგენად, თუ რომელი განახლებების შესახებ უნდა აცნობოს მომხმარებლებს
- **ფილტრაცია**: Tuist დაშბორდში ტრეკების მიხედვით პრევიუების ადვილად პოვნა და მართვა

> [!WARNING]
> **პრევიუების ხილვადობა**
>
> პრევიუებზე წვდომა მხოლოდ იმ ადამიანებს აქვთ, ვისაც აქვს წვდომა იმ ორგანიზაციაზე, რომელსაც პროექტი ეკუთვნის. ჩვენ ვგეგმავთ ვადაგასული ბმულების მხარდაჭერის დამატებას.

## გამოშვების შენიშვნები {#release-notes}

გამოიყენეთ ტრეკები გარემოს ჯგუფებისთვის და გამოშვების შენიშვნები ინდივიდუალური ბილდის დანიშნულებისთვის:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

გამოშვების შენიშვნები არის არასავალდებულო ჩვეულებრივი ტექსტი, 10,000 სიმბოლომდე. პირველი არაცარიელი ხაზი ჩანს ერთხაზიან ფრაგმენტად ვებ და iOS პრევიუების სიებში, რათა ბილდის ნომრები და სხვა საიდენტიფიკაციო ინფორმაცია ერთი შეხედვით იყოს ხილული. გრძელი ხაზები იკვეცება; სრული შენიშვნები ჩანს დეტალურ გვერდებზე. ძებნა ორივე სიაში ემთხვევა საჩვენებელ სახელებს და სრულ გამოშვების შენიშვნებს, მათ შორის იმ ხაზებსაც, რომლებიც ფრაგმენტში არ ჩანს. მრავალხაზიანი შენიშვნები მხარდაჭერილია, მაგალითად `--release-notes "$(< release-notes.txt)"`. ისინი არ ცვლიან აპლიკაციის საჩვენებელ სახელს ან მის ტრეკს.

### თავსებადობა {#preview-metadata-compatibility}

გამოშვების შენიშვნები არის დამატებითი მეტამონაცემები და არა პრევიუს იდენტობის ნაწილი. ძველი და ახალი კლიენტებიდან ატვირთვები კვლავ ჯგუფდებიან ერთ პრევიუში პლატფორმების მიხედვით. პირველი არაცარიელი შენიშვნები ნარჩუნდება: მოგვიანებით ატვირთვამ შეიძლება შეავსოს ადრე არარსებული შენიშვნები, მაგრამ არ შეუძლია არსებული შენიშვნების გადაწერა. `release_notes`-ის გამოტოვება, `null`-ის გაგზავნა ან ცარიელი ან მხოლოდ თეთრი სივრცის შემცველი სტრიქონის გაგზავნა არასდროს ასუფთავებს შენიშვნებს. არსებული პრევიუები არ ივსება უკან და რჩება ვალიდური შენიშვნების გარეშე.

სიის API-ის არასავალდებულო `track` მოთხოვნის პარამეტრი ემთხვევა მთელ ტრეკის სახელს, რეგისტრის მიუხედავად, რაც შეესაბამება არსებულ ტრეკების შენახვას. გამოტოვეთ ის ან გაგზავნეთ ცარიელი მნიშვნელობა (`?track=`), რათამ ჩამოთვალოთ ყველა ტრეკი. ტრეკის სახელები რჩება ღია სტრიქონებად და არა ფიქსირებული მნიშვნელობების სიად. iOS აპლიკაციის **ყველა ტრეკი** შერჩევა ტოვებს ფილტრს. iOS აპლიკაციის ტრეკის ღილაკები ტვირთავს სრულ პროექტის შეჯამებას `GET /api/projects/:account_handle/:project_handle/previews/tracks`-დან, იგივე პრევიუს წაკითხვის ავტორიზაციით, რაც ბილდების ჩამოთვლისას. ეს endpoint აბრუნებს `{total_count, tracks: [{name, count}]}`-ს დალაგებული, რეგისტრის მიუხედავად დაჯგუფებული სახელიანი ტრეკებით. რაოდენობები მოიცავს მთელ პროექტს პაგინაციის, ძებნის და შერჩეული ტრეკისგან დამოუკიდებლად; ჯამში შედის არატრეკირებული პრევიუები. ითვლება მხოლოდ ჩამოსათვლელი პრევიუები bundle identifier-ით. სიის API ასევე იღებს არასავალდებულო `search`-ს საჩვენებელი სახელის ან სრული გამოშვების შენიშვნების ლიტერალური, რეგისტრის მიუხედავად ქვესტრიქონისთვის, რაც ერწყმის ტრეკს პაგინაციამდე. არსებული `display_name` ფილტრაცია რჩება ზუსტი.

ძველ კლიენტებს შეუძლიათ განაგრძონ პრევიუების ატვირთვა და ჩამოთვლა ორივე ველის გაგზავნის გარეშე. ახალი კლიენტები იღებენ უფრო ძველ პასუხებს, რომლებიც ტოვებენ ტრეკს ან შენიშვნებს და იგნორირებენ მომავალი სერვერების მიერ დამატებულ უცნობ პასუხის თვისებებს. API ინტეგრაციებმა ასევე უნდა დაიგნორონ უცნობი პასუხის თვისებები, რათა დამატებითი მეტამონაცემები დარჩეს თავსებადი.

თვითმასპინძელ განლაგებებს სჭირდებათ სერვერის ვერსია, რომელიც მხარს უჭერს გამოშვების შენიშვნებს და ტრეკის ფილტრაციას, განახლებულ CLI-თან და აპთან ერთად, ამ ფუნქციების გამოყენებისთვის. უფრო ძველ სერვერებს შეუძლიათ დაიგნორონ შენიშვნები ან უცნობი მოთხოვნის პარამეტრები. თუ ტრეკის აღმოჩენა ხელმისაწვდომი არ არის, iOS აპლიკაცია ინარჩუნებს გაუფილტრავ ბრაუზინგს და ხსნის, რომ ტრეკის შერჩევა განახლებულ სერვერს მოითხოვს. თუ სერვერი აბრუნებს პრევიუებს სხვა ტრეკიდან აქტიური ფილტრის მიუხედავად, iOS აპლიკაცია იუწყება, რომ ფილტრაცია მხარდაჭერილი არ არის, ნაცვლად შეცდომაში შემყვანი შედეგების წარმოდგენისა. macOS აპლიკაცია ჯერ ითხოვს უახლეს თავსებად პრევიუს თითოეული აპისთვის; უფრო ძველ სერვერებზე, რომლებიც შერჩევენ განსხვავებულ აპებს პლატფორმის ფილტრების გამოყენებამდე, ის ბრუნდება პაგინირებულ ისტორიაზე ისეთი შეზღუდვის დაწესების გარეშე, რომელმაც შეიძლება დამალოს ხელმისაწვდომი ბილდი.

## Tuist macOS აპლიკაცია {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist Previews-ის გაშვების კიდევ უფრო გასამარტივებლად, შევქმენით Tuist macOS მენიუს ზოლის აპლიკაცია. Previews-ის Tuist CLI-ით გაშვების ნაცვლად, შეგიძლიათ [ჩამოტვირთოთ](https://tuist.dev/download) macOS აპლიკაცია. ასევე შეგიძლიათ დააინსტალიროთ აპლიკაცია `brew install --cask tuist/tuist/tuist`-ის გაშვებით.

როდესაც პრევიუს გვერდზე დააწკაპუნებთ „გაშვება“-ს, macOS აპლიკაცია ავტომატურად გაუშვებს მას თქვენს მიმდინარე შერჩეულ მოწყობილობაზე.

## Tuist iOS აპლიკაცია {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="ჩამოტვირთვა App Store-დან" style="height: 40px;">
    </a>
</div>

macOS აპლიკაციის მსგავსად, Tuist iOS აპლიკაცია ამარტივებს თქვენი პრევიუების წვდომას და გაშვებას. თითოეული პრევიუ აჩვენებს თავის ტრეკს. გამოიყენეთ ძებნის ველი აპის სახელით პრევიუების საპოვნელად, შემდეგ აირჩიეთ ღილაკი **ტრეკები**-ის ქვეშ გარემოს მიხედვით ფილტრაციისთვის. შერჩეული ღილაკი იქნება იისფერი; აირჩიეთ **ყველა** ტრეკის ფილტრის მოსახსნელად. თითოეული ღილაკი აჩვენებს პროექტის მასშტაბით პრევიუების რაოდენობას, ხოლო „ყველა“ მოიცავს ბილდებს ტრეკის გარეშე. ძებნა და ტრეკის ფილტრაცია ვრცელდება ყველა გვერდზე, არა მხოლოდ უკვე ჩატვირთულ პრევიუებზე. თითოეული ბილდის ტრეკის ნიშანი მდებარეობს მისი კომიტის ჰეშის გვერდით.

## Pull/merge request კომენტარები {#pullmerge-request-comments}

> [!WARNING]
> **Git პლატფორმასთან ინტეგრაცია სავალდებულოა**
>
> ავტომატური pull/merge request კომენტარების მისაღებად, შეაერთეთ თქვენი <.localized_link href="/guides/server/accounts-and-projects">დაშორებული პროექტი</.localized_link> <.localized_link href="/guides/server/authentication">Git პლატფორმასთან</.localized_link>.

ახალი ფუნქციონალის ტესტირება უნდა იყოს ნებისმიერი კოდის გადახედვის ნაწილი. მაგრამ აპის ადგილობრივად აგება ზედმეტ სირთულეს ქმნის, რაც ხშირად იწვევს იმას, რომ დეველოპერები საერთოდ ტოვებენ მოწყობილობაზე ფუნქციონალის ტესტირებას. მაგრამ *რა მოხდებოდა, თუ ყოველ pull request-ს ექნებოდა ბილდის ბმული, რომელიც ავტომატურად გაუშვებდა აპს თქვენს მიერ Tuist macOS აპში შერჩეულ მოწყობილობაზე?*

როგორც კი თქვენი Tuist პროექტი დაკავშირდება თქვენს Git პლატფორმასთან, როგორიცაა [GitHub](https://github.com), დაამატეთ <.localized_link href="/cli/share">`tuist share MyApp`</.localized_link> თქვენს CI სამუშაო ნაკადში. Tuist შემდეგ პირდაპირ თქვენს pull request-ებში განათავსებს პრევიუს ბმულს: ![GitHub აპის კომენტარი Tuist Preview ბმულით](/images/guides/features/github-app-with-preview.png)

## აპში განახლების შეტყობინებები {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) საშუალებას აძლევს თქვენს აპს აღმოაჩინოს, როდესაც ხელმისაწვდომია პრევიუს უფრო ახალი ვერსია და აცნობოს მომხმარებლებს. ეს სასარგებლოა ტესტერების უახლეს ბილდზე შესანარჩუნებლად.

SDK ამოწმებს განახლებებს იმავე **პრევიუს ტრეკში**. როდესაც პრევიუს აზიარებთ ცალსახა ტრეკით `--track`-ის გამოყენებით, SDK მოძებნის განახლებებს ამ ტრეკზე. თუ ტრეკი მითითებული არ არის, git განშტოება გამოიყენება როგორც ტრეკი — ასე რომ, `main` განშტოებიდან აგებული პრევიუ მხოლოდ `main`-დან აგებულ უფრო ახალ პრევიუებზე შეატყობინებს.

### ინსტალაცია {#sdk-installation}

დაამატეთ Tuist SDK როგორც Swift Package დამოკიდებულება:

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
> განახლების შემოწმება ავტომატურად გამორთულია სიმულატორებზე და App Store ბილდებში.

## README ბეჯი {#readme-badge}

Tuist Previews-ის თქვენს რეპოზიტორიაში უფრო შესამჩნევად გასახდელად, შეგიძლიათ დაამატოთ ბეჯი თქვენს `README` ფაილში, რომელიც მიუთითებს უახლეს Tuist Preview-ზე:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

ბეჯის თქვენს `README`-ში დასამატებლად, გამოიყენეთ შემდეგი markdown და ჩაანაცვლეთ ანგარიშისა და პროექტის სახელები თქვენით:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

თუ თქვენი პროექტი შეიცავს რამდენიმე აპს განსხვავებული bundle იდენტიფიკატორებით, შეგიძლიათ მიუთითოთ, რომელი აპის პრევიუს ბმული გსურთ `bundle-id` მოთხოვნის პარამეტრის დამატებით:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## ავტომატიზაციები {#automations}

შეგიძლიათ გამოიყენოთ `--json` ფლაგი `tuist share` ბრძანებიდან JSON გამოტანის მისაღებად:
```
tuist share --json
```

JSON გამოტანა სასარგებლოა მორგებული ავტომატიზაციების შესაქმნელად, მაგალითად, Slack-ში შეტყობინების გაგზავნისთვის თქვენი CI პროვაიდერის გამოყენებით. JSON შეიცავს `url` გასაღებს სრული პრევიუს ბმულით და `qrCodeURL` გასაღებს QR კოდის გამოსახულების URL-ით, რაც აადვილებს პრევიუების ჩამოტვირთვას რეალური მოწყობილობიდან. JSON გამოტანის მაგალითი მოცემულია ქვემოთ:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
