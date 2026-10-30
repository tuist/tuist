---
{
  "title": "შაბლონები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ისწავლეთ, როგორ შექმნათ და გამოიყენოთ შაბლონები Tuist-ში თქვენს პროექტებში კოდის გენერაციისთვის."
}
---
# შაბლონები {#templates}

პროექტებში დამკვიდრებული არქიტექტურით, დეველოპერებს შეიძლება სურდეთ ახალი კომპონენტების ან ფუნქციების ინიციალიზაცია, რომლებიც პროექტთან თანმიმდევრულია. `tuist scaffold`-ის საშუალებით შეგიძლიათ შაბლონიდან ფაილების გენერირება. შეგიძლიათ განსაზღვროთ საკუთარი შაბლონები ან გამოიყენოთ Tuist-თან ერთად მოწოდებული შაბლონები. აქ არის რამდენიმე სცენარი, სადაც შაბლონიზაცია შეიძლება სასარგებლო იყოს:

- ახალი ფუნქციის შექმნა, რომელიც ემორჩილება მოცემულ არქიტექტურას: `tuist scaffold viper --name MyFeature`.
- ახალი პროექტების შექმნა: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **არააღმქველობითი**
>
> Tuist არ აწესებს შეზღუდვებს თქვენი შაბლონების შინაარსზე ან მათი გამოყენების მიზნებზე. ერთადერთი მოთხოვნა ის არის, რომ ისინი განთავსდნენ კონკრეტულ დირექტორიაში.


## შაბლონის განსაზღვრა {#defining-a-template}

შაბლონების განსაზღვრისთვის, შეგიძლიათ გაუშვათ <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> და შემდეგ შექმნათ დირექტორია სახელწოდებით `name_of_template` დირექტორიაში `Tuist/Templates`, რომელიც წარმოადგენს თქვენს შაბლონს. შაბლონებს სჭირდებათ მანიფესტის ფაილი, `name_of_template.swift`, რომელიც აღწერს შაბლონს. ასე რომ, თუ ქმნით შაბლონს სახელწოდებით `framework`, უნდა შექმნათ ახალი დირექტორია `framework` მისამართზე `Tuist/Templates` მანიფესტის ფაილით `framework.swift`, რომელიც შეიძლება ასე გამოიყურებოდეს:


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

შაბლონის განსაზღვრის შემდეგ, შეგიძლიათ გამოიყენოთ ის ბრძანებიდან `scaffold`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> ვინაიდან platform არის არასავალდებულო არგუმენტი, ბრძანების გამოძახება შესაძლებელია `--platform macos` არგუმენტის გარეშეც.


თუ `.string` და `.files` საკმარის მოქნილობას არ უზრუნველყოფს, შეგიძლიათ გამოიყენოთ [Stencil](https://stencil.fuller.li/en/latest/)-ის შაბლონური ენა `.file` ვარიანტის მეშვეობით. ამასთან, ასევე შეგიძლიათ გამოიყენოთ აქ განსაზღვრული დამატებითი ფილტრები.

სტრიქონის ინტერპოლაციის გამოყენებით, ზემოთ მოცემული `\(nameAttribute)` გადაიქცევა `{{ name }}`-ად. თუ გსურთ Stencil-ის ფილტრების გამოყენება შაბლონის განსაზღვრაში, შეგიძლიათ ხელით გამოიყენოთ ეს ინტერპოლაცია და დაამატოთ ნებისმიერი სასურველი ფილტრი. მაგალითად, შეგიძლიათ გამოიყენოთ `{ { name | lowercase } }` `\(nameAttribute)`-ის ნაცვლად, რათა მიიღოთ name ატრიბუტის მნიშვნელობა პატარა ასოებით.

ასევე შეგიძლიათ გამოიყენოთ `.directory`, რაც საშუალებას გაძლევთ დააკოპიროთ მთლიანი საქაღალდეები მითითებულ გზაზე.

> [!TIP]
> **Project Description Helpers**
>
> შაბლონები მხარს უჭერს <.localized_link href="/guides/features/projects/code-sharing">project description helpers</.localized_link>-ის გამოყენებას, რათა კოდი ხელახლა გამოიყენოთ შაბლონებს შორის.
