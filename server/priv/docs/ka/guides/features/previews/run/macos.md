---
{
  "title": "პრევიუების გაშვება macOS-ის აპლიკაციით",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "გამოიყენეთ Tuist-ის macOS მენიუს ზოლის აპლიკაცია Apple-ის თავსებადი პრევიუების მოწყობილობებსა და სიმულატორებზე გასაშვებად."
}
---
# გაუშვით პრივიუები macOS აპლიკაციით

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Apple-ის პრივიუებისთვის Tuist-ის macOS მენიუს ზოლის აპლიკაცია არის CLI-ს ალტერნატივა, მიუხედავად იმისა, ბილდი Xcode-დან, Bazel-დან თუ Once-დან მოდის. გამოქვეყნების სამუშაო პროცესის ხელმოწერისა და შესაბამისობის მოთხოვნები კვლავ მოქმედებს.

## ინსტალაცია {#install}

[ჩამოტვირთეთ აპლიკაცია](https://tuist.dev/download) ან დააინსტალირეთ ბრძანებით `brew install --cask tuist/tuist/tuist`.

## ბილდის გაშვება {#run-a-build}

აირჩიეთ თავსებადი მოწყობილობა ან სიმულატორი მენიუს ზოლის აპლიკაციაში, შემდეგ კი დააჭირეთ **Run**-ს პრივიუს გვერდზე.

macOS აპლიკაცია ჯერ ითხოვს უახლეს თავსებად პრივიუს თითოეული აპლიკაციისთვის. ძველ სერვერებზე, რომლებიც პლატფორმის ფილტრების გამოყენებამდე ცალკეულ აპლიკაციებს ირჩევენ, ის გადადის დაფურცლულ ისტორიაზე ისეთი შეზღუდვის გარეშე, რომელმაც შეიძლება ხელმისაწვდომი ბილდი დამალოს.

წვდომისა და ორგანიზებისთვის იხილეთ <.localized_link href="/guides/features/previews#visibility">ხილვადობა და ტრეკები</.localized_link>.
