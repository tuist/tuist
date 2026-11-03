---
{
  "title": "ტესტების შარდინგი",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ ტესტები რამდენიმე CI გამშვებზე, რათა დააჩქაროთ თქვენი ტესტების კომპლექტი Tuist-ის ტესტების შარდინგით."
}
---
# ტესტების დაშლა {#test-sharding}

თანამედროვე CI ჰოსტები გთავაზობენ მრავალბირთვიან გარემოებს, რაც ტესტების გარკვეული დონის პარალიზაციას საშუალებას აძლევს. თუმცა, არსებობს სცენარები, როდესაც ერთი ჰოსტის შესაძლებლობებს უნდა გადააჭარბოთ — მაგალითად, როდესაც შეზღუდული ხართ ერთდროულად გაშვებადი სიმულატორების რაოდენობით, ან როდესაც თქვენი ტესტების ნაკრები უბრალოდ აღემატება ერთი მანქანის შესაძლებლობებს.

ამ შემთხვევებში, გჭირდებათ სისტემა, რომელიც ტესტებს რამდენიმე CI გამშვებზე (runner) გაანაწილებს და შედეგებს კვლავ ერთიანი ხედვის სახით შეკრებს. სწორედ ამას აკეთებს ტესტების დაშლა.

Tuist იყენებს ისტორიულ ტესტირების დროის მონაცემებს, რათა [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem)-ის გამოყენებით ინტელექტუალურად გაანაწილოს დატვირთვა შარდებზე, ისე, რომ თითოეული გამშვები დაახლოებით ერთდროულად დაასრულოს მუშაობა. ყველა შარდის შედეგები ავტომატურად იკრიბება <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>-ში, რაც გაძლევთ თქვენი ტესტების ნაკრების ერთიან ხედვას ყველა შარდის მიხედვით.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcode ტესტების დაშლა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="Tuist-ის მიერ გენერირებული პროექტების ტესტების დაშლა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle ტესტების დაშლა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="თქვენი Elixir პროექტის ტესტების დაშლა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo ტესტის სამიზნეების განაწილება პარალელურ CI მუშაკებზე."
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
