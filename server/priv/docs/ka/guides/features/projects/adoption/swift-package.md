---
{
  "title": "Tuist-ის გამოყენება Swift Package-თან ერთად",
  "titleTemplate": ":title · ინტეგრაცია · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაიგეთ, როგორ გამოიყენოთ Tuist Swift Package-თან ერთად."
}
---
# Tuist-ის გამოყენება Swift Package-თან <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist მხარს უჭერს `Package.swift`-ის გამოყენებას DSL-ად თქვენი პროექტებისთვის და გარდაქმნის პაკეტის სამიზნეებს (targets) ნატიურ Xcode პროექტად და სამიზნეებად.

> [!WARNING]
> ამ ფუნქციის მიზანია დეველოპერებს მარტივად შეაფასებინოს Tuist-ის დანერგვის გავლენა მათ Swift პაკეტებზე. შესაბამისად, ჩვენ არ ვგეგმავთ Swift Package Manager-ის ყველა ფუნქციის მხარდაჭერას ან Tuist-ის უნიკალური შესაძლებლობების, მაგალითად <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარე საშუალებების</.localized_link>, პაკეტების სამყაროში გადმოტანას.


> [!NOTE]
> **ძირითადი დირექტორია**
>
> Tuist ბრძანებები მოითხოვენ კონკრეტულ <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">დირექტორიების სტრუქტურას</.localized_link>, რომლის ძირიც იდენტიფიცირდება `Tuist` ან `.git` დირექტორიით.


## Tuist-ის გამოყენება Swift Package-თან {#using-tuist-with-a-swift-package}

ჩვენ გამოვიყენებთ Tuist-ს [TootSDK Package](https://github.com/TootSDK/TootSDK) რეპოზიტორიასთან, რომელიც შეიცავს Swift Package-ს. პირველი, რაც უნდა გავაკეთოთ, არის რეპოზიტორიის კლონირება:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

რეპოზიტორიის დირექტორიაში გადასვლის შემდეგ, უნდა დავაინსტალიროთ Swift Package Manager-ის დამოკიდებულებები:

```bash
tuist install
```

შიგნით `tuist install` იყენებს Swift Package Manager-ს პაკეტის დამოკიდებულებების ამოსაცნობად და ჩამოსატვირთად. ამოცნობის დასრულების შემდეგ, შეგიძლიათ შექმნათ პროექტი:

```bash
tuist generate
```

ვუალა! გაქვთ ნატიური Xcode პროექტი, რომლის გახსნაც და მუშაობის დაწყებაც შეგიძლიათ.
