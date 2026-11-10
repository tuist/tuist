---
{
  "title": "ტესტების შარდინგი",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ ტესტები რამდენიმე CI გამშვებზე Tuist-ის ტესტების შარდინგით, რათა დააჩქაროთ თქვენი ტესტების ნაკრები."
}
---
# ტესტების დაყოფა {#test-sharding}

თანამედროვე CI ჰოსტები გთავაზობენ მრავალბირთვიან გარემოებს, რაც ტესტების ნაწილობრივ პარალელიზაციას საშუალებას აძლევს. თუმცა, არსებობს სიტუაციები, როდესაც ერთი ჰოსტის შესაძლებლობებს უნდა გასცდეთ — მაგალითად, როცა შეზღუდული ხართ ერთდროულად გაშვებადი სიმულატორების რაოდენობით, ან როცა თქვენი ტესტების ნაკრები უბრალოდ აღემატება ერთი მანქანის შესაძლებლობებს.

ასეთ შემთხვევებში გჭირდებათ სისტემა, რომელიც ტესტებს რამდენიმე CI გამშვებზე (runner) გაანაწილებს და შედეგებს ერთიანი ხედვის სახით შეკრებს. სწორედ ამას აკეთებს ტესტების დაყოფა.

Tuist იყენებს ტესტების შესრულების ისტორიულ მონაცემებს, რათა [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem)-ის გამოყენებით ინტელექტუალურად გაანაწილოს დატვირთვა შარდებს შორის, ისე რომ თითოეული გამშვები დაახლოებით ერთდროულად დაასრულოს მუშაობა. ყველა შარდის შედეგები ავტომატურად იკრიბება <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>-ში, რაც გაძლევთ თქვენი ტესტების ნაკრების ერთიან ხედვას ყველა შარდის მიხედვით.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcode-ის ტესტების დაყოფა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="Tuist-ის მიერ გენერირებული პროექტების ტესტების დაყოფა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle-ის ტესტების დაყოფა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="თქვენი Elixir პროექტის ტესტების დაყოფა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo-ს ტესტების სამიზნეების განაწილება პარალელურ CI მუშაკებზე."
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Once"
    details="აღმოჩენილი Once ტესტების პაკეტების განაწილება CI მუშაკებზე ჰოსტინგის გეგმით და გაერთიანებული შედეგებით."
    link="/guides/features/test-sharding/once"
/>
</.home_cards>
