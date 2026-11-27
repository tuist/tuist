---
{
  "title": "უწყვეტი ინტეგრაცია",
  "titleTemplate": ":title · Swift · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაიგეთ, როგორ გამოიყენოთ Tuist Registry უწყვეტი ინტეგრაციის პროცესში."
}
---
# უწყვეტი ინტეგრაცია (CI) {#continuous-integration-ci}

რეესტრი მუშაობს CI-ზე დამატებითი ავთენტიფიკაციის გარეშე. ნაგულისხმევად, არაავთენტიფიცირებული მოთხოვნები შეზღუდულია სიჩქარით **1,000 მოთხოვნა წუთში** თითოეულ IP მისამართზე.

თუ გჭირდებათ უფრო მაღალი ლიმიტი — **20,000 მოთხოვნა წუთში**, შეგიძლიათ გაიაროთ ავთენტიფიკაცია `tuist registry login`-ის გაშვებით. ამისთვის საჭიროა გარემოს ცვლადის `TUIST_TOKEN` მნიშვნელობის დაყენება. ანგარიშის ტოკენის შესაქმნელად მიჰყევით <.localized_link href="/guides/server/authentication#account-tokens">ავთენტიფიკაციის სახელმძღვანელოს</.localized_link>.

> [!NOTE]
> ქვემოთ მოცემული keychain-ის კონფიგურაცია საჭიროა მხოლოდ მაშინ, თუ იყენებთ `tuist registry login`-ს უფრო მაღალი სიჩქარის ლიმიტების მისაღებად. უმეტეს შემთხვევაში, ნაგულისხმევი არაავთენტიფიცირებული ლიმიტი საკმარისია და ეს ნაბიჯი შეგიძლიათ გამოტოვოთ.
>
> დამატებით, ახალი, წინასწარ განბლოკილი keychain-ის შექმნა საჭიროა მხოლოდ პაკეტების Xcode-თან ინტეგრაციის გამოყენებისას.


ვინაიდან `tuist registry login` ინახავს სერთიფიკატებს keychain-ში, უნდა დარწმუნდეთ, რომ keychain-ზე წვდომა შესაძლებელია CI გარემოში. გაითვალისწინეთ, რომ ზოგიერთი CI პროვაიდერი ან ავტომატიზაციის ინსტრუმენტი, როგორიცაა [Fastlane](https://fastlane.tools/), უკვე ქმნის დროებით keychain-ს ან გთავაზობთ მისი შექმნის ჩაშენებულ გზას. თუმცა, შეგიძლიათ შექმნათ ის საკუთარი ნაბიჯის დამატებით შემდეგი კოდით:
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

## ინკრემენტული რეზოლუცია გარემოებს შორის {#incremental-resolution-across-environments}

სუფთა/ცივი რეზოლუციები ოდნავ უფრო სწრაფია ჩვენს რეესტრთან და კიდევ უფრო დიდ გაუმჯობესებას მიიღებთ, თუ შეინახავთ რეზოლვირებულ დამოკიდებულებებს CI ბილდებს შორის. გაითვალისწინეთ, რომ რეესტრის წყალობით, საქაღალდის ზომა, რომელიც უნდა შეინახოთ და აღადგინოთ, ბევრად უფრო მცირეა, ვიდრე რეესტრის გარეშე, რაც მნიშვნელოვნად ნაკლებ დროს მოითხოვს. დამოკიდებულებების კეშირებისთვის Xcode-ის პაკეტების ნაგულისხმევი ინტეგრაციის გამოყენებისას, საუკეთესო გზაა მითითოთ საკუთარი `clonedSourcePackagesDirPath` დამოკიდებულებების რეზოლუციისას `xcodebuild`-ის მეშვეობით. ეს შეგიძლიათ გააკეთოთ შემდეგი კოდის დამატებით თქვენს `Tuist.swift` ფაილში:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
        )
    )
)
```

დამატებით, უნდა იპოვოთ `Package.resolved`-ის გზა. გზის მისაღებად შეგიძლიათ გაუშვათ `ls **/Package.resolved`. გზა უნდა იყოს მსგავსი: `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Swift პაკეტებისა და XcodeProj-ზე დაფუძნებული ინტეგრაციისთვის შეგიძლიათ გამოიყენოთ ნაგულისხმევი `.build` დირექტორია, რომელიც მდებარეობს ან პროექტის ფესვში, ან `Tuist` დირექტორიაში. დარწმუნდით, რომ გზა სწორია თქვენი პაიპლაინის კონფიგურაციისას.

აქ არის GitHub Actions-ის სამუშაო ნაკადის მაგალითი დამოკიდებულებების რეზოლუციისა და კეშირებისთვის Xcode-ის პაკეტების ნაგულისხმევი ინტეგრაციის გამოყენებისას:
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
