---
{
  "title": "დაწყება",
  "titleTemplate": ":title · დაწყება · სახელმძღვანელოები · Tuist",
  "description": "აირჩიეთ Tuist-ის გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგებულებას: Xcode, გენერირებული Xcode პროექტები, Gradle, Elixir, Rust ან Bazel."
}
---
# დაწყება {#get-started}

აირჩიეთ გზა, რომელიც შეესაბამება იმას, თუ როგორ არის აგებული თქვენი აპლიკაცია დღეს. თითოეული მიმართულება განმარტავს, რა უნდა დააინსტალიროთ, როგორ ჩართოთ ქეშირების, ანალიტიკისა და ტესტირების ფუნქციები და როგორ შეამოწმოთ მთლიანი პროცესი ბოლომდე. შეგიძლიათ ისინი დამოუკიდებლად გამოიყენოთ ან გააერთიანოთ, თუ პროგრამულ უზრუნველყოფას ერთზე მეტ პლატფორმაზე აწვდით.

## Xcode-ის პროექტი {#existing-xcode-project}

შეინარჩუნეთ არსებული Xcode-ის პროექტი ან სამუშაო სივრცე და დაამატეთ Tuist-ის შესაძლებლობები ეტაპობრივად. პროექტის გენერაცია არ არის საჭირო.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## გენერირებული Xcode-ის პროექტი {#generated-xcode-project}

მიეცით Tuist-ს Swift-ის მანიფესტებიდან თქვენი Xcode-ის პროექტის განსაზღვრისა და გენერირების საშუალება. გენერირებული პროექტები ამოდებენ მოდულური Xcode-ის პროექტების სირთულეს და გრაფის მოკლე, დეკლარატიულ აღწერად აქცევენ; ისინი აუცილებელი წინაპირობაა <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშის</.localized_link> და <.localized_link href="/guides/features/selective-testing/generated-xcode-project">შერჩევითი ტესტირების</.localized_link> ფუნქციებისთვის.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle-ის პროექტი {#gradle-project}

დააკავშირეთ Gradle-ის პროექტი Tuist-ის დისტანციურ ქეშთან, ბილდის ანალიტიკასთან და ტესტების ანალიტიკასთან `dev.tuist` Gradle-ის პლაგინის მეშვეობით.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir-ის პროექტი {#elixir-project}

დააკავშირეთ Elixir-ის პროექტი Tuist-ის ბილდის ანალიტიკასთან, ტესტების ანალიტიკასთან, არასტაბილური ტესტების აღმოჩენასთან და ტესტების შარდინგთან `tuist_ex` Hex-ის პაკეტის მეშვეობით.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust-ის პროექტი {#rust-project}

გაუშვით Cargo Tuist CLI-ის მეშვეობით, რათა გადაგზავნოთ ბილდებისა და ცალკეული ტესტების შედეგები, doctests-ის ჩათვლით, და გამოიკვლიოთ არასტაბილური ტესტები.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel-ის პროექტი {#bazel-project}

მიმართეთ Bazel-ის სამუშაო სივრცე Tuist-ის Remote Execution API-ის ქეშსა და Build Event Service-ს, რათა გაუზიაროთ ქეშის მოხვედრები და ანალიტიკა თქვენს გუნდსა და CI-ს.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

ამ ნაბიჯებამდე, <.localized_link href="/guides/install-tuist">დააინსტალირეთ Tuist-ის კომანდური ხაზის ინტერფეისი</.localized_link>. გამონაკლისია Elixir-ის პროექტები: მათ მხოლოდ Hex-ის პაკეტი სჭირდებათ.
