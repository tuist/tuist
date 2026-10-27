---
{
  "title": "Issue reporting",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reporting bugs"
}
---
# Sorun raporlama {#issue-reporting}

Tuist kullanıcısı olarak, hatalarla veya beklenmedik davranışlarla
karşılaşabilirsiniz. Eğer karşılaşırsanız, bunları düzeltebilmemiz için rapor
etmenizi öneririz.

## GitHub sorunları bizim biletleme platformumuzdur {#github-issues-is-our-ticketing-platform}

Sorunlar Slack veya diğer platformlarda değil GitHub'da [GitHub
sorunları](https://github.com/tuist/tuist/issues) olarak bildirilmelidir. GitHub
sorunları izlemek ve yönetmek için daha iyidir, kod tabanına daha yakındır ve
sorunun ilerlemesini izlememize olanak tanır. Ayrıca, sorunun uzun biçimli bir
açıklamasını teşvik eder, bu da raportörü sorun hakkında düşünmeye ve daha fazla
bağlam sağlamaya zorlar.

## Bağlam çok önemlidir {#context-is-crucial}

Yeterli içeriğe sahip olmayan bir konu eksik kabul edilecek ve yazardan ek
içerik istenecektir. Ek içerik sağlanmadığı takdirde sorun kapatılacaktır. Şöyle
düşünün: Ne kadar çok bağlam sağlarsanız, sorunu anlamamız ve düzeltmemiz o
kadar kolay olur. Dolayısıyla, sorununuzun çözülmesini istiyorsanız, mümkün
olduğunca fazla bağlam sağlayın. Aşağıdaki soruları yanıtlamaya çalışın:

- Ne yapmaya çalışıyordun?
- Grafiğiniz nasıl görünüyor?
- Tuist'in hangi sürümünü kullanıyorsunuz?
- Bu seni engelliyor mu?

Ayrıca minimum **çoğaltılabilir bir proje** sağlamanızı istiyoruz.

## Tekrarlanabilir proje {#reproducible-project}

### Tekrar üretilebilir proje nedir? {#what-is-a-reproducible-project}

Tekrarlanabilir bir proje, bir sorunu göstermek için küçük bir Tuist projesidir
- genellikle bu sorun Tuist'teki bir hatadan kaynaklanır. Yeniden üretilebilir
projeniz, hatayı açıkça göstermek için gereken minimum özellikleri içermelidir.

### Neden tekrarlanabilir bir test senaryosu oluşturmalısınız? {#why-should-you-create-a-reproducible-test-case}

Tekrarlanabilir bir proje, bir sorunun nedenini izole etmemizi sağlar, bu da onu
düzeltmeye yönelik ilk adımdır! Herhangi bir hata raporunun en önemli kısmı,
hatayı yeniden üretmek için gereken adımları tam olarak tanımlamaktır.

Yeniden üretilebilir bir proje, bir hataya neden olan belirli bir ortamı
paylaşmanın harika bir yoludur. Tekrar üretilebilir projeniz, size yardım etmek
isteyen insanlara yardım etmenin en iyi yoludur.

### Tekrar üretilebilir bir proje oluşturmak için adımlar {#steps-to-create-a-reproducible-project}

- Yeni bir git deposu oluşturun.
- Depo dizinindeki `tuist init` adresini kullanarak bir projeyi başlatın.
- Gördüğünüz hatayı yeniden oluşturmak için gereken kodu ekleyin.
- Kodu yayınlayın (GitHub hesabınız bunu yapmak için iyi bir yerdir) ve ardından
  bir sorun oluştururken buna bağlantı verin.

### Tekrarlanabilir projelerin faydaları {#benefits-of-reproducible-projects}

- **Daha küçük yüzey alanı:** Hata dışında her şeyi kaldırdığınızda, hatayı
  bulmak için kazmanız gerekmez.
- **Gizli kod yayınlamanıza gerek yok:** Ana sitenizi yayınlayamayabilirsiniz
  (birçok nedenden dolayı). Küçük bir bölümünü tekrarlanabilir bir test vakası
  olarak yeniden oluşturmak, herhangi bir gizli kodu açığa çıkarmadan bir sorunu
  herkese açık bir şekilde göstermenizi sağlar.
- **Hatanın kanıtı:** Bazen bir hata, makinenizdeki bazı ayar
  kombinasyonlarından kaynaklanır. Tekrarlanabilir bir test durumu, katkıda
  bulunanların derlemenizi indirip kendi makinelerinde de test etmelerini
  sağlar. Bu, bir sorunun nedenini doğrulamaya ve daraltmaya yardımcı olur.
- **Hatanızı düzeltmek için yardım alın:** Başka biri sorununuzu yeniden
  üretebilirse, genellikle sorunu çözme şansı yüksektir. Bir hatayı, önce onu
  yeniden üretmeden düzeltmek neredeyse imkansızdır.
