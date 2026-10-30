---
{
  "title": "უწყვეტი ინტეგრაცია",
  "titleTemplate": ":title · Swift · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist Registry უწყვეტი ინტეგრაციის პროცესში."
}
---
# უწყვეტი ინტეგრაცია (CI) {#continuous-integration-ci}

რეესტრი CI-ზე მუშაობს დამატებითი ავთენტიფიკაციის გარეშე. ნაგულისხმევად, არაავთენტიფიცირებული მოთხოვნები შეზღუდულია **წუთში 1,000 მოთხოვნით** თითოეულ IP მისამართზე.

თუ გჭირდებათ უფრო მაღალი ლიმიტი — **წუთში 20,000 მოთხოვნა**, შეგიძლიათ გაიაროთ ავთენტიფიკაცია `tuist registry login`-ის გაშვებით. ამისთვის საჭიროა გარემოს ცვლადის `TUIST_TOKEN` მნიშვნელობის დაყენება. პროექტის ტოკენის შესაქმნელად მიჰყევით დოკუმენტაციას <.localized_link href="/guides/server/authentication#as-a-project">აქ</.localized_link>.

> [!NOTE]
> ქვემოთ მოცემული keychain-ის კონფიგურაცია საჭიროა მხოლოდ მაშინ, თუ იყენებთ `tuist registry login`-ს უფრო მაღალი ლიმიტების მისაღებად. უმეტეს შემთხვევაში, ნაგულისხმევი არაავთენტიფიცირებული ლიმიტი საკმარისია და ეს ნაბიჯი შეგიძლიათ გამოტოვოთ.
>
> დამატებით, ახალი, წინასწარ განბლოკილი keychain-ის შექმნა საჭიროა მხოლოდ მაშინ, თუ იყენებთ პაკეტების Xcode-თან ინტეგრაციას.


ვინაიდან `tuist registry login` ინახავს სერთიფიკატებს keychain-ში, უნდა დარწმუნდეთ, რომ keychain-ზე წვდომა შესაძლებელია CI გარემოში. გაითვალისწინეთ, რომ ზოგიერთი CI პროვაიდერი ან ავტომატიზაციის ხელსაწყო, მაგალითად [Fastlane](https://fastlane.tools/), უკვე ქმნის დროებით keychain-ს ან გთავაზობთ მისი შექმნის ჩაშენებულ გზას. თუმცა, შეგიძლიათ შექმნათ ის საკუთარი ნაბიჯის დამატებით შემდეგი კოდით:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

დარწმუნდით, რომ თქვენი ნაგულისხმევი keychain შექმნილი და განბლოკილია _მანამ, სანამ_ გაუშვებთ `tuist registry login`-ს.

### ინკრემენტული რეზოლუცია გარემოებს შორის {#incremental-resolution-across-environments}

ჩვენი რეესტრით „სუფთა“ ან „ცივი“ რეზოლუციები ოდნავ უფრო სწრაფია, და კიდევ უფრო დიდ გაუმჯობესებას მიიღებთ, თუ შენახულ დამოკიდებულებებს CI ბილდებს შორის შეინარჩუნებთ. გაითვალისწინეთ, რომ რეესტრის წყალობით, საქაღალდის ზომა, რომელიც უნდა შეინახოთ და აღადგინოთ, ბევრად უფრო მცირეა რეესტრის გარეშე მუშაობასთან შედარებით, რაც მნიშვნელოვნად ნაკლებ დროს მოითხოვს. დამოკიდებულებების ქეშირებისთვის Xcode-ის პაკეტების ნაგულისხმევი ინტეგრაციის გამოყენებისას, საუკეთესო გზაა `clonedSourcePackagesDirPath`-ის მითითება დამოკიდებულებების რეზოლუციისას `xcodebuild`-ის მეშვეობით. ეს შესაძლებელია თქვენს `Config.swift` ფაილში შემდეგი კოდის დამატებით:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

დამატებით, უნდა იპოვოთ `Package.resolved`-ის გზა. გზის მისაღებად შეგიძლიათ გაუშვათ `ls **/Package.resolved`. გზა უნდა იყოს მსგავსი: `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Swift პაკეტებისა და XcodeProj-ზე დაფუძნებული ინტეგრაციისთვის შეგიძლიათ გამოიყენოთ ნაგულისხმევი `.build` საქაღალდე, რომელიც მდებარეობს ან პროექტის ფესვში, ან `Tuist` საქაღალდეში. დარწმუნდით, რომ გზა სწორია თქვენი პაიპლაინის კონფიგურაციისას.

აქ არის GitHub Actions-ის სამუშაო ნაკადის მაგალითი დამოკიდებულებების რეზოლუციისა და ქეშირებისთვის Xcode-ის პაკეტების ნაგულისხმევი ინტეგრაციის გამოყენებისას:
```yaml
- name: Restore cache
  id: cache-restore
  uses: actions/cache/restore@v4
  with:
    path: .build
    key: ${{ runner.os }}-${{ hashFiles('App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
- name: Resolve dependencies
  if: steps.cache-restore.outputs.cache-hit != 'true'
  run: xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath .build
- name: Save cache
  id: cache-save
  uses: actions/cache/save@v4
  with:
    path: .build
    key: ${{ steps.cache-restore.outputs.cache-primary-key }}
```
