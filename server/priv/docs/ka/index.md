---
{
  "title": "რა არის Tuist?",
  "description": "ვირტუალური პლატფორმის გუნდი დეველოპერებისთვის. ააწყეთ ინფრასტრუქტურა Xcode-ის, Gradle-ის, Bazel-ის, Elixir-ისა და Rust-ისთვის ფუნქციებით, რომლებიც თითოეულ ინსტრუმენტთა ჯაჭვზეა მორგებული."
}
---

# ვირტუალური პლატფორმის გუნდი დეველოპერებისთვის, რომლებიც პროდუქტს უშვებენ

**Tuist ეხმარება გუნდებს აპლიკაციების განვითარების მასშტაბირებაში და სწრაფად გამოშვებაში**, დიდი კოდბაზების სირთულეს გარდაქმნის პროდუქტიულ გამოცდილებად, რომელიც იზრდება თქვენს გუნდთან ერთად. ის მუშაობს თქვენს მიერ უკვე გამოყენებულ ბილდ-სისტემებთან Xcode, Gradle, Bazel, Elixir და Rust პროექტებში. ხელმისაწვდომი ფუნქციები დამოკიდებულია თქვენს ინსტრუმენტებზე: Rust პროექტები იღებენ Cargo ბილდისა და ტესტების ანალიტიკას, მათ შორის doctests-ს, არასტაბილური ტესტების აღმოჩენას და ექსპერიმენტულ კომპილაციურ ქეშირებას.

დაიწყეთ <.localized_link href="/guides/install-tuist">Tuist-ის ბრძანების ხაზის ინტერფეისის</.localized_link> დაყენებით, შემდეგ გაჰყევით თქვენი ბილდ-სისტემის შესაბამის <.localized_link href="/guides/get-started">დაწყების გზას</.localized_link> .

<br/>

<.home_cards>
  <.home_card
    title="ქეში"
    details="გაუზიარეთ კომპილაციის შედეგები თქვენს გუნდსა და CI-ს. მუშაობს Xcode-ის კომპილაციურ ქეშთან, Tuist-ის მოდულის ქეშთან, Gradle-ის ბილდის ქეშთან, Bazel-ის დისტანციურ ქეშთან და Rust-ის ექსპერიმენტულ კომპილაციურ ქეშთან."
    supported_for="apple,gradle,bazel,rust"
    link="/guides/features/cache"
/>
  <.home_card
    title="ბილდისა და ტესტების ანალიტიკა"
    details="აკონტროლეთ ბილდისა და ტესტების ხანგრძლივობა, შეცდომები, არასტაბილურობა და რეგრესიები Xcode, Gradle, Bazel, Elixir და Rust პროექტებში."
    supported_for="apple,gradle,bazel,elixir,rust"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="შერჩევითი ტესტირება"
    details="გაუშვით მხოლოდ ის ტესტები, რომლებზეც ცვლილება აისახა, Xcode-სა და გენერირებულ პროექტებში, რათა უკუკავშირი წამებში მიიღოთ."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="რანერები"
    details="გაუშვით CI მართულ macOS და Linux რანერებზე, იმავე ქეშთან ახლოს, რომელსაც თქვენი დეველოპერული მანქანები იყენებენ."
    link="/guides/features/runners"
/>
  <.home_card
    title="პრივიუები"
    details="გაუზიარეთ თქვენი აპლიკაცია მყისიერად URL-ით. მაღაზიის გადახედვის დაყოვნებების გარეშე, რთული კონფიგურაციის გარეშე."
    link="/guides/features/previews"
/>
  <.home_card
    title="გენერირებული პროექტები"
    details="აღწერეთ Xcode პროექტები Swift-ში და გენერირება მოახდინეთ თანმიმდევრულად. აღმოფხვრეთ მერჯის კონფლიქტები და გახსენით მოდულის ქეში."
    link="/guides/features/projects"
/>
  <.home_card
    title="პაკეტების რეესტრი"
    details="გადაჭერით Swift პაკეტები წამებში წუთების ნაცვლად რეესტრის საშუალებით, რომელიც ეყრდნობა Tuist-ის ქეშის ქსელს."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="ბანდლის ზომა"
    details="გააანალიზეთ და შეინარჩუნეთ თქვენი აპლიკაცია მსუბუქი, რათა მომხმარებლებმა სწრაფად ჩამოტვირთონ და თქვენ შეასრულოთ მაღაზიის მოთხოვნები."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## ენდობიან გუნდები, რომლებიც მასშტაბურად უშვებენ პროდუქტს

**გუნდები [Trendyol](https://www.trendyol.com/)-ში, [Etsy](https://www.etsy.com/)-ში, [Bumble](https://bumble.com/)-ში, [Monzo](https://monzo.com/)-ში, [Bending Spoons](https://bendingspoons.com/)-ში და 100+ სხვა კომპანიაში** უფრო სწრაფად უშვებენ პროდუქტს Tuist-ის საშუალებით თავიანთ iOS და Android კოდბაზებში.
