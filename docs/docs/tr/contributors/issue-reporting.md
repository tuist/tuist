---
{
  "title": "Issue reporting",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reporting bugs"
}
---
# Sorun bildirimi {#issue-reporting}

Tuist kullanıcısı olarak, hatalar veya beklenmedik davranışlarla
karşılaşabilirsiniz. Böyle bir durumda, bunları düzeltebilmemiz için bize
bildirmenizi rica ederiz.

## GitHub sorunları bizim bilet platformumuzdur. {#github-issues-is-our-ticketing-platform}

Sorunlar Slack veya diğer platformlarda değil, GitHub'da [GitHub
sorunları](https://github.com/tuist/tuist/issues) olarak bildirilmelidir.
GitHub, sorunları izlemek ve yönetmek için daha uygundur, kod tabanına daha
yakındır ve sorunun ilerleyişini takip etmemizi sağlar. Ayrıca, sorunun uzun bir
şekilde açıklanmasını teşvik eder, bu da rapor eden kişinin sorunu düşünmesini
ve daha fazla bağlam sağlamasını sağlar.

## Bağlam çok önemlidir. {#context-is-crucial}

Yeterli bağlam içermeyen bir sorun eksik kabul edilecek ve yazardan ek bağlam
istenecektir. Sağlanmazsa, sorun kapatılacaktır. Şu şekilde düşünün: ne kadar
fazla bağlam sağlarsanız, sorunu anlamamız ve düzeltmemiz o kadar kolay olur.
Dolayısıyla, sorununuzun düzeltilmesini istiyorsanız, mümkün olduğunca fazla
bağlam sağlayın. Aşağıdaki soruları yanıtlamaya çalışın:

- Ne yapmaya çalışıyordunuz?
- Grafiğiniz nasıl görünüyor?
- Hangi Tuist sürümünü kullanıyorsunuz?
- Bu sizi engelliyor mu?

Ayrıca, en az **yeniden üretilebilir bir proje sunmanızı da talep ediyoruz**.

## Tekrarlanabilir proje {#reproducible-project}

### Tekrarlanabilir proje nedir? {#what-is-a-reproducible-project}

Tekrarlanabilir proje, bir sorunu göstermek için kullanılan küçük bir Tuist
projesidir. Bu sorun genellikle Tuist'teki bir hatadan kaynaklanır.
Tekrarlanabilir projeniz, hatayı açıkça göstermek için gereken minimum
özellikleri içermelidir.

### Neden tekrarlanabilir bir test senaryosu oluşturmalısınız? {#why-should-you-create-a-reproducible-test-case}

Tekrarlanabilir projeler, sorunun nedenini izole etmemizi sağlar ve bu, sorunu
çözmenin ilk adımıdır! Herhangi bir hata raporunun en önemli kısmı, hatayı
yeniden oluşturmak için gereken adımları tam olarak açıklamaktır.

Tekrarlanabilir bir proje, bir hataya neden olan belirli bir ortamı paylaşmak
için harika bir yoldur. Tekrarlanabilir projeniz, size yardım etmek isteyen
kişilere yardımcı olmanın en iyi yoludur.

### Tekrarlanabilir bir proje oluşturmak için adımlar {#steps-to-create-a-reproducible-project}

- Yeni bir git deposu oluşturun.
- `tuist init` komutunu kullanarak depo dizininde bir proje başlatın.
- Gördüğünüz hatayı yeniden oluşturmak için gerekli kodu ekleyin.
- Kodu yayınlayın (GitHub hesabınız bunu yapmak için uygun bir yerdir) ve
  ardından bir sorun oluştururken bu koda bağlantı verin.

### Tekrarlanabilir projelerin avantajları {#benefits-of-reproducible-projects}

- **Daha küçük yüzey alanı:** Hata dışında her şeyi kaldırarak, hatayı bulmak
  için derinlemesine araştırma yapmanız gerekmez.
- **Gizli kodu yayınlamaya gerek yok:** Ana sitenizi (çeşitli nedenlerle)
  yayınlayamayabilirsiniz. Sitenin küçük bir bölümünü yeniden oluşturarak
  yeniden üretilebilir bir test senaryosu haline getirirseniz, gizli kodu ifşa
  etmeden sorunu kamuya açık bir şekilde gösterebilirsiniz.
- **Hatanın kanıtı:** Bazen bir hata, makinenizdeki bazı ayarların birleşiminden
  kaynaklanır. Tekrarlanabilir bir test senaryosu, katkıda bulunanların sizin
  derlemenizi indirip kendi makinelerinde de test etmelerini sağlar. Bu, sorunun
  nedenini doğrulamaya ve daraltmaya yardımcı olur.
- **Hatanızı düzeltmek için yardım alın:** Başka biri sizin sorununuzu yeniden
  oluşturabilirse, sorunu çözme şansı genellikle yüksektir. Önce sorunu yeniden
  oluşturamadan bir hatayı düzeltmek neredeyse imkansızdır.
