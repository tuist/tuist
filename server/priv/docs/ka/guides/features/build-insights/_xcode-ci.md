## ბილდის ინსაიტები CI-ში {#continuous-integration}

CI-ზე ბილდის ინსაიტების თვალყურის სადევნებლად, დარწმუნდით, რომ CI არის <.localized_link href="/guides/server/authentication#continuous-integration">ავტორიზებული</.localized_link>.

Xcodebuild-ით მართული CI-ისთვის გჭირდებათ:
- გამოიყენეთ <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>, როცა იძახებთ `xcodebuild` ქმედებებს.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` ბრძანებაში.

`-resultBundlePath`-ის გარეშე, აუცილებელი აქტივობის ლოგები და შედეგების პაკეტები არ გენერირდება და `tuist inspect build` ვერ გააანალიზებს ბილდს.
