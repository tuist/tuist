---
{
  "title": "Kod incelemeleri",
  "titleTemplate": ":title · Katkıda Bulunanlar · Tuist",
  "description": "Kod inceleyerek Tuist'e nasıl katkıda bulunacağınızı öğrenin"
}
---
# Kod incelemeleri {#code-reviews}

Pull request’leri incelemek yaygın bir katkı türüdür. Sürekli entegrasyon (CI), kodun yapması gerekeni yaptığını garanti etse de bu yeterli değildir. Otomatize edilemeyen katkı nitelikleri vardır: tasarım, kod yapısı ve mimari, testlerin kalitesi veya yazım hataları. Aşağıdaki bölümler, kod inceleme sürecinin farklı yönlerini temsil eder.

## Okunabilirlik {#readability}

Kod amacını açıkça ifade ediyor mu? **Kodun ne yaptığını anlamak için çok zaman harcamanız gerekiyorsa, kod uygulamasının iyileştirilmesi gerekir.** Kodu daha küçük ve anlaşılması daha kolay soyutlamalara ayırmayı önerin. Alternatif olarak ve son çare olarak, arkasındaki mantığı açıklayan bir yorum ekleyebilirler. Kendinize, pull request açıklaması gibi bağlamlar olmadan yakın gelecekte kodu anlayıp anlayamayacağınızı sorun.

## Küçük pull request’ler {#small-pull-requests}

Büyük pull request’leri incelemek zordur ve detayların gözden kaçması daha kolaydır. Bir pull request çok büyük ve yönetilemez hale gelirse, yazarından bunu parçalara ayırmasını isteyin.

> [!NOTE]
> **İstisnalar**
>
> Değişiklikler sıkıca bağlı olduğunda ve ayrılamadığında olduğu gibi, pull request’i bölmek mümkün olmayan birkaç senaryo vardır. Bu durumlarda, yazar değişiklikleri ve bunların arkasındaki gerekçeleri açıkça açıklamalıdır.


## Tutarlılık {#consistency}

Değişikliklerin projenin geri kalanıyla tutarlı olması önemlidir. Tutarsızlıklar bakımı zorlaştırır, bu nedenle bunlardan kaçınmalıyız. Kullanıcıya mesaj verme veya hata bildirme konusunda bir yaklaşım varsa, buna bağlı kalmalıyız. Yazar projenin standartlarına katılmıyorsa, bunları daha fazla tartışabileceğimiz bir issue açmasını önerin.

## Testler {#tests}

Testler, kodu güvenle değiştirmenizi sağlar. Pull request’lerdeki kod test edilmeli ve tüm testler geçmelidir. İyi bir test, tutarlı şekilde aynı sonucu üreten ve anlaşılması ile bakımı kolay olan testtir. İnceleyenler inceleme süresinin çoğunu uygulama koduna harcar, ancak testler de kod olduğu için eşit derecede önemlidir.

## Yıkıcı değişiklikler {#breaking-changes}

Yıkıcı değişiklikler, Tuist kullanıcıları için kötü bir kullanıcı deneyimidir. Katkılar, kesinlikle gerekli olmadıkça yıkıcı değişiklikler getirmekten kaçınmalıdır. Tuist’in arayüzünü yıkıcı bir değişikliğe başvurmadan geliştirmek için yararlanabileceğimiz birçok dil özelliği vardır. Bir değişikliğin yıkıcı olup olmadığı her zaman açık olmayabilir. Değişikliğin yıkıcı olup olmadığını doğrulamanın bir yolu, Tuist’i fixtures dizinindeki sabit proje örneklerine karşı çalıştırmaktır. Bu, kendimizi kullanıcının yerine koyup değişikliklerin onları nasıl etkileyeceğini hayal etmemizi gerektirir.
