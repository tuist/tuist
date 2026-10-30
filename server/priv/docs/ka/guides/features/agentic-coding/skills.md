---
{
  "title": "უნარები",
  "titleTemplate": ":title · აგენტური კოდირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "წინასწარ შექმნილი უნარები, რომლებიც კოდირების აგენტებს შეუძლიათ გამოიყენონ Tuist-ის ჩვეულებითი ამოცანების შესასრულებლად, მაგალითად, პროექტის მიგრაციისთვის."
}
---

# უნარები

უნარები არის წინასწარ შექმნილი ინსტრუქციების ნაკრებები რთული, მრავალეტაპიანი Tuist ამოცანების შესასრულებლად. აგენტის მიგრაციის ან კონფიგურაციის პროცესში ხელით მიმართვის ნაცვლად, თქვენ აყენებთ უნარს და აგენტს საშუალებას აძლევთ ის თავად მოაგვაროს.

თუ თქვენი კოდირების აგენტი მხარდაჭერს პლაგინებს, [Tuist-ის პლაგინები](/guides/features/agentic-coding/plugins) ერთდროულად აყენებენ ამ უნარებს და განთავსებულ Model Context Protocol სერვერს.

## ხელმისაწვდომი უნარები

| უნარი | აღწერა |
| --- | --- |
| `migrate` | არსებული Xcode პროექტების მიგრაცია Tuist-ით გენერირებულ სამუშაო სივრცეებში ბილდისა და გაშვების ვალიდაციით, გარე დამოკიდებულებების ასახვით და მიგრაციის ჩეკლისტებით. |
| `generated-projects` | მიმართულებას იძლევა ყოველდღიური მუშაობისთვის Tuist-ით გენერირებულ სამუშაო სივრცეებში: გენერაცია, ბილდის/ტესტის ბრძანებები და ბილდირებადი საქაღალდეები. |
| `fix-flaky-tests` | ასწორებს არასტაბილურ ტესტებს Tuist-ის ტესტების ანალიზიდან მიღებული შეცდომების შაბლონების შესწავლით, ძირეული მიზეზების იდენტიფიცირებით და სამიზნე შესწორებების გამოყენებით. |
| `debug-generated-project` | აგვარებს პრობლემებს Tuist-ით გენერირებულ პროექტებში სცენარის აღწარმოებით, საჭიროების შემთხვევაში Tuist-ის წყაროდან აწყობით და იმის გარკვევით, არის ეს ბაგი, არასწორი კონფიგურაცია თუ გუნდის ჩართულობას მოითხოვს. |
| `compare-gradle-builds` | ადარებს ორ Gradle ბილდის გაშვებას ხანგრძლივობის რეგრესიების, ქეშის ცვლილებების და ამოცანების შედეგების სხვაობების გამოსავლენად. შეიძლება გამოძახებულ იქნას ბილდის ID-ებით, დაშბორდის URL-ებით ან ბრენჩების სახელებით. |

## ინსტალაცია {#installation}

Tuist უნარების ინსტალაციის რეკომენდებული გზაა [`skills`](https://github.com/vercel-labs/skills) CLI-ის გამოყენება. ის ავტომატურად ამოიცნობს თქვენს კოდირების აგენტებს და `SKILL.md` ფაილებს სწორ ადგილას ათავსებს.

### ყველა უნარის ინსტალაცია

```bash
npx skills add tuist/agent-skills
```

ინტერაქტიული მოთხოვნა გაძლევთ საშუალებას აირჩიოთ, რომელი უნარები და აგენტები დააინსტალიროთ.

### კონკრეტული უნარის ინსტალაცია

```bash
npx skills add tuist/agent-skills --skill migrate
```

### კონკრეტული აგენტისთვის ინსტალაცია

```bash
npx skills add tuist/agent-skills -a claude-code
```

### გლობალური ინსტალაცია

დაამატეთ `-g` ფლაგი უნარების თქვენს საწყის დირექტორიაში ინსტალაციისთვის, რათა ისინი ხელმისაწვდომი იყოს ყველა პროექტში:

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

### ხელით ინსტალაცია {#manual}

თუ `skills` CLI-ის გამოყენებას არ ამჯობინებთ, შეგიძლიათ `SKILL.md` ფაილები პირდაპირ ჩამოტვირთოთ. დააყენეთ ცვლადები სასურველი უნარისთვის და გაუშვით `curl` ბრძანება თქვენი აგენტისთვის:

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
