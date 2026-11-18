---
{
  "title": "Önbellek",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode, Gradle, Bazel, Elixir, Rust ve Once için Tuist Cache ile derleme sürelerini optimize edin."
}
---
# Önbellek {#cache}

Derleme yapıtları ortamlar arasında paylaşılmaz, bu da aynı kodu defalarca yeniden derlemenize neden olur. Tuist’in önbellekleme özelliği, yapıtları uzaktan paylaşır; böylece ekibiniz ve CI, daha önce derlenmiş olanları yeniden derlemeden daha hızlı derlemeler elde eder. Yerel ve uzak derleme önbelleklerinin farklı derleme sistemlerinde nasıl çalıştığını ve Xcode’un kendi önbelleklerinin ne olduğunu öğrenmek için bkz. <.localized_link href="/references/concepts/build-cache">Derleme önbelleği nedir?</.localized_link>. Bir önbellek seçmeden önce derlemelerin neden yavaş olduğunu anlamak için bkz. [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds).

Projenize veya dağıtım modelinize uygun önbellek iş akışını öğrenin:

<.home_cards>
  <.home_card
    title="Modül önbelleği"
    details="Tuist tarafından oluşturulan projeleri kullanan projeler için tek tek modülleri ikil (binary) olarak önbelleğe alın. Tuist proje oluşturma gerektirir."
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode önbelleği"
    details="Xcode derleme yapıtlarını ortamlar arasında paylaşın. Herhangi bir Xcode projesiyle çalışır; proje oluşturma gerekmez."
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle önbelleği"
    details="Gradle derleme önbelleği yapıtlarını uzaktan paylaşın. Performans görünürlüğü için derleme içgörülerini içerir."
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel önbelleği"
    details="Bazel’i Tuist’in Uzak Yürütme API önbelleğine yönlendirerek eylem çıktılarını ekibiniz ve CI arasında paylaşın."
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir önbelleği"
    details="Desteklenen Elixir bağımlılıkları için önbelleklemeyi etkinleştirin ve Mix kullanmaya devam edin. Önbellek isabetlerini ve aktarımları panoda inceleyin."
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust önbelleği (deneysel)"
    details="Desteklenen Rust derleme çıktılarını ve derleme betiği çalıştırmalarını yerelde ve Kura üzerinden yeniden kullanın. Önbelleklemeyi nasıl etkinleştireceğinizi ve önbellek etkinliğini nasıl inceleyeceğinizi öğrenin."
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Once önbelleği"
    details="Once’ın yerel Tuist sağlayıcısıyla önbelleğe alınmış betik ve graf eylemi sonuçlarını geliştirici makineleri ve CI arasında paylaşın."
    link="/guides/features/cache/once"
/>
  <.home_card
    title="Kendi sunucunuzda barındırma"
    details="Önbellek düğümlerini CI’ya, ofislere veya bölgesel hesaplama kaynaklarına yakın çalıştırın ve bunları barındırılan veya kendi sunucunuzda barındırdığınız Tuist’e bağlayın."
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **Tuist Runners üzerinde en hızlı**
>
> <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> üzerinde önbellek, çalıştırıcının özel ağına konumlandırılır ve geliştirici makinelerinizin kullandığı aynı önbellekle paylaşılır; böylece CI işleri, ayrıca ısıtılması gereken ayrı bir CI önbelleği olmadan kutudan çıkar çıkmaz sıcak isabetler alır.


## Yüklemeleri CI ile sınırla {#restrict-uploads-to-ci}

Hesap yöneticileri, geliştiricileri salt okunur yaparken CI’nın önbellek yapıtlarını yüklemesine izin verebilir. Tuist’te hesabın **Önbellek** ayarlarını açın ve **Önbellek yükleme erişimi** seçeneğini **Yalnızca CI ve hesap token’ları** olarak ayarlayın. Bundan sonra, oturum açma oturumlarıyla kimliği doğrulanan üyeler hâlâ önbellekten indirebilir, ancak yüklemeler için CI OIDC kimlik doğrulaması veya `project:cache:write` ya da `ci` gibi önbellek yazma kapsamlarına sahip bir hesap token’ı gerekir.

CI güvenilir önbellek üreticisi olduğunda ve yerel makinelerin yalnızca önbelleği tüketmesi gerektiğinde bunu kullanın. Bu ayar yalnızca önbellek yükleme yetkilendirmesini etkiler.
