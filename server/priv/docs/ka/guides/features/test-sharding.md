---
{
  "title": "ტესტების დაშლა",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ ტესტები რამდენიმე CI გამშვებზე, რათა Tuist Test Sharding-ით დააჩქაროთ თქვენი ტესტების ნაკრები."
}
---
# ტესტების შარდირება {#test-sharding}

თანამედროვე CI ჰოსტები გთავაზობენ მრავალბირთვიან გარემოებს, რომლებიც საშუალებას იძლევა ტესტების გარკვეული დონის პარალიზაციის. თუმცა, არსებობს სცენარები, როდესაც ერთი ჰოსტის შესაძლებლობებს აღემატებით — მაგალითად, როდესაც შეზღუდული ხართ სიმულატორების რაოდენობით, რომელთა ერთდროულად გაშვებაც შეგიძლიათ, ან როდესაც თქვენი ტესტების ნაკრები უბრალოდ აღემატება ერთი მანქანის შესაძლებლობებს.

ამ შემთხვევებში, გჭირდებათ სისტემა, რომელიც ტესტებს ანაწილებს მრავალ CI გამშვებზე და აჯამებს შედეგებს ერთიანი ხედვის სახით. სწორედ ამას აკეთებს ტესტების შარდირება.

Tuist იყენებს ისტორიულ ტესტების დროის მონაცემებს, რათა ინტელექტუალურად გაანაწილოს დატვირთვა შარდებს შორის [bin-packing algorithm](https://en.wikipedia.org/wiki/Bin_packing_problem)-ის გამოყენებით, ისე, რომ თითოეული გამშველი დაასრულოს მუშაობა დაახლოებით ერთდროულად. ყველა შარდიდან მიღებული შედეგები ავტომატურად იკრიბება <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>-ში, რაც გაძლევთ თქვენი ტესტების ნაკრების ერთიან ხედვას ყველა შარდის გასწვრივ. შარდირება ამცირებს რეალურ დროს, მაგრამ შეიძლება გაზარდოს მანქანური დრო; [Slow tests](https://tuist.dev/solutions/slow-tests) და [CI costs](https://tuist.dev/solutions/ci-costs) ხსნიან, თუ როგორ შეაფასოთ ეს ორი ფაქტორი.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcode ტესტების შარდირება პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="Tuist-ის მიერ გენერირებული პროექტების ტესტების შარდირება პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle ტესტების შარდირება პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="თქვენი Elixir პროექტის ტესტების შარდირება პარალელურ CI გამშვებზე."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo ტესტების სამიზნეების განაწილება პარალელურ CI მუშაკებზე."
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Once"
    details="აღმოჩენილი Once ტესტების ბათჩების განაწილება CI მუშაკებზე ჰოსტინგის გეგმით და გაერთიანებული შედეგებით."
    link="/guides/features/test-sharding/once"
/>
</.home_cards>
