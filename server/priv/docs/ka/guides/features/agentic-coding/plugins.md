---
{
  "title": "პლაგინები",
  "titleTemplate": ":title · Agentic coding · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "დააყენეთ Tuist-ის პლაგინი Cursor-ისთვის ან მომწოდებლისგან დამოუკიდებელი Agent Plugins პაკეტი."
}
---

# პლაგინები

Tuist თავის აგენტურ უნარებსა და ჰოსტინგულ MCP სერვერს პლაგინებად აწვდის, რათა ორივე ერთად დააყენოთ. აირჩიეთ პაკეტი, რომელიც შეესაბამება თქვენს კოდირების აგენტს.

## Claude Code

[Tuist Claude Code-ის მარკეტფლეისი](https://github.com/tuist/claude-plugin) Tuist-ის პლაგინს აწვდის შემდეგი ბრძანებებით დასაყენებლად:

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

პლაგინი უზრუნველყოფს Tuist-ის უნარებს და აკავშირებს Claude Code-ს ჰოსტინგულ MCP სერვერთან.

## Cursor

დააყენეთ [Tuist-ის პლაგინი Cursor-ისთვის](https://github.com/tuist/cursor-plugin) [Cursor-ის მარკეტფლეისიდან](https://cursor.com/marketplace):

1. გახსენით **Customize** Cursor-ის გვერდითა პანელში.
2. მოძებნეთ **Tuist**.
3. აირჩიეთ **Install**, შემდეგ გადაწყვიტეთ, დააყენოთ ის მიმდინარე პროექტისთვის თუ თქვენი მომხმარებლის ანგარიშისთვის.

ასევე შეგიძლიათ აკრიფოთ `/add-plugin` Cursor-ში იმავე ინსტალაციის ნაკადის გასახსნელად. პლაგინი უზრუნველყოფს Tuist-ის უნარებს და აკავშირებს Cursor-ს ჰოსტინგულ MCP სერვერთან.

თუ თქვენი ორგანიზაცია მართავს Cursor-ის მარკეტფლეისებს, ჯერ შემოიტანეთ `https://github.com/tuist/cursor-plugin` მენიუდან **Settings → Plugins → Team Marketplaces → Import Marketplace**.

## სხვა კოდირების აგენტები

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin) ემორჩილება ღია, ვენდორზე დამოუკიდებელ [Agent Plugins](https://agent-plugins.org/) სტანდარტს. მიმართეთ თავსებადი კლიენტი რეპოზიტორიისკენ, კლიენტის ინსტრუქციების შესაბამისად პლაგინების დასაყენებლად ან მითითებისთვის:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

ის აყენებს Tuist-ის უნარებს და არეგისტრირებს `https://tuist.dev/mcp`-ს როგორც დაშორებულ MCP სერვერს. კლიენტებისთვის, რომლებიც ჯერ არ უჭერენ მხარს Agent Plugins-ს, ცალ-ცალკე დააყენეთ [უნარები](/guides/features/agentic-coding/skills) ან მოაწყვეთ [MCP სერვერი](/guides/features/agentic-coding/mcp).

## ავთენტიკაცია

უმეტესი უნარი იყენებს Tuist-ის ბრძანების ხაზის ინტერფეისს, ამიტომ ერთხელ გაიარეთ ავთენტიკაცია, სანამ აგენტს სთხოვთ თქვენს პროექტის მონაცემებზე წვდომას:

```bash
tuist auth login
```

ჰოსტინგული MCP სერვერი საჭიროების შემთხვევაში ითხოვს საკუთარ შესვლას. კლიენტზე დამოკიდებული მოწყობისა და ავთენტიკაციის დეტალებისთვის იხილეთ [MCP-ის სახელმძღვანელო](/guides/features/agentic-coding/mcp).
