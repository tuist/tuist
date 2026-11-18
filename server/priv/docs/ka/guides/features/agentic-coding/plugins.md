---
{
  "title": "პლაგინები",
  "titleTemplate": ":title · აგენტური კოდირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "დააინსტალირეთ Tuist-ის პლაგინი Cursor-ისთვის ან მომწოდებლისგან დამოუკიდებელი Agent Plugins პაკეტი."
}
---

# პლაგინები

Tuist თავის აგენტურ უნარებსა და განთავსებულ MCP სერვერს პლაგინებად აფორმებს, რათა ორივე ერთად დააყენოთ. აირჩიეთ პაკეტი, რომელიც თქვენს კოდირების აგენტს შეესაბამება.

## Claude Code

[Tuist Claude Code-ის ბაზრობა](https://github.com/tuist/claude-plugin) Tuist-ის პლაგინს შემდეგი გზით აყენებს:

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

ასევე შეგიძლიათ ჩაწეროთ `/add-plugin` Cursor-ში იმავე ინსტალაციის ნაკადის გასახსნელად. პლაგინი უზრუნველყოფს Tuist-ის უნარებს და აკავშირებს Cursor-ს განთავსებულ MCP სერვერთან.

თუ თქვენი ორგანიზაცია მართავს Cursor-ის ბაზრობებს, ჯერ შემოიტანეთ `https://github.com/tuist/cursor-plugin` მენიუდან **Settings → Plugins → Team Marketplaces → Import Marketplace**.

## სხვა კოდირების აგენტები

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin) ემორჩილება ღია, ვენდორ-ნეიტრალურ [Agent Plugins](https://agent-plugins.org/) სტანდარტს. მიმართეთ თავსებადი კლიენტი რეპოზიტორიზე, ამ კლიენტის ინსტრუქციების შესაბამისად პლაგინების დირექტორიების დასაყენებლად ან მითითებისთვის:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

ის აყენებს Tuist-ის უნარებს და არეგისტრირებს `https://tuist.dev/mcp`-ს როგორც დაშორებულ MCP სერვერს. კლიენტებისთვის, რომლებიც ჯერ არ უჭერენ მხარს Agent Plugins-ს, ცალ-ცალკე დააყენეთ <.localized_link href="/guides/features/agentic-coding/skills">უნარები</.localized_link> ან მოაწყოთ <.localized_link href="/guides/features/agentic-coding/mcp">MCP სერვერი</.localized_link>.

## ავტორიზაცია

უმეტესი უნარი იყენებს Tuist-ის ბრძანების ხაზის ინტერფეისს, ამიტომ ერთხელ გაიარეთ ავტორიზაცია, სანამ აგენტს სთხოვთ თქვენს პროექტის მონაცემებზე წვდომას:

```bash
tuist auth login
```

განთავსებული MCP სერვერი საჭიროების შემთხვევაში ითხოვს საკუთარ შესვლას. კლიენტზე დამოკიდებული მოწყობისა და ავტორიზაციის დეტალებისთვის იხილეთ <.localized_link href="/guides/features/agentic-coding/mcp">MCP-ის სახელმძღვანელო</.localized_link>.
