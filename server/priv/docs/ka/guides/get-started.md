---
{
  "title": "დაწყება",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "აირჩიეთ Tuist-ის გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგების წესს: Xcode, გენერირებული Xcode პროექტები, Gradle, Elixir, Rust, Bazel ან Once."
}
---
# დაიწყეთ {#get-started}

აირჩიეთ გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგების წესს. თითოეული მათგანი გაგივლით საჭირო ინსტალაციას, კეშირების, ანალიტიკისა და ტესტირების ფუნქციების ჩართვის პროცესს, ასევე სრულად შემოწმების ეტაპებს. შეგიძლიათ ისინი დამოუკიდებლად გამოიყენოთ ან გააერთიანოთ, თუ ერთზე მეტ პლატფორმაზე ახორციელებთ განახლებების მიწოდებას.

უმეტესი გზა იყენებს <.localized_link href="/guides/install-tuist">Tuist-ის ბრძანების ხაზის ინტერფეისს</.localized_link>. Elixir იყენებს Hex-ის პაკეტს, ხოლო Once უკავშირდება თავისი ნატიური Tuist პროვაიდერის მეშვეობით; არცერთ მათგანს არ სჭირდება Tuist CLI ინტეგრაციისთვის.

## Xcode-ის პროექტი {#existing-xcode-project}

შეინარჩუნეთ თქვენი არსებული Xcode-ის პროექტი ან სამუშაო სივრცე და დაამატეთ Tuist-ის შესაძლებლობები ეტაპობრივად. პროექტის გენერაცია არ არის საჭირო.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## გენერირებული Xcode-ის პროექტი {#generated-xcode-project}

მიეცით Tuist-ს საშუალება განსაზღვროს და შექმნას თქვენი Xcode-ის პროექტი Swift მანიფესტებიდან. გენერირებული პროექტები ამცირებენ მოდულური Xcode-ის პროექტების სირთულეს გრაფის მოკლე, დეკლარატიულ აღწერამდე და წარმოადგენენ მკაცრად აუცილებელ პირობას <.localized_link href="/guides/features/cache/module-cache">მოდულის კეშის</.localized_link> და <.localized_link href="/guides/features/selective-testing/generated-xcode-project">შერჩევითი ტესტირების</.localized_link>თვის.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle-ის პროექტი {#gradle-project}

დააკავშირეთ Gradle-ის პროექტი Tuist-ის დისტანციურ კეშთან, ბილდის ანალიტიკასთან და ტესტების ანალიტიკასთან `dev.tuist` Gradle პლაგინის მეშვეობით.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir-ის პროექტი {#elixir-project}

დააკავშირეთ Elixir-ის პროექტი Tuist-ის ბილდის ანალიტიკასთან, ტესტების ანალიტიკასთან, არასტაბილური ტესტების აღმოჩენასთან და ტესტების შარდინგთან `tuist_ex` Hex პაკეტის მეშვეობით.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust-ის პროექტი {#rust-project}

გაუშვით Cargo Tuist CLI-ის მეშვეობით ბილდებისა და ცალკეული ტესტების შედეგების, მათ შორის doctests-ის, შესახებ ანგარიშგებისა და არასტაბილური ტესტების გამოსაკვლევად.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel-ის პროექტი {#bazel-project}

მიმართეთ Bazel-ის სამუშაო სივრცე Tuist-ის Remote Execution API კეშისა და Build Event Service-ისკენ, რათა გაუზიაროთ კეშის გამოყენების მაჩვენებლები და ანალიტიკა თქვენს გუნდსა და CI-ს.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Once-ის პროექტი {#once-project}

დააკავშირეთ Once-ის კეშირებადი სკრიპტები და ბილდის გრაფები Tuist-თან საერთო კეშირების, ბილდისა და ტესტების ცოცხალი ანალიტიკის, ჰოსტინგზე განთავსებული ტესტების შარდინგისა და აპლიკაციის პრევიუსებისთვის.

<.localized_link href="/guides/get-started/once-project">Start with a Once project →</.localized_link>
