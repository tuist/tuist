---
{
  "title": "პლაგინები",
  "titleTemplate": ":title · აგენტური კოდირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "დააინსტალირეთ Tuist-ის პლაგინი Cursor-ისთვის ან მომწოდებლისგან დამოუკიდებელი Agent Plugins პაკეტი."
}
---

# პლაგინები

Tuist აგენტის უნარებსა და განთავსებულ MCP სერვერს პლაგინების სახით აერთიანებს, რათა ორივე ერთად დააყენოთ. აირჩიეთ თქვენს კოდირების აგენტთან თავსებადი პაკეტი.

## Claude Code

[Tuist Claude Code-ის ბაზრობა](https://github.com/tuist/claude-plugin) შეიცავს Tuist-ის პლაგინს დასაყენებლად შემდეგი გზით:

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

პლაგინი უზრუნველყოფს Tuist-ის უნარებს და აკავშირებს Claude Code-ს განთავსებულ MCP სერვერთან.

## Cursor

დააყენეთ [Tuist-ის პლაგინი Cursor-ისთვის](https://github.com/tuist/cursor-plugin) [Cursor-ის ბაზრობიდან](https://cursor.com/marketplace):

1. გახსენით **Customize** Cursor-ის გვერდითა პანელში.
2. მოძებნეთ **Tuist**.
3. აირჩიეთ **Install**, შემდეგ გადაწყვიტეთ, დააყენოთ ის მიმდინარე პროექტისთვის თუ თქვენი მომხმარებლის ანგარიშისთვის.

ასევე შეგიძლიათ აკრიფოთ `/add-plugin` Cursor-ში იგივე დაყენების პროცესის გასახსნელად. პლაგინი უზრუნველყოფს Tuist-ის უნარებს და აკავშირებს Cursor-ს განთავსებულ MCP სერვერთან.

თუ თქვენი ორგანიზაცია მართავს Cursor-ის ბაზრობებს, ჯერ შემოიტანეთ `https://github.com/tuist/cursor-plugin` მისამართიდან **Settings → Plugins → Team Marketplaces → Import Marketplace**.

## სხვა კოდირების აგენტები

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin) ემორჩილება ღია, ვენდორისგან დამოუკიდებელ [Agent Plugins](https://agent-plugins.org/) სტანდარტს. მიმართეთ თავსებად კლიენტს რეპოზიტორიისკენ, იმ კლიენტის ინსტრუქციების მიხედვით პლაგინების დასაყენებლად ან საქაღალდეებზე მითითებისთვის:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

ის აყენებს Tuist-ის უნარებს და არეგისტრირებს `https://tuist.dev/mcp`-ს როგორც დაშორებულ MCP სერვერს. კლიენტებისთვის, რომლებიც ჯერ არ უჭერენ მხარს Agent Plugins-ს, ცალ-ცალკე დააყენეთ [უნარები](/guides/features/agentic-coding/skills) ან მოაწყოთ [MCP სერვერი](/guides/features/agentic-coding/mcp).

## ავთენტიკაცია

უმეტესი უნარი იყენებს Tuist-ის ბრძანების ხაზის ინტერფეისს, ამიტომ ერთხელ გაიარეთ ავთენტიკაცია, სანამ აგენტს სთხოვთ თქვენს პროექტის მონაცემებზე წვდომას:

```bash
tuist auth login
```

განთავსებული MCP სერვერი საჭიროების შემთხვევაში ითხოვს საკუთარ შესვლას. კლიენტისთვის სპეციფიკური მოწყობისა და ავთენტიკაციის დეტალებისთვის იხილეთ [MCP-ის სახელმძღვანელო](/guides/features/agentic-coding/mcp).
