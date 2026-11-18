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

თუ გსურთ დარწმუნდეთ, რომ რეესტრი ყოველ ჯერზე გამოიყენება დამოკიდებულებების ამოსაცნობად, უნდა განაახლოთ `dependencies` თქვენს `Package.swift` ფაილში, რათა გამოიყენოთ რეესტრის იდენტიფიკატორი URL-ის ნაცვლად.

<!-- @snippet: ./_registry-identifier -->
