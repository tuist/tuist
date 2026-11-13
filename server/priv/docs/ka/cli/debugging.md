---
{
  "title": "დაბაგვა",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "შეიტყვეთ, როგორ გამოასწოროთ პრობლემები Tuist-ში ლოგებისა და ქსელის ჩანაწერების გამოყენებით."
}
---
# გამართვა {#debugging}

Tuist გთავაზობთ რამდენიმე ინსტრუმენტს, რომელიც დაგეხმარებათ პრობლემების დიაგნოსტიკაში, როდესაც ბრძანებები არ მუშაობენ მოსალოდნელად.

> [!WARNING]
> სესიის მონაცემები შეიძლება შეიცავდეს კონფიდენციალურ ინფორმაციას, როგორიცაა ფაილის გზები, პროექტის სახელები და მოთხოვნა/პასუხის სხეულები. მიუხედავად იმისა, რომ მგრძნობიარე ჰედერები (მაგალითად, Authorization) ინიღბება, იყავით ყურადღებიანი სესიის მონაცემების სხვებთან გაზიარებისას.


## სესიის მონაცემები {#session-data}

თუ ბრძანების გამოძახება არ იძლევა სასურველ შედეგებს, შეგიძლიათ პრობლემის დიაგნოსტიკა სესიის მონაცემების შესწავლით. CLI აგზავნის ლოგებს [OSLog](https://developer.apple.com/documentation/os/oslog)-ში და ფაილურ სისტემაში.

ყოველი გაშვებისას ის ქმნის სესიის დირექტორიას მისამართზე `$XDG_STATE_HOME/tuist/sessions/{uuid}/`, სადაც `$XDG_STATE_HOME` იღებს მნიშვნელობას `~/.local/state`, თუ გარემოს ცვლადი არ არის დაყენებული. ასევე შეგიძლიათ გამოიყენოთ `$TUIST_XDG_STATE_HOME` Tuist-ისთვის სპეციფიკური მდგომარეობის დირექტორიის დასაყენებლად, რომელსაც უპირატესობა აქვს `$XDG_STATE_HOME`-თან შედარებით.

ყოველი სესიის დირექტორია შეიცავს:
- **`logs.txt`** - ტექსტური ლოგები CLI სესიიდან
- **`network.har`** - [HTTP Archive (HAR)](https://w3c.github.io/web-performance/specs/HAR/Overview.html) ფაილი, რომელიც შეიცავს სესიის განმავლობაში შესრულებულ ყველა ქსელურ მოთხოვნას და პასუხს

### HAR ფაილების ვიზუალიზაცია {#visualizing-har-files}

HAR ფაილი აღრიცხავს სესიის განმავლობაში შესრულებულ ყველა HTTP მოთხოვნას და პასუხს, რაც სასარგებლოა სერვერთან კომუნიკაციის პრობლემების გამოსასწორებლად. HAR ფაილების გახსნა რამდენიმე ინსტრუმენტით შეგიძლიათ:

- **[Proxyman](https://proxyman.io/)**: ნატიური macOS აპლიკაცია HTTP ტრაფიკის სანახავად და ანალიზისთვის. HAR ფაილის იმპორტი File > Import გზით.
- **ბრაუზერის დეველოპერის ინსტრუმენტები**: Chrome, Firefox და Safari მხარდაჭერენ HAR ფაილების იმპორტს მათ Network ჩანართში.
- **[HAR Viewer](http://www.softwareishard.com/har/viewer/)**: ვებზე დაფუძნებული HAR ფაილის მაყურებელი.

> [!TIP]
> შეიტყვეთ მეტი Tuist-ის დირექტორიების ორგანიზაციისა და მორგებული დირექტორიების კონფიგურაციის შესახებ <.localized_link href="/cli/directories">დირექტორიების დოკუმენტაციაში</.localized_link>.


> [!TIP]
> **xcodebuild-ის დაუმუშავებელი გამოტანა**
>
> ბრძანებები, რომლებიც ასრულებენ `xcodebuild`-ს, აფორმატებენ მის გამოტანას xcbeautify-ით. გადაეცით `--verbose` დაუმუშავებელი გამოტანის სანახავად. იხილეთ <.localized_link href="/guides/integrations/continuous-integration#xcodebuild-output-formatting">xcodebuild გამოტანის ფორმატირება</.localized_link>.

ნაგულისხმევად, CLI ასახელებს სესიის გზას, როდესაც შესრულება მოულოდნელად სრულდება. თუ ეს არ ხდება, სესიის მონაცემები ზემოთ ნახსენებ გზაზე (ანუ, უახლეს სესიის დირექტორიაში) შეგიძლიათ იპოვოთ.

5 დღეზე ძველი სესიის დირექტორიები ავტომატურად იშლება. Tuist ასევე ნაგულისხმევად ინახავს არაუმეტეს 50 არააქტიური სესიის დირექტორიას, თანამედროვედ ინახავს მიმდინარე Tuist პროცესების კუთვნილ სესიებს. CI გარემოებში, სადაც ერთი და იგივე მდგომარეობის დირექტორიით ბევრი Tuist ბრძანება სრულდება, შეგიძლიათ გაზარდოთ არააქტიური სესიების ზღვარი `TUIST_SESSION_MAX_SESSIONS`-ით, მაგალითად `TUIST_SESSION_MAX_SESSIONS=200`. არასწორი მნიშვნელობები, ნული და უარყოფითი მნიშვნელობები იგნორირდება და Tuist ბრუნდება ნაგულისხმევ 50-ზე.

### უწყვეტი ინტეგრაცია {#diagnose-issues-using-logs-ci}

CI-ში, სადაც გარემოებები დროებითია, შეიძლება გსურთ დააკონფიგურიროთ თქვენი CI პაიპლაინი Tuist სესიის მონაცემების ექსპორტისთვის. არტიფაქტების ექსპორტი ჩვეულებრივი შესაძლებლობაა CI სერვისებში და კონფიგურაცია დამოკიდებულია თქვენს მიერ გამოყენებულ სერვისზე. მაგალითად, GitHub Actions-ში შეგიძლიათ გამოიყენოთ `actions/upload-artifact` action სესიის მონაცემების არტიფაქტად ასატვირთად:

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist session data
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-sessions
          path: /tmp/tuist/sessions/
```

### Xcode ქეშის გამართვა {#cache-daemon-debugging}

Xcode ქეშის პრობლემების გამოსასწორებლად, დააყენეთ `TUIST_CAS_LOG` ფაილის გზაზე როგორც `tuist setup cache`-ის გაშვებისას, ასევე აგებისას. Tuist ამ ფაილს ამატებს ქეშის სტატისტიკასა და შეცდომებს:

```bash
export TUIST_CAS_LOG=$HOME/.local/state/tuist/cas.log
tuist setup cache
xcodebuild build -scheme YourScheme
```

CI-ზე Tuist წერს ამ ლოგს `~/.local/state/tuist/cas.log`-ში ნებისმიერი კონფიგურაციის გარეშე.

## ქსელური დროის ლიმიტებისა და ხელახალი ცდების მორგება {#tuning-network-timeouts}

Tuist-ის მთელი [Hypertext Transfer Protocol (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) ტრაფიკი, მათ შორის სერვერის ზარები, რეესტრი, პრევიუები და ქეშის არტიფაქტების გადაცემა, გადის საერთო `URLSession`-ში გონივრული ნაგულისხმევი მნიშვნელობებით. ნელი ან გადატვირთული ქსელური გზებზე (მაგალითად, თვითმასპინძელი სეტაპი, რომელიც ობიექტების საცავს კორპორატიული პროქსის მეშვეობით აღწევს), ცალკეულმა მოთხოვნამ შეიძლება ვერ მიიღოს რესურსი და დროის ლიმიტს მიაღწიოს დასრულებამდე. კერძოდ, ქეშის ჩამოტვირთვისას, დროის ლიმიტის მიღწევა აიძულებს Tuist-ს დაუბრუნდეს მოდულის წყაროდან აგებას, რაც გაცილებით ძვირია, ვიდრე ქეშირებული ბინარისთვის ოდნავ მეტი ლოდინი. შეგიძლიათ შეცვალოთ ძირითადი პარამეტრები გარემოს ცვლადების მეშვეობით, ნაგულისხმევი მნიშვნელობები გამოიყენება, როდესაც ისინი დაყენებული არ არის ან არასწორ მნიშვნელობაზეა დაყენებული:

```bash
# Maximum time (in seconds) a single resource transfer can take before it's cancelled
# (default: 90, or 600 for whole-file transfers such as test-product shard artifacts)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE=600

# Maximum time (in seconds) to wait for new data on an existing request (default: 120)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST=300

# Maximum number of simultaneous connections per host (default: 20)
export TUIST_HTTP_MAXIMUM_CONNECTIONS_PER_HOST=40

# Maximum retries after the initial attempt (default: 3, maximum: 10)
export TUIST_HTTP_MAXIMUM_RETRY_COUNT=1

# Initial exponential backoff delay in milliseconds (default: 100, maximum: 30000)
export TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS=250
```

რესურსის დროის ლიმიტი არის მთლიანი გადაცემის საათის მიხედვით ზღვარი, არა გაჩერების დამცავი, ამიტომ ის საკმარისად დიდი უნდა იყოს თქვენს მიერ გადატანილი უდიდესი არტიფაქტისთვის. მთლიანი ფაილის გადაცემები, როგორიცაა shard-ის მიერ ჩამოტვირთული სატესტო პროდუქტები, ნაგულისხმევად 10 წუთია 90 წამის ნაცვლად, და გაჩერებული გადაცემა მაინც მარცხდება `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST`-ის შემდეგ ახალი მონაცემების გარეშე. ეს გადაცემები კითხულობენ `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE`-ს მხოლოდ მათი ზღვრის გასაზრდელად, არასდროს 10 წუთზე დასაწევად, ამიტომ მნიშვნელობა, რომელიც არჩეულია ქეშის მოთხოვნების სწრაფად გასაუქმებლად, არ აუქმებს shard-ის მიერ სატესტო პროდუქტების ჩამოტვირთვას. `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE`-ის გაზრდა საშუალებას აძლევს აღდგენად, მაგრამ ნელ ჩამოტვირთვას დასრულდეს დროის ლიმიტის მიღწევის ნაცვლად. ქეშის ჩამოტვირთვისთვის ეს ნიშნავს ქეშში მოხვედრას წყაროდან აგებაზე დაბრუნების ნაცვლად, ამიტომ გაზარდეთ იგი განზრახ: იგივე მნიშვნელობა, რომელიც ინარჩუნებს ნელ ქეშის ჩამოტვირთვას, ასევე აყოვნებს წყაროდან აგებაზე დაბრუნებას. `TUIST_HTTP_MAXIMUM_RETRY_COUNT`-ის შემცირებამ შეიძლება თავიდან აიცილოს უარეს შემთხვევაში ლოდინის გამრავლება რამდენიმე ცდაზე. ხელახალი ცდის დაყოვნებები ორმაგდება ყოველი მარცხის შემდეგ, შეიცავს ერთ ბაზურ დაყოვნებას შემთხვევითი jitter-ით და არასდროს აღემატება 30 წამს.

## მორგებული CA სერტიფიკატის ნდობა {#trusting-a-custom-ca-certificate}

ნაგულისხმევად, Tuist ამოწმებს TLS სერტიფიკატებს ოპერაციული სისტემის root store-ის წინააღმდეგ. როდესაც თვითმასპინძელ Tuist ან Kura სერვერს აწარმოებთ, რომელიც იყენებს პირად სერტიფიკატების ავტორიტეტს, Tuist-საც უნდა ენდოს ამ CA-ს. root-ის System keychain-ში დაყენება (და SSL-ისთვის ნდობად მონიშვნა) სტანდარტული მიდგომაა, მაგრამ ეს ხშირად პრაქტიკული არ არის headless CI ჰოსტებზე, სადაც არ არის GUI სესია ან მობილური მოწყობილობების მართვა (MDM) ნდობის ბიტის დასაყენებლად.

ამ შემთხვევებში შეგიძლიათ მიუთითოთ Tuist-ს პირდაპირ CA სერტიფიკატების კონა. კონა შეიძლება იყოს PEM (ერთი ან მეტი შეერთებული `-----BEGIN CERTIFICATE-----` ბლოკი) ან ერთი DER ფაილი. სისტემის root store რჩება ნდობად მის გვერდით, ამიტომ საჯარო სერტიფიკატები ჩვეულებრივად მოწმდება და სერტიფიკატების შეფასება არასდროს არის გვერდის ავლილი.

```bash
# Path to a PEM/DER CA bundle to trust on top of the system root store (default: unset)
export TUIST_CA_CERTIFICATE=/etc/ssl/certs/self-hosted-ca.pem
```

ასევე შეგიძლიათ განაცხადოთ იგი თქვენს <.localized_link href="/references/tuist-toml">კონფიგურაციის ფაილში</.localized_link>:

```toml
[network]
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

`TUIST_CA_CERTIFICATE` გარემოს ცვლადს აქვს უპირატესობა კონფიგურაციის ფაილთან შედარებით, რაც მოსახერხებელს ხდის მის CI საიდუმლოდ მიწოდებას ჩაბარებული მანიფესტის შეცვლის გარეშე.
