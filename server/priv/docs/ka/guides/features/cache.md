---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize build times with Tuist Cache, including module cache, Xcode cache, Gradle cache, Bazel cache, Elixir dependency cache, and experimental Rust compilation caching."
}
---
# ქეში {#cache}

აგების არტეფაქტები არ არის გაზიარებული გარემოებს შორის, რაც გაიძულებთ ხელახლა ააწყოთ ერთი და იგივე კოდი. Tuist-ის ქეშირების ფუნქცია დისტანციურად აზიარებს არტეფაქტებს, რათა თქვენმა გუნდმა და CI-მ მიიღონ უფრო სწრაფი აგებები იმის გადაწყობის გარეშე, რაც უკვე აგებულია.

შეიტყვეთ ქეშის სამუშაო ნაკადი, რომელიც შეესაბამება თქვენს პროექტს ან განლაგების მოდელს:

<.home_cards>
  <.home_card
    title="მოდულის ქეში"
    details="ინდივიდუალური მოდულების ბინარულად ქეშირება Tuist-ით გენერირებული პროექტებისთვის. საჭიროა Tuist პროექტის გენერაცია."
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode ქეში"
    details="გააზიარეთ Xcode კომპილაციის არტეფაქტები გარემოებს შორის. მუშაობს ნებისმიერ Xcode პროექტთან, პროექტის გენერაცია არ არის საჭირო."
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle ქეში"
    details="დისტანციურად გააზიარეთ Gradle აგების ქეშის არტეფაქტები. მოიცავს აგების ინსაიტებს წარმადობის ხილვადობისთვის."
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel ქეში"
    details="მიმართეთ Bazel Tuist-ის Remote Execution API ქეშისკენ, რათა გააზიაროთ action outputs თქვენს გუნდსა და CI-ში."
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir ქეში"
    details="ჩართეთ ქეშირება მხარდაჭერილი Elixir დამოკიდებულებებისთვის და განაგრძეთ Mix-ის გამოყენება. დაათვალიერეთ ქეშის მოხვედრები და გადაცემები დაშბორდზე."
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust ქეში (ექსპერიმენტული)"
    details="ხელახლა გამოიყენეთ მხარდაჭერილი რეესტრის leaf-library გამოსავალი ლოკალურად და Kura-ს მეშვეობით. შეიტყვეთ, როგორ ჩართოთ ქეშირება და შეამოწმოთ ქეშის აქტივობა."
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="თვითმასპინძლობა"
    details="გაუშვით ქეშის კვანძები CI-თან, ოფისებთან ან რეგიონულ გამოთვლებთან ახლოს და დააკავშირეთ ისინი დაჰოსტულ ან თვითდაჰოსტულ Tuist-თან."
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **ყველაზე სწრაფი Tuist Runners-ზე**
>
> <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>-ზე, ქეში განთავსებულია runner-ის პირად ქსელზე და გაზიარებულია იმავე ქეშთან, რომელსაც თქვენი დეველოპერის მანქანები იყენებენ, ამიტომ CI ჯობები იღებენ „თბილ“ მოხვედრებს ყუთიდან ამოღებისას, ცალკე CI ქეშის გათბობის გარეშე.


## ატვირთვების შეზღუდვა CI-სთვის {#restrict-uploads-to-ci}

ანგარიშის ადმინისტრატორებს შეუძლიათ დეველოპერები მხოლოდ წაკითხვის რეჟიმში გადაიყვანონ, ხოლო CI-ს ატვირთვის უფლება მისცენ. გახსენით ანგარიშის **Cache** პარამეტრები Tuist-ში და დააყენეთ **Cache upload access** მნიშვნელობად **CI and account tokens only**. ამის შემდეგ, შესვლის სესიებით ავთენტიკირებულ წევრებს შეუძლიათ ქეშიდან ჩამოტვირთვა, მაგრამ ატვირთვები მოითხოვს CI OIDC ავთენტიკაციას ან ანგარიშის ტოკენს ქეშის ჩაწერის სკოპებით, როგორიცაა `project:cache:write` ან `ci`.

გამოიყენეთ ეს, როდესაც CI არის სანდო ქეშის მწარმოებელი და ლოკალურმა მანქანებმა მხოლოდ უნდა მოიხმარონ ქეში. პარამეტრი მოქმედებს მხოლოდ ქეშის ატვირთვის ავტორიზაციაზე.
