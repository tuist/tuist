---
{
  "title": "უნარები",
  "titleTemplate": ":title · აგენტური კოდირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "წინასწარ შექმნილი უნარები, რომლებიც კოდირების აგენტებს შეუძლიათ გამოიყენონ ისეთი ტიპური Tuist ამოცანების შესრულებისთვის, როგორიცაა პროექტის მიგრაცია."
}
---

# უნარები

უნარები არის წინასწარ შექმნილი ინსტრუქციების ნაკრებები რთული, მრავალეტაპიანი Tuist ამოცანების შესასრულებლად. აგენტის მიგრაციის ან დაყენების პროცესში ხელით მიმართვის ნაცვლად, თქვენ აყენებთ უნარს და აგენტს საშუალებას აძლევთ თავად განახორციელოს ის.

თუ თქვენი კოდირების აგენტი მხარდაჭერს პლაგინებს, <.localized_link href="/guides/features/agentic-coding/plugins">Tuist პლაგინები</.localized_link> ერთდროულად აყენებენ ამ უნარებს და ჰოსტინგზე განთავსებულ Model Context Protocol სერვერს.

## ხელმისაწვდომი უნარები

| უნარი | აღწერა |
| --- | --- |
| `migrate` | არსებული Xcode პროექტების მიგრაცია Tuist-ით გენერირებულ სამუშაო სივრცეებში ბილდისა და გაშვების ვალიდაციით, გარე დამოკიდებულებების მიბმით და მიგრაციის ჩეკლისტებით. |
| `generated-projects` | მიმართულება იძლევა ყოველდღიური მუშაობისთვის Tuist-ით გენერირებულ სამუშაო სივრცეებში: გენერაცია, ბილდის/ტესტის ბრძანებები და ბილდირებადი საქაღალდეები. |
| `fix-flaky-tests` | ასწორებს არასტაბილურ ტესტებს Tuist-ის ტესტირების ანალიზიდან მიღებული შეცდომების ნიმუშების შესწავლით, ძირეული მიზეზების გამოვლენით და სამიზნე შესწორებების გამოყენებით. |
| `debug-generated-project` | აგვარებს პრობლემებს Tuist-ით გენერირებულ პროექტებში სცენარის აღწარმოებით, საჭიროების შემთხვევაში Tuist-ის წყარო კოდიდან აწყობით და იმის გარკვევით, არის ეს ბაგი, არასწორი კონფიგურაცია თუ რაიმე, რასაც გუნდის ჩართულობა სჭირდება. |
| `compare-gradle-builds` | ადარებს ორ Gradle ბილდის გაშვებას ხანგრძლივობის რეგრესიების, ქეშის ცვლილებების და ამოცანების შედეგების სხვაობების გამოსავლენად. შესაძლებელია გამოძახება ბილდის ID-ებით, დაშბორდის URL-ებით ან ბრენჩების სახელებით. |

## დაყენება {#installation}

Tuist უნარების დაყენების რეკომენდებული გზაა [`skills`](https://github.com/vercel-labs/skills) CLI-ის გამოყენება. ის ავტომატურად აღმოაჩენს თქვენს კოდირების აგენტებს და `SKILL.md` ფაილებს საჭირო ადგილას ათავსებს.

### ყველა უნარის დაყენება

```bash
npx skills add tuist/agent-skills
```

ინტერაქტიული მოთხოვნა საშუალებას გაძლევთ აირჩიოთ, რომელი უნარები და აგენტებისთვის მოხდეს დაყენება.

### კონკრეტული უნარის დაყენება

```bash
npx skills add tuist/agent-skills --skill migrate
```

### კონკრეტული აგენტისთვის დაყენება

```bash
npx skills add tuist/agent-skills -a claude-code
```

### გლობალურად დაყენება

დაამატეთ `-g` ფლაგი უნარების თქვენს საწყის საქაღალდეში დასაყენებლად, რათა ისინი ხელმისაწვდომი იყოს ყველა პროექტში:

```bash
npx skills add tuist/agent-skills -g
```

### უნარების განახლება

```bash
npx skills update
```

### არაინტერაქტიული (CI)

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
