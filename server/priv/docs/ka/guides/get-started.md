---
{
  "title": "Get started",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Pick the Tuist path that matches how your app is built today: Xcode, generated Xcode projects, Gradle, Elixir, Rust, or Bazel."
}
---
# დაიწყეთ {#get-started}

აირჩიეთ გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგების წესს. თითოეული მათგანი გაგივლით იმას, თუ რა უნდა დააინსტალიროთ, როგორ ჩართოთ ქეშირების, ინსაიტებისა და ტესტირების ფუნქციები და როგორ შეამოწმოთ კონფიგურაცია ბოლომდე. შეგიძლიათ მიიღოთ ისინი დამოუკიდებლად ან გააერთიანოთ, თუ თქვენს პროდუქტს ერთზე მეტ პლატფორმაზე ავრცელებთ.

## Xcode-ის პროექტი {#existing-xcode-project}

შეინარჩუნეთ თქვენი არსებული Xcode-ის პროექტი ან სამუშაო სივრცე და დაამატეთ Tuist-ის შესაძლებლობები ერთდროულად. პროექტის გენერაცია არ არის საჭირო.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## გენერირებული Xcode-ის პროექტი {#generated-xcode-project}

მიეცით Tuist-ს საშუალება განსაზღვროს და შექმნას თქვენი Xcode-ის პროექტი Swift-ის მანიფესტებიდან. გენერირებული პროექტები ამცირებენ მოდულური Xcode-ის პროექტების სირთულეს გრაფის მოკლე, დეკლარატიულ აღწერამდე და წარმოადგენენ მკაცრ მოთხოვნას <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშისთვის</.localized_link> და <.localized_link href="/guides/features/selective-testing/generated-xcode-project">სელექციური ტესტირებისთვის</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle-ის პროექტი {#gradle-project}

დააკავშირეთ Gradle-ის პროექტი Tuist-ის დისტანციურ ქეშთან, აგების ინსაიტებთან და ტესტირების ინსაიტებთან `dev.tuist` Gradle-ის პლაგინის მეშვეობით.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir-ის პროექტი {#elixir-project}

დააკავშირეთ Elixir-ის პროექტი Tuist-ის აგების ინსაიტებთან, ტესტირების ინსაიტებთან, ცვალებადი ტესტების აღმოჩენასა და ტესტების შარდინგთან `tuist_ex` Hex-ის პაკეტის მეშვეობით.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust-ის პროექტი {#rust-project}

გაუშვით Cargo Tuist CLI-ის მეშვეობით, რათა მოახდინოთ აგებებისა და ინდივიდუალური ტესტების შედეგების, doctests-ის ჩათვლით, შეტყობინება და გამოიკვლიოთ ცვალებადი ტესტები.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel-ის პროექტი {#bazel-project}

მიმართეთ Bazel-ის სამუშაო სივრცე Tuist-ის Remote Execution API ქეშსა და Build Event Service-ს, რათა გაუზიაროთ ქეშის მოხვედრები და ინსაიტები თქვენს გუნდსა და CI-ს.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

ამ ყველაფრის დაწყებამდე, <.localized_link href="/guides/install-tuist">დააინსტალირეთ Tuist-ის ბრძანების ხაზის ინტერფეისი</.localized_link>. Elixir-ის პროექტები არის გამონაკლისი: მათ სჭირდებათ მხოლოდ Hex-ის პაკეტი.
