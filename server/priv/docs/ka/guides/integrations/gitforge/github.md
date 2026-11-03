---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git-ფორჯები | ინტეგრაციები | სახელმძღვანელოები | Tuist",
  "description": "გაიგეთ, როგორ შეგიძლიათ Tuist-ის GitHub-თან ინტეგრაცია გაუმჯობესებული სამუშაო პროცესებისთვის."
}
---
# GitHub-ის ინტეგრაცია {#github}

Git-რეპოზიტორიები წარმოადგენს პროგრამული უზრუნველყოფის პროექტების უმეტესობის საყრდენს. ჩვენ ვინტეგრირდებით GitHub-თან, რათა Tuist-ის ანალიტიკა პირდაპირ თქვენს pull request-ებში მივაწოდოთ და ზოგიერთი კონფიგურაცია შევამციროთ, მაგალითად, ნაგულისხმები შტოს სინქრონიზაცია.

## მორგება {#setup}

თქვენს ორგანიზაციის `Integrations` ჩანართში უნდა დააინსტალიროთ Tuist GitHub-ის აპლიკაცია: ![სურათი, რომელიც ასახავს ინტეგრაციების ჩანართს](/images/guides/integrations/gitforge/github/integrations.png)

ასევე შეგიძლიათ აპლიკაციის პირდაპირ GitHub-დან დაინსტალირება. საჭიროების შემთხვევაში შედით Tuist-ში, დაამტკიცეთ GitHub App, რათა Tuist-მა შეამოწმოს თქვენი წვდომა ინსტალაციასთან და აირჩიეთ დასაკავშირებელი Tuist-ის ორგანიზაცია. თქვენ უნდა ფლობდეთ GitHub-ის ორგანიზაციას (ან პირად GitHub-ის ანგარიშს), სადაც აპლიკაცია ინსტალირდება. ხელმისაწვდომია მხოლოდ თქვენს მიერ ადმინისტრირებადი Tuist-ის ორგანიზაციები და თქვენი პირადი Tuist-ის ანგარიში. თუ მხოლოდ ერთი ანგარიშია ხელმისაწვდომი, Tuist მას ავტომატურად აკავშირებს არჩევნის ფანჯრის გამოჩენის გარეშე. როცა Tuist-დან იწყებთ, ორგანიზაცია უკვე არჩეულია და ეს ნაბიჯი გამოტოვებულია.

ამის შემდეგ შეგიძლიათ დაამატოთ პროექტის კავშირი თქვენს GitHub-რეპოზიტორიასა და Tuist-ის პროექტს შორის:

![სურათი, რომელიც ასახავს პროექტის კავშირის დამატებას](/images/guides/integrations/gitforge/github/add-project-connection.png)

აპლიკაციის დაინსტალირების შემდეგ პროექტის დაკავშირება შესაძლებელია dashboard-ის გარეშეც:

- **CLI:** `tuist project repository connect owner/name`, და `tuist project repository disconnect` ბმულის წასაშლელად.
- **REST API:** `PUT` და `DELETE` ბოლოზე `/api/projects/{account_handle}/{project_handle}/vcs-connection`.
- **Model Context Protocol:** ინსტრუმენტები `connect_project_repository` და `disconnect_project_repository`.

რეპოზიტორია უნდა იყოს ისეთი, რომელსაც GitHub App-ის ინსტალაციას აქვს წვდომა, და პროექტი იღებს რეპოზიტორიის ნაგულისხმებ შტოს. ანგარიშის ტოკენებს სჭირდებათ `project:admin:write` scope.

> [!TIP]
> **IP-მისამართების თეთრ სიაში შეყვანა**
>
> თუ თქვენი GitHub-ის ორგანიზაცია იყენებს [IP-მისამართების თეთრ სიებს](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) ან თქვენი GitHub-ის ეგზემპლარი firewall-ის უკანაა, დარწმუნდით, რომ Tuist-ის <.localized_link href="/guides/server/network#outbound-ip-addresses">გამომავალი IP-მისამართები</.localized_link> თეთრ სიაში შეყვანილია, რათა ინტეგრაციამ შეძლოს თქვენს რეპოზიტორიასთან კომუნიკაცია.

### GitHub Enterprise Server {#github-enterprise-server}

Tuist ასევე ინტეგრირდება self-hosted GitHub Enterprise Server (GHES) ეგზემპლარებთან. GitHub-ის ინტეგრაციის ბარათში გადადით **Enterprise server** ჩანართზე, შეიყვანეთ თქვენი GHES-ის საბაზო URL (მაგალითად, `https://github.example.com`), და დააჭირეთ install.

რადგან GitHub Apps ერთ GitHub-ის ეგზემპლარამდეა შეზღუდული, Tuist ვერ გამოიყენებს თავის github.com-ის აპლიკაციას თქვენს GHES-ზე — ამის ნაცვლად, install ღილაკი გაგიყვანთ GitHub-ის [App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)-ში: GHES ადმინისტრატორს ატარებს ახალი Tuist App-ის რეგისტრაციის პროცესში ეგზემპლარზე, შემდეგ კი ახალი აპლიკაციის სერთიფიკატებს Tuist-ს უბრუნებს. Tuist ამ სერთიფიკატებს ინსტალაციის მიხედვით დაშიფრულად ინახავს და მომავალში ყოველ API-ზარში, webhook-ის ხელმოწერასა და თქვენს რეპოზიტორიებზე ბმულებში იყენებს.

დამატებითი Tuist-ის სერვერის კონფიგურაცია არ არის საჭირო; manifest flow ყველაფერს ავტომატურად ქმნის და აყენებს.

#### აპლიკაციის ნებართვები და webhook-ის მოვლენები {#github-app-permissions}

PR კომენტარებისა და bundle-ის ზომის შემოწმებებისთვის Tuist-ს სჭირდება შემდეგი **რეპოზიტორიის ნებართვები**:

| ნებართვა | წვდომა | გამოიყენება |
|---|---|---|
| მეტამონაცემები (`metadata`) | მხოლოდ კითხვა | რეპოზიტორიის ძირითადი მეტამონაცემები; GitHub-ის მიერ საჭიროა ყოველი აპლიკაციისთვის |
| Pull requests (`pull_requests`) | კითხვა და ჩაწერა | pull request-ების წაკითხვა, მათი head commit SHA-ს ჩათვლით, და PR კომენტარების ჩამოთვლა, გამოქვეყნება და განახლება |
| შემოწმებები (`checks`) | კითხვა და ჩაწერა | check run-ების შექმნა და განახლება, bundle-ის ზომის pass/fail შემოწმებების ჩათვლით |

Tuist იყენებს `check_run` webhook-ის მოვლენას bundle-ის ზომის შემოწმების მოქმედებების დასამუშავებლად. manifest flow ამ გამოწერას ავტომატურად აკონფიგურირებს.

github.com-ზე აპლიკაციის ხელით მორგებისთვის self-hosted Tuist-ის სერვერთან ერთად, იხილეთ <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">self-hosting-ის სახელმძღვანელო</.localized_link>.

#### ბრაუზერისა და API URL-ების გამიჯვნა {#separate-browser-and-api-urls}

თუ ინჟინრები GitHub Enterprise-ს შიდა hostname-ით ეწვდებიან, ხოლო მესამე მხარის სერვისები გარე proxy-ს იყენებენ, დააყენეთ ორივე მისამართი install-ზე დაჭერამდე:

| ველი | მაგალითი | გამოიყენება |
|---|---|---|
| **სერვერის URL** | `https://github.internal.company.com` | თქვენი ბრაუზერი, აპლიკაციის რეგისტრაციისა და ინსტალაციისთვის, და Tuist-დან GitHub-ზე ბმულებისთვის |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist-ის სერვერები, manifest-code-ის გაცვლის, წვდომის ტოკენების, რეპოზიტორიზე წვდომის, PR კომენტარებისა და შემოწმებებისთვის |

API URL არის სრული REST API-ის საბაზისო URL, `/api/v3`-ის ან თქვენი proxy-ს მიერ გამოჩენილი ეკვივალენტური ბილიკის ჩათვლით. Tuist არ ამატებს `/api/v3`-ს ცალსახად მითითებულ API URL-ზე. დატოვეთ ის ცარიელი, თუ ერთი hostname მუშაობს როგორც თქვენი ბრაუზერისთვის, ასევე Tuist-ისთვის; არსებული კავშირები განაგრძობენ `<Server URL>/api/v3`-ის გამოყენებას.

ორივე მისამართი უნდა მიმართავდეს **იმავე GitHub Enterprise ინსტანციას**. თქვენს ბრაუზერს სჭირდება მხოლოდ Server URL-თან მიღწევა, არა API proxy-სთან. Tuist-ის სერვერებს სჭირდება მხოლოდ API URL-თან მიღწევა, არა შიდა ბრაუზერის hostname-თან.

გარე proxy-სთვის:

- გამოიყენეთ HTTPS სერთიფიკატით, რომელსაც Tuist-ის სერვერები ენდობიან, და საჯარო DNS, რომელიც ხსნის საჯარო IP მისამართებს. API URL-ის გადაფარვა არ აუქმებს Tuist-ის private-IP/SSRF დაცვას. გადაფარვა უნდა მიმართავდეს თქვენს Enterprise ინსტანციას, არა `github.com`-ს ან `*.github.com` endpoint-ს.
- დაამატეთ allowlist-ში ყოველი Tuist-ის <.localized_link href="/guides/server/network#outbound-ip-addresses">გამავალი IP მისამართი</.localized_link>.
- გადაამისამართეთ Tuist-ის მიერ გამოყენებული REST API endpoint-ები, `POST /api/v3/app-manifests/{code}/conversions`-ის, `POST /api/v3/app/installations/{installation_id}/access_tokens`-ის და რეპოზიტორიის API endpoint-ების ჩათვლით კომენტარებისა და შემოწმებებისთვის. ესენი არის GitHub-ის upstream ბილიკები; გადათარგმნეთ ისინი, თუ თქვენი proxy სხვა პრეფიქსს აჩენს.
- გადაამისამართეთ მოთხოვნები GitHub-ზე HTTP გადამისამართებების ან ინტერაქტიული შესვლის გვერდის გარეშე. Tuist ავტომატურად არ მიჰყვება Enterprise API გადამისამართებებს, ამიტომ ისინი ვერ აუქმებენ საჯარო IP შემოწმებებს. manifest conversion endpoint უნდა იყოს ხელმისაწვდომი მორგების დროს, სანამ Tuist-ს ექნება აპლიკაციის სერთიფიკატები. GitHub Actions ლოგების ჩამოტვირთვები არის გამონაკლისი: Tuist მიჰყვება ხელმოწერილ არქივის გადამისამართებებს მხოლოდ HTTPS-ით, ამოწმებს და ამაგრებს ყოველ დანიშნულებას საჯარო IP-ზე და არ გადასცემს ინსტალაციის ტოკენს.

GitHub-მა შეიძლება დააბრუნოს pagination ბმულები თავისი შიდა hostname-ის გამოყენებით. Tuist ახდენს კონფიგურირებული GitHub ინსტანციის ბმულების გადაბაზირებას API URL-ზე, თქვენი proxy-ს ბილიკის პრეფიქსის შენარჩუნებით; არარელევანტური წყაროების ბმულები უარყოფილია.

ცალკე, GitHub-მა უნდა შეძლოს webhooks-ის მიწოდება `https://tuist.dev/webhooks/github`-ზე (ან `/webhooks/github`-ზე თქვენს self-hosted Tuist სერვერზე). ინჟინრებს უნდა შეეძლოთ Tuist-ზე დაბრუნება ბრაუზერის callback-ების დასასრულებლად. API URL არ ცვლის არცერთ დანიშნულებას.

ორგანიზაციის ადმინისტრატორებს ასევე შეუძლიათ შეცვალონ ან გაასუფთავონ API URL არსებულ Enterprise ინტეგრაციაზე ინტეგრაციის ბარათში **Save API URL**-ის გამოყენებით. აპლიკაციის ხელახლა ინსტალაცია ან პროექტის ხელახლა დაკავშირება არ არის საჭირო. გასუფთავება აღადგენს `<Server URL>/api/v3`-ს. შენახვა ამოწმებს URL ფორმატს, არა proxy-ს კავშირს. Webhook-ის დამუშავებას შეიძლება დასჭირდეს ერთ წუთამდე შეცვლილი მისამართის გამოსაყენებლად, რადგან ინსტალაციის ძიებები არის cached; უკვე მიმდინარე მოთხოვნებმა შეიძლება კვლავ გამოიყენონ წინა მისამართი.

> [!NOTE]
> **Enterprise გეგმა მხოლოდ hosted Tuist სერვერზე**
>
> Hosted Tuist სერვერზე (`https://tuist.dev`), GitHub Enterprise Server ინტეგრაცია ხელმისაწვდომია ექსკლუზიურად **Enterprise** გეგმაზე მყოფი ორგანიზაციებისთვის. Self-hosted Tuist განლაგებებს შეუძლიათ მისი გამოყენება ნებისმიერ გეგმაზე.

## Pull/merge request კომენტარები {#pull-merge-request-comments}

GitHub აპლიკაცია აქვეყნებს Tuist-ის გაშვების ანგარიშს, რომელიც მოიცავს PR-ის შეჯამებას, უახლეს <.localized_link href="/guides/features/previews/xcode#pullmerge-request-comments">previews</.localized_link> ან <.localized_link href="/guides/features/selective-testing#pullmerge-request-comments">tests</.localized_link>-ზე ბმულების ჩათვლით:

Tuist ანახლებს ერთ კომენტარს, როგორც კი შედეგები მოდის. Gradle ბილდები ჩნდება ცალ-ცალკე ყოველი root პროექტისა და მოთხოვნილი ამოცანების ნაკრებისთვის; იმავე ამოცანების ხელახლა გაშვება ცვლის იმ გამოძახების წინა შედეგს. სრული ბილდის ისტორია რჩება ხელმისაწვდომი Tuist-ზე.

კომენტარები ნაგულისხმევად ჩართულია, რაც ინარჩუნებს ანგარიშგებას არსებული ინტეგრაციებისთვის. მათ გამოსართავად ან ხელახლა ჩასართავად პროექტისთვის, გახსენით **Project Settings → Integrations** და ჩართეთ/გამორთეთ **GitHub → Run report comments**. ყოველ პროექტს აქვს საკუთარი პარამეტრი; რეპოზიტორიის კავშირები რჩება მართული ორგანიზაციის პარამეტრებში.

კომენტარების გამორთვა არ თიშავს ბილდის ან ტესტების ატვირთვას, GitHub Actions სამუშაოს შეჯამებებს, რეპოზიტორიის კავშირებს ან GitHub ინტეგრაციის სხვა ფუნქციებს. არსებული კომენტარები არ იშლება.

![სურათი, რომელიც აჩვენებს pull request კომენტარს](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **მოთხოვნები**
>
> კომენტარი ქვეყნდება მხოლოდ მაშინ, როცა თქვენი CI გაშვებები არის <.localized_link href="/guides/integrations/continuous-integration#authentication">authenticated</.localized_link>.

> [!NOTE]
> **Github_ref**
>
> თუ გაქვთ მორგებული workflow, რომელიც არ იწყება PR commit-ზე, არამედ მაგალითად, GitHub კომენტარზე, შეიძლება დაგჭირდეთ დარწმუნება, რომ `GITHUB_REF` ცვლადი დაყენებულია ან `refs/pull/<PR_NUMBER>/merge`-ზე, ან `refs/pull/<PR_NUMBER>/head`-ზე.
>
> შეგიძლიათ გაუშვათ შესაბამისი ბრძანება, როგორიცაა `tuist share`, პრეფიქსირებული `GITHUB_REF` გარემოს ცვლადით: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions სამუშაოს შეჯამება {#github-actions-job-summary}

Tuist CLI და Gradle plugin წერენ ტესტებისა და ბილდების შედეგებს GitHub Actions-ის [job summary](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)-ში. შეჯამება ბმავს სრულ ანგარიშს Tuist-ზე, სადაც ხელმისაწვდომია უფრო მდიდარი ინსაითები, როგორიცაა არასტაბილური ტესტები და bundle-ის ზომის ცვლილებები.

Gradle-ისთვის, ყოველი წარმატებით ატვირთული ბილდის ან ტესტის ანგარიში ამატებს საკუთარ შეჯამებას, ინარჩუნებს სხვა შინაარსს, რომელიც დაწერილია ისეთი ინსტრუმენტებით, როგორიცაა `gradle/actions/setup-gradle`. ეს მოითხოვს plugin-ის ვერსიას, რომელიც მოიცავს job summary მხარდაჭერას; უფრო ძველი Gradle plugin ვერსიები მხოლოდ ანგარიშგებენ GitHub App-ის PR კომენტარის მეშვეობით. GitHub App-ის დაკავშირება არ არის საჭირო job summaries-ისთვის და **Run report comments**-ის გამორთვა არ მოქმედებს მათზე.

როცა GitHub Actions შეჯამების დანიშნულება ხელმისაწვდომია, Gradle ელოდება ატვირთვებსა და შეჯამებებს გასვლამდე, მაშინაც კი, თუ `uploadInBackground` არის ჩართული. GitHub იჭერს შეჯამებას, როცა workflow ნაბიჯი სრულდება.

![სურათი, რომელიც აჩვენებს Tuist-ის გაშვების ანგარიშს GitHub Actions სამუშაოს შეჯამებაში](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

ეს განსაკუთრებით სასარგებლოა [merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)-თან ერთად. Merge queue გაშვება არ არის მიბმული pull request-ზე, ამიტომ კომენტარი არ ქვეყნდება, მაგრამ job summary კვლავ აჩენს შედეგებს.

> [!NOTE]
> **მოთხოვნები**
>
> Job summaries მოითხოვს ანგარიშის წარმატებულ ატვირთვას. Hosted Tuist სერვერზე, თქვენი CI გაშვებები უნდა იყოს <.localized_link href="/guides/integrations/continuous-integration#authentication">authenticated</.localized_link>. Self-hosted ინსტანციებს ასევე შეუძლიათ მიიღონ სერთიფიკატების გარეშე ანგარიშები, როცა ქსელში სანდო ანგარიშის გამოქვეყნება არის ჩართული.
