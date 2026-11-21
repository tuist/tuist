---
{
  "title": "პრივიუების გაშვება macOS აპლიკაციით",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "გამოიყენეთ Tuist-ის macOS მენიუს ზოლის აპლიკაცია Apple-ის თავსებადი პრივიუების მოწყობილობებსა და სიმულატორებზე გასაშვებად."
}
---
# პრივიუების გაშვება macOS აპლიკაციით

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Apple პრივიუებისთვის Tuist-ის macOS მენიუს ზოლის აპლიკაცია წარმოადგენს CLI-ის ალტერნატივას, მიუხედავად იმისა, ბილდი Xcode-დან, Bazel-დან თუ Struo-დან მოდის. გამოქვეყნების სამუშაო პროცესის ხელმოწერისა და შესაბამისობის მოთხოვნები კვლავ ძალაშია.

## ინსტალაცია {#install}

[ჩამოტვირთეთ აპლიკაცია](https://tuist.dev/download) ან დააინსტალირეთ ის `brew install --cask tuist/tuist/tuist`-ით.

## ბილდის გაშვება {#run-a-build}

აირჩიეთ თავსებადი მოწყობილობა ან სიმულატორი მენიუს ზოლის აპლიკაციაში, შემდეგ კი პრივიუს გვერდზე დააჭირეთ **Run**.

macOS აპლიკაცია ჯერ ითხოვს უახლეს თავსებად პრივიუს თითოეული აპლიკაციისთვის. ძველ სერვერებზე, რომლებიც პლატფორმის ფილტრების გამოყენებამდე ცალკეულ აპლიკაციებს არჩევენ, ის მიმართავს დაფურცლულ ისტორიას ისეთი შეზღუდვის გარეშე, რამაც შეიძლება ხელმისაწვდომი ბილდი დამალოს.

წვდომისა და ორგანიზაციისთვის, იხილეთ <.localized_link href="/guides/features/previews#visibility">ხილვადობა და ტრეკები</.localized_link>.
