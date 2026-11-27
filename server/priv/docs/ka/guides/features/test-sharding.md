---
{
  "title": "ტესტების დაშლა",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ ტესტები რამდენიმე CI გამშვებზე, რათა ააჩქაროთ თქვენი ტესტების ნაკრები Tuist Test Sharding-ით."
}
---
# ტესტების დაშლა {#test-sharding}

თანამედროვე CI ჰოსტები გთავაზობენ მრავალბირთვიან გარემოებს, რომლებიც საშუალებას აძლევს ტესტების ნაწილობრივ პარალელიზაციას. თუმცა, არსებობს სცენარები, როდესაც ერთი ჰოსტის შესაძლებლობები არ არის საკმარისი — მაგალითად, როდესაც შეზღუდული ხართ ერთდროულად გაშვებადი სიმულატორების რაოდენობით, ან როდესაც თქვენი ტესტების ნაკრები უბრალოდ აღემატება ერთი მანქანის შესაძლებლობებს.

ასეთ შემთხვევებში გჭირდებათ სისტემა, რომელიც ტესტებს განაწილებს რამდენიმე CI გამშვებზე (runner) და აერთიანებს შედეგებს ერთიან ხედვაში. სწორედ ამას აკეთებს ტესტების დაშლა.

Tuist იყენებს ტესტების შესრულების ისტორიულ მონაცემებს, რათა ინტელექტუალურად გაანაწილოს დატვირთვა შარდებს შორის [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem)-ის გამოყენებით, ისე, რომ თითოეული გამშვები დაასრულოს მუშაობა დაახლოებით ერთსა და იმავე დროს. ყველა შარდის შედეგები ავტომატურად აგრეგირდება <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>-ში, რაც გაძლევთ თქვენი ტესტების ნაკრების ერთიან ხედვას ყველა შარდის მიხედვით. დაშლა ამცირებს რეალურ დროს, მაგრამ შეიძლება გაზარდოს მანქანური დრო; [Slow tests](https://tuist.dev/solutions/slow-tests) და [CI costs](https://tuist.dev/solutions/ci-costs) ხსნიან, როგორ შეაფასოთ ეს ორი ფაქტორი.

<.home_cards>
  <.home_card
    title="Xcode"
    details="დაყავით Xcode ტესტები პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="დაყავით Tuist-ის მიერ გენერირებული პროექტების ტესტები პარალელურ CI გამშვებზე."
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
    details="განაწილეთ Cargo ტესტის სამიზნეები პარალელურ CI მუშაკებზე."
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Struo"
    details="განაწილეთ აღმოჩენილი Struo ტესტების პაკეტები CI მუშაკებზე ჰოსტინგის გეგმით და გაერთიანებული შედეგებით."
    link="/guides/features/test-sharding/struo"
/>
</.home_cards>
