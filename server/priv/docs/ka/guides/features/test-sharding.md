---
{
  "title": "Test Sharding",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Distribute tests across multiple CI runners to speed up your test suite with Tuist Test Sharding."
}
---
# ტესტების დაყოფა {#test-sharding}

თანამედროვე CI ჰოსტები გვთავაზობენ მრავალბირთვიან გარემოებს, რაც ტესტების ნაწილობრივ პარალელიზაციას საშუალებას აძლევს. თუმცა, არსებობს სცენარები, როდესაც ერთი ჰოსტის შესაძლებლობებს სჭირდება გადახედვა — მაგალითად, როდესაც შეზღუდული ხართ სიმულატორების რაოდენობით, რომელთა ერთდროულად გაშვება შეგიძლიათ, ან როდესაც თქვენი ტესტების ნაკრები უბრალოდ აღემატება ერთი მანქანის შესაძლებლობებს.

ასეთ შემთხვევებში, თქვენ გჭირდებათ სისტემა, რომელიც ტესტებს განაწილებს მრავალ CI გამშვებზე და აჯამებს შედეგებს ერთიანი ხედვის სახით. სწორედ ამას აკეთებს ტესტების დაყოფა.

Tuist იყენებს ისტორიულ ტესტირების დროის მონაცემებს, რათა ინტელექტუალურად გაანაწილოს დატვირთვა ნაწილებს შორის [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem)-ის გამოყენებით, ისე რომ თითოეული გამშვები დაახლოებით ერთდროულად დაასრულოს მუშაობა. ყველა ნაწილის შედეგები ავტომატურად იკრიბება <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>-ში, რაც გაძლევთ თქვენი ტესტების ნაკრების ერთიან ხედვას ყველა ნაწილის მიხედვით.

<.home_cards>
  <.home_card
    title="Xcode"
    details="დაყავით Xcode ტესტები პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="დაყავით ტესტები Tuist-ის მიერ გენერირებულ პროექტებში პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="დაყავით Gradle ტესტები პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="დაყავით თქვენი Elixir პროექტის ტესტები პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="გაიგეთ ტესტების დაყოფის ხელმისაწვდომობა ჩვეულებრივი Cargo ტესტების გაშვებისთვის."
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
