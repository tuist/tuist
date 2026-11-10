---
{
  "title": "უწყვეტი ინტეგრაცია",
  "titleTemplate": ":title · Swift · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist Registry უწყვეტი ინტეგრაციის პროცესში."
}
---
# უწყვეტი ინტეგრაცია (CI) {#continuous-integration-ci}

რეგისტრი CI-ზე მუშაობს დამატებითი ავთენტიფიკაციის კონფიგურაციის გარეშე. ნაგულისხმევად, არაავთენტიფიცირებული მოთხოვნები შეზღუდულია **წუთში 1,000 მოთხოვნამდე** თითოეული IP მისამართისთვის.

თუ საჭიროა უფრო მაღალი ლიმიტი — **წუთში 20,000 მოთხოვნა**, შეგიძლიათ გაიაროთ ავთენტიფიკაცია `tuist registry login`-ის გაშვებით. ამისთვის აუცილებელია გარემოს ცვლადის `TUIST_TOKEN` მნიშვნელობის დაყენება. ანგარიშის ტოკენის შესაქმნელად მიჰყევით <.localized_link href="/guides/server/authentication#account-tokens">ავთენტიფიკაციის სახელმძღვანელოს</.localized_link>.

> [!NOTE]
> ქვემოთ მოცემული keychain-ის კონფიგურაცია საჭიროა მხოლოდ მაშინ, თუ იყენებთ `tuist registry login`-ს უფრო მაღალი ლიმიტების მისაღებად. უმეტეს შემთხვევაში, ნაგულისხმევი არაავთენტიფიცირებული ლიმიტი საკმარისია და ეს ნაბიჯი შეგიძლიათ გამოტოვოთ.
>
> დამატებით, ახალი წინასწარ განბლოკილი keychain-ის შექმნა საჭიროა მხოლოდ პაკეტების Xcode-თან ინტეგრაციის გამოყენებისას.


ვინაიდან `tuist registry login` სერთიფიკატებს ინახავს keychain-ში, უნდა დარწმუნდეთ, რომ keychain-ზე წვდომა შესაძლებელია CI გარემოში. გაითვალისწინეთ, რომ ზოგიერთი CI პროვაიდერი ან ავტომატიზაციის ინსტრუმენტი, როგორიცაა [Fastlane](https://fastlane.tools/), უკვე ქმნის დროებით keychain-ს ან გთავაზობთ მისი შექმნის ჩაშენებულ გზას. თუმცა, შეგიძლიათ თავადაც შექმნათ ის ქვემოთ მოცემული კოდის შემცველი კუსტომური ნაბიჯის დამატებით:
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

სუფთა/ცივი რეზოლუციები ჩვენს რეგისტრთან ოდნავ უფრო სწრაფია და კიდევ უფრო დიდ გაუმჯობესებას მიიღებთ, თუ რეზოლვირებულ დამოკიდებულებებს შეინახავთ CI ბილდებს შორის. გაითვალისწინეთ, რომ რეგისტრის წყალობით, საქაღალდის ზომა, რომელიც უნდა შეინახოთ და აღადგინოთ, ბევრად უფრო მცირეა რეგისტრის გარეშე არსებულ ვარიანტთან შედარებით, რაც მნიშვნელოვნად ნაკლებ დროს მოითხოვს. დამოკიდებულებების კეშირებისთვის Xcode-ის პაკეტების ნაგულისხმევი ინტეგრაციის გამოყენებისას, საუკეთესო გზაა კუსტომური `clonedSourcePackagesDirPath`-ის მითითება დამოკიდებულებების რეზოლუციისას `xcodebuild`-ის მეშვეობით. ეს შესაძლებელია `Tuist.swift` ფაილში ქვემოთ მოცემული კოდის დამატებით:

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

დამატებით, დაგჭირდებათ `Package.resolved`-ის ბილიკის პოვნა. ბილიკის მისაღებად შეგიძლიათ გაუშვათ `ls **/Package.resolved`. ბილიკი უნდა ჰგავდეს რაღაც ასეთს: `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Swift პაკეტებისა და XcodeProj-ზე დაფუძნებული ინტეგრაციისთვის შეგვიძლია გამოვიყენოთ ნაგულისხმევი `.build` დირექტორია, რომელიც მდებარეობს ან პროექტის ფესვში, ან `Tuist` დირექტორიაში. დარწმუნდით, რომ ბილიკი სწორია თქვენი პაიპლაინის კონფიგურაციისას.

აქ მოცემულია GitHub Actions-ის სამუშაო ნაკადის მაგალითი დამოკიდებულებების რეზოლუციისა და კეშირებისთვის Xcode-ის პაკეტების ნაგულისხმევი ინტეგრაციის გამოყენებისას:
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
