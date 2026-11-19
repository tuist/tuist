---
{
  "title": "არასტაბილური ტესტები",
  "titleTemplate": ":title · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ავტომატურად აღმოაჩინეთ და თვალყური ადევნეთ არასტაბილურ ტესტებს თქვენს CI მილსადენებში."
}
---
# არასტაბილური ტესტები {#flaky-tests}

არასტაბილური ტესტები არის ტესტები, რომლებიც ერთი და იგივე კოდის რამდენიმეჯერ გაშვებისას განსხვავებულ შედეგებს (წარმატება ან ჩავარდნა) აჩვენებენ. ისინი ამცირებენ ნდობას თქვენი ტესტების ნაკრადის მიმართ და ფუჭად ხარჯავენ დეველოპერების დროს ცრუ ჩავარდნების გამოძიებაზე. Tuist ავტომატურად აღმოაჩენს არასტაბილურ ტესტებს და გეხმარებათ მათ თვალყურის დევნაში დროთა განმავლობაში. იმის შესახებ, თუ როგორ გამოიძიოთ და შეზღუდოთ ისინი გუნდურად, იხილეთ [არასტაბილური ტესტები](https://tuist.dev/solutions/flaky-tests). ხელსაწყოსგან დამოუკიდებელი ახსნისთვის, თუ რა არის ჩვეულებრივი მიზეზები და როგორ უნდა გაზომოთ არასტაბილურობა, იხილეთ <.localized_link href="/references/concepts/flaky-test">რა არის არასტაბილური ტესტი?</.localized_link>.

<.home_cards>
  <.home_card
    title="Xcode"
    details="აღმოაჩინეთ, მართეთ და იზოლირეთ არასტაბილური ტესტები Xcode პროექტებში tuist xcodebuild test-ის საშუალებით."
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="აღმოაჩინეთ, მართეთ და იზოლირეთ არასტაბილური ტესტები Tuist-ის მიერ გენერირებულ პროექტებში tuist test-ის საშუალებით."
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="აღმოაჩინეთ და მართეთ არასტაბილური ტესტები Gradle პროექტებში."
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="აღმოაჩინეთ, დააყუჩეთ და გამოტოვეთ არასტაბილური Bazel ტესტის შემთხვევები tuist bazel test-ის საშუალებით."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="აღმოაჩინეთ და მართეთ არასტაბილური ტესტები Elixir პროექტებში ტესტების ხელახალი გაშვების მექანიზმით."
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="აღმოაჩინეთ და გამოიძიეთ არასტაბილური Cargo ტესტები CI გაშვებების შედეგების გამოყენებით."
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Once"
    details="გამოიძიეთ არათანმიმდევრული ტესტის შედეგები შეტყობინებული ხელახალი ცდების და CI ისტორიის მეშვეობით."
    link="/guides/features/test-insights/flaky-tests/once"
/>
</.home_cards>
