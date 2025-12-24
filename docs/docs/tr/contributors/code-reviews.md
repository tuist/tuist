---
{
  "title": "Code reviews",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Kod incelemeleri {#code-reviews}

Çekme isteklerini gözden geçirmek yaygın bir katkı türüdür. Sürekli entegrasyon
(CI) kodun yapması gerekeni yapmasını sağlasa da yeterli değildir.
Otomatikleştirilemeyen katkı özellikleri vardır: tasarım, kod yapısı ve
mimarisi, test kalitesi veya yazım hataları. Aşağıdaki bölümler kod inceleme
sürecinin farklı yönlerini temsil etmektedir.

## Okunabilirlik {#readability}

Kod amacını açıkça ifade ediyor mu? **Kodun ne yaptığını anlamak için çok fazla
zaman harcamanız gerekiyorsa, kod uygulamasının iyileştirilmesi gerekir.** Kodu,
anlaşılması daha kolay olan daha küçük soyutlamalara bölmeyi önerin. Alternatif
ve son kaynak olarak, bunun arkasındaki mantığı açıklayan bir yorum
ekleyebilirler. Kendinize, yakın bir gelecekte, çekme isteği açıklaması gibi
herhangi bir bağlam olmadan kodu anlayıp anlayamayacağınızı sorun.

## Küçük çekme istekleri {#small-pull-requests}

Büyük talepleri incelemek zordur ve ayrıntıları gözden kaçırmak daha kolaydır.
Bir çekme isteği çok büyük ve yönetilemez hale gelirse, yazara onu parçalamasını
önerin.

::: info EXCEPTIONS
<!-- -->
Değişikliklerin birbirine sıkı sıkıya bağlı olduğu ve bölünemediği durumlar
gibi, çekme isteğini bölmenin mümkün olmadığı birkaç senaryo vardır. Bu
durumlarda, yazar değişikliklerin ve arkasındaki gerekçelerin net bir
açıklamasını sunmalıdır.
<!-- -->
:::

## Tutarlılık {#consistency}

Değişikliklerin projenin geri kalanıyla tutarlı olması önemlidir. Tutarsızlıklar
bakımı zorlaştırır ve bu nedenle bunlardan kaçınmalıyız. Kullanıcıya mesaj
çıktısı vermek veya hataları bildirmek için bir yaklaşım varsa, buna bağlı
kalmalıyız. Yazar projenin standartlarına katılmıyorsa, daha fazla
tartışabileceğimiz bir sorun açmalarını önerin.

## Testler {#tests}

Testler kodun güvenle değiştirilmesini sağlar. Çekme taleplerindeki kod test
edilmeli ve tüm testler geçmelidir. İyi bir test, tutarlı bir şekilde aynı
sonucu üreten ve anlaşılması ve sürdürülmesi kolay olan bir testtir. Gözden
geçirenler, gözden geçirme süresinin çoğunu uygulama kodunda geçirirler, ancak
testler de kod oldukları için eşit derecede önemlidir.

## Kırılma değişiklikleri {#breaking-changes}

Kırıcı değişiklikler Tuist kullanıcıları için kötü bir kullanıcı deneyimidir.
Katkılar, kesinlikle gerekli olmadıkça kırıcı değişiklikler yapmaktan
kaçınmalıdır. Kırıcı bir değişikliğe başvurmadan Tuist'in arayüzünü geliştirmek
için yararlanabileceğimiz birçok dil özelliği vardır. Bir değişikliğin kırıcı
olup olmadığı açık olmayabilir. Değişikliğin kırıcı olup olmadığını doğrulamak
için bir yöntem, Tuist'i fikstürler dizinindeki fikstür projelerine karşı
çalıştırmaktır. Bu, kendimizi kullanıcının yerine koymayı ve değişikliklerin
onları nasıl etkileyeceğini hayal etmeyi gerektirir.
