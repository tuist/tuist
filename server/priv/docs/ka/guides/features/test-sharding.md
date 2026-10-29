---
{
  "title": "ტესტების დაყოფა",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ ტესტები რამდენიმე CI გამშვებზე, რათა Tuist Test Sharding-ის საშუალებით დააჩქაროთ თქვენი ტესტების კრებული."
}
---
# ტესტების შარდინგი {#test-sharding}

თანამედროვე CI ჰოსტები გთავაზობენ მრავალბირთვიან გარემოებს, რაც ტესტების ნაწილობრივ პარალელიზაციას საშუალებას აძლევს. თუმცა, არსებობს სცენარები, როდესაც ერთი ჰოსტის შესაძლებლობებს უნდა გასცდეთ — მაგალითად, როცა შეზღუდული ხართ ერთდროულად გაშვებადი სიმულატორების რაოდენობით, ან როცა თქვენი ტესტების ნაკრები უბრალოდ აღემატება ერთი მანქანის შესაძლებლობებს.

ასეთ შემთხვევებში გჭირდებათ სისტემა, რომელიც ტესტებს რამდენიმე CI გამშვებზე (runner) გაანაწილებს და შედეგებს კვლავ ერთიანი ხედვის სახით შეკრებს. სწორედ ამას აკეთებს ტესტების შარდინგი.

Tuist იყენებს ისტორიულ ტესტირების დროის მონაცემებს, რათა [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem)-ის გამოყენებით ინტელექტუალურად გაანაწილოს დატვირთვა შარდებს შორის, ისე რომ თითოეული გამშვები (runner) დაახლოებით ერთდროულად დაასრულოს მუშაობა. ყველა შარდის შედეგები ავტომატურად იკრიბება <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>-ში, რაც თქვენს ტესტების ნაკრებს ყველა შარდის მიხედვით ერთიანი ხედვის სახით გაჩვენებთ.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcode-ის ტესტების შარდინგი პარალელურ CI გამშვებებზე (runners)."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="Tuist-ის მიერ გენერირებული პროექტების ტესტების შარდინგი პარალელურ CI გამშვებებზე (runners)."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle-ის ტესტების შარდინგი პარალელურ CI გამშვებებზე (runners)."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="თქვენი Elixir პროექტის ტესტების შარდინგი პარალელურ CI გამშვებებზე (runners)."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo-ს ტესტის სამიზნეების განაწილება პარალელურ CI მუშაკებზე (workers)."
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
