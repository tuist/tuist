---
{
  "title": "Test Sharding",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Distribute tests across multiple CI runners to speed up your test suite with Tuist Test Sharding."
}
---
# ტესტების დაყოფა {#test-sharding}

თანამედროვე CI ჰოსტები გთავაზობენ მრავალბირთვიან გარემოს, რაც ტესტების გარკვეულ დონეზე პარალიზაციას საშუალებას აძლევს. თუმცა, არსებობს სცენარები, როდესაც ერთი ჰოსტის შესაძლებლობებს უნდა გასცდეთ - მაგალითად, როდესაც შეზღუდული ხართ ერთდროულად გაშვებული სიმულატორების რაოდენობით, ან როდესაც თქვენი ტესტების ნაკრები უბრალოდ აღემატება ერთი მანქანის შესაძლებლობებს.

ამ შემთხვევებში, გჭირდებათ სისტემა, რომელიც ტესტებს რამდენიმე CI გამშვებზე (runner) გაანაწილებს და შედეგებს ერთიან ხედვაში აერთიანებს. სწორედ ამას აკეთებს ტესტების დაყოფა.

Tuist იყენებს ისტორიულ ტესტირების დროის მონაცემებს, რათა ჭკვიანურად გაანაწილოს დატვირთვა ნაწილებად (shards) [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem)-ის გამოყენებით, ისე, რომ თითოეული გამშვები დაახლოებით ერთდროულად დაასრულოს მუშაობა. ყველა ნაწილის შედეგები ავტომატურად ერთიანდება <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>-ში, რაც გაძლევთ თქვენი ტესტების ნაკრების ერთიან ხედვას ყველა ნაწილის მიხედვით.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcode ტესტების დაყოფა პარალელურ CI გამშვებებზე."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="ტესტების დაყოფა Tuist-ის მიერ გენერირებულ პროექტებში პარალელურ CI გამშვებებზე."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle ტესტების დაყოფა პარალელურ CI გამშვებებზე."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="თქვენი Elixir პროექტის ტესტების დაყოფა პარალელურ CI გამშვებებზე."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo ტესტის სამიზნეების განაწილება პარალელურ CI მუშაკებზე."
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
