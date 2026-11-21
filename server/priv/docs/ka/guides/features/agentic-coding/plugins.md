---
{
  "title": "პლაგინები",
  "titleTemplate": ":title · აგენტური კოდირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "დააყენეთ Tuist-ის პლაგინი Cursor-ისთვის ან მომწოდებლისგან დამოუკიდებელი Agent Plugins პაკეტი."
}
---

# პლაგინები

Tuist აგენტის უნარებსა და ჰოსტინგულ MCP სერვერს პლაგინების სახით აერთიანებს, რათა ორივე ერთად დააყენოთ. აირჩიეთ პაკეტი, რომელიც შეესაბამება თქვენს კოდირების აგენტს.

## Claude Code

[Tuist Claude Code-ის ბაზრობა](https://github.com/tuist/claude-plugin) Tuist-ის პლაგინს შემდეგი ბრძანებებით აყენებს:

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

პლაგინი უზრუნველყოფს Tuist-ის უნარებს და აკავშირებს Claude Code-ს ჰოსტინგულ MCP სერვერთან.

## Cursor

დააყენეთ [Tuist-ის პლაგინი Cursor-ისთვის](https://github.com/tuist/cursor-plugin) [Cursor-ის ბაზრობიდან](https://cursor.com/marketplace):

1. Cursor-ის გვერდით პანელზე გახსენით **Customize**.
2. მოძებნეთ **Tuist**.
3. აირჩიეთ **Install**, შემდეგ მიუთითეთ, გსურთ თუ არა მისი დაყენება მიმდინარე პროექტისთვის თუ თქვენი მომხმარებლის ანგარიშისთვის.

ასევე შეგიძლიათ Cursor-ში ჩაწეროთ `/add-plugin`, რათა იგივე დაყენების ნაკადი გახსნათ. პლაგინი უზრუნველყოფს Tuist-ის უნარებს და აკავშირებს Cursor-ს ჰოსტინგულ MCP სერვერთან.

თუ თქვენი ორგანიზაცია მართავს Cursor-ის ბაზრობებს, ჯერ შემოიტანეთ `https://github.com/tuist/cursor-plugin` მისამართიდან **Settings → Plugins → Team Marketplaces → Import Marketplace**.

## სხვა კოდირების აგენტები

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin) ემორჩილება ღია, ვენდორისგან დამოუკიდებელ [Agent Plugins](https://agent-plugins.org/) სტანდარტს. მიმართეთ თავსებადი კლიენტი რეპოზიტორიისკენ, კლიენტის ინსტრუქციების შესაბამისად პლაგინის დირექტორიების დასაყენებლად ან მითითებისთვის:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

ის აყენებს Tuist-ის უნარებს და რეგისტრირდება `https://tuist.dev/mcp` როგორც დისტანციური MCP სერვერი. იმ კლიენტებისთვის, რომლებიც ჯერ არ უჭერენ მხარს Agent Plugins-ს, ცალ-ცალკე დააყენეთ <.localized_link href="/guides/features/agentic-coding/skills">უნარები</.localized_link> ან დააკონფიგურირეთ <.localized_link href="/guides/features/agentic-coding/mcp">MCP სერვერი</.localized_link>.

## ავტორიზაცია

უმეტესი უნარი იყენებს Tuist-ის ბრძანების ხაზის ინტერფეისს, ამიტომ სანამ აგენტს თხოვთ თქვენს პროექტის მონაცემებზე წვდომას, ერთხელ გაიარეთ ავტორიზაცია:

```bash
tuist auth login
```

ჰოსტინგული MCP სერვერი საჭიროების შემთხვევაში თავისთავად ითხოვს შესვლას. კლიენტის სპეციფიკური დაყენებისა და ავტორიზაციის დეტალებისთვის იხილეთ <.localized_link href="/guides/features/agentic-coding/mcp">MCP-ის სახელმძღვანელო</.localized_link>.
