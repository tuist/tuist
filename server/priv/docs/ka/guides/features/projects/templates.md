---
{
  "title": "შაბლონები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ისწავლეთ, როგორ შექმნათ და გამოიყენოთ შაბლონები Tuist-ში თქვენს პროექტებში კოდის გენერაციისთვის."
}
---
# შაბლონები {#templates}

არქიტექტურის მქონე პროექტებში დეველოპერებს შეიძლება სურდეთ ახალი კომპონენტების ან ფუნქციების ინიციალიზაცია, რომლებიც პროექტთან თანმიმდევრულია. `tuist scaffold`-ის საშუალებით შეგიძლიათ ფაილების გენერირება შაბლონიდან. შეგიძლიათ განსაზღვროთ თქვენი საკუთარი შაბლონები ან გამოიყენოთ Tuist-თან ერთად მოწოდებული შაბლონები. აქ არის რამდენიმე სცენარი, სადაც შაბლონების გამოყენება სასარგებლო შეიძლება იყოს:

- ახალი ფუნქციის შექმნა, რომელიც მიჰყვება მოცემულ არქიტექტურას: `tuist scaffold viper --name MyFeature`.
- ახალი პროექტების შექმნა: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **არააღმავლობითი**
>
> Tuist არ აწესებს შეზღუდვებს თქვენი შაბლონების შინაარსზე ან მათი გამოყენების მიზნებზე. ერთადერთი მოთხოვნაა, რომ ისინი განთავსდნენ კონკრეტულ დირექტორიაში.


## შაბლონის განსაზღვრა {#defining-a-template}

შაბლონების განსაზღვრისთვის შეგიძლიათ გაუშვათ <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> და შემდეგ შექმნათ დირექტორია სახელით `name_of_template` დირექტორიაში `Tuist/Templates`, რომელიც წარმოადგენს თქვენს შაბლონს. შაბლონებს სჭირდებათ მანიფესტის ფაილი, `name_of_template.swift`, რომელიც აღწერს შაბლონს. მაგალითად, თუ ქმნით შაბლონს სახელით `framework`, უნდა შექმნათ ახალი დირექტორია `framework` მისამართზე `Tuist/Templates` მანიფესტის ფაილით სახელით `framework.swift`, რომელიც შეიძლება ასე გამოიყურებოდეს:


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

შაბლონის განსაზღვრის შემდეგ, მისი გამოყენება შესაძლებელია `scaffold` ბრძანებით:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> ვინაიდან platform არის არააუცილებელი არგუმენტი, ბრძანების გამოძახება შესაძლებელია `--platform macos` არგუმენტის გარეშეც.


თუ `.string` და `.files` არ უზრუნველყოფს საკმარის მოქნილობას, შეგიძლიათ გამოიყენოთ [Stencil](https://stencil.fuller.li/en/latest/) შაბლონიზაციის ენა `.file` ვარიანტის მეშვეობით. ამის გარდა, შეგიძლიათ გამოიყენოთ აქ განსაზღვრული დამატებითი ფილტრები.

სტრიქონის ინტერპოლაციის გამოყენებით, ზემოთ მოცემული `\(nameAttribute)` გადაიქცევა `{{ name }}`-ად. თუ გსურთ Stencil-ის ფილტრების გამოყენება შაბლონის განსაზღვრაში, შეგიძლიათ ხელით გამოიყენოთ ეს ინტერპოლაცია და დაამატოთ ნებისმიერი სასურველი ფილტრი. მაგალითად, შეგიძლიათ გამოიყენოთ `{ { name | lowercase } }` `\(nameAttribute)`-ის ნაცვლად name ატრიბუტის მნიშვნელობის პატარა ასოებით მისაღებად.

ასევე შეგიძლიათ გამოიყენოთ `.directory`, რაც საშუალებას გაძლევთ დააკოპიროთ მთელი საქაღალდეები მითითებულ მისამართზე.

> [!TIP]
> **პროექტის აღწერის დამხმარეები**
>
> შაბლონები უზრუნველყოფენ <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარეების</.localized_link> გამოყენებას, რაც საშუალებას გაძლევთ ხელახლა გამოიყენოთ კოდი სხვადასხვა შაბლონში.
