---
{
  "title": "არასტაბილური ტესტები",
  "titleTemplate": ":title · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ავტომატურად აღმოაჩინეთ და თვალყური ადევნეთ არასტაბილურ ტესტებს თქვენს CI მილსადენებში."
}
---
# არასტაბილური ტესტები {#flaky-tests}

არასტაბილური ტესტები არის ტესტები, რომლებიც ერთი და იგივე კოდით რამდენჯერმე გაშვებისას განსხვავებულ შედეგებს (წარმატება ან ჩავარდნა) იძლევა. ისინი ამცირებენ ნდობას თქვენი ტესტების ნაკრადის მიმართ და ფლანგავენ დეველოპერების დროს ცრუ ჩავარდნების გამოკვლევაში. Tuist ავტომატურად აღმოაჩენს არასტაბილურ ტესტებს და გეხმარებათ მათ თვალყურის დევნაში დროთა განმავლობაში. იმის შესახებ, თუ როგორ გამოიკვლიოთ და შეზღუდოთ ისინი გუნდურად, იხილეთ [არასტაბილური ტესტები](https://tuist.dev/solutions/flaky-tests). ხელსაწყოსგან დამოუკიდებელი ახსნისთვის გავრცელებული მიზეზებისა და არასტაბილურობის გაზომვის შესახებ, იხილეთ <.localized_link href="/references/concepts/flaky-test">რა არის არასტაბილური ტესტი?</.localized_link>.

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
    details="აღმოაჩინეთ, დაამუნჯეთ და გამოტოვეთ არასტაბილური Bazel ტესტის შემთხვევები tuist bazel test-ის მეშვეობით."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="აღმოაჩინეთ და მართეთ არასტაბილური ტესტები Elixir პროექტებში ტესტების გამეორებით."
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="აღმოაჩინეთ და გამოიკვლიეთ არასტაბილური Cargo ტესტები CI გაშვებების შედეგების გამოყენებით."
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Struo"
    details="გამოიკვლიეთ არათანმიმდევრული ტესტის შედეგები შეტყობინებული გამეორების მცდელობებისა და CI ისტორიის მეშვეობით."
    link="/guides/features/test-insights/flaky-tests/struo"
/>
</.home_cards>
