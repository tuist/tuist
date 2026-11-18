---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git-ფორჯები | ინტეგრაციები | სახელმძღვანელოები | Tuist",
  "description": "გაიგეთ, როგორ შეგიძლიათ Tuist-ის GitHub-თან ინტეგრირება გაუმჯობესებული სამუშაო პროცესებისთვის."
}
---
# GitHub-ის ინტეგრაცია {#github}

Git-ის რეპოზიტორიები პროგრამული უზრუნველყოფის პროექტების უმეტესობის ცენტრალური ნაწილია. ჩვენ ვაერთიანებთ GitHub-თან, რათა Tuist-ის ანალიტიკა პირდაპირ თქვენს pull request-ებში გქონდეთ და ზოგიერთი კონფიგურაციის საჭიროება მოგაშოროთ, მაგალითად, ძირითადი შტოს სინქრონიზაცია.

## მოწყობა {#setup}

თქვენს ორგანიზაციის `Integrations` ჩანართში უნდა დააინსტალიროთ Tuist GitHub App: ![სურათი, რომელიც აჩვენებს ინტეგრაციების ჩანართს](/images/guides/integrations/gitforge/github/integrations.png)

ასევე შეგიძლიათ პირდაპირ GitHub-დან დააინსტალიროთ აპლიკაცია. საჭიროების შემთხვევაში, შედით Tuist-ში, დააავტორეთ GitHub App, რათა Tuist-მა შეამოწმოს თქვენი წვდომა ინსტალაციასთან და აირჩიეთ დასაკავშირებელი Tuist ორგანიზაცია. თქვენ უნდა ფლობდეთ GitHub ორგანიზაციას (ან პირად GitHub ანგარიშს), სადაც აპლიკაცია ინსტალირდება. ხელმისაწვდომია მხოლოდ თქვენ მიერ ადმინისტრირებული Tuist ორგანიზაციები და თქვენი პირადი Tuist ანგარიში. Tuist გამოტოვებს არჩევანს მხოლოდ მაშინ, როცა აპლიკაცია ინსტალირებულია თქვენს პირად GitHub ანგარიშზე და თქვენი პირადი Tuist ანგარიში ერთადერთი ვარიანტია. GitHub ორგანიზაციისთვის Tuist ყოველთვის ითხოვს არჩევანს, მაშინაც კი, თუ თქვენი პირადი ანგარიში ერთადერთი ვარიანტია. თუ თქვენი გუნდის Tuist ორგანიზაცია სიაში არ ჩანს, აირჩიეთ **ორგანიზაციის შექმნა** ან სთხოვეთ მის ერთ-ერთ ადმინისტრატორს, გახდეთ ადმინისტრატორი. სია განახლდება გვერდის გახსნილობისას, ამიტომ ორგანიზაცია გამოჩნდება თავიდან დაწყების გარეშე, თუ მას Tuist-ზე დაბრუნებიდან ათი წუთის განმავლობაში აირჩევთ. როცა Tuist-დან იწყებთ, ორგანიზაცია უკვე არჩეულია და ეს ნაბიჯი გამოტოვებულია.

ამის შემდეგ, შეგიძლიათ დაამატოთ პროექტის კავშირი თქვენს GitHub რეპოზიტორიასა და Tuist პროექტს შორის:

![სურათი, რომელიც აჩვენებს პროექტის კავშირის დამატებას](/images/guides/integrations/gitforge/github/add-project-connection.png)

აპლიკაციის ინსტალაციის შემდეგ, ასევე შეგიძლიათ დააკავშიროთ პროექტი dashboard-ის გარეშე:

- **CLI:** `tuist project repository connect owner/name`, და `tuist project repository disconnect` ბმულის წასაშლელად.
- **REST API:** `PUT` და `DELETE` ბმულზე `/api/projects/{account_handle}/{project_handle}/vcs-connection`.
- **Model Context Protocol:** ინსტრუმენტები `connect_project_repository` და `disconnect_project_repository`.

რეპოზიტორია უნდა იყოს ისეთი, რომელზეც GitHub App ინსტალაციას აქვს წვდომა, და პროექტი იღებს რეპოზიტორიის ძირითად შტოს. ანგარიშის ტოკენებს სჭირდებათ `project:admin:write` scope.

> [!TIP]
> **IP მისამართების თეთრ სიაში შეყვანა**
>
> თუ თქვენი GitHub ორგანიზაცია იყენებს [IP მისამართების თეთრ სიებს](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) ან თქვენი GitHub ინსტანცია firewall-ის უკანაა, დარწმუნდით, რომ Tuist-ის <.localized_link href="/guides/server/network#outbound-ip-addresses">გამომავალი IP მისამართები</.localized_link> თეთრ სიაში შეგიყვანიათ, რათა ინტეგრაციამ შეძლოს თქვენს რეპოზიტორიასთან კომუნიკაცია.

### GitHub Enterprise Server {#github-enterprise-server}

Tuist ასევე ინტეგრირდება self-hosted GitHub Enterprise Server (GHES) ინსტანციებთან. GitHub ინტეგრაციის ბარათში გადადით **Enterprise server** ჩანართზე, შეიყვანეთ თქვენი GHES საბაზისო URL (მაგალითად, `https://github.example.com`), და დააჭირეთ install.

რადგან GitHub Apps ერთ GitHub ინსტანციაზეა შეზღუდული, Tuist ვერ გამოიყენებს თავის github.com App-ს თქვენს GHES-ზე — ამის ნაცვლად, install ღილაკი გაგიყვანთ GitHub-ის [App manifest flow](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest)-ში: GHES თქვენს ადმინისტრატორს გაატარებს ახალი Tuist App-ის რეგისტრაციის პროცესში ინსტანციაზე, შემდეგ კი ახალი App-ის სარწმუნოებებს უკან გადასცემს Tuist-ს. Tuist ინახავს ამ სარწმუნოებებს დაშიფრულად თითოეული ინსტალაციისთვის და იყენებს მათ ყოველი API გამოძახების, webhook ხელმოწერისა და თქვენს რეპოზიტორიებზე ბმულებისთვის.

დამატებითი Tuist სერვერის კონფიგურაცია არ არის საჭირო; manifest flow ავტომატურად ქმნის და ამზადებს ყველაფერს.

#### App-ის ნებართვები და webhook მოვლენები {#github-app-permissions}

PR კომენტარებისა და bundle-ის ზომის შემოწმებებისთვის Tuist-ს სჭირდება შემდეგი **რეპოზიტორიის ნებართვები**:

| ნებართვა | წვდომა | გამოიყენება |
|---|---|---|
| მეტა მონაცემები (`metadata`) | მხოლოდ კითხვა | ძირითადი რეპოზიტორიის მეტა მონაცემები; GitHub-ის მიერ საჭიროა ყოველი App-ისთვის |
| Pull requests (`pull_requests`) | კითხვა და ჩაწერა | Pull request-ების წაკითხვა, მათი head commit SHA-ის ჩათვლით, და PR კომენტარების სიის ჩამოთვლა, გამოქვეყნება და განახლება |
| Checks (`checks`) | კითხვა და ჩაწერა | Check run-ების შექმნა და განახლება, bundle-ის ზომის pass/fail შემოწმებების ჩათვლით |

Tuist იყენებს `check_run` webhook მოვლენას bundle-ის ზომის შემოწმების ქმედებების დასამუშავებლად. Manifest flow ავტომატურად აკონფიგურირებს ამ გამოწერას.

github.com-ზე App-ის ხელით მოწყობისთვის self-hosted Tuist სერვერთან ერთად, იხილეთ <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">self-hosting სახელმძღვანელო</.localized_link>.

#### ბრაუზერისა და API URL-ების განცალკევება {#separate-browser-and-api-urls}

თუ ინჟინრები GitHub Enterprise-ს შიდა hostname-ით უკავშირდებიან, ხოლო მესამე მხარის სერვისები გარე proxy-ს იყენებენ, install-ზე დაჭერამდე ორივე მისამართი დააკონფიგურირეთ:

| ველი | მაგალითი | გამოიყენება |
|---|---|---|
| **Server URL** | `https://github.internal.company.com` | თქვენი ბრაუზერი, App-ის რეგისტრაციისა და ინსტალაციისთვის, და Tuist-დან GitHub-ზე ბმულებისთვის |
| **API URL** | `https://github-proxy.company.com/api/v3` | Tuist-ის სერვერები, manifest-code გაცვლისთვის, წვდომის ტოკენებისთვის, რეპოზიტორიის წვდომისთვის, PR კომენტარებისთვის და checks-ებისთვის |

API URL არის სრული REST API საბაზისო URL, `/api/v3`-ის ან თქვენი proxy-ს მიერ გამოჩენილი ეკვივალენტური გზის ჩათვლით. Tuist არ უმატებს `/api/v3`-ს ცხად API URL-ს. დატოვეთ ის ცარიელი, თუ ერთი hostname მუშაობს როგორც თქვენი ბრაუზერისთვის, ასევე Tuist-ისთვის; არსებული კავშირები განაგრძობენ `<Server URL>/api/v3`-ის გამოყენებას.

ორივე მისამართი უნდა მიემართოს **იმავე GitHub Enterprise ინსტანსზე**. თქვენს ბრაუზერს მხოლოდ Server URL-ზე მიღწევა სჭირდება, არა API proxy-ზე. Tuist-ის სერვერებს მხოლოდ API URL-ზე მიღწევა სჭირდებათ, არა შიდა ბრაუზერის hostname-ზე.

გარე proxy-სთვის:

- გამოიყენეთ HTTPS იმ სერთიფიკატით, რომელსაც Tuist-ის სერვერები ენდობიან, და საჯარო DNS, რომელიც საჯარო IP მისამართებზე გადაწყდება. API URL გადაფარვები არ აუქმებს Tuist-ის private-IP/SSRF დაცვას. გადაფარვა უნდა მიემართოს თქვენს Enterprise ინსტანსს, არა `github.com`-ს ან `*.github.com` endpoint-ს.
- დაამატეთ allowlist-ზე ყველა Tuist <.localized_link href="/guides/server/network#outbound-ip-addresses">გამავალი IP მისამართი</.localized_link>.
- გადაამისამართეთ REST API endpoint-ები, რომლებსაც Tuist იყენებს, `POST /api/v3/app-manifests/{code}/conversions`-ის, `POST /api/v3/app/installations/{installation_id}/access_tokens`-ის და კომენტარებისა და checks-ების რეპოზიტორიის API endpoint-ების ჩათვლით. ესენი არის GitHub-ის upstream გზები; გადათარგმნეთ ისინი, თუ თქვენი proxy სხვა პრეფიქსს ამჟღავნებს.
- გადაამისამართეთ მოთხოვნები GitHub-ზე HTTP გადამისამართებების ან ინტერაქტიული შესვლის გვერდის გარეშე. Tuist ავტომატურად არ მიჰყვება Enterprise API გადამისამართებებს, ამიტომ ისინი ვერ აუვლიან გვერდს საჯარო-IP შემოწმებებს. Manifest conversion endpoint ხელმისაწვდომი უნდა იყოს მოწყობის დროს, სანამ Tuist-ს App-ის სერთიფიკატები ექნება. GitHub Actions ლოგების ჩამოტვირთვები გამონაკლისია: Tuist მიჰყვება ხელმოწერილ არქივის გადამისამართებებს მხოლოდ HTTPS-ით, ამოწმებს და ამაგრებს ყოველ დანიშნულებას საჯარო IP-ზე და არ გადასცემს ინსტალაციის ტოკენს.

GitHub-მა შეიძლება დააბრუნოს paginaciis bmebi მისი შიდა hostname-ის გამოყენებით. Tuist ახდენს კონფიგურირებული GitHub ინსტანსიდან ბმულების გადატანას API URL-ზე, თქვენი proxy-ს გზის პრეფიქსის შენარჩუნებით; არარელევანტური წყაროების ბმულები უარყოფილია.

ცალკე, GitHub-მა უნდა შეძლოს webhooks-ების მიწოდება `https://tuist.dev/webhooks/github`-ზე (ან `/webhooks/github`-ზე თქვენს self-hosted Tuist სერვერზე). ინჟინრებმა უნდა შეძლონ Tuist-ზე დაბრუნება ბრაუზერის callback-ების დასასრულებლად. API URL არ ცვლის არცერთ დანიშნულებას.

ორგანიზაციის ადმინისტრატორებს ასევე შეუძლიათ შეცვალონ ან გაასუფთავონ API URL არსებულ Enterprise ინტეგრაციაზე ინტეგრაციის ბარათში **Save API URL**-ის გამოყენებით. App-ის ხელახალი ინსტალაცია ან პროექტის ხელახალი დაკავშირება არ არის საჭირო. გასუფთავება აღადგენს `<Server URL>/api/v3`-ს. შენახვა ამოწმებს URL ფორმატს, არა proxy კავშირს. Webhook-ების დამუშავებას შეიძლება ერთი წუთი დასჭირდეს შეცვლილი მისამართის გამოსაყენებლად, რადგან ინსტალაციის ძიებები cached-ია; უკვე მიმდინარე მოთხოვნებმა შეიძლება კვლავ გამოიყენონ წინა მისამართი.

> [!NOTE]
> **Enterprise გეგმა მხოლოდ hosted Tuist სერვერზე**
>
> Hosted Tuist სერვერზე (`https://tuist.dev`), GitHub Enterprise Server ინტეგრაცია ხელმისაწვდომია მხოლოდ **Enterprise** გეგმაზე მყოფი ორგანიზაციებისთვის. Self-hosted Tuist განლაგებებს შეუძლიათ მისი გამოყენება ნებისმიერ გეგმაზე.

## Pull/merge request კომენტარები {#pull-merge-request-comments}

GitHub app აქვეყნებს Tuist run report-ს, რომელიც მოიცავს PR-ის შეჯამებას, უახლეს <.localized_link href="/guides/features/previews/xcode#pullmerge-request-comments">previews</.localized_link>-ზე ან <.localized_link href="/guides/features/selective-testing/generated-xcode-project#pullmerge-request-comments">tests</.localized_link>-ზე ბმულების ჩათვლით:

Tuist ანახლებს ერთ კომენტარს, როგორც კი შედეგები მოდის. Gradle builds ჩანს ცალ-ცალკე ყოველი root project-ისა და მოთხოვნილი tasks-ების ნაკრებისთვის; იმავე tasks-ების ხელახლა გაშვება ცვლის იმ გამოძახების წინა შედეგს. სრული build ისტორია ხელმისაწვდომი რჩება Tuist-ზე.

კომენტარები ჩართულია ნაგულისხმევად, რაც ინარჩუნებს reporting-ს არსებული ინტეგრაციებისთვის. მათ გამოსართავად ან ხელახლა ჩასართავად პროექტისთვის, გახსენით **Project Settings → Integrations** და ჩართეთ/გამორთეთ **GitHub → Run report comments**. ყოველ პროექტს აქვს საკუთარი პარამეტრი; რეპოზიტორიის კავშირები კვლავ იმართება ორგანიზაციის პარამეტრებში.

კომენტარების გამორთვა არ თიშავს build ან test ატვირთვებს, GitHub Actions job შეჯამებებს, რეპოზიტორიის კავშირებს ან სხვა GitHub ინტეგრაციის ფუნქციებს. არსებული კომენტარები არ იშლება.

![სურათი, რომელიც აჩვენებს pull request კომენტარს](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **მოთხოვნები**
>
> კომენტარი ქვეყნდება მხოლოდ მაშინ, როცა თქვენი CI runs არიან <.localized_link href="/guides/server/authentication#continuous-integration">ავთენტიფიცირებული</.localized_link>.

> [!NOTE]
> **`GITHUB_REF`**
>
> თუ გაქვთ custom workflow, რომელიც არ არის triggered PR commit-ზე, არამედ, მაგალითად, GitHub კომენტარზე, შეიძლება დაგჭირდეთ უზრუნველყოფა, რომ `GITHUB_REF` ცვლადი დაყენებული იყოს ან `refs/pull/<PR_NUMBER>/merge`-ზე, ან `refs/pull/<PR_NUMBER>/head`-ზე.
>
> შეგიძლიათ გაუშვათ შესაბამისი ბრძანება, როგორიცაა `tuist share`, პრეფიქსირებული `GITHUB_REF` გარემოს ცვლადით: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## GitHub Actions job შეჯამება {#github-actions-job-summary}

Tuist CLI და Gradle plugin წერენ test და build შედეგებს GitHub Actions-ის [job summary](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)-ში. შეჯამება ბმავს სრულ report-ზე Tuist-ზე, სადაც ხელმისაწვდომია უფრო მდიდარი insights, როგორიცაა არასტაბილური ტესტები და bundle-size deltas.

Gradle-ისთვის, ყოველი წარმატებით ატვირთული build ან test report ამატებს საკუთარ შეჯამებას, ინარჩუნებს სხვა შინაარსს, რომელიც დაწერილია ისეთი ინსტრუმენტების მიერ, როგორიცაა `gradle/actions/setup-gradle`. ეს საჭიროებს plugin ვერსიას, რომელიც მოიცავს job summary მხარდაჭერას; უფრო ძველი Gradle plugin ვერსიები მხოლოდ GitHub App-ის PR კომენტარის მეშვეობით ანგარიშობენ. GitHub App-ს არ სჭირდება დაკავშირება job შეჯამებებისთვის და **Run report comments**-ის გამორთვა მათზე არ მოქმედებს.

როდესაც GitHub Actions შეჯამების დანიშნულება ხელმისაწვდომია, Gradle ელოდება ატვირთვებს და შეჯამებებს გასვლამდე, მაშინაც კი, თუ `uploadInBackground` ჩართულია. GitHub იჭერს შეჯამებას, როდესაც workflow step სრულდება.

![სურათი, რომელიც აჩვენებს Tuist run report-ს GitHub Actions job შეჯამებაში](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

ეს განსაკუთრებით სასარგებლოა [merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)-თან ერთად. Merge queue run არ არის მიბმული pull request-ზე, ამიტომ კომენტარი არ ქვეყნდება, მაგრამ job შეჯამება კვლავ აჩვენებს შედეგებს.

> [!NOTE]
> **მოთხოვნები**
>
> Job შეჯამებებს სჭირდებათ წარმატებული report ატვირთვა. Hosted Tuist სერვერზე, თქვენი CI runs უნდა იყოს <.localized_link href="/guides/server/authentication#continuous-integration">ავთენტიფიცირებული</.localized_link>. Self-hosted ინსტანსებს ასევე შეუძლიათ მიიღონ credential-free reports, როდესაც network-trusted report publishing ჩართულია.
