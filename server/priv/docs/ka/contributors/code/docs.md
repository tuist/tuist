---
{
  "title": "დოკუმენტაცია",
  "titleTemplate": ":title · კოდი · კონტრიბუტორები · Tuist",
  "description": "შეიტანეთ წვლილი Tuist-ის დოკუმენტაციის საიტში."
}
---
# დოკუმენტაცია {#docs}

წყარო: [github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## რისთვისაა {#what-it-is-for}

დოკუმენტაციის საიტი მასპინძლობს Tuist-ის პროდუქტისა და კონტრიბუტორების დოკუმენტაციას. ის აგებულია VitePress-ით.

## როგორ შევიტანოთ წვლილი {#how-to-contribute}

### ლოკალურად მომზადება {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### არჩევითი გენერირებული მონაცემები {#optional-generated-data}

დოკუმენტაციაში ჩავსვამთ ზოგიერთ გენერირებულ მონაცემს:

- CLI-ის ცნობარის მონაცემები: `mise run generate-cli-docs`

ეს არჩევითია. დოკუმენტაცია მათ გარეშეც რენდერდება, ამიტომ გაუშვით მხოლოდ მაშინ, როცა გენერირებული შინაარსის განახლება გჭირდებათ.

ProjectDescription API-ის ცნობარი ცალკეა განთავსებული DocC საიტზე [projectdescription.tuist.dev](https://projectdescription.tuist.dev). ლოკალურად ასაგებად, რეპოზიტორიის ფესვიდან გაუშვით `mise run docs:project-description`.
