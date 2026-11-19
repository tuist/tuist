---
{
  "title": "არასტაბილური ტესტები",
  "titleTemplate": ":title · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ავტომატურად აღმოაჩინეთ და თვალყური ადევნეთ არასტაბილურ ტესტებს თქვენს CI მილებში."
}
---
# არასტაბილური ტესტები {#flaky-tests}

არასტაბილური ტესტებია ისეთი ტესტები, რომლებიც ერთი და იგივე კოდის რამდენჯერმე გაშვებისას განსხვავებულ შედეგებს (წარმატება ან ჩავარდნა) აჩვენებენ. ისინი ამცირებენ ნდობას თქვენი ტესტების ნაკრადის მიმართ და ართულებენ დეველოპერების მუშაობას ცრუ ჩავარდნების გამოკვლევის საჭიროებით. Tuist ავტომატურად აღმოაჩენს არასტაბილურ ტესტებს და გეხმარებათ მათი თვალყურის დევნაში. გუნდურად მათი გამოკვლევისა და შეკავების შესახებ იხილეთ [არასტაბილური ტესტები](https://tuist.dev/solutions/flaky-tests). ხელსაწყოსგან დამოუკიდებელი ახსნა ხშირი მიზეზებისა და არასტაბილურობის გაზომვის შესახებ იხილეთ <.localized_link href="/references/concepts/flaky-test">რა არის არასტაბილური ტესტი?</.localized_link>.

<.home_cards>
  <.home_card
    title="Xcode"
    details="აღმოაჩინეთ, მართეთ და მოათავსეთ კარანტინში არასტაბილური ტესტები Xcode პროექტებში tuist xcodebuild test-ის მეშვეობით."
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="აღმოაჩინეთ, მართეთ და მოათავსეთ კარანტინში არასტაბილური ტესტები Tuist-ით გენერირებულ პროექტებში tuist test-ის მეშვეობით."
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="აღმოაჩინეთ და მართეთ არასტაბილური ტესტები Gradle პროექტებში."
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="აღმოაჩინეთ, დაამუნჯეთ და გამოტოვეთ არასტაბილური Bazel ტესტების შემთხვევები tuist bazel test-ის მეშვეობით."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="აღმოაჩინეთ და მართეთ არასტაბილური ტესტები Elixir პროექტებში ტესტების ხელახალი გაშვების მეშვეობით."
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="აღმოაჩინეთ და გამოიკვლიეთ არასტაბილური Cargo ტესტები CI გაშვებების შედეგების გამოყენებით."
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Struo"
    details="გამოიკვლიეთ არათანმიმდევრული ტესტების შედეგები გაშვების ხელახალი ცდებისა და CI ისტორიის საფუძველზე."
    link="/guides/features/test-insights/flaky-tests/struo"
/>
</.home_cards>
