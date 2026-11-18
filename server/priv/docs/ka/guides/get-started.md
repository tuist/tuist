---
{
  "title": "დაწყება",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "აირჩიეთ Tuist-ის გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგების წესს: Xcode, გენერირებული Xcode პროექტები, Gradle, Elixir, Rust, Bazel ან Once."
}
---
# დაიწყეთ {#get-started}

აირჩიეთ გზა, რომელიც შეესაბამება თქვენი აპლიკაციის ამჟამინდელ აგების წესს. თითოეული მათგანი გაგივლით საჭირო ინსტალაციას, კეშირების, ანალიტიკის და ტესტირების ფუნქციების ჩართვას, ასევე სრულად გამართული კონფიგურაციის შემოწმებას. შეგიძლიათ ისინი დამოუკიდებლად გამოიყენოთ ან გააერთიანოთ, თუ პროგრამულ უზრუნველყოფას ერთზე მეტ პლატფორმაზე აწვდით.

უმეტესი გზა იყენებს <.localized_link href="/guides/install-tuist">Tuist-ის ბრძანების სტრიქონის ინტერფეისს</.localized_link>. Elixir იყენებს Hex-ის პაკეტს, ხოლო Once უკავშირდება მშობლიური Tuist პროვაიდერის მეშვეობით; არცერთ მათგანს ინტეგრაციისთვის Tuist CLI არ სჭირდება.

## Xcode-ის პროექტი {#existing-xcode-project}

შეინარჩუნეთ არსებული Xcode-ის პროექტი ან სამუშაო სივრცე და დაამატეთ Tuist-ის შესაძლებლობები ეტაპობრივად. პროექტის გენერაცია არ არის საჭირო.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## გენერირებული Xcode-ის პროექტი {#generated-xcode-project}

მიეცით Tuist-ს თქვენი Xcode-ის პროექტის Swift მანიფესტებიდან განსაზღვრისა და გენერირების საშუალება. გენერირებული პროექტები ამოდენენ მოდულური Xcode-ის პროექტების სირთულეს გრაფის ლაკონურ, დეკლარატიულ აღწერაში და წარმოადგენენ მკაცრ მოთხოვნას <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშის</.localized_link> და <.localized_link href="/guides/features/selective-testing/generated-xcode-project">შერჩევითი ტესტირებისთვის</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle-ის პროექტი {#gradle-project}

დააკავშირეთ Gradle-ის პროექტი Tuist-ის დისტანციურ ქეშთან, აგების ანალიტიკასთან და ტესტების ანალიტიკასთან `dev.tuist` Gradle პლაგინის მეშვეობით.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir-ის პროექტი {#elixir-project}

დააკავშირეთ Elixir-ის პროექტი Tuist-ის აგების ანალიტიკასთან, ტესტების ანალიტიკასთან, არასტაბილური ტესტების აღმოჩენასთან და ტესტების ნაწილებად გაყოფასთან `tuist_ex` Hex პაკეტის მეშვეობით.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust-ის პროექტი {#rust-project}

გაუშვით Cargo Tuist CLI-ის მეშვეობით აგებებისა და ინდივიდუალური ტესტების შედეგების, doctests-ის ჩათვლით, მოსახსენებლად და არასტაბილური ტესტების კვლევისთვის.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel-ის პროექტი {#bazel-project}

მიმართეთ Bazel-ის სამუშაო სივრცე Tuist-ის Remote Execution API ქეშისა და Build Event Service-ისკენ, რათა გაუზიაროთ ქეშის მოხვედრები და ანალიტიკა თქვენს გუნდსა და CI-ს.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Once-ის პროექტი {#once-project}

დააკავშირეთ Once-ის ქეშირებადი სკრიპტები და აგების გრაფები Tuist-თან საერთო ქეშირების, აგებისა და ტესტების ცოცხალი ანალიტიკის, ჰოსტინგზე განთავსებული ტესტების ნაწილებად გაყოფისა და აპლიკაციის წინასწარი ჩვენებებისთვის.

<.localized_link href="/guides/get-started/once-project">Start with a Once project →</.localized_link>
