---
{
  "title": "შერჩევითი ტესტირება",
  "titleTemplate": ":title · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით მხოლოდ ის ტესტები, რომლებზეც გავლენას ახდენს თქვენი უახლესი ცვლილებები Tuist Selective Testing-ის გამოყენებით, რათა უწყვეტი ინტეგრაცია უკუკავშირს წამებში მოგაწოდოთ."
}
---
# შერჩევითი ტესტირება {#selective-testing}

როგორც პროექტები იზრდება, ყოველ push-ზე ყველა ტესტის გაშვება აღარ არის რეალისტური. Tuist Selective Testing მკვეთრად ამცირებს ტესტირების დროს, აწარმოებს მხოლოდ იმ ტესტებს, რომლებზეც გავლენა მოახდინა ბოლო წარმატებული გაშვების შემდეგ მომხდარ ცვლილებებმა, ჩვენი <.localized_link href="/guides/features/projects/hashing">ჰეშირების ალგორითმის</.localized_link> გამოყენებით. ტესტირების დროის შემცირების სხვა გზებისთვის, როგორიცაა შარდინგი და ნელი ტესტების გამოსწორება, იხილეთ [ნელი ტესტები](https://tuist.dev/solutions/slow-tests).

## მხარდაჭერილი ბილდის სისტემები {#supported-build-systems}

- <.localized_link href="/guides/features/selective-testing/generated-xcode-project">Generated Xcode project</.localized_link>

სხვა ბილდის სისტემების მხარდაჭერა დაგეგმილია.
