## ბილდის ინსაიტები CI-ში {#continuous-integration}

იმისთვის, რომ CI-ში ბილდის ინსაიტები თვალყურს ადევნოთ, დარწმუნდით, რომ CI არის <.localized_link href="/guides/server/authentication#continuous-integration">ავტორიზებული</.localized_link>.

Xcodebuild-ზე დაფუძნებული CI-სთვის საჭიროა:
- გამოიყენეთ <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>, როდესაც იძახებთ `xcodebuild` ქმედებებს.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` ბრძანებას.

`-resultBundlePath`-ის გარეშე, საჭირო აქტივობის ლოგები და შედეგების ბანდლები არ გენერირდება და `tuist inspect build` ვერ შეძლებს ბილდის ანალიზს.
