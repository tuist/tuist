---
{
  "title": "შერჩევითი ტესტირება",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "Tuist Selective Testing-ის საშუალებით გაუშვით მხოლოდ თქვენი უახლესი ცვლილებებით დაზარალებული ტესტები, რათა უწყვეტი ინტეგრაციის სისტემამ უკუკავშირი წამებში მოგაწოდოთ."
}
---
# შერჩევითი ტესტირება {#selective-testing}

როგორც კი პროექტები იზრდება, ყოველ push-ზე ყველა ტესტის გაშვება აღარ არის მიზანშეწონილი. Tuist Selective Testing მკვეთრად ამცირებს ტესტირების დროს, რადგან ის უშვებს მხოლოდ იმ ტესტებს, რომლებზეც გავლენა მოახდინა ბოლო წარმატებული გაშვების შემდეგ განხორციელებულმა ცვლილებებმა, ჩვენი <.localized_link href="/guides/features/projects/hashing">ჰეშირების ალგორითმის</.localized_link> გამოყენებით.

## მხარდაჭერილი ბილდის სისტემები {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

სხვა ბილდის სისტემების მხარდაჭერა დაგეგმილია.
