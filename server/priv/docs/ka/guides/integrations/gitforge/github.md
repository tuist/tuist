---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git-ფორჯები | ინტეგრაციები | სახელმძღვანელოები | Tuist",
  "description": "შეიტყვეთ, როგორ დააინტეგროთ Tuist GitHub-თან გაუმჯობესებული სამუშაო პროცესებისთვის."
}
---
# GitHub-ის ინტეგრაცია {#github}

Git რეპოზიტორიები პროგრამული პროექტების უმეტესობის საფუძველია. ჩვენ ვინტეგრირდებით GitHub-თან, რათა Tuist-ის ანალიტიკა პირდაპირ თქვენს pull request-ებში იყოს ხელმისაწვდომი და ზოგიერთი კონფიგურაცია შევამციროთ, მაგალითად, ნაგულისხმები ტოტის სინქრონიზაცია.

## მოწყობა {#setup}

თქვენ უნდა დააინსტალიროთ Tuist-ის GitHub აპი თქვენი ორგანიზაციის `Integrations` ჩანართში: ![სურათი, რომელიც ასახავს ინტეგრაციების ჩანართს](/images/guides/integrations/gitforge/github/integrations.png)

აპის ინსტალაცია შესაძლებელია პირდაპირ GitHub-დანაც. საჭიროების შემთხვევაში შედით Tuist-ში, მიანიჭეთ GitHub App-ს წვდომა, რათა Tuist-მა შეამოწმოს თქვენი წვდომა ინსტალაციაზე, და აირჩიეთ დასაკავშირებელი Tuist ორგანიზაცია. თქვენ უნდა ფლობდეთ GitHub ორგანიზაციას (ან პირად GitHub ანგარიშს), სადაც აპი ინსტალირდება. ხელმისაწვდომია მხოლოდ თქვენ მიერ ადმინისტრირებადი Tuist ორგანიზაციები და თქვენი პირადი Tuist ანგარიში. Tuist გამოტოვებს არჩევანს მხოლოდ მაშინ, როცა აპი ინსტალირებულია თქვენს პირად GitHub ანგარიშზე და თქვენი პირადი Tuist ანგარიში ერთადერთი ვარიანტია. GitHub ორგანიზაციისთვის Tuist ყოველთვის ითხოვს არჩევანს, მაშინაც კი, თუ თქვენი პირადი ანგარიში ერთადერთი ვარიანტია. თუ თქვენი გუნდის Tuist ორგანიზაცია სიაში არ ჩანს, აირჩიეთ **ორგანიზაციის შექმნა**, ან სთხოვეთ მის ერთ-ერთ ადმინისტრატორს, გახდეთ ადმინისტრატორი. სია განახლდება გვერდის გახსნილ მდგომარეობაში, ამიტომ ორგანიზაცია გამოჩნდება თავიდან დაწყების გარეშე, თუ მას Tuist-ზე დაბრუნებიდან ათი წუთის განმავლობაში აირჩევთ. როცა Tuist-დან იწყებთ, ორგანიზაცია უკვე შერჩეულია და ეს ნაბიჯი გამოტოვებულია.

ამის შემდეგ შეგიძლიათ დაამატოთ პროექტის კავშირი თქვენს GitHub რეპოზიტორიასა და Tuist პროექტს შორის:

![სურათი, რომელიც ასახავს პროექტის კავშირის დამატებას](/images/guides/integrations/gitforge/github/add-project-connection.png)

აპის ინსტალაციის შემდეგ პროექტის მიბმაც შესაძლებელია დაშბორდის გარეშე:

- **CLI:** `tuist project repository connect owner/name`, და `tuist project repository disconnect` ბმულის მოსაშორებლად.
- **REST API:** `PUT` და `DELETE` ბოლოზე `/api/projects/{account_handle}/{project_handle}/vcs-connection`.
- **Model Context Protocol:** ხელსაწყოები `connect_project_repository` და `disconnect_project_repository`.

რეპოზიტორია უნდა იყოს ისეთი, რომელზეც GitHub App ინსტალაციას აქვს წვდომა, და პროექტი იღებს რეპოზიტორიის ნაგულისხმებ ტოტს. ანგარიშის ტოკენებს სჭირდებათ `project:admin:write` სკოუპი.

> [!TIP]
> **IP-მისამართების თეთრ სიაში დამატება**
>
> თუ თქვენი GitHub ორგანიზაცია იყენებს [IP-მისამართების თეთრ სიებს](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) ან თქვენი GitHub ეგზემპლარი ცეცხლკედლის უკანაა, დარწმუნდით, რომ Tuist-ის <.localized_link href="/guides/server/network#outbound-ip-addresses">გამომავალი IP-მისამართები</.localized_link> თეთრ სიაშია, რათა ინტეგრაციამ შეძლოს თქვენს რეპოზიტორიასთან კომუნიკაცია.

### GitHub Enterprise Server {#github-enterprise-server}

Tuist ასევე ინტეგრირდება თვითმასპინძლებელ GitHub Enterprise Server (GHES) ეგზემპლარებთან. GitHub ინტეგრაციის ბარათში გადადით **Enterprise server** ჩანართზე, შეიყვანეთ თქვენი GHES-ის საბაზო URL (მაგალითად, `https://github.example.com`), და დააჭირეთ ინსტალაციას.

რადგან GitHub Apps ერთ GitHub ეგზემპლარზეა შეზღუდული, Tuist ვერ გამოიყენებს თავის github.com აპს თქვენს GHES-ზე — ამის ნაცვლად, ინსტალაციის ღილაკი გაგიყვანთ GitHub-ის [App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)-ში: GHES თქვენს ადმინისტრატორს გაატარებს ეგზემპლარზე ახალი Tuist App-ის რეგისტრაციის პროცესში, შემდეგ კი ახალი აპის მონაცემებს Tuist-ს გადასცემს. Tuist ამ მონაცემებს ინსტალაციის მიხედვით დაშიფრულად ინახავს და იყენებს ყოველ API გამოძახებაში, webhook-ის ხელმოწერასა და თქვენს რეპოზიტორიებზე ბმულებში.

დამატებითი Tuist სერვერის კონფიგურაცია არ არის საჭირო; manifest flow ყველაფერს ავტომატურად ქმნის და აწვდის.

#### აპის ნებართვები და webhook მოვლენები {#github-app-permissions}

PR კომენტარებისა და bundle-ის ზომის შემოწმებებისთვის Tuist-ს სჭირდება შემდეგი **რეპოზიტორიის ნებართვები**:

| ნებართვა | წვდომა | გამოიყენება |
|---|---|---|
| მეტამონაცემები (`metadata`) | მხოლოდ კითხვა | ძირითადი რეპოზიტორიის მეტამონაცემები; GitHub-ის მიერ საჭიროა ყოველი აპისთვის |
| Pull requests (`pull_requests`) | კითხვა და ჩაწერა | Pull request-ების წაკითხვა, მათ შორის head commit SHA, და PR კომენტარების სიაში გამოტანა, გამოქვეყნება და განახლება |
| Checks (`checks`) | კითხვა და ჩაწერა | Check run-ების შექმნა და განახლება, მათ შორის bundle-ის ზომის pass/fail შემოწმებები |

Tuist იყენებს `check_run` webhook მოვლენას bundle-ის ზომის შემოწმების ქმედებების დასამუშავებლად. Manifest flow ამ გამოწერას ავტომატურად აკონფიგურირებს.

github.com-ზე აპის ხელით მოწყობისთვის თვითმასპინძლებელ Tuist სერვერთან, იხილეთ <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">თვითმასპინძლობის სახელმძღვანელო</.localized_link>.

#### ბრაუზერისა და API URL-ების განცალკევება {#separate-browser-and-api-urls}

თუ ინჟინრები GitHub Enterprise-ს შიდა ჰოსტნეიმით უკავშირდებიან, ხოლო მესამე მხარის სერვისები გარე პროქსის იყენებენ, ინსტალაციაზე დაჭერამდე კონფიგურირეთ ორივე მისამართი:

| ველი | მაგალითი | გამოიყენება |
|---|---|---|
| **Server URL** | `https://github.internal.company.com` | თქვენი ბრაუზერი, აპის რეგისტრაციისა და ინსტალაციისთვის, და GitHub-ზე ბმულებისთვის Tuist-დან |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist-ის სერვერები, manifest-code-ის გაცვლის, წვდომის ტოკენების, რეპოზიტორიის წვდომის, PR კომენტარებისა და checks-ებისთვის |

API URL არის სრული REST API საბაზისო URL, `/api/v3`-ის ან თქვენი პროქსის მიერ გამოჩენილი ეკვივალენტური ბილიკის ჩათვლით. Tuist არ ამატებს `/api/v3`-ს ცხად API URL-ს. დატოვეთ ცარიელი, თუ ერთი ჰოსტნეიმი მუშაობს როგორც თქვენი ბრაუზერის, ისე Tuist-ისთვის; არსებული კავშირები განაგრძობენ `<Server URL>/api/v3`-ის გამოყენებას.

ორივე მისამართი უნდა მიემართებოდეს **GitHub Enterprise-ის იმავე ინსტანსს**. თქვენს ბრაუზერს მხოლოდ Server URL-თან მიღწევა სჭირდება, არა API პროქსთან. Tuist-ის სერვერებს მხოლოდ API URL-თან მიღწევა სჭირდებათ, არა შიდა ბრაუზერის ჰოსტნეიმთან.

გარე პროქსისთვის:

- გამოიყენეთ HTTPS სერთიფიკატით, რომელსაც Tuist-ის სერვერები ენდობიან, და საჯარო DNS, რომელიც საჯარო IP მისამართებზე იხსნება. API URL-ის გადაკეთებები არ ავლიან Tuist-ის პირადი-IP/SSRF დაცვას. გადაკეთება უნდა მიემართებოდეს თქვენს Enterprise ინსტანსს, არა `github.com`-ს ან `*.github.com` endpoint-ს.
- დაამატეთ whitelist-ში ყველა Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">გამავალი IP მისამართი</.localized_link>.
- გადაამისამართეთ REST API endpoint-ები, რომლებსაც Tuist იყენებს, მათ შორის `POST /api/v3/app-manifests/{code}/conversions`, `POST /api/v3/app/installations/{installation_id}/access_tokens`, და რეპოზიტორიის API endpoint-ები კომენტარებისა და checks-ებისთვის. ესენი არის GitHub-ის upstream ბილიკები; გადათარგმნეთ ისინი, თუ თქვენი პროქსი სხვა პრეფიქსს აჩენს.
- გადაამისამართეთ მოთხოვნები GitHub-ზე HTTP გადამისამართებების ან ინტერაქტიული შესვლის გვერდის გარეშე. Tuist ავტომატურად არ მიჰყვება Enterprise API გადამისამართებებს, ამიტომ ისინი ვერ ავლიან საჯარო-IP შემოწმებებს. Manifest conversion endpoint ხელმისაწვდომი უნდა იყოს მოწყობის დროს, სანამ Tuist-ს აპის სერთიფიკატები ექნება. GitHub Actions ლოგების ჩამოტვირთვები გამონაკლისია: Tuist მიჰყვება ხელმოწერილ არქივის გადამისამართებებს მხოლოდ HTTPS-ით, ამოწმებს და ამაგრებს ყოველ დანიშნულებას საჯარო IP-ზე და არ გადასცემს ინსტალაციის ტოკენს.

GitHub-მა შეიძლება დააბრუნოს pagination ბმულები თავისი შიდა ჰოსტნეიმის გამოყენებით. Tuist ახდენს ბმულების გადაბაზირებას კონფიგურირებული GitHub ინსტანსიდან API URL-ზე, ინარჩუნებს თქვენი პროქსის ბილიკის პრეფიქსს; ბმულები არარელევანტური წყაროებისკენ უარყოფილია.

ცალკე, GitHub-მა უნდა შეძლოს webhooks-ის მიწოდება `https://tuist.dev/webhooks/github`-ზე (ან `/webhooks/github`-ზე თქვენს თვითმასპინძლებელ Tuist სერვერზე). ინჟინრებს უნდა შეეძლოთ Tuist-ზე დაბრუნება ბრაუზერის callback-ების დასასრულებლად. API URL არ ცვლის არცერთ დანიშნულებას.

ორგანიზაციის ადმინისტრატორებს ასევე შეუძლიათ შეცვალონ ან გაასუფთავონ API URL არსებულ Enterprise ინტეგრაციაზე ინტეგრაციის ბარათში **Save API URL**-ის გამოყენებით. აპის ხელახალი ინსტალაცია ან პროექტის ხელახალი დაკავშირება არ არის საჭირო. გასუფთავება აღადგენს `<Server URL>/api/v3`-ს. შენახვა ამოწმებს URL ფორმატს, არა პროქსის კავშირს. Webhook-ის დამუშავებას შეიძლება ერთი წუთი დასჭირდეს შეცვლილი მისამართის გამოსაყენებლად, რადგან ინსტალაციის ძიებები cached არის; უკვე მიმდინარე მოთხოვნებმა შეიძლება კვლავ გამოიყენონ წინა მისამართი.

> [!NOTE]
> **Enterprise გეგმა მხოლოდ hosted Tuist სერვერზე**
>
> Hosted Tuist სერვერზე (`https://tuist.dev`), GitHub Enterprise Server ინტეგრაცია ხელმისაწვდომია მხოლოდ **Enterprise** გეგმაზე მყოფი ორგანიზაციებისთვის. თვითმასპინძლებელ Tuist განლაგებებს შეუძლიათ მისი გამოყენება ნებისმიერ გეგმაზე.

## Pull/merge request კომენტარები {#pull-merge-request-comments}

GitHub აპი აქვეყნებს Tuist run report-ს, რომელიც მოიცავს PR-ის შეჯამებას, მათ შორის ბმულებს უახლეს <.localized_link href="/guides/features/previews/xcode#pullmerge-request-comments">previews</.localized_link>-ზე ან <.localized_link href="/guides/features/selective-testing/generated-xcode-project#pullmerge-request-comments">tests</.localized_link>-ზე:

Tuist ანახლებს ერთ კომენტარს, როგორც კი შედეგები მოდის. Gradle ბილდები ჩანს ცალ-ცალკე ყოველი root project-ისა და მოთხოვნილი tasks-ის ნაკრებისთვის; იმავე tasks-ის ხელახლა გაშვება ცვლის იმავე გამოძახების წინა შედეგს. სრული ბილდის ისტორია ხელმისაწვდომი რჩება Tuist-ზე.

კომენტარები ჩართულია ნაგულისხმევად, ინარჩუნებს reporting-ს არსებული ინტეგრაციებისთვის. მათ გამოსართავად ან ხელახლა ჩასართავად პროექტისთვის, გახსენით **Project Settings → Integrations** და ჩართეთ/გამორთეთ **GitHub → Run report comments**. ყოველ პროექტს აქვს საკუთარი პარამეტრი; რეპოზიტორიის კავშირები კვლავ იმართება ორგანიზაციის პარამეტრებში.

კომენტარების გამორთვა არ თიშავს ბილდის ან ტესტების ატვირთვას, GitHub Actions job summaries-ს, რეპოზიტორიის კავშირებს ან GitHub ინტეგრაციის სხვა ფუნქციებს. არსებული კომენტარები არ იშლება.

![სურათი, რომელიც აჩვენებს pull request კომენტარს](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **მოთხოვნები**
>
> კომენტარი ქვეყნდება მხოლოდ მაშინ, როცა თქვენი CI გაშვებები არის <.localized_link href="/guides/server/authentication#continuous-integration">ავთენტიფიცირებული</.localized_link>.

> [!NOTE]
> **`GITHUB_REF`**
>
> თუ გაქვთ custom workflow, რომელიც არ იწყება PR commit-ზე, არამედ, მაგალითად, GitHub კომენტარზე, შეიძლება დაგჭირდეთ დარწმუნება, რომ `GITHUB_REF` ცვლადი დაყენებულია ან `refs/pull/<PR_NUMBER>/merge`-ზე, ან `refs/pull/<PR_NUMBER>/head`-ზე.
>
> შეგიძლიათ გაუშვათ შესაბამისი ბრძანება, როგორიცაა `tuist share`, პრეფიქსირებული `GITHUB_REF` გარემოს ცვლადით: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions job summary {#github-actions-job-summary}

Tuist CLI და Gradle plugin წერენ ტესტებისა და ბილდების შედეგებს GitHub Actions-ის [job summary](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)-ში. შეჯამება აკავშირებს სრულ report-ს Tuist-ზე, სადაც ხელმისაწვდომია უფრო მდიდარი insights, როგორიცაა არასტაბილური ტესტები და bundle-ის ზომის ცვლილებები.

Gradle-ისთვის, ყოველი წარმატებით ატვირთული ბილდის ან ტესტის report ამატებს საკუთარ შეჯამებას, ინარჩუნებს სხვა კონტენტს, რომელიც დაწერილია ისეთი ინსტრუმენტების მიერ, როგორიცაა `gradle/actions/setup-gradle`. ეს საჭიროებს plugin-ის ვერსიას, რომელიც მოიცავს job summary მხარდაჭერას; Gradle plugin-ის უფრო ძველი ვერსიები მხოლოდ GitHub App-ის PR კომენტარის მეშვეობით იტყობინებიან. GitHub App-ის დაკავშირება არ არის საჭირო job summaries-ისთვის და **Run report comments**-ის გამორთვა მათ არ ახდენს გავლენას.

როცა GitHub Actions summary დანიშნულება ხელმისაწვდომია, Gradle ელოდება ატვირთვებსა და შეჯამებებს გასვლამდე, მაშინაც კი, თუ `uploadInBackground` ჩართულია. GitHub იჭერს შეჯამებას, როცა workflow ნაბიჯი სრულდება.

![სურათი, რომელიც აჩვენებს Tuist run report-ს GitHub Actions job summary-ში](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

ეს განსაკუთრებით სასარგებლოა [merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)-თან. Merge queue გაშვება არ არის მიბმული pull request-ზე, ამიტომ კომენტარი არ ქვეყნდება, მაგრამ job summary მაინც აჩენს შედეგებს.

> [!NOTE]
> **მოთხოვნები**
>
> Job summaries საჭიროებენ წარმატებულ report ატვირთვას. Hosted Tuist სერვერზე, თქვენი CI გაშვებები უნდა იყოს <.localized_link href="/guides/server/authentication#continuous-integration">ავთენტიფიცირებული</.localized_link>. თვითმასპინძლებელ ინსტანსებს ასევე შეუძლიათ მიიღონ credential-free reports, როცა network-trusted report publishing ჩართულია.
