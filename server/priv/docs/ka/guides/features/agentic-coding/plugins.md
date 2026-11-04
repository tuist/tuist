---
{
  "title": "პლაგინები",
  "titleTemplate": ":title · აგენტური კოდირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "დააინსტალირეთ Tuist-ის პლაგინი Cursor-ისთვის ან მომწოდებლისგან დამოუკიდებელი Agent Plugins პაკეტი."
}
---

# პლაგინები

Tuist თავის აგენტურ უნარებს და დაჰოსტულ MCP სერვერს პლაგინებად აერთიანებს, რათა ორივე ერთად დააყენოთ. აირჩიეთ პაკეტი, რომელიც შეესაბამება თქვენს კოდირების აგენტს.

## Claude Code

[Tuist Claude Code-ის მარკეტპლეისი](https://github.com/tuist/claude-plugin) აერთიანებს Tuist-ის პლაგინს დასაყენებლად შემდეგი ბრძანებებით:

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

პლაგინი უზრუნველყოფს Tuist-ის უნარებს და აკავშირებს Claude Code-ს დაჰოსტულ MCP სერვერთან.

## Cursor

დააყენეთ [Tuist-ის პლაგინი Cursor-ისთვის](https://github.com/tuist/cursor-plugin) [Cursor-ის მარკეტპლეისიდან](https://cursor.com/marketplace):

1. გახსენით **Customize** Cursor-ის გვერდითა პანელში.
2. მოძებნეთ **Tuist**.
3. აირჩიეთ **Install**, შემდეგ მიუთითეთ, გსურთ თუ არა მისი დაყენება მიმდინარე პროექტისთვის თუ თქვენი მომხმარებლის ანგარიშისთვის.

ასევე შეგიძლიათ ჩაწეროთ `/add-plugin` Cursor-ში იგივე დაყენების ნაკადის გასახსნელად. პლაგინი უზრუნველყოფს Tuist-ის უნარებს და აკავშირებს Cursor-ს დაჰოსტულ MCP სერვერთან.

თუ თქვენი ორგანიზაცია მართავს Cursor-ის მარკეტპლეისებს, ჯერ შემოიტანეთ `https://github.com/tuist/cursor-plugin` **Settings → Plugins → Team Marketplaces → Import Marketplace**-დან.

## სხვა კოდირების აგენტები

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin) ემორჩილება ღია, ვენდორ-ნეიტრალურ [Agent Plugins](https://agent-plugins.org/) სტანდარტს. მიმართეთ თავსებადი კლიენტი რეპოზიტორიისკენ, იმ კლიენტის ინსტრუქციების მიხედვით პლაგინების დირექტორიების დასაყენებლად ან მითითებისთვის:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

ის აყენებს Tuist-ის უნარებს და რეგისტრირებს `https://tuist.dev/mcp`-ს როგორც დაშორებულ MCP სერვერს. იმ კლიენტებისთვის, რომლებიც ჯერ არ უჭერენ მხარს Agent Plugins-ს, ცალ-ცალკე დააყენეთ [უნარები](/guides/features/agentic-coding/skills) ან მოაწყვეთ [MCP სერვერი](/guides/features/agentic-coding/mcp).

## ავტორიზაცია

უნარების უმეტესობა იყენებს Tuist-ის ბრძანების ხაზის ინტერფეისს, ამიტომ ერთხელ გაიარეთ ავტორიზაცია, სანამ აგენტს სთხოვთ თქვენს პროექტის მონაცემებზე წვდომას:

```bash
tuist auth login
```

დაჰოსტული MCP სერვერი საჭიროების შემთხვევაში ითხოვს საკუთარ შესვლას. კლიენტზე დამოკიდებული მოწყობისა და ავტორიზაციის დეტალებისთვის იხილეთ [MCP-ის სახელმძღვანელო](/guides/features/agentic-coding/mcp).
