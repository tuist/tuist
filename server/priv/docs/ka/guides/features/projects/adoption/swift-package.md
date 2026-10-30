---
{
  "title": "Tuist-ის გამოყენება Swift Package-თან ერთად",
  "titleTemplate": ":title · ინტეგრაცია · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist Swift Package-თან ერთად."
}
---
# Tuist-ის გამოყენება Swift Package-თან <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist მხარს უჭერს `Package.swift`-ის გამოყენებას თქვენი პროექტების DSL-ად და გარდაქმნის თქვენს პაკეტის სამიზნეებს (targets) ნატიურ Xcode პროექტად და სამიზნეებად.

> [!WARNING]
> ამ ფუნქციის მიზანია დეველოპერებს მარტივად შეაფასებინოს Tuist-ის დანერგვის გავლენა მათ Swift Package-ებზე. შესაბამისად, არ ვგეგმავთ Swift Package Manager-ის ყველა ფუნქციის მხარდაჭერას ან Tuist-ის ისეთი უნიკალური შესაძლებლობების გატანას პაკეტების სამყაროში, როგორიცაა <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარეები</.localized_link>.


> [!NOTE]
> **ძირითადი დირექტორია**
>
> Tuist ბრძანებები ელიან კონკრეტულ <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">დირექტორიების სტრუქტურას</.localized_link>, რომლის ძირიც იდენტიფიცირდება `Tuist` ან `.git` დირექტორიით.


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

შიგნით `tuist install` იყენებს Swift Package Manager-ს პაკეტის დამოკიდებულებების ამოსაცნობად და ჩამოსატანად. ამოცნობის დასრულების შემდეგ, შეგიძლიათ დააგენერიროთ პროექტი:

```bash
tuist generate
```

ვუალა! გაქვთ ნატიური Xcode პროექტი, რომლის გახსნაც და მუშაობის დაწყებაც შეგიძლიათ.
