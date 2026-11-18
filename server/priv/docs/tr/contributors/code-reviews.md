---
{
  "title": "Kod incelemeleri",
  "titleTemplate": ":title · Katkıda Bulunanlar · Tuist",
  "description": "Kod inceleyerek Tuist'e nasıl katkıda bulunacağınızı öğrenin"
}
---
# Kod incelemeleri {#code-reviews}

Pull request’leri incelemek yaygın bir katkı türüdür. Sürekli entegrasyon (CI), kodun yapması gerekeni yaptığını garanti etse de bu yeterli değildir. Otomatize edilemeyen katkı özellikleri vardır: tasarım, kod yapısı ve mimari, testlerin kalitesi veya yazım hataları. Aşağıdaki bölümler, kod inceleme sürecinin farklı yönlerini temsil eder.

## Okunabilirlik {#readability}

Kod amacını açıkça ifade ediyor mu? **Kodun ne yaptığını anlamak için çok zaman harcamanız gerekiyorsa, kod uygulamasının iyileştirilmesi gerekir.** Kodu daha kolay anlaşılacak daha küçük soyutlamalara ayırmayı önerin. Alternatif olarak ve son çare olarak, arkasındaki mantığı açıklayan bir yorum ekleyebilirler. Pull request açıklaması gibi bağlamlar olmadan, yakın gelecekte kodu anlayıp anlayamayacağınızı kendinize sorun.

## Küçük pull request’ler {#small-pull-requests}

Büyük pull request’leri incelemek zordur ve detayları gözden kaçırmak daha kolaydır. Bir pull request çok büyük ve yönetilemez hale gelirse, yazardan bunu parçalara ayırmasını isteyin.

> [!NOTE]
> **İstisnalar**
>
> Değişikliklerin sıkıca bağlı olduğu ve ayrılamadığı durumlar gibi, pull request’i bölmenin mümkün olmadığı birkaç senaryo vardır. Bu durumlarda, yazar değişiklikleri ve bunların ardındaki mantığı açıkça açıklamalıdır.


## Tutarlılık {#consistency}

Değişikliklerin projenin geri kalanıyla tutarlı olması önemlidir. Tutarsızlıklar bakımı zorlaştırır, bu nedenle bunlardan kaçınmalıyız. Kullanıcıya mesaj iletmek veya hata bildirmek için bir yaklaşım varsa, buna sadık kalmalıyız. Yazar projenin standartlarına katılmıyorsa, bunları daha fazla tartışabileceğimiz bir issue açmasını önerin.

## Testler {#tests}

Testler, kodu güvenle değiştirmenizi sağlar. Pull request’lerdeki kod test edilmeli ve tüm testler geçmelidir. İyi bir test, tutarlı şekilde aynı sonucu üreten ve anlaşılması ile bakımı kolay olan testtir. İnceleyenler inceleme süresinin çoğunu uygulama koduna harcar, ancak testler de kod olduğu için eşit derecede önemlidir.

## Kırıcı değişiklikler {#breaking-changes}

Kırıcı değişiklikler, Tuist kullanıcıları için kötü bir kullanıcı deneyimidir. Katkılar, kesinlikle gerekli olmadıkça kırıcı değişiklikler getirmekten kaçınmalıdır. Kırıcı bir değişikliğe başvurmadan Tuist arayüzünü geliştirmek için yararlanabileceğimiz birçok dil özelliği vardır. Bir değişikliğin kırıcı olup olmadığı her zaman açık olmayabilir. Değişikliğin kırıcı olup olmadığını doğrulamanın bir yolu, Tuist’i fixtures dizinindeki fixture projelere karşı çalıştırmaktır. Kendimizi kullanıcının yerine koyup değişikliklerin onları nasıl etkileyeceğini hayal etmemiz gerekir.
