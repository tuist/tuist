---
{
  "title": "Swift-პაკეტი",
  "titleTemplate": ":title · Swift · პაკეტების რეესტრები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist Registry Swift-პაკეტში."
}
---
# Swift პაკეტი {#swift-package}

თუ Swift პაკეტზე მუშაობთ, შეგიძლიათ გამოიყენოთ `--replace-scm-with-registry` ფლაგი დამოკიდებულებების რეესტრიდან ამოსაცნობად, თუ ისინი ხელმისაწვდომია:

```bash
swift package --replace-scm-with-registry resolve
```

თუ გსურთ უზრუნველყოთ, რომ რეესტრი ყოველ ჯერზე გამოყენებულ იქნას დამოკიდებულებების ამოცნობისას, `dependencies`-ში უნდა განაახლოთ `Package.swift` ფაილი, რათა URL-ის ნაცვლად რეესტრის იდენტიფიკატორი გამოიყენოთ.

<!-- @snippet: ./_registry-identifier -->
