---
{
  "title": "უნარები",
  "titleTemplate": ":title · აგენტური კოდირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "წინასწარ განსაზღვრული უნარები, რომლებიც კოდირების აგენტებს შეუძლიათ გამოიყენონ Tuist-ის ჩვეულებითი ამოცანების შესასრულებლად, მაგალითად, პროექტის მიგრაციისთვის."
}
---

# უნარები

უნარები არის წინასწარ მომზადებული ინსტრუქციების ნაკრებები რთული, მრავალეტაპიანი Tuist ამოცანების შესასრულებლად. აგენტის ხელით მიმართვის ნაცვლად მიგრაციის ან დაყენების პროცესში, თქვენ აყენებთ უნარს და აგენტს საშუალებას აძლევთ თავად იმუშაოს.

თუ თქვენი კოდირების აგენტი მხარდაჭერს პლაგინებს, <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link> ერთდროულად აყენებს ამ უნარებს და განთავსებულ Model Context Protocol სერვერს.

## ხელმისაწვდომი უნარები

| უნარი | აღწერა |
| --- | --- |
| `migrate` | მიგრირებს არსებულ Xcode პროექტებს Tuist-ით გენერირებულ სამუშაო სივრცეებში ბილდისა და გაშვების ვალიდაციით, გარე დამოკიდებულებების მიბმითა და მიგრაციის ჩეკლისტებით. |
| `generated-projects` | მიმართულებას აძლევს ყოველდღიურ მუშაობას Tuist-ით გენერირებულ სამუშაო სივრცეებში: გენერაცია, ბილდის/ტესტის ბრძანებები და ასაწყობი საქაღალდეები. |
| `fix-flaky-tests` | ასწორებს არასტაბილურ ტესტებს Tuist-ის ტესტის ანალიტიკიდან შეცდომების ნიმუშების ანალიზით, ძირეული მიზეზების იდენტიფიცირებითა და მიზნობრივი შესწორებების გამოყენებით. |
| `debug-generated-project` | აგვარებს Tuist-ით გენერირებულ პროექტებთან დაკავშირებულ პრობლემებს სცენარის აღწარმოებით, საჭიროების შემთხვევაში Tuist-ის წყაროდან აწყობით და კლასიფიცირებით, არის ეს ბაგი, არასწორი კონფიგურაცია თუ გუნდის ჩართვას მოითხოვს. |
| `compare-gradle-builds` | ადარებს ორ Gradle ბილდის გაშვებას ხანგრძლივობის რეგრესიების, ქეშის ცვლილებებისა და ამოცანების შედეგების სხვაობების გამოსავლენად. შეიძლება გამოძახებულ იქნას ბილდის ID-ებით, დაშბორდის URL-ებით ან ბრენჩის სახელებით. |

## დაყენება {#installation}

Tuist უნარების დაყენების რეკომენდებული გზაა [`skills`](https://github.com/vercel-labs/skills) CLI-ის გამოყენება. ის ავტომატურად ამოიცნობს თქვენს კოდირების აგენტებს და `SKILL.md` ფაილებს სწორ ადგილას ათავსებს.

### ყველა უნარის დაყენება

```bash
npx skills add tuist/agent-skills
```

ინტერაქტიული მოთხოვნა საშუალებას გაძლევთ აირჩიოთ, რომელი უნარები და აგენტებისთვის ხდება დაყენება.

### კონკრეტული უნარის დაყენება

```bash
npx skills add tuist/agent-skills --skill migrate
```

### კონკრეტული აგენტისთვის დაყენება

```bash
npx skills add tuist/agent-skills -a claude-code
```

### გლობალურად დაყენება

დაამატეთ `-g` ფლაგი უნარების თქვენს საწყის საქაღალდეში დასაყენებლად, რათა ისინი ყველა პროექტში იყოს ხელმისაწვდომი:

```bash
npx skills add tuist/agent-skills -g
```

### უნარების განახლება

```bash
npx skills update
```

### არაინტერაქტიური (CI)

```bash
npx skills add tuist/agent-skills --all -y
```

### ხელით დაყენება {#manual}

თუ არ გსურთ `skills` CLI-ის გამოყენება, შეგიძლიათ პირდაპირ ჩამოტვირთოთ `SKILL.md` ფაილები. დააყენეთ ცვლადები სასურველი უნარისთვის და გაუშვით `curl` ბრძანება თქვენი აგენტისთვის:

```bash
SKILL_NAME=tuist-migrate          # or tuist-generated-projects
SKILL_URL=https://tuist.dev/skills/migrate/SKILL.md  # or .../generated-projects/SKILL.md
```

::: code-group

```bash [Claude Code]
mkdir -p .claude/skills/$SKILL_NAME
curl -o .claude/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Codex]
mkdir -p .codex/skills/$SKILL_NAME
curl -o .codex/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Amp]
mkdir -p .agents/skills/$SKILL_NAME
curl -o .agents/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [OpenCode]
mkdir -p .opencode/skills/$SKILL_NAME
curl -o .opencode/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

:::
