---
{
  "title": "API",
  "titleTemplate": ":title · CI პროვაიდერები · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით სამუშაოები Tuist-ის გამშვებებზე თქვენი git-ფორგიდან ან ორკესტრატორიდან: შექმენით სამუშაო ერთი API მოთხოვნით და მიჰყევით ვებჰუკების საშუალებით."
}
---
# API {#api}

Git forges, merge queues და agent orchestrators, რომლებსაც საკუთარი runner პროტოკოლი არ აქვთ, შეუძლიათ პირდაპირ Tuist Runners-ზე გაუშვან სამუშაოები. თქვენ ქმნით სამუშაოს ერთი მოთხოვნით, თქვენ მიერ შერჩეული <.localized_link href="/guides/features/runners/profiles">პროფილის</.localized_link> Tuist მანქანა იღებს კომიტს და ასრულებს თქვენს სკრიპტს, ხოლო Tuist აგზავნის შედეგს თქვენს webhook endpoint-ზე.

## სამუშაოს გაშვება {#run-a-job}

1. **შექმენით ანგარიშის ტოკენი** `account:runners:write` სკოპით:

   ```bash
   tuist account tokens create my-org --scopes account:runners:write --name forge
   ```

2. **შექმენით სამუშაო.** ჩვეულებრივი გამომძახებელი ამას push hook-დან აკეთებს, მოკლევადიანი ტოკენით, რომელიც მანქანას რეპოზიტორიის კლონირების საშუალებას აძლევს:

   ```bash
   curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs \
     -H "Authorization: Bearer $TUIST_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "profile": "tuist-macos",
       "repository_url": "https://git.example.com/acme/app.git",
       "clone_token": "<short-lived token>",
       "commit_sha": "4f1c2d0e9b8a7c6d5e4f3a2b1c0d9e8f7a6b5c4d",
       "ref": "refs/heads/main",
       "name": "test",
       "script": "mise install\nmise run test",
       "secrets": { "SIGNING_KEY": "..." },
       "timeout_minutes": 30,
       "idempotency_key": "acme/app:4f1c2d0e:test"
     }'
   ```

   პასუხი არის სამუშაო თავისი `workflow_job_id`-ით. ის მაშინვე ჩნდება თქვენი Tuist დაშბორდის **Runners** განყოფილებაში და იწყება, როგორც კი შესაბამისი პროფილის მანქანა თავისუფალი იქნება. „თბილი“ მანქანები ჩვეულებრივ რამდენიმე წამში იწყებენ მას.

3. **მიჰყევით სამუშაოს.** გამოიწერეთ <.localized_link href="/guides/integrations/webhooks">webhook endpoint</.localized_link> `runner_job.started` და `runner_job.completed` ღონისძიებებზე. დასრულების ღონისძიება შეიცავს სამუშაოს `conclusion`-ს: `success`, `failure` ან `cancelled`. ასევე შეგიძლიათ გამოიკითხოთ `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}` და წაიკითხოთ ლოგი `GET /api/accounts/my-org/runners/jobs/{workflow_job_id}/logs`-დან.

## git forge-ის ინტეგრაცია {#integrate-a-git-forge}

forge, რომელსაც runner პროტოკოლი არ აქვს, უკავშირდება მცირე ხიდის მეშვეობით, რომელიც შეიძლება იყოს თვითონ forge-ის სერვისი ან ფუნქცია, რომელსაც ის hooks-დან იძახებს:

1. **push-ის დროს**, forge-ის push hook აღწევს ხიდამდე. ხიდი ამოწმებს hook-ს, გადაწყვეტს, თუ რომელი შემოწმებებია საჭირო კომიტისთვის და გასცემს რეპოზიტორიისთვის მხოლოდ-წაკითხვადი კლონირების ტოკენს, რომელიც იწურება სამუშაოს таймаუტის შემდეგ.
2. **თითოეული შემოწმებისთვის**, ხიდი ქმნის სამუშაოს `idempotency_key`-ით, რომელიც დაყენებულია `<repository>:<commit>:<check>`-ზე, ისე რომ ხელახლა მიწოდებულმა hook-მა არაფერი ახალი არ შექმნას. ის ინახავს დაბრუნებულ `workflow_job_id`-ს და შეუძლია forge-ში შემოწმება pending-ად მონიშნოს.
3. **`runner_job.started` და `runner_job.completed` ღონისძიებებზე**, ხიდი ამოწმებს `Tuist-Signature` ჰედერს endpoint-ის საიდუმლოთი, პოულობს შემოწმებას `workflow_job_id`-ით ან `idempotency_key`-ით და ანახლებს forge-ის კომიტის სტატუსს `conclusion`-ით. მას შეუძლია სტატუსი დააკავშიროს Tuist დაშბორდში სამუშაოს გვერდთან.
4. **როდესაც push ცვლის კომიტს**, ხიდი აუქმებს ძველი კომიტისთვის შექმნილ სამუშაოებს.

## როგორ მუშაობს სამუშაო {#how-the-job-runs}

მანქანა HTTPS-ით იღებს `commit_sha`-ს `repository_url`-დან. როდესაც სერვერი SHA-ით არ გასცემს კომიტს, ის ნაცვლად იღებს `ref`-ს, რომელიც უნდა შეიცავდეს კომიტს. `clone_token`, თუ მიუთითებთ, იგზავნება როგორც `Authorization: Bearer <token>` მხოლოდ რეპოზიტორიის ჰოსტისთვის. ის არასდროს ხვდება თქვენს სკრიპტში ან სამუშაოს ლოგში.

თქვენი სკრიპტი ეშვება Bash-ით login shell-ში, `set -eo pipefail`-ით, checkout-ის ფესვიდან. სამუშაო ვერდება, როდესაც სკრიპტი ბრუნდება არანულოვანი სტატუსით ან გადაცილებულია `timeout_minutes`, რომლის ნაგულისხმები მნიშვნელობაა 60 და შეიძლება იყოს 360-მდე. თქვენი `env` და `secrets`-ის გარდა, სკრიპტი ხედავს `CI=true`, `TUIST_JOB_ID`, `TUIST_JOB_NAME`, `TUIST_JOB_REPOSITORY_URL`, `TUIST_JOB_REF` და `TUIST_JOB_COMMIT_SHA`. `secrets`-ის მნიშვნელობები დამალულია სამუშაოს ლოგში.

## განმეორებითი ცდები და იდემპოტენტურობა {#idempotency}

მიანიჭეთ თითოეულ სამუშაოს `idempotency_key`, რომელიც აღწერს მის დანიშნულებას, მაგალითად `<repository>:<commit>:<check>`. მოთხოვნა, რომელსაც აქვს თქვენს ანგარიშში უკვე გამოყენებული გასაღები, აბრუნებს არსებულ სამუშაოს 201-ის ნაცვლად 200 სტატუსით და არაფერს ქმნის. ეს საშუალებას აძლევს თქვენს push hook-ს მოთხოვნა გადასცეს განმეორებითი ცდების რიგს დუბლირებული სამუშაოების რისკის გარეშე.

Webhook-ის მიწოდებები მეორდება, სანამ თქვენი endpoint არ უპასუხებს 2xx სტატუსით, ამიტომ ღონისძიება შეიძლება ერთზე მეტჯერ მოვიდეს. გამოიყენეთ envelope-ის `id` ან სამუშაოს `workflow_job_id` ღონისძიების ტიპთან ერთად დუბლიკატების აღმოსაფხვრელად.

## სამუშაოს გაუქმება {#cancel-a-job}

```bash
curl -X POST https://tuist.dev/api/accounts/my-org/runners/jobs/{workflow_job_id}/cancel \
  -H "Authorization: Bearer $TUIST_TOKEN"
```

სამუშაო, რომელიც არცერთ მანქანას არ დაუწყია, მაშინვე უქმდება. მიმდინარე სამუშაო რამდენიმე წამში ჩერდება და მისი დასრულების ღონისძიება იუწყება `cancelled`-ს. სამუშაო, რომელიც 24 საათის განმავლობაში არცერთ მანქანას არ დაუწყია, ავტომატურად უქმდება.

## ქეშირება და ნდობა {#trust}

ნებისმიერს, ვისაც რეპოზიტორიაში push-ის უფლება აქვს, შეუძლია შეცვალოს, თუ რას ასრულებს სამუშაო, ამიტომ API სამუშაოები განიხილება როგორც არასანდო: ისინი არ იღებენ თქვენი ანგარიშის საერთო <.localized_link href="/guides/features/runners/cache-volumes">ქეშის ტომებს</.localized_link> ან მის ქეშის ხელმოწერის ნებართვას. სამუშაოს საიდუმლოები, სკრიპტი და კლონირების ტოკენი ინახება დაშიფრული და იშლება სამუშაოს დასრულების შემდეგ.
