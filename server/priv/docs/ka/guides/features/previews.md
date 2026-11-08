---
{
  "title": "პრევიუები",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუზიარეთ მობილური აპლიკაციები, დესკტოპის აპლიკაციები და კომანდური ხაზის ინსტრუმენტები Tuist Previews-ით, რათა გუნდის წევრებმა შეძლონ ბილდის გამოცდა მისი ლოკალურად ხელახლა აწყობის გარეშე."
}
---
# პრევიუები {#previews}

Tuist Previews საშუალებას აძლევს გუნდის წევრებს, სცადონ მობილური აპლიკაციები, დესკტოპ აპლიკაციები და კომანდური ხაზის ინსტრუმენტები ლოკალურად ხელახლა აგების გარეშე. გამოაქვეყნეთ ბილდი თქვენს Tuist პროექტში, შემდეგ გაუზიარეთ მისი პრევიუს ბმული.

## რა შეგიძლიათ იხილოთ {#what-you-can-preview}

- **მობილური აპლიკაციები:** Android APK-ები და Apple აპლიკაციის ბანდლები ან IPA ფაილები. მხარდაჭერილი მოწყობილობები, სიმულატორები და ხელმოწერის მოთხოვნები დამოკიდებულია გამოქვეყნების სამუშაო პროცესზე.
- **დესკტოპ აპლიკაციები:** macOS აპლიკაციის ბანდლები.
- **კომანდური ხაზის ინსტრუმენტები:** macOS ან Linux შესრულებადი ფაილები, ცალკე ან დამოკიდებულებებთან ერთად.

შეფუთვისა და თავსებადობის მოთხოვნებისთვის იხილეთ <.localized_link href="/guides/features/previews/types">მხარდაჭერილი ტიპები</.localized_link>. არტიფაქტის ტიპი განსაზღვრავს, სად შეუძლია პრევიუს გაშვება; ის არ განსაზღვრავს, რომელი აგების სისტემა ქმნის მას.

## პრევიუს გამოქვეყნება {#publish-a-preview}

აირჩიეთ თქვენი აგების სისტემა კონფიგურაციისა და გამოქვეყნების ბრძანებებისთვის:

<.home_cards>
  <.home_card
    title="Xcode"
    details="გაუზიარეთ აპლიკაციები არსებული Xcode პროექტებიდან ან Tuist-ით გენერირებული პროექტებიდან."
    link="/guides/features/previews/xcode"
  />
  <.home_card
    title="Gradle"
    details="გაუზიარეთ Android აპლიკაციები და ნატიური კომანდური ხაზის ინსტრუმენტები Gradle პროექტებიდან."
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="გაუზიარეთ Android აპლიკაციები, Apple აპლიკაციები და კომანდური ხაზის ინსტრუმენტები Bazel-ის დამხმარე წესებით."
    link="/guides/features/previews/bazel"
  />
  <.home_card
    title="Once"
    details="გამოაქვეყნეთ შესაბამისი Android, Apple სიმულატორისა და macOS აპლიკაციები Once-ის ნატიური არტიფაქტის პროვაიდერით."
    link="/guides/features/previews/once"
  />
</.home_cards>

თუ უკვე გაქვთ მხარდაჭერილი ბილდი, გამოიყენეთ <.localized_link href="/cli/share">`tuist share`</.localized_link> მის გამოსაქვეყნებლად აგების სისტემასთან ინტეგრაციის გარეშე. შეფუთვისა და ხელმოწერის მოთხოვნები კვლავ მოქმედებს.

## პრევიუს გაშვება {#run-a-preview}

მიმღებებს არ სჭირდებათ აგების სისტემა, რომელმაც შექმნა პრევიუ. აირჩიეთ, როგორ მიუწვდეთ თავსებად ბილდს:

<.home_cards>
  <.home_card
    title="CLI"
    details="გაუშვით მობილური აპლიკაციები, macOS აპლიკაციები და კომანდური ხაზის პრევიუები tuist run-ით."
    link="/guides/features/previews/run/cli"
  />
  <.home_card
    title="macOS აპლიკაცია"
    details="გაუშვით თავსებადი Apple პრევიუები Tuist-ის მენიუს ზოლის აპლიკაციის მეშვეობით."
    link="/guides/features/previews/run/macos"
  />
  <.home_card
    title="iPhone აპლიკაცია"
    details="იპოვეთ და მიუწვდით თქვენს Apple პრევიუებს iPhone-ზე."
    link="/guides/features/previews/run/ios"
  />
</.home_cards>

## ხილვადობა {#visibility}

პრევიუები იყენებენ პროექტის ნაგულისხმევ ხილვადობას. პირადი პრევიუები მოითხოვს ავთენტიფიკაციასა და პროექტზე წვდომას. გახადეთ პრევიუები საჯარო პროექტის პარამეტრებში მხოლოდ მაშინ, როცა ბილდის გაზიარება ნებისმიერთან არის შესაძლებელი. საჯარო ხილვადობა არ აუქმებს პლატფორმის ხელმოწერის ან მოწყობილობაზე ინსტალაციის მოთხოვნებს.

## ტრეკები {#tracks}

ტრეკები აჯგუფებენ პრევიუებს სახელდარქმეულ ჯგუფებად, მაგალითად, `beta` შიდა ტესტერებისთვის ან `nightly` ავტომატური ბილდებისთვის. მიუთითეთ ტრეკი გამოქვეყნების ბრძანებით თქვენი სამუშაო პროცესისთვის; ტრეკები იქმნება ზარმაცად პირველი გამოყენებისას. გამოიყენეთ ისინი პრევიუების მიზნობრივად დასაჯგუფებლად და Tuist დაშბორდზე ფილტრაციისთვის.

## README ბეჯი {#readme-badge}

დაამატეთ ბეჯი თქვენი რეპოზიტორიის `README`-ში, რომელიც მიუთითებს უახლეს პრევიუზე:

[![Tuist Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

შეცვალეთ ანგარიშისა და პროექტის იდენტიფიკატორები თქვენით:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

თუ პროექტი შეიცავს რამდენიმე აპლიკაციას განსხვავებული ბანდლის იდენტიფიკატორებით, დაამატეთ `bundle-id` კვერის პარამეტრი აპლიკაციის არჩევისთვის:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```
