---
{
  "title": "გამართვა",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "შეიტყვეთ, როგორ გამოასწოროთ Tuist-თან დაკავშირებული პრობლემები ლოგებისა და ქსელური ჩანაწერების გამოყენებით."
}
---
# გამართვა {#debugging}

Tuist გთავაზობთ რამდენიმე ინსტრუმენტს, რომელიც დაგეხმარებათ პრობლემების დიაგნოსტიკაში, როდესაც ბრძანებები არ მუშაობენ მოსალოდნელად.

> [!WARNING]
> სესიის მონაცემები შეიძლება შეიცავდეს მგრძნობიარე ინფორმაციას, როგორიცაა ფაილების გზები, პროექტების სახელები და მოთხოვნა/პასუხის სხეულები. მიუხედავად იმისა, რომ მგრძნობიარე ჰედერები (მაგალითად, Authorization) ინიღბება, იყავით ყურადღებიანი სესიის მონაცემების სხვებთან გაზიარებისას.


## სესიის მონაცემები {#session-data}

თუ ბრძანების გამოძახება არ იძლევა სასურველ შედეგებს, შეგიძლიათ პრობლემა დაადგინოთ სესიის მონაცემების შესწავლით. CLI გადასცემს ლოგებს [OSLog](https://developer.apple.com/documentation/os/oslog)-ზე და ფაილურ სისტემაზე.

ყოველ გაშვებაზე ის ქმნის სესიის საქაღალდეს `$XDG_STATE_HOME/tuist/sessions/{uuid}/`-ში, სადაც `$XDG_STATE_HOME` იღებს მნიშვნელობას `~/.local/state`, თუ გარემოს ცვლადი არ არის დაყენებული. ასევე შეგიძლიათ გამოიყენოთ `$TUIST_XDG_STATE_HOME` Tuist-ისთვის სპეციფიკური მდგომარეობის საქაღალდის დასაყენებლად, რომელსაც აქვს უპირატესობა `$XDG_STATE_HOME`-თან შედარებით.

ყოველი სესიის საქაღალდე შეიცავს:
- **`logs.txt`** - ტექსტური ლოგები CLI სესიიდან
- **`network.har`** - [HTTP Archive (HAR)](https://w3c.github.io/web-performance/specs/HAR/Overview.html) ფაილი, რომელიც შეიცავს სესიის განმავლობაში შესრულებულ ყველა ქსელურ მოთხოვნას და პასუხს

### HAR ფაილების ვიზუალიზაცია {#visualizing-har-files}

HAR ფაილი აღრიცხავს სესიის განმავლობაში შესრულებულ ყველა HTTP მოთხოვნას და პასუხს, რაც სასარგებლოა სერვერთან კომუნიკაციის პრობლემების დაფიქსირებისთვის. HAR ფაილების გახსნა შეგიძლიათ რამდენიმე ინსტრუმენტით:

- **[Proxyman](https://proxyman.io/)**: ნატიური macOS აპლიკაცია HTTP ტრაფიკის სანახავად და ანალიზისთვის. შემოიტანეთ HAR ფაილი File > Import გზით.
- **ბრაუზერის დეველოპერული ინსტრუმენტები**: Chrome, Firefox და Safari ყველა მხარს უჭერს HAR ფაილების შემოტანას მათ Network ჩანართში.
- **[HAR Viewer](http://www.softwareishard.com/har/viewer/)**: ვებზე დაფუძნებული HAR ფაილის ნახვის ინსტრუმენტი.

> [!TIP]
> შეიტყვეთ მეტი Tuist-ის საქაღალდეების ორგანიზაციისა და მორგებული საქაღალდეების კონფიგურაციის შესახებ <.localized_link href="/cli/directories">საქაღალდეების დოკუმენტაციაში</.localized_link>.


> [!TIP]
> **Raw xcodebuild output**
>
> ბრძანებები, რომლებიც აწარმოებენ `xcodebuild`, აფორმატებენ მის გამონატანს xcbeautify-ით. გადაეცით `--verbose` დაუფორმატებელი გამონატანის სანახავად. იხილეთ <.localized_link href="/guides/integrations/continuous-integration#xcodebuild-output-formatting">xcodebuild output formatting</.localized_link>.

ნაგულისხმევად, CLI აჩვენებს სესიის გზას, როდესაც შესრულება მოულოდნელად სრულდება. თუ არა, შეგიძლიათ იპოვოთ სესიის მონაცემები ზემოთ ნახსენებ გზაზე (ანუ, უახლეს სესიის საქაღალდეში).

5 დღეზე ძველი სესიის საქაღალდეები ავტომატურად იშლება. Tuist ასევე ნაგულისხმევად ინახავს მაქსიმუმ 50 არააქტიურ სესიის საქაღალდეს, თანახმად ინახავს ამჟამად მომუშავე Tuist პროცესების კუთვნილ სესიებს. CI გარემოებში, სადაც ერთი და იგივე მდგომარეობის საქაღალდით ბევრი Tuist ბრძანება სრულდება, შეგიძლიათ გაზარდოთ არააქტიური სესიების ლიმიტი `TUIST_SESSION_MAX_SESSIONS`-ით, მაგალითად `TUIST_SESSION_MAX_SESSIONS=200`. არასწორი მნიშვნელობები, ნული და უარყოფითი მნიშვნელობები იგნორირდება და Tuist უბრუნდება ნაგულისხმევ 50-ს.

### უწყვეტი ინტეგრაცია {#diagnose-issues-using-logs-ci}

CI-ში, სადაც გარემოებები დროებითია, შეიძლება გსურთ დააკონფიგურიროთ თქვენი CI პაიპლაინი Tuist სესიის მონაცემების ექსპორტისთვის. არტიფაქტების ექსპორტი ხშირი შესაძლებლობაა CI სერვისებში და კონფიგურაცია დამოკიდებულია თქვენს მიერ გამოყენებულ სერვისზე. მაგალითად, GitHub Actions-ში შეგიძლიათ გამოიყენოთ `actions/upload-artifact` action სესიის მონაცემების არტიფაქტად ასატვირთად:

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

### Xcode-ის ქეშის გამართვა {#cache-daemon-debugging}

Xcode ქეშის პრობლემების დაფიქსირებისთვის, დააყენეთ `TUIST_CAS_LOG` ფაილის გზაზე როგორც `tuist setup cache`-ის გაშვებისას, ასევე ბილდის დროს. Tuist ამ ფაილს ამატებს ქეშის სტატისტიკას და შეცდომებს:

```bash
export TUIST_CAS_LOG=$HOME/.local/state/tuist/cas.log
tuist setup cache
xcodebuild build -scheme YourScheme
```

CI-ზე, Tuist წერს ამ ლოგს `~/.local/state/tuist/cas.log`-ში ნებისმიერი კონფიგურაციის გარეშე.

## ქსელის მოლოდინის დროების და ცდების რეგულირება {#tuning-network-timeouts}

Tuist-ის მთელი [Hypertext Transfer Protocol (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) ტრაფიკი, მათ შორის სერვერის გამოძახებები, რეესტრი, პრევიუები და ქეშის არტიფაქტების გადაცემები, გადის საერთო `URLSession`-ში გონივრული ნაგულისხმევი მნიშვნელობებით. ნელი ან გადატვირთული ქსელური გზებზე (მაგალითად, თვითმასპინძლებული setup, რომელიც ობიექტების საცავს აღწევს კორპორატიული პროქსის მეშვეობით), ინდივიდუალურმა მოთხოვნამ შეიძლება ვერ მიიღოს რესურსები და შეეჯახოს რესურსის ტაიმაუთს სანამ დასრულდება. ქეშის ჩამოტვირთვების შემთხვევაში, ტაიმაუთის მიღწევა აიძულებს Tuist-ს დაუბრუნდეს მოდულის წყაროდან აგებას, რაც გაცილებით ძვირია, ვიდრე ოდნავ მეტი ლოდინი ქეშში არსებული ბინარისთვის. შეგიძლიათ მორგოთ საბაზისო პარამეტრები გარემოს ცვლადების მეშვეობით, ნაგულისხმევი მნიშვნელობები გამოიყენება, როდესაც ისინი არ არის დაყენებული ან დაყენებულია არასწორ მნიშვნელობაზე:

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

რესურსის ტაიმაუთი არის მთლიანი გადაცემის საათისმიერი ლიმიტი, არა გაჩერების დამცავი, ამიტომ ის საკმარისად დიდი უნდა იყოს თქვენს მიერ გადატანილი უდიდესი არტიფაქტისთვის. მთლიანი ფაილის გადაცემები, როგორიცაა shard-ის მიერ ჩამოტვირთული ტესტის პროდუქტები, ნაგულისხმევად 10 წუთია 90 წამის ნაცვლად და გაჩერებული გადაცემა მაინც ვერ ხერხდება `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST`-ის შემდეგ ახალი მონაცემების გარეშე. ეს გადაცემები კითხულობენ `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE`-ს მხოლოდ მათი ლიმიტის გასაზრდელად, არასდროს ამცირებენ მას 10 წუთზე ნაკლებად, ამიტომ მნიშვნელობა, რომელიც არჩეულია ქეშის მოთხოვნების სწრაფი შეცდომისთვის, არ აუქმებს ასევე shard-ის მიერ მისი ტესტის პროდუქტების ჩამოტვირთვას. `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE`-ის გაზრდა საშუალებას აძლევს აღდგენად, მაგრამ ნელ ჩამოტვირთვას დასრულდეს ტაიმაუთის ნაცვლად. ქეშის ჩამოტვირთვებისთვის, ეს ნიშნავს ქეშში მოხვედრას წყაროდან აგებაზე დაბრუნების ნაცვლად, ამიტომ გაზარდეთ ის გონივრულად: იგივე მნიშვნელობა, რომელიც ინარჩუნებს ნელ ქეშის ჩამოტვირთვას, ასევე აყოვნებს წყაროდან აგებაზე დაბრუნებას. `TUIST_HTTP_MAXIMUM_RETRY_COUNT`-ის შემცირებამ შეიძლება თავიდან აიცილოს უარესი შემთხვევის ლოდინის გამრავლება რამდენიმე ცდის განმავლობაში. ხელახალი ცდის დაყოვნებები ორმაგდება ყოველი შეცდომის შემდეგ, შეიცავს შემთხვევითი jitter-ის ერთ საბაზისო დაყოვნებას და არასდროს აღემატება 30 წამს.

## მორგებული CA სერტიფიკატის ნდობა {#trusting-a-custom-ca-certificate}

ნაგულისხმევად, Tuist ამოწმებს TLS სერთიფიკატებს ოპერაციული სისტემის root store-ის წინააღმდეგ. როდესაც აწარმოებთ თვითმასპინძლებულ Tuist ან Kura სერვერს, რომელიც იყენებს პირად სერთიფიკატის ავტორიტეტს, Tuist-საც უნდა ენდოს ამ CA-ს. root-ის ინსტალაცია System keychain-ში (და მისი ნდობად მონიშვნა SSL-ისთვის) არის სტანდარტული მიდგომა, მაგრამ ეს ხშირად არაპრაქტიკულია headless CI ჰოსტებზე, სადაც არ არის GUI სესია ან მობილური მოწყობილობების მართვა (MDM) ნდობის ბიტის დასაყენებლად.

ამ შემთხვევებში შეგიძლიათ მიუთითოთ Tuist-ს პირდაპირ CA სერთიფიკატების bundle-ზე. bundle შეიძლება იყოს PEM (ერთი ან მეტი შეერთებული `-----BEGIN CERTIFICATE-----` ბლოკი) ან ერთი DER ფაილი. სისტემის root store რჩება ნდობად მის გვერდით, ამიტომ საჯარო სერთიფიკატები ჩვეულებრივად მოწმდება და სერთიფიკატის შეფასება არასდროს იგნორირდება.

```bash
# Path to a PEM/DER CA bundle to trust on top of the system root store (default: unset)
export TUIST_CA_CERTIFICATE=/etc/ssl/certs/self-hosted-ca.pem
```

ასევე შეგიძლიათ განაცხადოთ ის თქვენს <.localized_link href="/references/tuist-toml">კონფიგურაციის ფაილში</.localized_link>:

```toml
[network]
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

`TUIST_CA_CERTIFICATE` გარემოს ცვლადს აქვს უპირატესობა კონფიგურაციის ფაილთან შედარებით, რაც მოსახერხებელია მის CI საიდუმლოდ მიწოდებისთვის კომიტირებული მანიფესტის შეცვლის გარეშე.
