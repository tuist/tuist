---
{
  "title": "შაბლონები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაიგეთ, როგორ შექმნათ და გამოიყენოთ შაბლონები Tuist-ში თქვენს პროექტებში კოდის გენერირებისთვის."
}
---
# შაბლონები {#templates}

არქიტექტურის მქონე პროექტებში დეველოპერებს შეიძლება სურდეთ ახალი კომპონენტების ან ფუნქციების ინიციალიზაცია, რომლებიც პროექტთან თავსებადია. `tuist scaffold`-ით შეგიძლიათ ფაილების გენერირება შაბლონიდან. შეგიძლიათ განსაზღვროთ საკუთარი შაბლონები ან გამოიყენოთ Tuist-თან ერთად მოწოდებული შაბლონები. აქ არის რამდენიმე სცენარი, სადაც შაბლონიზაცია შეიძლება სასარგებლო იყოს:

- ახალი ფუნქციის შექმნა, რომელიც ემორჩილება მოცემულ არქიტექტურას: `tuist scaffold viper --name MyFeature`.
- ახალი პროექტების შექმნა: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **არაფორმალური**
>
> Tuist არ აწესებს შეზღუდვებს თქვენი შაბლონების შინაარსზე ან მათი გამოყენების მიზანზე. ერთადერთი მოთხოვნაა, რომ ისინი იყოს კონკრეტულ საქაღალდეში.


## შაბლონის განსაზღვრა {#defining-a-template}

შაბლონების განსაზღვრისთვის შეგიძლიათ გაუშვათ <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> და შემდეგ შექმნათ საქაღალდე სახელით `name_of_template` საქაღალდეში `Tuist/Templates`, რომელიც წარმოადგენს თქვენს შაბლონს. შაბლონებს სჭირდებათ მანიფესტის ფაილი `name_of_template.swift`, რომელიც აღწერს შაბლონს. მაგალითად, თუ ქმნით შაბლონს სახელით `framework`, უნდა შექმნათ ახალი საქაღალდე `framework` საქაღალდეში `Tuist/Templates` მანიფესტის ფაილით `framework.swift`, რომელიც შეიძლება ასე გამოიყურებოდეს:


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

შაბლონის განსაზღვრის შემდეგ, შეგიძლიათ გამოიყენოთ ის ბრძანებით `scaffold`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> რადგან platform არის არააუცილებელი არგუმენტი, ბრძანების გამოძახება შესაძლებელია `--platform macos` არგუმენტის გარეშეც.


თუ `.string` და `.files` არ იძლევა საკმარის მოქნილობას, შეგიძლიათ გამოიყენოთ [Stencil](https://stencil.fuller.li/en/latest/) შაბლონიზაციის ენა `.file` ვარიანტის მეშვეობით. ამასთან, შეგიძლიათ გამოიყენოთ დამატებითი ფილტრები, რომლებიც აქ არის განსაზღვრული.

სტრიქონის ინტერპოლაციის გამოყენებით, ზემოთ მოცემული `\(nameAttribute)` გადაიქცევა `{{ name }}`-ად. თუ გსურთ Stencil-ის ფილტრების გამოყენება შაბლონის განსაზღვრაში, შეგიძლიათ ხელით გამოიყენოთ ეს ინტერპოლაცია და დაამატოთ ნებისმიერი სასურველი ფილტრი. მაგალითად, შეგიძლიათ გამოიყენოთ `{ { name | lowercase } }` `\(nameAttribute)`-ის ნაცვლად name ატრიბუტის მნიშვნელობის პატარა ასოებში გადასაყვანად.

ასევე შეგიძლიათ გამოიყენოთ `.directory`, რაც იძლევა მთელი საქაღალდეების კოპირების შესაძლებლობას მითითებულ გზაზე.

> [!TIP]
> **პროექტის აღწერის დამხმარე ფუნქციები**
>
> შაბლონები მხარს უჭერენ <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარე ფუნქციების</.localized_link> გამოყენებას კოდის ხელახლა გამოყენებისთვის სხვადასხვა შაბლონში.
