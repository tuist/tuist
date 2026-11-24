---
{
  "title": "Tuist-ის გამოყენება Swift Package-თან ერთად",
  "titleTemplate": ":title · ინტეგრაცია · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist Swift Package-თან ერთად."
}
---
# Tuist-ის გამოყენება Swift პაკეტთან <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist მხარდაჭერას უწევს `Package.swift`-ის გამოყენებას თქვენი პროექტების DSL-ად და გარდაქმნის თქვენს პაკეტის მიზნებს ნატიურ Xcode პროექტად და მიზნებად.

> [!WARNING]
> ამ ფუნქციის მიზანია დეველოპერებს მარტივად შეაფასებინოს Tuist-ის დანერგვის გავლენა მათ Swift პაკეტებში. შესაბამისად, ჩვენ არ ვგეგმავთ Swift Package Manager-ის ყველა ფუნქციის მხარდაჭერას ან Tuist-ის ყველა უნიკალური ფუნქციის, მაგალითად <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარე საშუალებები</.localized_link>, პაკეტების სამყაროში გადმოტანას.


> [!NOTE]
> **ძირითადი დირექტორია**
>
> Tuist ბრძანებები ელიან კონკრეტულ <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">დირექტორიების სტრუქტურას</.localized_link>, რომლის ძირიც იდენტიფიცირდება `Tuist` ან `.git` დირექტორიით.


## Tuist-ის გამოყენება Swift პაკეტთან {#using-tuist-with-a-swift-package}

ჩვენ გამოვიყენებთ Tuist-ს [TootSDK პაკეტის](https://github.com/TootSDK/TootSDK) რეპოზიტორიასთან, რომელიც შეიცავს Swift პაკეტს. პირველი, რაც უნდა გავაკეთოთ, არის რეპოზიტორიის კლონირება:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

რეპოზიტორიის დირექტორიაში გადასვლის შემდეგ, უნდა დავაინსტალიროთ Swift Package Manager-ის დამოკიდებულებები:

```bash
tuist install
```

შიგნით `tuist install` იყენებს Swift Package Manager-ს პაკეტის დამოკიდებულებების გადასაწყვეტად და ჩამოსატვირთად. გადაწყვეტის დასრულების შემდეგ, შეგიძლიათ დააგენერიროთ პროექტი:

```bash
tuist generate
```

ვაილა! გაქვთ ნატიური Xcode პროექტი, რომელიც შეგიძლიათ გახსნათ და მუშაობა დაიწყოთ.
