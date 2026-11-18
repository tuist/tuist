---
{
  "title": "Sorun bildirimi",
  "titleTemplate": ":title · Katkıda Bulunanlar · Tuist",
  "description": "Hataları bildirerek Tuist'e nasıl katkıda bulunacağınızı öğrenin"
}
---
# Sorun bildirimi {#issue-reporting}

Tuist kullanıcısı olarak hatalarla veya beklenmeyen davranışlarla karşılaşabilirsiniz. Böyle bir durumda, bunları düzeltebilmemiz için bildirmenizi öneririz.

## GitHub issues bilet platformumuzdur {#github-issues-is-our-ticketing-platform}

Sorunlar Slack veya diğer platformlarda değil, GitHub'da [GitHub issues](https://github.com/tuist/tuist/issues) olarak bildirilmelidir. GitHub, sorunları izlemek ve yönetmek için daha iyidir, kod tabanına daha yakındır ve sorunun ilerlemesini takip etmemize olanak tanır. Ayrıca, sorunun uzun bir açıklamasını teşvik eder; bu da raporlayan kişiyi sorun hakkında düşünmeye ve daha fazla bağlam sağlamaya zorlar.

## Bağlam çok önemlidir {#context-is-crucial}

Yeterli bağlam içermeyen bir sorun eksik kabul edilir ve yazardan ek bağlam istenir. Sağlanmazsa sorun kapatılır. Şöyle düşünün: Ne kadar çok bağlam sağlarsanız, sorunu anlamamız ve düzeltmemiz o kadar kolay olur. Sorununuzun çözülmesini istiyorsanız mümkün olduğunca fazla bağlam sağlayın. Aşağıdaki soruları yanıtlamaya çalışın:

- Ne yapmaya çalışıyordunuz?
- Grafınız nasıl görünüyor?
- Tuist'in hangi sürümünü kullanıyorsunuz?
- Bu sizi engelliyor mu?

Ayrıca minimal bir **reproducible project** sağlamanızı talep ediyoruz.

## Tekrarlanabilir proje {#reproducible-project}

### Tekrarlanabilir proje nedir? {#what-is-a-reproducible-project}

Tekrarlanabilir proje, bir sorunu göstermek için küçük bir Tuist projesidir; genellikle bu sorun Tuist'teki bir hatadan kaynaklanır. Tekrarlanabilir projeniz, hatayı açıkça göstermek için gereken asgari özellikleri içermelidir.

### Neden tekrarlanabilir bir test senaryosu oluşturmalısınız? {#why-should-you-create-a-reproducible-test-case}

Tekrarlanabilir bir proje, bir sorunun nedenini izole etmemizi sağlar; bu da onu düzeltmeye yönelik ilk adımdır! Herhangi bir hata raporunun en önemli kısmı, hatayı yeniden üretmek için gereken kesin adımları açıklamaktır.

Tekrarlanabilir bir proje, hataya neden olan belirli bir ortamı paylaşmanın harika bir yoludur. Tekrarlanabilir projeniz, size yardımcı olmak isteyen insanlara yardım etmenin en iyi yoludur.

### Tekrarlanabilir bir proje oluşturma adımları {#steps-to-create-a-reproducible-project}

- Yeni bir git deposu oluşturun.
- Depo dizininde `tuist init` kullanarak bir proje başlatın.
- Gördüğünüz hatayı yeniden oluşturmak için gereken kodu ekleyin.
- Kodu yayınlayın (bunu yapmak için GitHub hesabınız iyi bir yerdir) ve ardından bir sorun oluştururken ona bağlantı verin.

### Tekrarlanabilir projelerin faydaları {#benefits-of-reproducible-projects}

- **Daha küçük kapsama alanı:** Hata dışındaki her şeyi kaldırarak hatayı bulmak için derinlere inmenize gerek kalmaz.
- **Gizli kodu yayınlamanıza gerek yok:** Ana sitenizi (birçok nedenle) yayınlayamayabilirsiniz. Küçük bir bölümünü tekrarlanabilir bir test senaryosu olarak yeniden oluşturmak, herhangi bir gizli kodu açığa çıkarmadan bir sorunu herkese açık şekilde göstermenize olanak tanır.
- **Hatanın kanıtı:** Bazen bir hata, makinenizdeki ayarların belirli bir kombinasyonundan kaynaklanır. Tekrarlanabilir bir test senaryosu, katkıda bulunanların derlemenizi indirip kendi makinelerinde de test etmelerine olanak tanır. Bu, bir sorunun nedenini doğrulamaya ve daraltmaya yardımcı olur.
- **Hatanızı düzeltme konusunda yardım alın:** Başka biri sorununuzu yeniden üretebiliyorsa, sorunu çözme şansı genellikle yüksektir. Önce onu yeniden üretemeden bir hatayı düzeltmek neredeyse imkansızdır.
