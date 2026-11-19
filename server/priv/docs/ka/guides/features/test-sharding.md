---
{
  "title": "ტესტების დაშლა",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ ტესტები რამდენიმე CI გამშვებზე, რათა Tuist Test Sharding-ის გამოყენებით დააჩქაროთ თქვენი ტესტების ნაკრები."
}
---
# ტესტების დაშლა {#test-sharding}

თანამედროვე CI ჰოსტები გთავაზობენ მრავალბირთვიან გარემოებს, რაც ტესტების გარკვეულ დონეზე პარალელიზაციას საშუალებას აძლევს. თუმცა, არსებობს სცენარები, როდესაც ერთი ჰოსტის შესაძლებლობებს მიღმა უნდა წახვიდეთ — მაგალითად, როდესაც შეზღუდული ხართ ერთდროულად გაშვებული სიმულატორების რაოდენობით, ან როდესაც თქვენი ტესტების ნაკრები უბრალოდ აღემატება ერთი მანქანის შესაძლებლობებს.

ასეთ შემთხვევებში, გჭირდებათ სისტემა, რომელიც ტესტებს რამდენიმე CI გამშვებზე (runner) განაწილებს და შედეგებს კვლავ ერთიანი ხედვის სახით აჯამებს. სწორედ ამას აკეთებს ტესტების დაშლა.

Tuist იყენებს ტესტების შესრულების ისტორიულ მონაცემებს, რათა ჭკვიანურად დააბალანსოს დატვირთვა შარდებს შორის [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem)-ის გამოყენებით, ისე, რომ თითოეული გამშვები დაახლოებით ერთდროულად დაასრულოს მუშაობა. ყველა შარდიდან მიღებული შედეგები ავტომატურად იკრიბება <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>-ში, რაც გაძლევთ თქვენი ტესტების ნაკრების ერთიან ხედვას ყველა შარდის მიხედვით. დაშლა ამცირებს რეალურ დროს, მაგრამ შეიძლება გაზარდოს მანქანური დრო; [Slow tests](https://tuist.dev/solutions/slow-tests) და [CI costs](https://tuist.dev/solutions/ci-costs) ხსნიან, როგორ შეაფასოთ ეს ორი ფაქტორი.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcode-ის ტესტების დაშლა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="Tuist-ის მიერ გენერირებული პროექტების ტესტების დაშლა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle-ის ტესტების დაშლა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="თქვენი Elixir პროექტის ტესტების დაშლა პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo-ს ტესტების სამიზნეების განაწილება პარალელურ CI მუშაკებზე."
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Struo"
    details="აღმოჩენილი Struo-ს ტესტების პაკეტების განაწილება CI მუშაკებზე ჰოსტინგის გეგმით და გაერთიანებული შედეგებით."
    link="/guides/features/test-sharding/struo"
/>
</.home_cards>
