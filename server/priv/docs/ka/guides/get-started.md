---
{
  "title": "დაიწყეთ მუშაობა",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "აირჩიეთ Tuist-ის ის გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგებულებას: Xcode, გენერირებული Xcode პროექტები, Gradle, Elixir, Rust, Bazel ან Struo."
}
---
# დაწყება {#get-started}

აირჩიეთ გზა, რომელიც შეესაბამება იმას, თუ როგორ არის აგებული თქვენი აპლიკაცია დღეს. თითოეული მათგანი გადის იმაზე, თუ რა უნდა დააინსტალიროთ, როგორ ჩართოთ ქეშირების, ინსაიტებისა და ტესტირების ფუნქციები და როგორ გადაამოწმოთ კონფიგურაცია ბოლომდე. შეგიძლიათ ისინი დამოუკიდებლად გამოიყენოთ, ან გააერთიანოთ, თუ პროგრამულ უზრუნველყოფას ერთზე მეტ პლატფორმაზე ავრცელებთ.

უმეტესი გზა იყენებს <.localized_link href="/guides/install-tuist">Tuist-ის კომანდური ხაზის ინტერფეისს</.localized_link>. Elixir იყენებს Hex პაკეტს, ხოლო Struo უკავშირდება თავისი ნატიური Tuist პროვაიდერის საშუალებით; არცერთს არ სჭირდება Tuist CLI ინტეგრაციისთვის.

## Xcode-ის პროექტი {#existing-xcode-project}

შეინარჩუნეთ თქვენი არსებული Xcode-ის პროექტი ან სამუშაო სივრცე და დაამატეთ Tuist-ის შესაძლებლობები თანმიმდევრულად. პროექტის გენერაცია არ არის საჭირო.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## გენერირებული Xcode-ის პროექტი {#generated-xcode-project}

მიეცით Tuist-ს საშუალება განსაზღვროს და შექმნას თქვენი Xcode-ის პროექტი Swift მანიფესტებიდან. გენერირებული პროექტები ამცირებენ მოდულური Xcode-ის პროექტების სირთულეს გრაფის მოკლე, დეკლარატიულ აღწერამდე და წარმოადგენენ მკაცრ მოთხოვნას <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშის</.localized_link> და <.localized_link href="/guides/features/selective-testing/generated-xcode-project">შერჩევითი ტესტირების</.localized_link>თვის.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle-ის პროექტი {#gradle-project}

დაუკავშირეთ Gradle-ის პროექტი Tuist-ის დისტანციურ ქეშს, აგების ინსაიტებსა და ტესტების ინსაიტებს `dev.tuist` Gradle პლაგინის საშუალებით.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir-ის პროექტი {#elixir-project}

დაუკავშირეთ Elixir-ის პროექტი Tuist-ის აგების ინსაიტებს, ტესტების ინსაიტებს, არასტაბილური ტესტების აღმოჩენასა და ტესტების შარდირებას `tuist_ex` Hex პაკეტის საშუალებით.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust-ის პროექტი {#rust-project}

გაუშვით Cargo Tuist CLI-ის საშუალებით, რათა ანგარიშგება მოახდინოთ აგებებზე და ცალკეულ ტესტების შედეგებზე, doctests-ის ჩათვლით, და გამოიკვლიოთ არასტაბილური ტესტები.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel-ის პროექტი {#bazel-project}

მიმართეთ Bazel-ის სამუშაო სივრცე Tuist-ის Remote Execution API ქეშისა და Build Event Service-ისკენ, რათა გააზიაროთ ქეშის მოხვედრები და ინსაიტები თქვენს გუნდსა და CI-ში.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Struo-ს პროექტი {#struo-project}

<a id="once-project"></a>

დაუკავშირეთ Struo-ს ქეშირებადი სკრიპტები და აგების გრაფები Tuist-ს საერთო ქეშირების, აგებისა და ტესტების ცოცხალი ინსაიტების, ჰოსტინგზე განთავსებული ტესტების შარდირებისა და აპლიკაციის პრევიუსებისთვის.

<.localized_link href="/guides/get-started/struo-project">Start with a Struo project →</.localized_link>
