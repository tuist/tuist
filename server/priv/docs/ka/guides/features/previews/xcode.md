---
{
  "title": "Xcode პრევიუები",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "გაუზიარეთ აპლიკაციის პრევიუები არსებული Xcode პროექტებიდან და Tuist-ით გენერირებული პროექტებიდან."
}
---
# Xcode-ის პრევიუები

ააწყვეთ თქვენი აპლიკაცია, შემდეგ კი გამოიყენეთ `tuist share`, რათა ის თქვენს Tuist-ის პროექტში გამოაქვეყნოთ. ჯერ დააკავშირეთ თქვენი პროექტი <.localized_link href="/guides/get-started/existing-xcode-project">არსებული Xcode-ის პროექტის</.localized_link> ან <.localized_link href="/guides/get-started/generated-xcode-project">გენერირებული პროექტის</.localized_link> სახელმძღვანელოს მიხედვით.

## აწყობა და გაზიარება

Tuist-ით გენერირებული პროექტისთვის:

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

არსებული Xcode-ის პროექტისთვის:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

ჩაანაცვლეთ სქემის, პროექტის და სამუშაო სივრცის სახელები თქვენი სახელებით. Release აწყობის გასაზიარებლად, აწყობისას გამოიყენეთ `-configuration Release`, ხოლო გაზიარებისას — `--configuration Release`.

## ფიზიკური მოწყობილობები

თქვენ ხართ პასუხისმგებელი მოწყობილობის აწყობების ხელმოწერაზე ისეთი პროვიზიონინგის პროფილით, რომელიც იძლევა ინსტალაციის შესაძლებლობას მიმღების მოწყობილობაზე. ააწყვეთ მოწყობილობის დანიშნულებისამებრ სიმულატორის SDK-ის ნაცვლად:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

ასევე შეგიძლიათ გააზიაროთ უკვე ექსპორტირებული IPA:

```bash
tuist share App.ipa
```

მიმღებებს შეუძლიათ გახსნან IPA პრევიუს ბმული მათ მობილურ მოწყობილობაზე აპლიკაციის ინსტალაციისთვის. ავტორიზაცია და პროექტის პრევიუს ხილვადობა კვლავ ძალაშია.

## CI და აწყობის ნომრები

გამოიყენეთ თქვენი არსებული <.localized_link href="/guides/integrations/continuous-integration">CI ავტორიზაცია</.localized_link> და გახადეთ `CFBundleVersion` უნიკალური ყოველი ახალი აწყობისთვის. მაგალითად, გამოიყენეთ GitHub Actions-ის <code v-pre>${{ github.run_number }}</code>. იგივე ბინარული ფაილისა და აწყობის ნომრის ხელახლა ატვირთვა `tuist share`-ით ვერ მოხდება და დუბლიკატი არ შეიქმნება.

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

იხილეთ <.localized_link href="/guides/features/previews#run-a-preview">პრევიუს გაშვება</.localized_link> გამოქვეყნებული აწყობების გასაშვებად, წვდომის, ტრეკების და README ბეჯებისთვის.

<!-- @snippet: ./_tuist-share -->

მიმღებებს შეუძლიათ გამოიყენონ <.localized_link href="/guides/features/previews/run/macos">Tuist macOS აპლიკაცია</.localized_link> ან <.localized_link href="/guides/features/previews/run/ios">iPhone აპლიკაცია</.localized_link> აწყობის სისტემასთან ინტეგრაციისგან დამოუკიდებლად. iPhone-ის სახელმძღვანელო ასევე მოიცავს <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">აპლიკაციაში განახლების შეტყობინებებს</.localized_link> Tuist SDK-ით.
