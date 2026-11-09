---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git-ფორჯები | ინტეგრაციები | სახელმძღვანელოები | Tuist",
  "description": "შეიტყვეთ, როგორ მოახდინოთ Tuist-ის ინტეგრაცია GitHub-თან გაუმჯობესებული სამუშაო პროცესებისთვის."
}
---
# GitHub-ის ინტეგრაცია {#github}

Git რეპოზიტორიები პროგრამული უზრუნველყოფის პროექტების უმეტესობის ცენტრალური ნაწილია. ჩვენ ვინტეგრირდებით GitHub-თან, რათა Tuist-ის ანალიტიკა პირდაპირ თქვენს pull request-ებში მოგაწოდოთ და ზოგიერთი კონფიგურაცია შეგინახოთ, მაგალითად, ძირითადი შტოს სინქრონიზაცია.

## მოწყობა {#setup}

თქვენ უნდა დააინსტალიროთ Tuist GitHub აპი თქვენი ორგანიზაციის `Integrations` ჩანართში: ![სურათი, რომელიც აჩვენებს ინტეგრაციების ჩანართს](/images/guides/integrations/gitforge/github/integrations.png)

ასევე შეგიძლიათ აპის პირდაპირ GitHub-დან დაინსტალიროთ. საჭიროების შემთხვევაში, შედით Tuist-ში, ავტორიზეთ GitHub App, რათა Tuist-მა შეამოწმოს თქვენი წვდომა ინსტალაციასთან და აირჩიეთ დასაკავშირებელი Tuist ორგანიზაცია. თქვენ უნდა ფლობდეთ GitHub ორგანიზაციას (ან პირად GitHub ანგარიშს), სადაც აპი ინსტალირდება. ხელმისაწვდომია მხოლოდ თქვენ მიერ ადმინისტრირებადი Tuist ორგანიზაციები და თქვენი პირადი Tuist ანგარიში. თუ მხოლოდ ერთი ანგარიშია ხელმისაწვდომი, Tuist მას ავტომატურად დააკავშირებს არჩევნის ფანჯრის გამოჩენის გარეშე. როდესაც Tuist-დან იწყებთ, ორგანიზაცია უკვე შერჩეულია და ეს ნაბიჯი გამოტოვებულია.

ამის შემდეგ შეგიძლიათ დაამატოთ პროექტის კავშირი თქვენს GitHub რეპოზიტორიასა და Tuist პროექტს შორის:

![სურათი, რომელიც აჩვენებს პროექტის კავშირის დამატებას](/images/guides/integrations/gitforge/github/add-project-connection.png)

აპის ინსტალაციის შემდეგ, პროექტის დაკავშირება ასევე შეგიძლიათ dashboard-ის გარეშე:

- **CLI:** `tuist project repository connect owner/name`, და `tuist project repository disconnect` ბმულის წასაშლელად.
- **REST API:** `PUT` და `DELETE` ბმულზე `/api/projects/{account_handle}/{project_handle}/vcs-connection`.
- **Model Context Protocol:** ინსტრუმენტები `connect_project_repository` და `disconnect_project_repository`.

რეპოზიტორი უნდა იყოს ისეთი, რომელზეც GitHub App ინსტალაციას აქვს წვდომა, და პროექტი იღებს რეპოზიტორის ძირითად შტოს. ანგარიშის ტოკენებს სჭირდებათ `project:admin:write` წვდომის არეალი.

> [!TIP]
> **IP მისამართების თეთრ სიაში შეყვანა**
>
> თუ თქვენი GitHub ორგანიზაცია იყენებს [IP მისამართების თეთრ სიებს](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) ან თქვენი GitHub ეგზემპლარი საფარის ქვეშაა, დარწმუნდით, რომ Tuist-ის <.localized_link href="/guides/server/network#outbound-ip-addresses">გამომავალი IP მისამართები</.localized_link> თეთრ სიაში შეგიყვანიათ, რათა ინტეგრაციამ შეძლოს თქვენს რეპოზიტორთან კომუნიკაცია.

### GitHub Enterprise Server {#github-enterprise-server}

Tuist ასევე ინტეგრირდება თვითმასპინძლებელ GitHub Enterprise Server (GHES) ეგზემპლარებთან. GitHub ინტეგრაციის ბარათში გადადით **Enterprise server** ჩანართზე, შეიყვანეთ თქვენი GHES საბაზო URL (მაგალითად, `https://github.example.com`), და დააჭირეთ ინსტალაციას.

რადგან GitHub Apps ერთ GitHub ეგზემპლარზეა შეზღუდული, Tuist ვერ გამოიყენებს თავის github.com აპს თქვენს GHES-ზე — ამის ნაცვლად, ინსტალაციის ღილაკი გაგივლით GitHub-ის [App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)-ში: GHES თქვენს ადმინისტრატორს ატარებს ეგზემპლარზე ახალი Tuist App-ის რეგისტრაციის პროცესში, შემდეგ კი ახალი აპის სერთიფიკატებს Tuist-ს უბრუნებს. Tuist ამ სერთიფიკატებს თითოეული ინსტალაციისთვის დაშიფრულად ინახავს და მათ იყენებს ყოველ API ზარში, webhook ხელმოწერასა და თქვენს რეპოზიტორებთან ბმულებში.

დამატებითი Tuist სერვერის კონფიგურაცია არ არის საჭირო; manifest flow ყველაფერს ავტომატურად ქმნის და აწვდის.

#### აპის ნებართვები და webhook მოვლენები {#github-app-permissions}

PR კომენტარებისა და bundle-ის ზომის შემოწმებებისთვის Tuist-ს სჭირდება შემდეგი **რეპოზიტორიის ნებართვები**:

| ნებართვა | წვდომა | გამოიყენება |
|---|---|---|
| მეტამონაცემები (`metadata`) | მხოლოდ კითხვა | ძირითადი რეპოზიტორიის მეტამონაცემები; GitHub-ის მიერ საჭიროა ყოველი აპისთვის |
| Pull requests (`pull_requests`) | კითხვა და ჩაწერა | Pull requests-ის წაკითხვა, მათი head commit SHA-ის ჩათვლით, და PR კომენტარების ჩამონათვალის შედგენა, გამოქვეყნება და განახლება |
| Checks (`checks`) | კითხვა და ჩაწერა | Check runs-ის შექმნა და განახლება, bundle-ის ზომის წარმატებული/შეცდომიანი შემოწმებების ჩათვლით |

Tuist იყენებს `check_run` webhook მოვლენას bundle-ის ზომის შემოწმების მოქმედებების დასამუშავებლად. Manifest flow ამ გამოწერას ავტომატურად აკონფიგურირებს.

github.com-ზე აპის ხელით მოწყობისთვის თვითმასპინძლებელ Tuist სერვერთან ერთად, იხილეთ <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">თვითმასპინძლობის სახელმძღვანელო</.localized_link>.

#### ბრაუზერისა და API URL-ების განცალკევება {#separate-browser-and-api-urls}

თუ ინჟინრები GitHub Enterprise-ს შიდა ჰოსტნეიმით წვდებიან, ხოლო მესამე მხარის სერვისები გარე პროქსის იყენებენ, ინსტალაციაზე დაჭერამდე ორივე მისამართი დააკონფიგურირეთ:

| ველი | მაგალითი | გამოიყენება |
|---|---|---|
| **სერვერის URL** | `https://github.internal.company.com` | თქვენი ბრაუზერი, აპის რეგისტრაციისა და ინსტალაციისთვის, და Tuist-დან GitHub-ზე ბმულებისთვის |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist-ის სერვერები, manifest-კოდის გაცვლის, წვდომის ტოკენების, რეპოზიტორიის წვდომის, PR კომენტარებისა და checks-ისთვის |

API URL არის სრული REST API საბაზისო URL, `/api/v3`-ის ან თქვენი პროქსის მიერ გამოფენილი ეკვივალენტური ბილიკის ჩათვლით. Tuist არ ამატებს `/api/v3`-ს ცხად API URL-ზე. დატოვეთ ის ცარიელი, თუ ერთი ჰოსტნეიმი მუშაობს როგორც თქვენი ბრაუზერისთვის, ასევე Tuist-ისთვის; არსებული კავშირები აგრძელებენ `<Server URL>/api/v3`-ის გამოყენებას.

ორივე მისამართი უნდა მიემართებოდეს **იგივე GitHub Enterprise ინსტანციას**. თქვენს ბრაუზერს სჭირდება მხოლოდ სერვერის URL-ზე მიღწევა, არა API პროქსიზე. Tuist-ის სერვერებს სჭირდებათ მხოლოდ API URL-ზე მიღწევა, არა შიდა ბრაუზერის ჰოსტნეიმზე.

გარე პროქსისთვის:

- გამოიყენეთ HTTPS სერთიფიკატით, რომელსაც Tuist-ის სერვერები ენდობიან, და საჯარო DNS, რომელიც საჯარო IP მისამართებზე იხსნება. API URL-ის გადაწერა არ ავლის Tuist-ის პირადი-IP/SSRF დაცვას. გადაწერა უნდა მიემართებოდეს თქვენს Enterprise ინსტანციას, არა `github.com`-ს ან `*.github.com` endpoint-ს.
- ჩაამატეთ allowlist-ში ყოველი Tuist-ის <.localized_link href="/guides/server/network#outbound-ip-addresses">გამომავალი IP მისამართი</.localized_link>.
- გადაამისამართეთ REST API endpoint-ები, რომლებსაც Tuist იყენებს, `POST /api/v3/app-manifests/{code}/conversions`-ის, `POST /api/v3/app/installations/{installation_id}/access_tokens`-ის და კომენტარებისა და checks-ის რეპოზიტორიის API endpoint-ების ჩათვლით. ესენი არის GitHub-ის upstream ბილიკები; გადათარგმნეთ ისინი, თუ თქვენი პროქსი სხვა პრეფიქსს გამოფენს.
- გადაამისამართეთ მოთხოვნები GitHub-ზე HTTP გადამისამართებების ან ინტერაქტიული შესვლის გვერდის გარეშე. Tuist ავტომატურად არ მიჰყვება Enterprise API გადამისამართებებს, ამიტომ მათ არ შეუძლიათ საჯარო-IP შემოწმებების ავლა. Manifest კონვერტაციის endpoint ხელმისაწვდომი უნდა იყოს მოწყობის დროს, სანამ Tuist-ს ექნება აპის სარწმუნოებები. GitHub Actions ლოგების ჩამოტვირთვა გამონაკლისია: Tuist მიჰყვება ხელმოწერილ არქივის გადამისამართებებს მხოლოდ HTTPS-ზე, ამოწმებს და ამაგრებს ყოველ დანიშნულებას საჯარო IP-ზე და არ გადასცემს ინსტალაციის ტოკენს.

GitHub-მა შეიძლება დააბრუნოს პაგინაციის ბმულები თავისი შიდა ჰოსტნეიმის გამოყენებით. Tuist ახდენს ბმულების რებაზირებას კონფიგურირებული GitHub ინსტანციიდან API URL-ზე, თქვენი პროქსის ბილიკის პრეფიქსის შენარჩუნებით; არარელევანტური წყაროების ბმულები უარყოფილია.

ცალკე, GitHub-მა უნდა შეძლოს webhooks-ის მიწოდება `https://tuist.dev/webhooks/github`-ზე (ან `/webhooks/github`-ზე თქვენს თვითმასპინძლებელ Tuist სერვერზე). ინჟინრებს უნდა შეეძლოთ Tuist-ზე დაბრუნება ბრაუზერის callback-ების დასასრულებლად. API URL არ ცვლის არცერთ დანიშნულებას.

ორგანიზაციის ადმინისტრატორებს ასევე შეუძლიათ შეცვალონ ან გაასუფთაონ API URL არსებულ Enterprise ინტეგრაციაზე ინტეგრაციის ბარათში **Save API URL**-ის გამოყენებით. აპის ხელახალი ინსტალაცია ან პროექტის ხელახალი დაკავშირება არ არის საჭირო. გასუფთავება აღადგენს `<Server URL>/api/v3`-ს. შენახვა ამოწმებს URL ფორმატს, არა პროქსის კავშირს. Webhook-ის დამუშავებას შეიძლება დასჭირდეს ერთ წუთამდე შეცვლილი მისამართის გამოსაყენებლად, რადგან ინსტალაციის ძიებები cache-შია; უკვე მიმდინარე მოთხოვნებმა შეიძლება კვლავ გამოიყენონ წინა მისამართი.

> [!NOTE]
> **Enterprise გეგმა მხოლოდ hosted Tuist სერვერზე**
>
> Hosted Tuist სერვერზე (`https://tuist.dev`), GitHub Enterprise Server ინტეგრაცია ხელმისაწვდომია მხოლოდ **Enterprise** გეგმაზე მყოფი ორგანიზაციებისთვის. თვითმასპინძლებელ Tuist განლაგებებს შეუძლიათ მისი გამოყენება ნებისმიერ გეგმაზე.

## Pull/merge request კომენტარები {#pull-merge-request-comments}

GitHub აპი აქვეყნებს Tuist-ის გაშვების ანგარიშს, რომელიც მოიცავს PR-ის შეჯამებას, უახლეს <.localized_link href="/guides/features/previews/xcode#pullmerge-request-comments">previews</.localized_link>-ზე ან <.localized_link href="/guides/features/selective-testing/generated-xcode-project#pullmerge-request-comments">ტესტებზე</.localized_link> ბმულების ჩათვლით:

Tuist ანახლებს ერთ კომენტარს, როგორც კი შედეგები მოდის. Gradle ბილდები ჩანს ცალ-ცალკე ყოველი root პროექტისა და მოთხოვნილი ამოცანების ნაკრებისთვის; იგივე ამოცანების ხელახლა გაშვება ცვლის იმ გამოძახების წინა შედეგს. სრული ბილდის ისტორია რჩება ხელმისაწვდომი Tuist-ზე.

კომენტარები ჩართულია ნაგულისხმევად, რაც ინარჩუნებს ანგარიშგებას არსებული ინტეგრაციებისთვის. მათ გამოსართავად ან ხელახლა ჩასართავად პროექტისთვის, გახსენით **Project Settings → Integrations** და ჩართეთ/გამორთეთ **GitHub → Run report comments**. ყოველ პროექტს აქვს თავისი პარამეტრი; რეპოზიტორიის კავშირები კვლავ იმართება ორგანიზაციის პარამეტრებში.

კომენტარების გამორთვა არ თიშავს ბილდის ან ტესტების ატვირთვას, GitHub Actions სამუშაოს შეჯამებებს, რეპოზიტორიის კავშირებს ან GitHub ინტეგრაციის სხვა ფუნქციებს. არსებული კომენტარები არ იშლება.

![სურათი, რომელიც აჩვენებს pull request კომენტარს](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **მოთხოვნები**
>
> კომენტარი ქვეყნდება მხოლოდ მაშინ, როცა თქვენი CI გაშვებები არის <.localized_link href="/guides/server/authentication#continuous-integration">ავთენტიკირებული</.localized_link>.

> [!NOTE]
> **`GITHUB_REF`**
>
> თუ გაქვთ მორგებული workflow, რომელიც არ არის გამოწვეული PR commit-ზე, არამედ მაგალითად, GitHub კომენტარზე, შეიძლება დაგჭირდეთ უზრუნველყოთ, რომ `GITHUB_REF` ცვლადი დაყენებული იყოს ან `refs/pull/<PR_NUMBER>/merge`-ზე, ან `refs/pull/<PR_NUMBER>/head`-ზე.
>
> შეგიძლიათ გაუშვათ შესაბამისი ბრძანება, როგორიცაა `tuist share`, პრეფიქსირებული `GITHUB_REF` გარემოს ცვლადით: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions სამუშაოს შეჯამება {#github-actions-job-summary}

Tuist CLI და Gradle პლაგინი წერენ ტესტებისა და ბილდის შედეგებს GitHub Actions-ის [სამუშაოს შეჯამებაში](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/). შეჯამება ბმავს სრულ ანგარიშზე Tuist-ზე, სადაც ხელმისაწვდომია უფრო მდიდარი ინსაითები, როგორიცაა არასტაბილური ტესტები და bundle-ის ზომის დელტები.

Gradle-ისთვის, ყოველი წარმატებით ატვირთული ბილდის ან ტესტის ანგარიში ამატებს თავის შეჯამებას, ინარჩუნებს სხვა შინაარსს, რომელიც დაწერილია ისეთი ინსტრუმენტების მიერ, როგორიცაა `gradle/actions/setup-gradle`. ეს მოითხოვს პლაგინის ვერსიას, რომელიც მოიცავს სამუშაოს შეჯამების მხარდაჭერას; Gradle პლაგინის უფრო ძველი ვერსიები ანგარიშგებენ მხოლოდ GitHub აპის PR კომენტარის მეშვეობით. GitHub აპის დაკავშირება არ არის საჭირო სამუშაოს შეჯამებებისთვის და **Run report comments**-ის გამორთვა მათზე არ მოქმედებს.

როდესაც GitHub Actions შეჯამების დანიშნულება ხელმისაწვდომია, Gradle ელოდება ატვირთვებსა და შეჯამებებს გასვლამდე, მაშინაც კი, თუ `uploadInBackground` ჩართულია. GitHub იჭერს შეჯამებას, როდესაც workflow ნაბიჯი სრულდება.

![სურათი, რომელიც აჩვენებს Tuist-ის გაშვების ანგარიშს GitHub Actions სამუშაოს შეჯამებაში](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

ეს განსაკუთრებით სასარგებლოა [merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)-თან ერთად. Merge queue გაშვება არ არის მიბმული pull request-ზე, ამიტომ კომენტარი არ ქვეყნდება, მაგრამ სამუშაოს შეჯამება კვლავ აჩენს შედეგებს.

> [!NOTE]
> **მოთხოვნები**
>
> სამუშაოს შეჯამებები მოითხოვენ ანგარიშის წარმატებულ ატვირთვას. Hosted Tuist სერვერზე, თქვენი CI გაშვებები უნდა იყოს <.localized_link href="/guides/server/authentication#continuous-integration">ავთენტიკირებული</.localized_link>. თვითმასპინძლებელ ინსტანციებს ასევე შეუძლიათ მიიღონ სარწმუნოებების გარეშე ანგარიშები, როდესაც ქსელში სანდო ანგარიშის გამოქვეყნება ჩართულია.
