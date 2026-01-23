---
{
  "title": "Code reviews",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Kod incelemeleri {#code-reviews}

Çekme isteklerini incelemek yaygın bir katkı türüdür. Sürekli entegrasyon (CI)
kodun olması gerektiği gibi çalıştığından emin olsa da, bu yeterli değildir.
Otomatikleştirilemeyen katkı özellikleri vardır: tasarım, kod yapısı ve
mimarisi, test kalitesi veya yazım hataları. Aşağıdaki bölümler, kod inceleme
sürecinin farklı yönlerini temsil eder.

## Okunabilirlik {#readability}

Kod, amacını açıkça ifade ediyor mu? **Kodun ne yaptığını anlamak için çok zaman
harcamanız gerekiyorsa, kod uygulaması iyileştirilmelidir.** Kodu, anlaşılması
daha kolay olan daha küçük soyutlamalara bölmeyi önerin. Alternatif olarak ve
son çare olarak, bunun arkasındaki mantığı açıklayan bir yorum ekleyebilirler.
Pull request açıklaması gibi herhangi bir bağlam olmadan, yakın gelecekte kodu
anlayıp anlayamayacağınızı kendinize sorun.

## Küçük çekme istekleri {#small-pull-requests}

Büyük çekme istekleri incelemesi zordur ve ayrıntıları gözden kaçırmak daha
kolaydır. Bir çekme isteği çok büyük ve yönetilemez hale gelirse, yazara onu
bölmesini önerin.

::: info EXCEPTIONS
<!-- -->
Değişikliklerin birbiriyle sıkı bir şekilde bağlantılı olduğu ve ayrılamadığı
durumlar gibi, çekme isteğinin bölünmesinin mümkün olmadığı birkaç senaryo
vardır. Bu durumlarda, yazar değişiklikleri ve bunların ardındaki gerekçeleri
açık bir şekilde açıklamalıdır.
<!-- -->
:::

## Tutarlılık {#consistency}

Değişikliklerin projenin geri kalanıyla tutarlı olması önemlidir. Tutarsızlıklar
bakımı zorlaştırır, bu nedenle bunlardan kaçınmalıyız. Kullanıcıya mesaj
göndermek veya hataları bildirmek için bir yaklaşım varsa, buna bağlı
kalmalıyız. Yazar projenin standartlarına katılmıyorsa, bunları daha ayrıntılı
olarak tartışabileceğimiz bir sorun açmasını önerin.

## Testler {#tests}

Testler, kodu güvenle değiştirmenizi sağlar. Pull isteklerindeki kod test
edilmeli ve tüm testler başarılı olmalıdır. İyi bir test, tutarlı bir şekilde
aynı sonucu veren, anlaşılması ve bakımı kolay bir testtir. İnceleme yapanlar,
inceleme süresinin çoğunu uygulama kodunda geçirirler, ancak testler de kod
olduğu için aynı derecede önemlidir.

## Önemli değişiklikler {#breaking-changes}

Kırılma değişiklikleri, Tuist kullanıcıları için kötü bir kullanıcı deneyimi
oluşturur. Katkılar, kesinlikle gerekli olmadıkça kırılma değişiklikleri
yapmaktan kaçınmalıdır. Kırılma değişikliğine başvurmadan Tuist arayüzünü
geliştirmek için yararlanabileceğimiz birçok dil özelliği vardır. Bir
değişikliğin kırılma değişikliği olup olmadığı açık olmayabilir. Değişikliğin
kırıcı olup olmadığını doğrulamak için bir yöntem, Tuist'i fixtures dizinindeki
fixture projeleri üzerinde çalıştırmaktır. Bu, kendimizi kullanıcının yerine
koymamızı ve değişikliklerin onlara nasıl etki edeceğini hayal etmemizi
gerektirir.
