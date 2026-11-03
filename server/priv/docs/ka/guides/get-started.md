---
{
  "title": "დაიწყეთ",
  "titleTemplate": ":title · დაიწყეთ · სახელმძღვანელოები · Tuist",
  "description": "აირჩიეთ Tuist-ის გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგების მეთოდს: Xcode, გენერირებული Xcode პროექტები, Gradle, Elixir, Rust ან Bazel."
}
---
# დაიწყეთ {#get-started}

აირჩიეთ გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგების წესს. თითოეული მათგანი გაგივლით იმას, თუ რა უნდა დააინსტალიროთ, როგორ ჩართოთ ქეშირების, ინსაიტებისა და ტესტირების ფუნქციები და როგორ შეამოწმოთ კონფიგურაცია ბოლომდე. შეგიძლიათ მიიღოთ ისინი დამოუკიდებლად ან გააერთიანოთ, თუ პროგრამულ უზრუნველყოფას ერთზე მეტ პლატფორმაზე აგზავნით.

## Xcode-ის პროექტი {#existing-xcode-project}

შეინარჩუნეთ არსებული Xcode-ის პროექტი ან სამუშაო სივრცე და დაამატეთ Tuist-ის შესაძლებლობები ერთ-ერთი. პროექტის გენერაცია არ არის საჭირო.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## გენერირებული Xcode-ის პროექტი {#generated-xcode-project}

მიეცით Tuist-ს თქვენი Xcode-ის პროექტის განსაზღვრისა და გენერირების უფლება Swift-ის მანიფესტებიდან. გენერირებული პროექტები ამოდ კომპლექსურობას მოდულური Xcode-ის პროექტებიდან და გადააქვთ ის გრაფის ლაკონურ, დეკლარატიულ აღწერაში; ისინი მკაცრად აუცილებელია <.localized_link href="/guides/features/cache/module-cache">მოდიულის ქეშის</.localized_link> და <.localized_link href="/guides/features/selective-testing/generated-xcode-project">შერჩევითი ტესტირებისთვის</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle-ის პროექტი {#gradle-project}

დააკავშირეთ Gradle-ის პროექტი Tuist-ის დისტანციურ ქეშთან, აგების ინსაიტებთან და ტესტების ინსაიტებთან `dev.tuist` Gradle-ის პლაგინის მეშვეობით.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir-ის პროექტი {#elixir-project}

დააკავშირეთ Elixir-ის პროექტი Tuist-ის აგების ინსაიტებთან, ტესტების ინსაიტებთან, არასტაბილური ტესტების აღმოჩენასთან და ტესტების შარდინგთან `tuist_ex` Hex-ის პაკეტის მეშვეობით.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust-ის პროექტი {#rust-project}

გაუშვით Cargo Tuist CLI-ის მეშვეობით, რათა შეატყობინოთ აგებები და ცალკეული ტესტების შედეგები, doctests-ის ჩათვლით, და გამოიკვლიოთ არასტაბილური ტესტები.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel-ის პროექტი {#bazel-project}

მიმართეთ Bazel-ის სამუშაო სივრცე Tuist-ის Remote Execution API-ის ქეშსა და Build Event Service-ზე, რათა გააზიაროთ ქეშის მოხვედრები და ინსაიტები თქვენს გუნდსა და CI-ში.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

ამ ნაბიჯებამდე, <.localized_link href="/guides/install-tuist">დააინსტალირეთ Tuist-ის კომანდური ხაზის ინტერფეისი</.localized_link>. გამონაკლისია Elixir-ის პროექტები: მათ მხოლოდ Hex-ის პაკეტი სჭირდებათ.
