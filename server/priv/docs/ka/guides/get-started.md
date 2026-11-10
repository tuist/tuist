---
{
  "title": "დაწყება",
  "titleTemplate": ":title · დაწყება · სახელმძღვანელოები · Tuist",
  "description": "აირჩიეთ Tuist-ის გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგების წესს: Xcode, გენერირებული Xcode პროექტები, Gradle, Elixir, Rust, Bazel ან Once."
}
---
# დაწყება {#get-started}

აირჩიეთ გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგების წესს. თითოეული მათგანი განმარტავს, რა უნდა დააინსტალიროთ, როგორ ჩართოთ კეშირების, ინსაიტებისა და ტესტირების ფუნქციები და როგორ გადაამოწმოთ კონფიგურაცია ბოლომდე. შეგიძლიათ მიიღოთ ისინი დამოუკიდებლად ან გააერთიანოთ, თუ პროგრამულ უზრუნველყოფას ერთზე მეტ პლატფორმაზე ავრცელებთ.

უმეტესი გზა იყენებს <.localized_link href="/guides/install-tuist">Tuist-ის ბრძანების სტრიქონის ინტერფეისს</.localized_link>. Elixir იყენებს Hex-პაკეტს, ხოლო Once უკავშირდება თავისი ნატიური Tuist-პროვაიდერის საშუალებით; არცერთ მათგანს არ სჭირდება Tuist CLI ინტეგრაციისთვის.

## Xcode-ის პროექტი {#existing-xcode-project}

შეინარჩუნეთ თქვენი არსებული Xcode-ის პროექტი ან სამუშაო სივრცე და დაამატეთ Tuist-ის შესაძლებლობები თანმიმდევრულად. პროექტის გენერაცია არ არის საჭირო.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## გენერირებული Xcode-ის პროექტი {#generated-xcode-project}

მიეცით Tuist-ს საშუალება განსაზღვროს და შექმნას თქვენი Xcode-ის პროექტი Swift-მანიფესტებიდან. გენერირებული პროექტები ამცირებენ მოდულური Xcode-ის პროექტების სირთულეს გრაფის მოკლე, დეკლარატიულ აღწერამდე და წარმოადგენენ მკაცრ მოთხოვნას <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშის</.localized_link> და <.localized_link href="/guides/features/selective-testing/generated-xcode-project">შერჩევითი ტესტირებისთვის</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle-ის პროექტი {#gradle-project}

დაუკავშირეთ Gradle-ის პროექტი Tuist-ის დისტანციურ ქეშს, ბილდის ინსაიტებსა და ტესტის ინსაიტებს `dev.tuist` Gradle-პლაგინის საშუალებით.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir-ის პროექტი {#elixir-project}

დაუკავშირეთ Elixir-ის პროექტი Tuist-ის ბილდის ინსაიტებს, ტესტის ინსაიტებს, არასტაბილური ტესტების აღმოჩენასა და ტესტების შარდინგს `tuist_ex` Hex-პაკეტის საშუალებით.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust-ის პროექტი {#rust-project}

გაუშვით Cargo Tuist CLI-ის საშუალებით ბილდებისა და ცალკეული ტესტების შედეგების, doctests-ის ჩათვლით, შესახებ ინფორმაციის გადასაცემად და არასტაბილური ტესტების გამოსაკვლევად.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel-ის პროექტი {#bazel-project}

მიმართეთ Bazel-ის სამუშაო სივრცე Tuist-ის Remote Execution API ქეშსა და Build Event Service-ს, რათა გაუზიაროთ ქეშში მოხვედრები და ინსაიტები თქვენს გუნდსა და CI-ს.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Once-ის პროექტი {#once-project}

დაუკავშირეთ Once-ის ქეშირებადი სკრიპტები და ბილდის გრაფები Tuist-ს საერთო ქეშირების, ბილდისა და ტესტების ცოცხალი ინსაიტების, ჰოსტინგზე განთავსებული ტესტების შარდინგისა და აპლიკაციის პრივიუებისთვის.

<.localized_link href="/guides/get-started/once-project">Start with a Once project →</.localized_link>
