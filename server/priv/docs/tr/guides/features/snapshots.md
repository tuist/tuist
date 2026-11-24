---
{
  "title": "Anlık Görüntüler",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode ve Gradle projelerinde görsel gerilemeleri yakalayın: Tuist, anlık görüntü resimlerinizi depolar, her çekme isteğini temel çizgisiyle karşılaştırır ve değişiklikleri panodan veya çekme isteğinden onaylamanıza ya da reddetmenize olanak tanır."
}
---
# Snapshotlar {#snapshots}

> [!IMPORTANT]
> **Davet usulü**
>
> Snapshotlar şu anda davet usulüdür. Hesabınız için erişim istemek üzere [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack kanalında](https://slack.tuist.dev) bize yazın.

Snapshot testleri, kullanıcı arayüzünüzü görsellere dönüştürür ve görsel gerilemeleri yakalamak için bunları referans görsellerle karşılaştırır. Bu referans görselleri deponuza eklemek yerine, her test çalıştırmasında oluşturulan görselleri Tuist'e yüklersiniz. Tuist bunları bir **baz çizgi** ile karşılaştırır, panoda nelerin değiştiğini gösterir ve biri değişiklikleri onaylayana kadar çalıştırmayı başarısız sayar.

- Git'te referans görsel olmadığından kopyalar küçük kalır ve kimse PNG dosyalarında çakışma çözmez.
- İnceleyenler değişiklikleri kodun yanında görür: yan yana, fark olarak veya silme ya da soğan zarı katmanlı görünümle.
- Değişiklikler panoda veya çekme isteğinde onaylanır ya da reddedilir ve dal birleştirildiğinde onay yeni baz çizgi haline gelir.

## Nasıl çalışır {#how-it-works}

1. Testleriniz görseller oluşturur; örneğin her SwiftUI veya Compose önizlemesi için.
2. Tuist CLI veya Gradle eklentisi bunları geçerli commit'in **snapshot derlemesi** olarak yükler.
3. Tuist baz çizgiyi seçer: dalınızın başladığı commit'teki varsayılan dalınızın derlemesini.
4. Her görsel baz çizgisiyle karşılaştırılır ve değiştirilmiş, eklenmiş, kaldırılmış veya değişmemiş olarak işaretlenir.
5. Derleme bir karara varır:

| Karar | Çalıştırma | Ne zaman |
| --- | --- | --- |
| Baz çizgi | Geçer | Derleme varsayılan daldan geldiği için sonraki derlemeler bununla karşılaştırılır. |
| Geçti | Geçer | Hiçbir görsel değişmedi veya kaldırılmadı. Yeni görsellerin incelenmesine gerek yok. |
| İnceleme gerekli | Başarısız | Görseller değişti veya kaldırıldı ve henüz kimse incelemedi. |
| Onaylandı | Geçer | Birisi değişiklikleri onayladı. |
| Reddedildi | Başarısız | Birisi değişiklikleri reddetti. |

Derlemeler bir **küme** içinde karşılaştırılır; örneğin `ios-iphone` veya `android-phone`. Farklı boyutlarda oluşturulan görsellerin birbirleriyle asla karşılaştırılmaması için cihaz yapılandırması başına bir küme kullanın.

## Kurulum {#set-up}

Projeniz için entegrasyonu seçin:

<.home_cards>
  <.home_card
    title="Xcode"
    details="tuist xcodebuild test ile bir Xcode projesinin her SwiftUI önizlemesinin snapshot'ını alın."
    link="/guides/features/snapshots/xcode"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="tuist test ile Tuist tarafından oluşturulan bir projenin her SwiftUI önizlemesinin snapshot'ını alın."
    link="/guides/features/snapshots/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle eklentisiyle her Compose önizlemesinin snapshot'ını alın veya Paparazzi ve Roborazzi'nin kaydettiklerini yükleyin."
    link="/guides/features/snapshots/gradle"
/>
</.home_cards>

## Değişiklikleri panoda inceleyin {#dashboard}

Her snapshot derlemesi, projenizin panosunda **Testler → Snapshots** altında bir sayfaya sahiptir. Derlemenin kararını, dalını, commit'ini, çekme isteğini ve baz çizgisini gösterir; görselleri duruma ve gruba göre listeler. Derlemeyi incelemek için **Değişiklikleri onayla** veya **Değişiklikleri reddet** seçeneklerini kullanın. Bir incelemeyi daha sonra değiştirebilirsiniz.

![Baz çizgisiyle yan yana duran değiştirilmiş bir görsel içeren, inceleme gerektiren bir snapshot derlemesi](/images/guides/features/snapshots/review.png)

**Yan yana**, değişen pikselleri vurgulayan **Fark**, baz çizgi ile yeni görsel arasında kaydırma yapan **Silme** ve birini diğerine karıştıran **Soğan zarı** arasında geçiş yapın. Her görsel tam ekran açılabilir.

![Baz çizgi ile yeni görsel arasında kaydırma yapan silme modu](/images/guides/features/snapshots/wipe.png)

## Çekme isteğinde değişiklikleri inceleyin {#pull-request}

<.localized_link href="/guides/integrations/gitforge/github">GitHub uygulaması</.localized_link> yüklüyken, bir çekme isteğinin her snapshot derlemesi `tuist/snapshots (<set>)` adlı bir denetim alır. Değişikliklerin incelenmesi gerekirken veya bir inceleme tarafından reddedildikten sonra, denetim başarısız olur ve gerekiyorsa birleştirmeyi engeller:

![Değişiklikler reddedildiği için snapshots denetiminin başarısız olduğu çekme isteğinin birleştirme kutusu](/images/guides/features/snapshots/github-pr-checks.png)

Denetim, kümenin değiştirilen, eklenen ve kaldırılan görsellerini sayar ve panodaki derlemeye bağlantı verir. GitHub'dan ayrılmadan denetimin sayfasından değişiklikleri onaylayın veya reddedin. Denetim, inceleyen kişinin adıyla güncellenir ve reddedilen bir derleme daha sonra onaylanabilir.

![Değişiklikler reddedildikten sonra GitHub'daki snapshots denetimi, bunları onaylamak için düğmeyle birlikte](/images/guides/features/snapshots/github-check-run.png)

Onaylama testlerinizi yeniden çalıştırmaz: denetimi geçer kılar. Aynı dalın sonraki derlemeleri, tam olarak aynı değişikliklere sahip oldukları sürece onayı korur; bu nedenle CI'yı yeniden çalıştırmak veya incelenen görsellere dokunmayan bir commit göndermek de geçer sonuç verir. Görsellere yönelik başka herhangi bir değişiklik yeni bir inceleme gerektirir. Dal birleştirildiğinde, varsayılan dalın derlemesi yeni baz çizgi haline gelir.
