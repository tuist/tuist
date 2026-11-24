---
{
  "title": "შაბლონები",
  "titleTemplate": ":title · პროექტები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "ისწავლეთ, როგორ შექმნათ და გამოიყენოთ შაბლონები Tuist-ში თქვენს პროექტებში კოდის გენერირებისთვის."
}
---
# შაბლონები {#templates}

პროექტებში ჩამოყალიბებული არქიტექტურით, დეველოპერებს შეიძლება სურდეთ ახალი კომპონენტების ან ფუნქციების ინიციალიზაცია, რომლებიც პროექტთან თანმიმდევრულია. `tuist scaffold`-ის საშუალებით შეგიძლიათ ფაილების გენერირება შაბლონიდან. შეგიძლიათ განსაზღვროთ თქვენი საკუთარი შაბლონები ან გამოიყენოთ Tuist-თან ერთად მოწოდებული შაბლონები. აქ არის რამდენიმე სცენარი, სადაც შაბლონიზაცია შეიძლება სასარგებლო იყოს:

- ახალი ფუნქციის შექმნა, რომელიც მიჰყვება მოცემულ არქიტექტურას: `tuist scaffold viper --name MyFeature`.
- ახალი პროექტების შექმნა: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **არაფორმალური**
>
> Tuist არ აწესებს წესებს თქვენი შაბლონების შინაარსზე და მათი გამოყენების მიზანზე. ერთადერთი მოთხოვნა ისაა, რომ ისინი იყოს კონკრეტულ დირექტორიაში.


## შაბლონის განსაზღვრა {#defining-a-template}

შაბლონების განსაზღვრისთვის, შეგიძლიათ გაუშვათ <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> და შემდეგ შექმნათ დირექტორია სახელით `name_of_template` ქვეშ `Tuist/Templates`, რომელიც წარმოადგენს თქვენს შაბლონს. შაბლონებს სჭირდებათ მანიფესტის ფაილი, `name_of_template.swift`, რომელიც აღწერს შაბლონს. ასე რომ, თუ ქმნით შაბლონს სახელით `framework`, უნდა შექმნათ ახალი დირექტორია `framework` ადგილას `Tuist/Templates` მანიფესტის ფაილით სახელით `framework.swift`, რომელიც შეიძლება ასე გამოიყურებოდეს:


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

შაბლონის განსაზღვრის შემდეგ, შეგვიძლია მისი გამოყენება `scaffold` ბრძანებიდან:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> ვინაიდან platform არის არააუცილებელი არგუმენტი, ბრძანების გამოძახება შესაძლებელია `--platform macos` არგუმენტის გარეშეც.


თუ `.string` და `.files` არ უზრუნველყოფს საკმარის მოქნილობას, შეგიძლიათ გამოიყენოთ [Stencil](https://stencil.fuller.li/en/latest/) შაბლონიზაციის ენა `.file` ვარიანტის მეშვეობით. ამასთან, შეგიძლიათ გამოიყენოთ აქ განსაზღვრული დამატებითი ფილტრები.

სტრიქონის ინტერპოლაციის გამოყენებით, ზემოთ მოცემული `\(nameAttribute)` გადაიქცევა `{{ name }}`-ად. თუ გსურთ Stencil ფილტრების გამოყენება შაბლონის განსაზღვრაში, შეგიძლიათ ხელით გამოიყენოთ ეს ინტერპოლაცია და დაამატოთ ნებისმიერი ფილტრი. მაგალითად, შეგიძლიათ გამოიყენოთ `{ { name | lowercase } }` `\(nameAttribute)`-ის ნაცვლად name ატრიბუტის მნიშვნელობის პატარა ასოებით მისაღებად.

ასევე შეგიძლიათ გამოიყენოთ `.directory`, რაც იძლევა მთელი საქაღალდეების კოპირების შესაძლებლობას მოცემულ გზაზე.

> [!TIP]
> **პროექტის აღწერის დამხმარე საშუალებები**
>
> შაბლონები უჭერენ მხარს <.localized_link href="/guides/features/projects/code-sharing">პროექტის აღწერის დამხმარე საშუალებების</.localized_link> გამოყენებას კოდის ხელახლა გამოსაყენებლად შაბლონებს შორის.
