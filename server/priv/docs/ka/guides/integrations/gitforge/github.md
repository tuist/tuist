---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git-ფორჯები | ინტეგრაციები | სახელმძღვანელოები | Tuist",
  "description": "შეიტყვეთ, როგორ შეგიძლიათ Tuist-ის GitHub-თან ინტეგრირება გაუმჯობესებული სამუშაო პროცესებისთვის."
}
---
# GitHub ინტეგრაცია {#github}

Git რეპოზიტორიები არის პროგრამული უზრუნველყოფის პროექტების უმეტესობის ცენტრალური ნაწილი. ჩვენ ვინტეგრირდებით GitHub-თან, რათა Tuist-ის ანალიტიკა პირდაპირ თქვენს pull request-ებში მივაწოდოთ და ზოგიერთი კონფიგურაციის საჭიროება მოგაშოროთ, მაგალითად, ძირითადი შტოს სინქრონიზაცია.

## მოწყობა {#setup}

თქვენ უნდა დააინსტალიროთ Tuist GitHub აპლიკაცია თქვენი ორგანიზაციის `Integrations` ტაბში: ![სურათი, რომელიც ასახავს ინტეგრაციების ტაბს](/images/guides/integrations/gitforge/github/integrations.png)

ასევე შეგიძლიათ აპლიკაციის პირდაპირ GitHub-დან დაინსტალირება. საჭიროების შემთხვევაში, შედით Tuist-ში, ავტორიზეთ GitHub App, რათა Tuist-მა შეამოწმოს თქვენი წვდომა ინსტალაციასთან და აირჩიეთ დასაკავშირებელი Tuist ორგანიზაცია. თქვენ უნდა ფლობდეთ GitHub ორგანიზაციას (ან პირად GitHub ანგარიშს), სადაც აპლიკაციაა დაინსტალირებული. ხელმისაწვდომია მხოლოდ თქვენ მიერ ადმინისტრირებადი Tuist ორგანიზაციები და თქვენი პირადი Tuist ანგარიში. თუ მხოლოდ ერთი ანგარიშია ხელმისაწვდომი, Tuist მას ავტომატურად დააკავშირებს არჩევანის ჩვენების გარეშე. როდესაც Tuist-იდან იწყებთ, ორგანიზაცია უკვე შერჩეულია და ეს ნაბიჯი გამოტოვებულია.

ამის შემდეგ, შეგიძლიათ დაამატოთ პროექტის კავშირი თქვენს GitHub რეპოზიტორიასა და Tuist პროექტს შორის:

![სურათი, რომელიც ასახავს პროექტის კავშირის დამატებას](/images/guides/integrations/gitforge/github/add-project-connection.png)

აპლიკაციის დაინსტალირების შემდეგ, ასევე შეგიძლიათ პროექტის დაკავშირება dashboard-ის გარეშე:

- **CLI:** `tuist project repository connect owner/name`, და `tuist project repository disconnect` ბმულის წასაშლელად.
- **REST API:** `PUT` და `DELETE` მისამართზე `/api/projects/{account_handle}/{project_handle}/vcs-connection`.
- **Model Context Protocol:** ინსტრუმენტები `connect_project_repository` და `disconnect_project_repository`.

რეპოზიტორია უნდა იყოს ისეთი, რომელზეც GitHub App ინსტალაციას აქვს წვდომა, და პროექტი იღებს რეპოზიტორიის ძირითად შტოს. ანგარიშის ტოკენებს სჭირდებათ `project:admin:write` scope.

> [!TIP]
> **IP მისამართების თეთრ სიაში შეყვანა**
>
> თუ თქვენი GitHub ორგანიზაცია იყენებს [IP მისამართების ნებართვების სიას](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) ან თქვენი GitHub ინსტანცია სახანძრო კედლის უკანაა, დარწმუნდით, რომ Tuist-ის <.localized_link href="/guides/server/network#outbound-ip-addresses">შემომავალი IP მისამართები</.localized_link> შეყვანილია ნებართვების სიაში, რათა ინტეგრაციამ შეძლოს თქვენს რეპოზიტორთან კომუნიკაცია.

### GitHub Enterprise Server {#github-enterprise-server}

Tuist ასევე ინტეგრირდება self-hosted GitHub Enterprise Server (GHES) ინსტანციებთან. GitHub ინტეგრაციის ბარათში გადადით **Enterprise server** ტაბზე, შეიყვანეთ თქვენი GHES საბაზისო URL (მაგალითად, `https://github.example.com`), და დააჭირეთ install.

რადგან GitHub Apps მხოლოდ ერთ GitHub ინსტანციაზეა შეზღუდული, Tuist ვერ გამოიყენებს თავის github.com App-ს თქვენს GHES-ზე — ამის ნაცვლად, install ღილაკი გაგიყვანთ GitHub-ის [App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)-ში: GHES თქვენს ადმინისტრატორს გაატარებს ახალი Tuist App-ის რეგისტრაციის პროცესში ინსტანციაზე, შემდეგ კი ახალი App-ის სერთიფიკატებს Tuist-ს გადასცემს. Tuist ინახავს ამ სერთიფიკატებს დაშიფრულად თითოეული ინსტალაციისთვის და იყენებს მათ ყოველი API ზარის, webhook ხელმოწერისა და თქვენს რეპოზიტორიებზე ბმულებისთვის.

დამატებითი Tuist სერვერის კონფიგურაცია არ არის საჭირო; manifest flow ყველაფერს ავტომატურად ქმნის და აწვდის.

#### App-ის ნებართვები და webhook მოვლენები {#github-app-permissions}

PR კომენტარებისა და bundle-ის ზომის შემოწმებებისთვის Tuist-ს სჭირდება შემდეგი **რეპოზიტორიის ნებართვები**:

| ნებართვა | წვდომა | გამოიყენება |
|---|---|---|
| მეტამონაცემები (`metadata`) | მხოლოდ კითხვა | ძირითადი რეპოზიტორიის მეტამონაცემები; GitHub-ის მიერ საჭიროა ყოველი App-ისთვის |
| Pull requests (`pull_requests`) | კითხვა და ჩაწერა | Pull requests-ის წაკითხვა, მათი head commit SHA-ს ჩათვლით, და PR კომენტარების ჩამონათვალის შედგენა, გამოქვეყნება და განახლება |
| Checks (`checks`) | კითხვა და ჩაწერა | Check runs-ის შექმნა და განახლება, bundle-ის ზომის pass/fail შემოწმებების ჩათვლით |

Tuist იყენებს `check_run` webhook მოვლენას bundle-ის ზომის შემოწმების მოქმედებების დასამუშავებლად. Manifest flow ამ გამოწერას ავტომატურად აკონფიგურირებს.

github.com-ზე ხელით App-ის დასაყენებლად self-hosted Tuist სერვერთან ერთად, იხილეთ <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">self-hosting სახელმძღვანელო</.localized_link>.

#### ბრაუზერისა და API URL-ების განცალკევება {#separate-browser-and-api-urls}

თუ ინჟინრები GitHub Enterprise-ს შიდა ჰოსტნეიმით წვდებიან, ხოლო მესამე მხარის სერვისები გარე პროქსის იყენებენ, install-ზე დაჭერამდე ორივე მისამართი დააკონფიგურირეთ:

| ველი | მაგალითი | გამოიყენება |
|---|---|---|
| **Server URL** | `https://github.internal.company.com` | თქვენი ბრაუზერი App-ის რეგისტრაციისა და ინსტალაციისთვის, ასევე Tuist-დან GitHub-ზე ბმულებისთვის |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist-ის სერვერები manifest-code-ის გაცვლის, წვდომის ტოკენების, რეპოზიტორიის წვდომის, PR კომენტარებისა და checks-ისთვის |

API URL არის სრული REST API საბაზისო URL, `/api/v3`-ის ან თქვენი პროქსის მიერ გამოფენილი ეკვივალენტური ბილიკის ჩათვლით. Tuist არ ამატებს `/api/v3`-ს ცხადად მითითებულ API URL-ს. დატოვეთ ის ცარიელი, თუ ერთი ჰოსტნეიმი მუშაობს როგორც თქვენი ბრაუზერის, ისე Tuist-ისთვის; არსებული კავშირები განაგრძობენ `<Server URL>/api/v3`-ის გამოყენებას.

ორივე მისამართი უნდა მიმართავდეს **იმავე GitHub Enterprise ინსტანციას**. თქვენს ბრაუზერს მხოლოდ Server URL-ზე მიღწევა სჭირდება, არა API პროქსიზე. Tuist-ის სერვერებს მხოლოდ API URL-ზე მიღწევა სჭირდებათ, არა შიდა ბრაუზერის ჰოსტნეიმზე.

გარე პროქსისთვის:

- გამოიყენეთ HTTPS სერთიფიკატით, რომელსაც Tuist-ის სერვერები ენდობიან, და საჯარო DNS, რომელიც საჯარო IP მისამართებს ხსნის. API URL-ის გადაწერა არ აუქმებს Tuist-ის კერძო-IP/SSRF დაცვას. გადაწერამ უნდა მიმართოს თქვენს Enterprise ინსტანციას, არა `github.com`-ს ან `*.github.com` endpoint-ს.
- დაამატეთ allowlist-ში ყოველი Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">გამომავალი IP მისამართი</.localized_link>.
- გადაამისამართეთ REST API endpoint-ები, რომლებსაც Tuist იყენებს, `POST /api/v3/app-manifests/{code}/conversions`-ის, `POST /api/v3/app/installations/{installation_id}/access_tokens`-ის და კომენტარებისა და checks-ის რეპოზიტორიის API endpoint-ების ჩათვლით. ესენი GitHub-ის upstream ბილიკებია; გადათარგმნეთ ისინი, თუ თქვენი პროქსი სხვა პრეფიქსს აჩენს.
- გადაამისამართეთ მოთხოვნები GitHub-ზე HTTP გადამისამართებების ან ინტერაქტიული შესვლის გვერდის გარეშე. Tuist ავტომატურად არ მიჰყვება Enterprise API გადამისამართებებს, ამიტომ ისინი ვერ აუვლიან გვერდს საჯარო-IP შემოწმებებს. Manifest conversion endpoint უნდა იყოს ხელმისაწვდომი დაყენების დროს, სანამ Tuist-ს App-ის სერთიფიკატები ექნება. GitHub Actions ლოგების ჩამოტვირთვა გამონაკლისია: Tuist მიჰყვება ხელმოწერილ არქივის გადამისამართებებს მხოლოდ HTTPS-ით, ამოწმებს და ამაგრებს ყოველ დანიშნულებას საჯარო IP-ზე და არ გადასცემს ინსტალაციის ტოკენს.

GitHub-მა შეიძლება დააბრუნოს pagination ბმულები თავისი შიდა ჰოსტნეიმის გამოყენებით. Tuist ახდენს ბმულების rebasing-ს კონფიგურირებული GitHub ინსტანციიდან API URL-ზე, თქვენი პროქსის ბილიკის პრეფიქსის შენარჩუნებით; არარელევანტური წყაროების ბმულები უარყოფილია.

ცალკე, GitHub-მა უნდა შეძლოს webhooks-ის მიწოდება `https://tuist.dev/webhooks/github`-ზე (ან `/webhooks/github`-ზე თქვენს self-hosted Tuist სერვერზე). ინჟინრებს უნდა შეეძლოთ Tuist-ზე დაბრუნება ბრაუზერის callback-ების დასასრულებლად. API URL არ ცვლის არცერთ დანიშნულებას.

ორგანიზაციის ადმინისტრატორებს ასევე შეუძლიათ შეცვალონ ან გაასუფთავონ API URL არსებულ Enterprise ინტეგრაციაზე ინტეგრაციის ბარათში **Save API URL**-ის გამოყენებით. App-ის ხელახლა ინსტალაცია ან პროექტის ხელახლა მიერთება არ არის საჭირო. გასუფთავება აღადგენს `<Server URL>/api/v3`-ს. შენახვა ამოწმებს URL ფორმატს, არა პროქსის კავშირს. Webhook-ის დამუშავებას შეიძლება ერთი წუთი დასჭირდეს შეცვლილი მისამართის გამოსაყენებლად, რადგან ინსტალაციის ძიება cache-შია; ფრენაში უკვე მყოფი მოთხოვნები შეიძლება კვლავ წინა მისამართს იყენებდნენ.

> [!NOTE]
> **Enterprise გეგმა მხოლოდ hosted Tuist სერვერზე**
>
> Hosted Tuist სერვერზე (`https://tuist.dev`), GitHub Enterprise Server ინტეგრაცია ხელმისაწვდომია მხოლოდ **Enterprise** გეგმაზე მყოფი ორგანიზაციებისთვის. Self-hosted Tuist განლაგებებს შეუძლიათ მისი გამოყენება ნებისმიერ გეგმაზე.

## Pull/merge request კომენტარები {#pull-merge-request-comments}

GitHub app აქვეყნებს Tuist run report-ს, რომელიც მოიცავს PR-ის შეჯამებას, უახლესი <.localized_link href="/guides/features/previews#pullmerge-request-comments">previews</.localized_link> ან <.localized_link href="/guides/features/selective-testing#pullmerge-request-comments">tests</.localized_link> ბმულების ჩათვლით:

Tuist ანახლებს ერთ კომენტარს, როგორც კი შედეგები მოდის. Gradle ბილდები ჩანს ცალ-ცალკე თითოეული root project-ისა და მოთხოვნილი tasks-ის ნაკრებისთვის; იგივე tasks-ის ხელახლა გაშვება ცვლის ამ გამოძახების წინა შედეგს. სრული ბილდის ისტორია Tuist-ზე ხელმისაწვდომი რჩება.

კომენტარები ნაგულისხმევად ჩართულია, რაც ინარჩუნებს არსებული ინტეგრაციების ანგარიშგებას. მათ გამოსართავად ან ხელახლა ჩასართავად პროექტისთვის, გახსენით **Project Settings → Integrations** და ჩართეთ/გამორთეთ **GitHub → Run report comments**. თითოეულ პროექტს აქვს საკუთარი პარამეტრი; რეპოზიტორიის კავშირები კვლავ ორგანიზაციის პარამეტრებში იმართება.

კომენტარების გამორთვა არ თიშავს ბილდის ან ტესტის ატვირთვებს, GitHub Actions job summary-ებს, რეპოზიტორიის კავშირებს ან GitHub ინტეგრაციის სხვა ფუნქციებს. არსებული კომენტარები არ იშლება.

![სურათი, რომელიც აჩვენებს pull request კომენტარს](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **მოთხოვნები**
>
> კომენტარი ქვეყნდება მხოლოდ მაშინ, როცა თქვენი CI გაშვებები <.localized_link href="/guides/integrations/continuous-integration#authentication">ავთენტიკირებულია</.localized_link>.

> [!NOTE]
> **Github_ref**
>
> თუ გაქვთ custom workflow, რომელიც არ იწყება PR commit-ზე, არამედ მაგალითად, GitHub კომენტარზე, შეიძლება დაგჭირდეთ დარწმუნება, რომ `GITHUB_REF` ცვლადი დაყენებულია ან `refs/pull/<PR_NUMBER>/merge`-ზე, ან `refs/pull/<PR_NUMBER>/head`-ზე.
>
> შეგიძლიათ გაუშვათ შესაბამისი ბრძანება, როგორიცაა `tuist share`, პრეფიქსირებული `GITHUB_REF` გარემოს ცვლადით: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions job summary {#github-actions-job-summary}

Tuist CLI და Gradle plugin წერენ ტესტისა და ბილდის შედეგებს GitHub Actions-ის [job summary](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)-ში. შეჯამება ბმავს სრულ report-ზე Tuist-ზე, სადაც ხელმისაწვდომია უფრო მდიდარი insights, როგორიცაა არასტაბილური ტესტები და bundle-ის ზომის ცვლილებები.

Gradle-ისთვის, ყოველი წარმატებით ატვირთული ბილდის ან ტესტის report ამატებს საკუთარ შეჯამებას, რაც ინარჩუნებს ისეთი ინსტრუმენტების მიერ დაწერილ სხვა კონტენტს, როგორიცაა `gradle/actions/setup-gradle`. ეს მოითხოვს plugin-ის ვერსიას, რომელიც მოიცავს job summary მხარდაჭერას; Gradle plugin-ის უფრო ძველი ვერსიები მხოლოდ GitHub App-ის PR კომენტარით ანგარიშგებენ. GitHub App-ის მიერთება job summary-ებისთვის არ არის საჭირო და **Run report comments**-ის გამორთვა მათზე არ მოქმედებს.

როცა GitHub Actions summary დანიშნულება ხელმისაწვდომია, Gradle ელოდება ატვირთვებსა და შეჯამებებს გასვლამდე, მაშინაც კი, თუ `uploadInBackground` ჩართულია. GitHub იჭერს შეჯამებას, როცა workflow step მთავრდება.

![სურათი, რომელიც აჩვენებს Tuist run report-ს GitHub Actions job summary-ში](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

ეს განსაკუთრებით სასარგებლოა [merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)-თან ერთად. Merge queue გაშვება არ არის მიბმული pull request-ზე, ამიტომ კომენტარი არ ქვეყნდება, მაგრამ job summary კვლავ აჩენს შედეგებს.

> [!NOTE]
> **მოთხოვნები**
>
> Job summary-ებს სჭირდებათ წარმატებული report ატვირთვა. Hosted Tuist სერვერზე, თქვენი CI გაშვებები უნდა იყოს <.localized_link href="/guides/integrations/continuous-integration#authentication">ავთენტიკირებული</.localized_link>. Self-hosted ინსტანციებს ასევე შეუძლიათ მიიღონ სერთიფიკატების გარეშე report-ები, როცა ქსელში სანდო report-ის გამოქვეყნება ჩართულია.
