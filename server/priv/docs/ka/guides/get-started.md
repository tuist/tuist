---
{
  "title": "დაწყება",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "აირჩიეთ Tuist-ის გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგების წესს: Xcode, გენერირებული Xcode პროექტები, Gradle, Elixir, Rust, Bazel ან Struo."
}
---
# დაწყება {#get-started}

აირჩიეთ გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგების წესს. თითოეული მათგანი გაგივლით ინსტალაციის ნაბიჯებს, კეშირების, ანალიტიკის და ტესტირების ფუნქციების ჩართვის წესებს, ასევე სრულად შემოწმების პროცესს. შეგიძლიათ ისინი დამოუკიდებლად გამოიყენოთ, ან გააერთიანოთ, თუ ერთზე მეტ პლატფორმაზე ახდენთ პროდუქტის მიწოდებას.

უმეტესი გზა იყენებს <.localized_link href="/guides/install-tuist">Tuist-ის ბრძანების ხაზის ინტერფეისს</.localized_link>. Elixir იყენებს Hex პაკეტს, ხოლო Struo უკავშირდება თავისი საკუთარი Tuist პროვაიდერის მეშვეობით; არცერთ მათგანს არ სჭირდება Tuist CLI ინტეგრაციისთვის.

## Xcode-ის პროექტი {#existing-xcode-project}

შეინარჩუნეთ თქვენი არსებული Xcode-ის პროექტი ან სამუშაო სივრცე და დაამატეთ Tuist-ის შესაძლებლობები ეტაპობრივად. პროექტის გენერაცია არ არის საჭირო.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## გენერირებული Xcode-ის პროექტი {#generated-xcode-project}

მიეცით Tuist-ს საშუალება განსაზღვროს და შექმნას თქვენი Xcode-ის პროექტი Swift მანიფესტებიდან. გენერირებული პროექტები ამცირებენ მოდულური Xcode-ის პროექტების სირთულეს გრაფის მოკლე, დეკლარატიულ აღწერამდე და არის მკაცრი მოთხოვნა <.localized_link href="/guides/features/cache/module-cache">მოდულის კეშის</.localized_link> და <.localized_link href="/guides/features/selective-testing/generated-xcode-project">შერჩევითი ტესტირებისთვის</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle-ის პროექტი {#gradle-project}

დააკავშირეთ Gradle-ის პროექტი Tuist-ის დისტანციურ კეშთან, აგების ანალიტიკასთან და ტესტების ანალიტიკასთან `dev.tuist` Gradle პლაგინის მეშვეობით.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir-ის პროექტი {#elixir-project}

დააკავშირეთ Elixir-ის პროექტი Tuist-ის აგების ანალიტიკასთან, ტესტების ანალიტიკასთან, არასტაბილური ტესტების აღმოჩენასთან და ტესტების შარდინგთან `tuist_ex` Hex პაკეტის მეშვეობით.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust-ის პროექტი {#rust-project}

გაუშვით Cargo Tuist CLI-ის მეშვეობით, რათა გადასცეთ აგების და ცალკეული ტესტების შედეგები, doctests-ის ჩათვლით, და გამოიკვლიოთ არასტაბილური ტესტები.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel-ის პროექტი {#bazel-project}

მიმართეთ Bazel-ის სამუშაო სივრცე Tuist-ის Remote Execution API კეშისა და Build Event Service-ისკენ, რათა გაუზიაროთ კეშის მოხვედრები და ანალიტიკა თქვენს გუნდსა და CI-ს.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Struo-ს პროექტი {#struo-project}

<a id="once-project"></a>

დააკავშირეთ Struo-ს კეშირებადი სკრიპტები და აგების გრაფები Tuist-თან საერთო კეშირების, აგებისა და ტესტების ცოცხალი ანალიტიკის, ჰოსტინგზე განთავსებული ტესტების შარდინგისა და აპლიკაციის პრევიუსებისთვის.

<.localized_link href="/guides/get-started/struo-project">Start with a Struo project →</.localized_link>
