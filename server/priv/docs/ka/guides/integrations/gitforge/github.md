---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git-ფორჯები | ინტეგრაციები | სახელმძღვანელოები | Tuist",
  "description": "შეიტყვეთ, როგორ შეგიძლიათ Tuist-ის GitHub-თან ინტეგრაცია გაუმჯობესებული სამუშაო პროცესებისთვის."
}
---
# GitHub-ის ინტეგრაცია {#github}

Git რეპოზიტორიები პროგრამული უზრუნველყოფის პროექტების უმეტესობის ცენტრალური ნაწილია. ჩვენ ვინტეგრირდებით GitHub-თან, რათა Tuist-ის ანალიტიკა პირდაპირ თქვენს pull request-ებში მივაწოდოთ და ზოგიერთი კონფიგურაცია შევინარჩუნოთ, მაგალითად, თქვენი ძირითადი შტოს სინქრონიზაცია.

## მოწყობა {#setup}

თქვენ უნდა დააინსტალიროთ Tuist GitHub აპი თქვენი ორგანიზაციის `Integrations` ჩანართში: ![სურათი, რომელიც ასახავს ინტეგრაციების ჩანართს](/images/guides/integrations/gitforge/github/integrations.png)

ასევე შეგიძლიათ აპის პირდაპირ GitHub-დან დააინსტალიროთ. საჭიროების შემთხვევაში, შედით Tuist-ში, ავტორიზეთ GitHub App, რათა Tuist-მა შეამოწმოს თქვენი წვდომა ინსტალაციასთან, და აირჩიეთ დასაკავშირებელი Tuist ორგანიზაცია. თქვენ უნდა ფლობდეთ GitHub ორგანიზაციას (ან პირად GitHub ანგარიშს), სადაც აპი ინსტალირდება. ხელმისაწვდომია მხოლოდ თქვენ მიერ ადმინისტრირებადი Tuist ორგანიზაციები და თქვენი პირადი Tuist ანგარიში. Tuist გამოტოვებს არჩევანს მხოლოდ მაშინ, როდესაც აპი ინსტალირებულია თქვენს პირად GitHub ანგარიშზე და თქვენი პირადი Tuist ანგარიში ერთადერთი ვარიანტია. GitHub ორგანიზაციისთვის Tuist ყოველთვის ითხოვს არჩევანს, მაშინაც კი, თუ თქვენი პირადი ანგარიში ერთადერთი ვარიანტია. თუ თქვენი გუნდის Tuist ორგანიზაცია სიაში არ არის, აირჩიეთ **ორგანიზაციის შექმნა**, ან სთხოვეთ მის ერთ-ერთ ადმინისტრატორს, გახადოთ ადმინისტრატორად. სია განახლდება გვერდის გახსნილობისას, ამიტომ ორგანიზაცია გამოჩნდება თავიდან დაწყების გარეშე, თუ მას Tuist-ზე დაბრუნებიდან ათი წუთის განმავლობაში აირჩევთ. როდესაც Tuist-დან იწყებთ, ორგანიზაცია უკვე არჩეულია და ეს ნაბიჯი გამოტოვებულია.

ამის შემდეგ, შეგიძლიათ დაამატოთ პროექტის კავშირი თქვენს GitHub რეპოზიტორიასა და თქვენს Tuist პროექტს შორის:

![სურათი, რომელიც ასახავს პროექტის კავშირის დამატებას](/images/guides/integrations/gitforge/github/add-project-connection.png)

აპის ინსტალაციის შემდეგ, ასევე შეგიძლიათ დააკავშიროთ პროექტი დაშბორდის გარეშე:

- **CLI:** `tuist project repository connect owner/name`, და `tuist project repository disconnect` ბმულის წასაშლელად.
- **REST API:** `PUT` და `DELETE` ბმულზე `/api/projects/{account_handle}/{project_handle}/vcs-connection`.
- **Model Context Protocol:** ინსტრუმენტები `connect_project_repository` და `disconnect_project_repository`.

რეპოზიტორია უნდა იყოს ისეთი, რომელსაც GitHub App ინსტალაცია წვდომას აქვს, და პროექტი იღებს რეპოზიტორიის ძირითად შტოს. ანგარიშის ტოკენებს სჭირდებათ `project:admin:write` სკოუპი.

> [!TIP]
> **IP მისამართების თეთრ სიაში შეყვანა**
>
> თუ თქვენი GitHub ორგანიზაცია იყენებს [IP მისამართების თეთრ სიებს](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) ან თქვენი GitHub ინსტანცია სახანძრო კედლის უკანაა, დარწმუნდით, რომ Tuist-ის <.localized_link href="/guides/server/network#outbound-ip-addresses">გამავალი IP მისამართები</.localized_link> თეთრ სიაში შეიყვანეთ, რათა ინტეგრაციამ შეძლოს თქვენს რეპოზიტორიასთან კომუნიკაცია.

### GitHub Enterprise Server {#github-enterprise-server}

Tuist ასევე ინტეგრირდება თვითმასპინძელ GitHub Enterprise Server (GHES) ინსტანციებთან. GitHub ინტეგრაციის ბარათში გადადით **Enterprise server** ჩანართზე, შეიყვანეთ თქვენი GHES საბაზო URL (მაგალითად `https://github.example.com`), და დააჭირეთ ინსტალაციას.

რადგან GitHub Apps ერთ GitHub ინსტანციაზეა შეზღუდული, Tuist ვერ გამოიყენებს თავის github.com აპს თქვენს GHES-ზე — ამის ნაცვლად, ინსტალაციის ღილაკი გაგიყვანთ GitHub-ის [App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)-ში: GHES მიჰყავს თქვენს ადმინისტრატორს ახალი Tuist App-ის რეგისტრაციის პროცესში ინსტანციაზე, შემდეგ კი აბრუნებს ახალი აპის სერთიფიკატებს Tuist-ში. Tuist ინახავს ამ სერთიფიკატებს დაშიფრულად თითოეული ინსტალაციისთვის და იყენებს მათ ყოველი API ზარისთვის, webhook ხელმოწერისთვის და თქვენს რეპოზიტორიებზე ბმულებისთვის მომავალში.

დამატებითი Tuist სერვერის კონფიგურაცია არ არის საჭირო; manifest flow ავტომატურად ქმნის და აწვდის ყველაფერს.

#### აპის ნებართვები და webhook მოვლენები {#github-app-permissions}

Tuist-ს სჭირდება შემდეგი **რეპოზიტორიის ნებართვები** PR კომენტარებისა და bundle-ის ზომის შემოწმებებისთვის:

| ნებართვა | წვდომა | გამოიყენება |
|---|---|---|
| მეტამონაცემები (`metadata`) | მხოლოდ კითხვა | ძირითადი რეპოზიტორიის მეტამონაცემები; GitHub-ის მიერ მოთხოვნილია ყოველი აპისთვის |
| Pull requests (`pull_requests`) | კითხვა და ჩაწერა | pull request-ების წაკითხვა, მათი head commit SHA-ს ჩათვლით, და PR კომენტარების ჩამოთვლა, გამოქვეყნება და განახლება |
| Checks (`checks`) | კითხვა და ჩაწერა | check runs-ის შექმნა და განახლება, bundle-ის ზომის pass/fail შემოწმებების ჩათვლით |

Tuist იყენებს `check_run` webhook მოვლენას bundle-ის ზომის შემოწმების მოქმედებების დასამუშავებლად. manifest flow ავტომატურად აკონფიგურირებს ამ გამოწერას.

github.com-ზე აპის ხელით მოწყობისთვის თვითმასპინძელ Tuist სერვერთან, იხილეთ <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">თვითმასპინძლობის სახელმძღვანელო</.localized_link>.

#### ბრაუზერისა და API URL-ების გამიჯვნა {#separate-browser-and-api-urls}

თუ ინჟინრები GitHub Enterprise-ს შიდა ჰოსტნეიმით უკავშირდებიან, ხოლო მესამე მხარის სერვისები გარე პროქსის იყენებენ, ინსტალაციაზე დაჭერამდე დააკონფიგურირეთ ორივე მისამართი:

| ველი | მაგალითი | გამოიყენება |
|---|---|---|
| **სერვერის URL** | `https://github.internal.company.com` | თქვენი ბრაუზერი, აპის რეგისტრაციისა და ინსტალაციისთვის, და Tuist-დან GitHub-ზე ბმულებისთვის |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist-ის სერვერები, manifest-code გაცვლისთვის, წვდომის ტოკენებისთვის, რეპოზიტორიის წვდომისთვის, PR კომენტარებისა და checks-ისთვის |

API URL არის სრული REST API საბაზისო URL, `/api/v3`-ის ან თქვენი პროქსის მიერ გამოჩენილი ეკვივალენტური გზის ჩათვლით. Tuist არ ამატებს `/api/v3`-ს ცხად API URL-ს. დატოვეთ ის ცარიელი, თუ ერთი ჰოსტნეიმი მუშაობს როგორც თქვენი ბრაუზერისთვის, ასევე Tuist-ისთვის; არსებული კავშირები განაგრძობენ `<Server URL>/api/v3`-ის გამოყენებას.

ორივე მისამართი უნდა მიემართებოდეს **GitHub Enterprise-ის იმავე ინსტანსს**. თქვენს ბრაუზერს მხოლოდ სერვერის URL-თან მიღწევა სჭირდება, არა API პროქსთან. Tuist-ის სერვერებს მხოლოდ API URL-თან მიღწევა სჭირდებათ, არა შიდა ბრაუზერის ჰოსტნეიმთან.

გარე პროქსისთვის:

- გამოიყენეთ HTTPS სერთიფიკატით, რომელსაც Tuist-ის სერვერები ენდობიან, და საჯარო DNS, რომელიც საჯარო IP მისამართებზე გადაიხედება. API URL-ის გადაფარვა არ აუქმებს Tuist-ის პირადი-IP/SSRF დაცვას. გადაფარვა უნდა მიემართებოდეს თქვენს Enterprise ინსტანსს, არა `github.com`-ს ან `*.github.com` endpoint-ს.
- დაამატეთ ყველა Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">გამავალი IP მისამართი</.localized_link> allowlist-ში.
- გადაამისამართეთ REST API endpoint-ები, რომლებსაც Tuist იყენებს, `POST /api/v3/app-manifests/{code}/conversions`-ის, `POST /api/v3/app/installations/{installation_id}/access_tokens`-ის და რეპოზიტორიის API endpoint-ების ჩათვლით კომენტარებისა და checks-ისთვის. ესენი არის GitHub-ის upstream გზები; გადათარგმნეთ ისინი, თუ თქვენი პროქსი სხვა პრეფიქსს ამჟავნებს.
- გადაამისამართეთ მოთხოვნები GitHub-ზე HTTP გადამისამართებების ან ინტერაქტიული შესვლის გვერდის გარეშე. Tuist არ მიჰყვება Enterprise API გადამისამართებებს ავტომატურად, ამიტომ ისინი ვერ აუვლიან გვერდს საჯარო-IP შემოწმებებს. manifest conversion endpoint ხელმისაწვდომი უნდა იყოს მოწყობის დროს, სანამ Tuist-ს ექნება აპის სერთიფიკატები. GitHub Actions ლოგების ჩამოტვირთვები არის გამონაკლისი: Tuist მიჰყვება ხელმოწერილ არქივის გადამისამართებებს მხოლოდ HTTPS-ზე, ამოწმებს და ამაგრებს ყველა დანიშნულებას საჯარო IP-ზე და არ გადასცემს ინსტალაციის ტოკენს.

GitHub-მა შეიძლება დააბრუნოს პაგინაციის ბმულები თავისი შიდა ჰოსტნეიმის გამოყენებით. Tuist ახდენს ბმულების გადაბაზირებას კონფიგურირებული GitHub ინსტანსიდან API URL-ზე, ინარჩუნებს თქვენი პროქსის გზის პრეფიქსს; ბმულები დაუკავშირებელ წყაროებზე უარყოფილია.

ცალკე, GitHub-მა უნდა შეძლოს webhooks-ის მიწოდება `https://tuist.dev/webhooks/github`-ზე (ან `/webhooks/github`-ზე თქვენს თვითმასპინძელ Tuist სერვერზე). ინჟინრებს უნდა შეეძლოთ Tuist-ზე დაბრუნება ბრაუზერის callback-ების დასასრულებლად. API URL არ ცვლის არცერთ დანიშნულებას.

ორგანიზაციის ადმინისტრატორებს ასევე შეუძლიათ შეცვალონ ან გაასუფთაონ API URL არსებულ Enterprise ინტეგრაციაზე ინტეგრაციის ბარათში **Save API URL**-ის გამოყენებით. აპის ხელახალი ინსტალაცია ან პროექტის ხელახალი დაკავშირება არ არის საჭირო. გასუფთავება აღადგენს `<Server URL>/api/v3`-ს. შენახვა ამოწმებს URL ფორმატს, არა პროქსის კავშირს. Webhook-ის დამუშავებას შეიძლება ერთი წუთი დასჭირდეს შეცვლილი მისამართის გამოსაყენებლად, რადგან ინსტალაციის ძიებები cached-ია; მოთხოვნები, რომლებიც უკვე მიმდინარეობს, შეიძლება კვლავ იყენებდნენ წინა მისამართს.

> [!NOTE]
> **Enterprise გეგმა მხოლოდ hosted Tuist სერვერზე**
>
> hosted Tuist სერვერზე (`https://tuist.dev`), GitHub Enterprise Server ინტეგრაცია ხელმისაწვდომია მხოლოდ **Enterprise** გეგმაზე მყოფი ორგანიზაციებისთვის. თვითმასპინძელ Tuist განლაგებებს შეუძლიათ მისი გამოყენება ნებისმიერ გეგმაზე.

## Pull/merge request კომენტარები {#pull-merge-request-comments}

GitHub აპი აქვეყნებს Tuist run report-ს, რომელიც მოიცავს PR-ის შეჯამებას, უახლეს <.localized_link href="/guides/features/previews/xcode#pullmerge-request-comments">previews</.localized_link>-ზე ან <.localized_link href="/guides/features/selective-testing/generated-xcode-project#pullmerge-request-comments">tests</.localized_link>-ზე ბმულების ჩათვლით:

Tuist აახლებს ერთ კომენტარს, როგორც კი შედეგები მოდის. Gradle builds ჩანს ცალ-ცალკე თითოეული root project-ისა და მოთხოვნილი tasks-ის ნაკრებისთვის; იგივე tasks-ის ხელახლა გაშვება ცვლის ამ გამოძახების წინა შედეგს. სრული build ისტორია ხელმისაწვდომია Tuist-ზე.

კომენტარები ჩართულია ნაგულისხმევად, რაც ინარჩუნებს ანგარიშგებას არსებული ინტეგრაციებისთვის. მათ გამოსართავად ან ხელახლა ჩასართავად პროექტისთვის, გახსენით **Project Settings → Integrations** და გადართეთ **GitHub → Run report comments**. თითოეულ პროექტს აქვს საკუთარი პარამეტრი; რეპოზიტორიის კავშირები კვლავ იმართება ორგანიზაციის პარამეტრებში.

კომენტარების გათიშვა არ თიშავს build ან test ატვირთვებს, GitHub Actions job summaries-ს, რეპოზიტორიის კავშირებს ან სხვა GitHub ინტეგრაციის ფუნქციებს. არსებული კომენტარები არ იშლება.

![სურათი, რომელიც აჩვენებს pull request კომენტარს](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **მოთხოვნები**
>
> კომენტარი ქვეყნდება მხოლოდ მაშინ, როდესაც თქვენი CI runs არიან <.localized_link href="/guides/server/authentication#continuous-integration">აუთენტიფიცირებული</.localized_link>.

> [!NOTE]
> **`GITHUB_REF`**
>
> თუ გაქვთ custom workflow, რომელიც არ არის გაშვებული PR commit-ზე, არამედ მაგალითად, GitHub კომენტარზე, შეიძლება დაგჭირდეთ დარწმუნება, რომ `GITHUB_REF` ცვლადი დაყენებულია ან `refs/pull/<PR_NUMBER>/merge`-ზე, ან `refs/pull/<PR_NUMBER>/head`-ზე.
>
> შეგიძლიათ გაუშვათ შესაბამისი ბრძანება, როგორიცაა `tuist share`, პრეფიქსირებული `GITHUB_REF` გარემოს ცვლადით: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions job summary {#github-actions-job-summary}

Tuist CLI და Gradle plugin წერენ test და build შედეგებს GitHub Actions-ის [job summary](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)-ში. შეჯამება ბმავს სრულ report-ს Tuist-ზე, სადაც ხელმისაწვდომია უფრო მდიდარი insights, როგორიცაა არასტაბილური ტესტები და bundle-size deltas.

Gradle-ისთვის, თითოეული წარმატებით ატვირთული build ან test report ამატებს საკუთარ შეჯამებას, ინარჩუნებს სხვა კონტენტს, რომელიც დაწერილია ისეთი ინსტრუმენტების მიერ, როგორიცაა `gradle/actions/setup-gradle`. ეს მოითხოვს plugin ვერსიას, რომელიც მოიცავს job summary მხარდაჭერას; უფრო ძველი Gradle plugin ვერსიები მხოლოდ ანგარიშობენ GitHub App-ის PR კომენტარის მეშვეობით. GitHub App-ს არ სჭირდება დაკავშირება job summaries-სთვის და **Run report comments**-ის გათიშვა არ ახდენს მათზე გავლენას.

როდესაც GitHub Actions summary დანიშნულება ხელმისაწვდომია, Gradle ელოდება ატვირთვებსა და შეჯამებებს გასვლამდე, მაშინაც კი, თუ `uploadInBackground` არის ჩართული. GitHub იჭერს შეჯამებას, როდესაც workflow step სრულდება.

![სურათი, რომელიც აჩვენებს Tuist run report-ს GitHub Actions job summary-ში](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

ეს განსაკუთრებით სასარგებლოა [merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)-თან. merge queue run არ არის მიბმული pull request-ზე, ამიტომ კომენტარი არ ქვეყნდება, მაგრამ job summary კვლავ აჩვენებს შედეგებს.

> [!NOTE]
> **მოთხოვნები**
>
> Job summaries მოითხოვს წარმატებულ report ატვირთვას. hosted Tuist სერვერზე, თქვენი CI runs უნდა იყოს <.localized_link href="/guides/server/authentication#continuous-integration">აუთენტიფიცირებული</.localized_link>. თვითმასპინძელ ინსტანსებს ასევე შეუძლიათ მიიღონ credential-free reports, როდესაც network-trusted report publishing არის ჩართული.
