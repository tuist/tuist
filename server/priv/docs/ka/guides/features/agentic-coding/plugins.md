---
{
  "title": "პლაგინები",
  "titleTemplate": ":title · აგენტური კოდირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "დააინსტალირეთ Tuist-ის პლაგინი Cursor-ისთვის ან მომწოდებლისგან დამოუკიდებელი Agent Plugins პაკეტი."
}
---

# პლაგინები

Tuist აფორმებს თავის აგენტურ უნარებს და დაჰოსტებულ MCP სერვერს პლაგინებად, რათა ორივე ერთად დააყენოთ. აირჩიეთ პაკეტი, რომელიც შეესაბამება თქვენს კოდირების აგენტს.

## Claude Code

[Tuist Claude Code-ის ბაზრობა](https://github.com/tuist/claude-plugin) აფორმებს Tuist-ის პლაგინს დასაყენებლად შემდეგი ბრძანებებით:

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

პლაგინი უზრუნველყოფს Tuist-ის უნარებს და აკავშირებს Claude Code-ს დაჰოსტებულ MCP სერვერთან.

## Cursor

დააყენეთ [Tuist-ის პლაგინი Cursor-ისთვის](https://github.com/tuist/cursor-plugin) [Cursor-ის ბაზრობიდან](https://cursor.com/marketplace):

1. გახსენით **Customize** Cursor-ის გვერდითა პანელში.
2. მოძებნეთ **Tuist**.
3. აირჩიეთ **Install**, შემდეგ მიუთითეთ, გსურთ თუ არა მისი დაყენება მიმდინარე პროექტისთვის თუ თქვენი მომხმარებლის ანგარიშისთვის.

ასევე შეგიძლიათ ჩაწეროთ `/add-plugin` Cursor-ში იგივე დაყენების ნაკადის გასახსნელად. პლაგინი უზრუნველყოფს Tuist-ის უნარებს და აკავშირებს Cursor-ს დაჰოსტებულ MCP სერვერთან.

თუ თქვენი ორგანიზაცია მართავს Cursor-ის ბაზრობებს, ჯერ შემოიტანეთ `https://github.com/tuist/cursor-plugin` მისამართიდან **Settings → Plugins → Team Marketplaces → Import Marketplace**.

## სხვა კოდირების აგენტები

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin) ემორჩილება ღია, ვენდორისგან დამოუკიდებელ [Agent Plugins](https://agent-plugins.org/) სტანდარტს. მიმართეთ თავსებადი კლიენტი რეპოზიტორიისკენ, იმ კლიენტის ინსტრუქციების მიხედვით პლაგინების დასაყენებლად ან მითითებისთვის:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

ის აყენებს Tuist-ის უნარებს და რეგისტრირებს `https://tuist.dev/mcp`-ს როგორც დაშორებულ MCP სერვერს. იმ კლიენტებისთვის, რომლებიც ჯერ არ უჭერენ მხარს Agent Plugins-ს, ცალ-ცალკე დააყენეთ <.localized_link href="/guides/features/agentic-coding/skills">უნარები</.localized_link> ან დააკონფიგურირეთ <.localized_link href="/guides/features/agentic-coding/mcp">MCP სერვერი</.localized_link>.

## ავთენტიკაცია

უმეტესი უნარი იყენებს Tuist-ის ბრძანების ხაზის ინტერფეისს, ამიტომ ერთხელ გაიარეთ ავთენტიკაცია, სანამ აგენტს სთხოვთ თქვენს პროექტის მონაცემებზე წვდომას:

```bash
tuist auth login
```

დაჰოსტებული MCP სერვერი საჭიროების შემთხვევაში ითხოვს საკუთარ შესვლას. კლიენტისთვის სპეციფიკური დაყენებისა და ავთენტიკაციის დეტალებისთვის იხილეთ <.localized_link href="/guides/features/agentic-coding/mcp">MCP-ის სახელმძღვანელო</.localized_link>.
