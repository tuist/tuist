---
{
  "title": "Tuist-ის გამოყენება Swift Package-თან ერთად",
  "titleTemplate": ":title · ინტეგრაცია · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაიგეთ, როგორ გამოიყენოთ Tuist Swift Package-თან ერთად."
}
---
# Tuist-ის გამოყენება Swift Package-თან <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist მხარდაჭერას უწევს `Package.swift`-ის გამოყენებას თქვენი პროექტების DSL-ად და გარდაქმნის თქვენს პაკეტის სამიზნეებს ნატიურ Xcode პროექტად და სამიზნეებად.

> [!WARNING]
> ამ ფუნქციის მიზანია მარტივი გზა შესთავაზოს დეველოპერებს, რათა შეაფასონ Tuist-ის ათვისების გავლენა მათ Swift Packages-ზე. ამიტომ, არ ვგეგმავთ Swift Package Manager-ის ყველა ფუნქციის მხარდაჭერას ან Tuist-ის ყველა უნიკალური ფუნქციის, როგორიცაა <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარე საშუალებები</.localized_link>, გადატანას პაკეტების სამყაროში.


> [!NOTE]
> **ძირითადი დირექტორია**
>
> Tuist ბრძანებები ელიან კონკრეტულ <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">დირექტორიების სტრუქტურას</.localized_link>, რომლის ძირითადი დირექტორია იდენტიფიცირდება `Tuist` ან `.git` დირექტორიით.


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

შიგნით `tuist install` იყენებს Swift Package Manager-ს პაკეტის დამოკიდებულებების გადასაწყვეტად და ჩამოსატვირთად. გადაწყვეტის დასრულების შემდეგ, შეგიძლიათ შექმნათ პროექტი:

```bash
tuist generate
```

ვალია! გაქვთ ნატიური Xcode პროექტი, რომლის გახსნა და მუშაობის დაწყებაც შეგიძლიათ.
