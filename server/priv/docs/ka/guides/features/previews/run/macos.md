---
{
  "title": "პრევიუების გაშვება macOS აპლიკაციით",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "გამოიყენეთ Tuist-ის macOS მენიუს ზოლის აპლიკაცია, რათა თავსებადი Apple პრევიუები მოწყობილობებზე და სიმულატორებში გაუშვათ."
}
---
# პრივიუსების გაშვება macOS აპლიკაციით

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Apple-ის პრივიუსებისთვის Tuist-ის macOS მენიუს ზოლის აპლიკაცია წარმოადგენს CLI-ის ალტერნატივას, მიუხედავად იმისა, ბილდი Xcode-დან, Bazel-დან თუ Once-დან მოდის. გამოქვეყნების სამუშაო პროცესის ხელმოწერისა და შესაბამისობის მოთხოვნები კვლავ ძალაში რჩება.

## ინსტალაცია {#install}

[აპლიკაციის ჩამოტვირთვა](https://tuist.dev/download) ან მისი ინსტალაცია `brew install --cask tuist/tuist/tuist`-ით.

## ბილდის გაშვება {#run-a-build}

აირჩიეთ თავსებადი მოწყობილობა ან სიმულატორი მენიუს ზოლის აპლიკაციაში, შემდეგ კი დააჭირეთ **Run**-ს პრივიუსის გვერდზე.

macOS აპლიკაცია ჯერ ითხოვს უახლეს თავსებად პრივიუსს თითოეული აპლიკაციისთვის. ძველ სერვერებზე, რომლებიც პლატფორმის ფილტრების გამოყენებამდე ცალკეულ აპლიკაციებს არჩევენ, ის გადადის დაყოფილ ისტორიაზე ისეთი შეზღუდვის დაწესების გარეშე, რომელმაც შეიძლება ხელმისაწვდომი ბილდი დამალოს.

წვდომისა და ორგანიზაციისთვის, იხილეთ <.localized_link href="/guides/features/previews#visibility">ხილვადობა და ტრეკები</.localized_link>.
