---
{
  "title": "არასტაბილური ტესტები",
  "titleTemplate": ":title · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ავტომატურად აღმოაჩინეთ და თვალყური ადევნეთ არასტაბილურ ტესტებს თქვენს CI მილებში."
}
---
# არასტაბილური ტესტები {#flaky-tests}

არასტაბილური ტესტებია ისეთი ტესტები, რომლებიც ერთი და იმავე კოდის რამდენჯერმე გაშვებისას სხვადასხვა შედეგს (წარმატებას ან ჩავარდნას) აჩვენებენ. ისინი არღვევენ ნდობას თქვენი ტესტების ნაკრადის მიმართ და ფლანგავენ დეველოპერების დროს ცრუ ჩავარდნების გამოკვლევაში. Tuist ავტომატურად აღმოაჩენს არასტაბილურ ტესტებს და გეხმარებათ მათ თვალყურის დევნაში დროთა განმავლობაში. იმის შესახებ, თუ როგორ გამოიკვლიოთ და შეზღუდოთ ისინი გუნდურად, იხილეთ [არასტაბილური ტესტები](https://tuist.dev/solutions/flaky-tests).

<.home_cards>
  <.home_card
    title="Xcode"
    details="აღმოაჩინეთ, მართეთ და იზოლირეთ არასტაბილური ტესტები Xcode პროექტებში tuist xcodebuild test-ის საშუალებით."
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="აღმოაჩინეთ, მართეთ და იზოლირეთ არასტაბილური ტესტები Tuist-ით გენერირებულ პროექტებში tuist test-ის საშუალებით."
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="აღმოაჩინეთ და მართეთ არასტაბილური ტესტები Gradle პროექტებში."
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="აღმოაჩინეთ, დააყუჩეთ და გამოტოვეთ არასტაბილური Bazel ტესტები tuist bazel test-ის საშუალებით."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="აღმოაჩინეთ და მართეთ არასტაბილური ტესტები Elixir პროექტებში ტესტების ხელახლა გაშვების მექანიზმით."
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="აღმოაჩინეთ და გამოიკვლიეთ არასტაბილური Cargo ტესტები CI გაშვებების შედეგების გამოყენებით."
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Once"
    details="გამოიკვლიეთ არათანმიმდევრული ტესტების შედეგები ნაჩვენები ხელახლა გაშვების მცდელობებისა და CI ისტორიის მეშვეობით."
    link="/guides/features/test-insights/flaky-tests/once"
/>
</.home_cards>
