---
{
  "title": "არასტაბილური ტესტები",
  "titleTemplate": ":title · ტესტების ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ავტომატურად აღმოაჩინეთ და თვალყური ადევნეთ არასტაბილურ ტესტებს თქვენს CI მილებში."
}
---
# არასტაბილური ტესტები {#flaky-tests}

არასტაბილური ტესტები ისეთი ტესტებია, რომლებიც ერთი და იგივე კოდის რამდენჯერმე გაშვებისას განსხვავებულ შედეგებს (წარმატება ან შეცდომა) იძლევიან. ისინი ამცირებენ ნდობას თქვენს ტესტების ნაკრებში და ფლანგავენ დეველოპერების დროს ყალბი შეცდომების გამოკვლევაზე. Tuist ავტომატურად აღმოაჩენს არასტაბილურ ტესტებს და გეხმარებათ მათი თვალყურის დევნაში დროთა განმავლობაში.

<.home_cards>
  <.home_card
    title="Xcode"
    details="აღმოაჩინეთ, მართეთ და მოათავსეთ კარანტინში Xcode პროექტებში არსებული არასტაბილური ტესტები tuist xcodebuild test-ის საშუალებით."
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="აღმოაჩინეთ, მართეთ და მოათავსეთ კარანტინში Tuist-ით გენერირებულ პროექტებში არსებული არასტაბილური ტესტები tuist test-ის საშუალებით."
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="აღმოაჩინეთ და მართეთ Gradle პროექტებში არსებული არასტაბილური ტესტები."
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="აღმოაჩინეთ, დააყუჩეთ და გამოტოვეთ Bazel-ის არასტაბილური ტესტები tuist bazel test-ის საშუალებით."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="აღმოაჩინეთ და მართეთ Elixir პროექტებში არსებული არასტაბილური ტესტები ტესტების ხელახალი გაშვების მექანიზმით."
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="აღმოაჩინეთ და გამოიკვლიეთ Cargo-ს არასტაბილური ტესტები CI-ს სხვადასხვა გაშვების შედეგების გამოყენებით."
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Once"
    details="გამოიკვლიეთ არათანმიმდევრული ტესტების შედეგები დაფიქსირებული ხელახალი ცდებისა და CI-ს ისტორიის მიხედვით."
    link="/guides/features/test-insights/flaky-tests/once"
/>
</.home_cards>
