---
{
  "title": "შაბლონები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ისწავლეთ, როგორ შექმნათ და გამოიყენოთ შაბლონები Tuist-ში თქვენს პროექტებში კოდის გენერაციისთვის."
}
---
# შაბლონები {#templates}

პროექტებში ჩამოყალიბებული არქიტექტურით, დეველოპერებს შეიძლება სურდეთ ახალი კომპონენტების ან ფუნქციების ბუთსტრაპინგი, რომლებიც პროექტთან თანმიმდევრული იქნება. `tuist scaffold`-ის საშუალებით შეგიძლიათ ფაილების გენერირება შაბლონიდან. შეგიძლიათ განსაზღვროთ საკუთარი შაბლონები ან გამოიყენოთ Tuist-თან ერთად მოწოდებული შაბლონები. აქ არის რამდენიმე სცენარი, სადაც სკაფოლდინგი სასარგებლო შეიძლება იყოს:

- ახალი ფუნქციის შექმნა, რომელიც მოცემულ არქიტექტურას მიჰყვება: `tuist scaffold viper --name MyFeature`.
- ახალი პროექტების შექმნა: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **არააზრიანი**
>
> Tuist არ აწესებს შეზღუდვებს თქვენი შაბლონების შინაარსზე და მათი გამოყენების მიზანზე. ერთადერთი მოთხოვნაა, რომ ისინი კონკრეტულ საქაღალდეში იყოს განთავსებული.


## შაბლონის განსაზღვრა {#defining-a-template}

შაბლონების განსაზღვრისთვის შეგიძლიათ გაუშვათ <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> და შემდეგ შექმნათ საქაღალდე `name_of_template`, რომელიც წარმოადგენს თქვენს შაბლონს, `Tuist/Templates`-ის ქვეშ. შაბლონებს სჭირდებათ მანიფესტის ფაილი, `name_of_template.swift`, რომელიც აღწერს შაბლონს. ასე რომ, თუ ქმნით შაბლონს სახელწოდებით `framework`, უნდა შექმნათ ახალი საქაღალდე `framework` `Tuist/Templates`-ში მანიფესტის ფაილით `framework.swift`, რომელიც შეიძლება ასე გამოიყურებოდეს:


```swift
import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")

let template = Template(
    description: "Custom template",
    attributes: [
        nameAttribute,
        .optional("platform", default: "ios"),
    ],
    items: [
        .string(
            path: "Project.swift",
            contents: "My template contents of name \(nameAttribute)"
        ),
        .file(
            path: "generated/Up.swift",
            templatePath: "generate.stencil"
        ),
        .directory(
            path: "destinationFolder",
            sourcePath: "sourceFolder"
        ),
    ]
)
```

## შაბლონის გამოყენება {#using-a-template}

შაბლონის განსაზღვრის შემდეგ, შეგიძლიათ გამოიყენოთ ის `scaffold` ბრძანებიდან:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> რადგან პლატფორმა არის არააუცილებელი არგუმენტი, ბრძანების გამოძახება შესაძლებელია `--platform macos` არგუმენტის გარეშეც.


თუ `.string` და `.files` საკმარის მოქნილობას არ იძლევა, შეგიძლიათ გამოიყენოთ [Stencil](https://stencil.fuller.li/en/latest/) შაბლონური ენა `.file` შემთხვევის მეშვეობით. ამასთან, ასევე შეგიძლიათ გამოიყენოთ აქ განსაზღვრული დამატებითი ფილტრები.

სტრიქონის ინტერპოლაციის გამოყენებით, ზემოთ მოცემული `\(nameAttribute)` გადაიქცევა `{{ name }}`-ად. თუ გსურთ Stencil-ის ფილტრების გამოყენება შაბლონის განსაზღვრაში, შეგიძლიათ ეს ინტერპოლაცია ხელით გამოიყენოთ და დაამატოთ ნებისმიერი სასურველი ფილტრი. მაგალითად, შეგიძლიათ გამოიყენოთ `{ { name | lowercase } }` `\(nameAttribute)`-ის ნაცვლად, რათა მიიღოთ name ატრიბუტის მნიშვნელობა პატარა ასოებით.

ასევე შეგიძლიათ გამოიყენოთ `.directory`, რაც იძლევა მთელი საქაღალდეების კოპირების შესაძლებლობას მოცემულ გზაზე.

> [!TIP]
> **Project Description Helpers**
>
> შაბლონები მხარს უჭერენ <.localized_link href="/guides/features/projects/code-sharing">project description helpers</.localized_link>-ის გამოყენებას კოდის ხელახლა გამოსაყენებლად შაბლონებს შორის.
