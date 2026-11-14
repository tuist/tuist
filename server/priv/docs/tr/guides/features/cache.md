---
{
  "title": "Önbellek",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode, Gradle, Bazel, Elixir, Rust ve Once için Tuist Önbellek ile derleme sürelerini optimize edin."
}
---
# Önbellek {#cache}

Derleme yapıtları ortamlar arasında paylaşılmaz, bu da aynı kodu defalarca yeniden derlemenize neden olur. Tuist’in önbellekleme özelliği, yapıtları uzaktan paylaşarak ekibinizin ve CI’nızın zaten derlenmiş olanları yeniden derlemeden daha hızlı derlemeler elde etmesini sağlar. Bir önbellek seçmeden önce derlemelerin neden yavaş olduğunu anlamak için [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds) bölümüne bakın.

Projenize veya dağıtım modelinize uygun önbellek iş akışını öğrenin:

<.home_cards>
  <.home_card
    title="Modül önbelleği"
    details="Tuist tarafından oluşturulan projeleri kullanan projelerde bağımsız modülleri ikil olarak önbelleğe alır. Tuist proje oluşturma gerektirir."
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode önbelleği"
    details="Xcode derleme yapıtlarını ortamlar arasında paylaşır. Herhangi bir Xcode projesiyle çalışır, proje oluşturma gerekmez."
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle önbelleği"
    details="Gradle derleme önbelleği yapıtlarını uzaktan paylaşır. Performans görünürlüğü için derleme içgörülerini içerir."
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel önbelleği"
    details="Ekip ve CI arasında eylem çıktılarını paylaşmak için Bazel’i Tuist’in Uzaktan Yürütme API önbelleğine yönlendirin."
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir önbelleği"
    details="Desteklenen Elixir bağımlılıkları için önbellekleme etkinleştirin ve Mix kullanmaya devam edin. Panoda önbellek isabetlerini ve aktarımları inceleyin."
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust önbelleği (deneysel)"
    details="Desteklenen Rust derleme çıktılarını ve betik çalıştırmalarını yerel olarak ve Kura üzerinden yeniden kullanın. Önbellekleme nasıl etkinleştirilir ve önbellek etkinliği nasıl incelenir öğrenin."
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Once önbelleği"
    details="Once’ın yerel Tuist sağlayıcısıyla önbelleğe alınmış betik ve grafik eylemi sonuçlarını geliştirici makineleri ve CI arasında paylaşın."
    link="/guides/features/cache/once"
/>
  <.home_card
    title="Kendi sunucunuzda barındırma"
    details="Önbellek düğümlerini CI, ofisler veya bölgesel hesaplama kaynaklarına yakın çalıştırın ve bunları barındırılan veya kendi sunucunuzda barındırdığınız Tuist’e bağlayın."
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **Tuist Runners üzerinde en hızlı**
>
> <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> üzerinde önbellek, çalıştırıcının özel ağında konumlandırılır ve geliştirici makinelerinizin kullandığı aynı önbellekle paylaşılır; böylece CI işleri ayrı bir CI önbelleğini ısıtmaya gerek kalmadan kutudan çıkar çıkmaz sıcak isabetler alır.


## Yüklemeleri CI ile sınırla {#restrict-uploads-to-ci}

Hesap yöneticileri, geliştiricileri salt okunur yaparken CI’nın önbellek yapıtlarını yüklemesine izin verebilir. Tuist’te hesabın **Önbellek** ayarlarını açın ve **Önbellek yükleme erişimi** seçeneğini **Yalnızca CI ve hesap token’ları** olarak ayarlayın. Bundan sonra, oturum açma kimlik doğrulamasıyla giriş yapan üyeler hâlâ önbellekten indirebilir, ancak yüklemeler için CI OIDC kimlik doğrulaması veya `project:cache:write` ya da `ci` gibi önbellek yazma kapsamlarına sahip bir hesap token’ı gerekir.

CI güvenilir önbellek üreticisi olduğunda ve yerel makinelerin yalnızca önbelleği tüketmesi gerektiğinde bunu kullanın. Bu ayar yalnızca önbellek yükleme yetkilendirmesini etkiler.
