---
{
  "title": "ტესტების დაშლა",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ ტესტები რამდენიმე CI გამშვებზე, რათა Tuist Test Sharding-ის გამოყენებით დააჩქაროთ თქვენი ტესტების ნაკრები."
}
---
# ტესტების დაყოფა {#test-sharding}

თანამედროვე CI ჰოსტები გთავაზობენ მრავალბირთვიან გარემოებს, რაც ტესტების ნაწილობრივ პარალელურად შესრულების საშუალებას იძლევა. თუმცა, არსებობს სიტუაციები, როდესაც ერთი ჰოსტის შესაძლებლობები არასაკმარისია — მაგალითად, როდესაც შეზღუდული ხართ ერთდროულად გაშვებადი სიმულატორების რაოდენობით, ან როდესაც თქვენი ტესტების ნაკრები უბრალოდ აღემატება ერთი მანქანის შესაძლებლობებს.

ასეთ შემთხვევებში საჭიროა სისტემა, რომელიც ტესტებს რამდენიმე CI გამშვებზე (runner) გაანაწილებს და შედეგებს კვლავ ერთიანი ხედვის სახით გააერთიანებს. სწორედ ამას აკეთებს ტესტების დაყოფა (sharding).

Tuist იყენებს ტესტების შესრულების ისტორიულ დროით მონაცემებს, რათა [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem)-ის გამოყენებით ინტელექტუალურად გაანაწილოს დატვირთვა შარდებს (shards) შორის, ისე რომ თითოეული გამშვები დაახლოებით ერთდროულად დაასრულოს მუშაობა. ყველა შარდის შედეგები ავტომატურად ჯამდება <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>-ში, რაც გაძლევთ თქვენი ტესტების ნაკრების ერთიან ხედვას ყველა შარდის მიხედვით. დაყოფა ამცირებს რეალურ დროს, მაგრამ შეიძლება გაზარდოს მანქანური დრო; [Slow tests](https://tuist.dev/solutions/slow-tests) და [CI costs](https://tuist.dev/solutions/ci-costs) ხსნიან, თუ როგორ შეაფასოთ ეს ორი ფაქტორი.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcode-ის ტესტების დაყოფა პარალელურ CI გამშვებებზე."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="Tuist-ის მიერ გენერირებული პროექტების ტესტების დაყოფა პარალელურ CI გამშვებებზე."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle-ის ტესტების დაყოფა პარალელურ CI გამშვებებზე."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="თქვენი Elixir პროექტის ტესტების დაყოფა პარალელურ CI გამშვებებზე."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo-ს ტესტების სამიზნეების განაწილება პარალელურ CI მუშაკებზე."
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Once"
    details="აღმოჩენილი Once-ის ტესტების პაკეტების განაწილება CI მუშაკებზე ჰოსტინგის გეგმით და გაერთიანებული შედეგებით."
    link="/guides/features/test-sharding/once"
/>
</.home_cards>
