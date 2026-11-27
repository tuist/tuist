## ბილდის ანალიტიკა CI-ში {#continuous-integration}

CI-ში ბილდის ანალიტიკის თვალყურის დევნებისთვის დარწმუნდით, რომ CI არის <.localized_link href="/guides/server/authentication#continuous-integration">ავტორიზებული</.localized_link>.

Xcodebuild-ზე დაფუძნებული CI-სთვის საჭიროა:
- გამოიყენეთ <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>, როდესაც იწვევთ `xcodebuild` ქმედებებს.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` ბრძანებაში.

`-resultBundlePath`-ის გარეშე საჭირო აქტივობის ჟურნალები და შედეგების პაკეტები არ გენერირდება და `tuist inspect build` ვერ გააანალიზებს ბილდს.
