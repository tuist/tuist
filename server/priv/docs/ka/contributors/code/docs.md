---
{
  "title": "დოკუმენტაცია",
  "titleTemplate": ":title · კოდი · მომხმარებლები · Tuist",
  "description": "შეიტანეთ წვლილი Tuist-ის დოკუმენტაციის საიტში."
}
---
# დოკუმენტაცია {#docs}

წყარო: [github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## რისთვისაა განკუთვნილი {#what-it-is-for}

დოკუმენტაციის საიტი შეიცავს Tuist-ის პროდუქტისა და კონტრიბუტორების დოკუმენტაციას. ის აგებულია VitePress-ზე.

## როგორ შეგიძლიათ წვლილის შეტანა {#how-to-contribute}

### ლოკალურად გაშვება {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### არჩევითი გენერირებული მონაცემები {#optional-generated-data}

დოკუმენტაციაში ჩვენ ვსვამთ ზოგიერთ გენერირებულ მონაცემს:

- CLI-ის ცნობარის მონაცემები: `mise run generate-cli-docs`

ეს არჩევითია. დოკუმენტაცია მათ გარეშეც გამოისახება, ამიტომ გაუშვით მხოლოდ მაშინ, როცა გენერირებული შინაარსის განახლება გჭირდებათ.

ProjectDescription API-ის ცნობარი ცალკეა განთავსებული როგორც DocC საიტი მისამართზე [projectdescription.tuist.dev](https://projectdescription.tuist.dev). მისი ლოკალურად ასაგებად, რეპოზიტორიის ფესვიდან გაუშვით `mise run docs:project-description`.
