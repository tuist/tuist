---
{
  "title": "Önbellek",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode, Gradle, Bazel, Elixir, Rust ve Struo için Tuist Önbelleği ile derleme sürelerini optimize edin."
}
---
# Önbellek {#cache}

Derleme yapıtları ortamlar arasında paylaşılmaz, bu da aynı kodu tekrar tekrar derlemenize neden olur. Tuist'in önbellekleme özelliği, yapıtları uzaktan paylaşarak ekibinizin ve CI sisteminizin zaten derlenmiş olanları yeniden derlemeden daha hızlı derlemeler elde etmesini sağlar. Yerel ve uzak derleme önbelleklerinin farklı derleme sistemlerinde nasıl çalıştığını ve Xcode'un kendi önbelleklerinin ne olduğunu öğrenmek için bkz. <.localized_link href="/references/concepts/build-cache">Derleme önbelleği nedir?</.localized_link>. Bir önbellek seçmeden önce derlemelerin neden yavaş olduğunu anlamak için bkz. [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds).

Projenize veya dağıtım modelinize uygun önbellek iş akışını öğrenin:

<.home_cards>
  <.home_card
    title="Modül önbelleği"
    details="Tuist tarafından oluşturulan projeleri kullanan projeler için tek tek modülleri ikili dosya olarak önbelleğe alın. Tuist proje oluşturma işlemi gerektirir."
    link="/guides/features/cache/module-cache"
/>
  <.home_card
    title="Xcode önbelleği"
    details="Xcode derleme yapıtlarını ortamlar arasında paylaşın. Herhangi bir Xcode projesiyle çalışır, proje oluşturma işlemi gerekmez."
    link="/guides/features/cache/xcode-cache"
/>
  <.home_card
    title="Gradle önbelleği"
    details="Gradle derleme önbelleği yapıtlarını uzaktan paylaşın. Performans görünürlüğü için derleme içgörülerini içerir."
    link="/guides/features/cache/gradle-cache"
/>
  <.home_card
    title="Bazel önbelleği"
    details="Ekip ve CI arasında eylem çıktılarını paylaşmak için Bazel'i Tuist'in Uzaktan Yürütme API önbelleğine yönlendirin."
    link="/guides/features/cache/bazel-cache"
/>
  <.home_card
    title="Elixir önbelleği"
    details="Desteklenen Elixir bağımlılıkları için önbellekleme özelliğini etkinleştirin ve Mix kullanmaya devam edin. Önbellek isabetlerini ve aktarımları panoda inceleyin."
    link="/guides/features/cache/elixir"
/>
  <.home_card
    title="Rust önbelleği (deneysel)"
    details="Desteklenen Rust derleme çıktılarını ve derleme betiği çalıştırmalarını yerel olarak ve Kura aracılığıyla yeniden kullanın. Önbelleklemenin nasıl etkinleştirileceğini ve önbellek etkinliğinin nasıl inceleneceğini öğrenin."
    supported_for="rust"
    link="/guides/features/cache/rust"
/>
  <.home_card
    title="Struo önbelleği"
    details="Struo'nun yerel Tuist sağlayıcısı ile önbelleğe alınmış betik ve graf eylemi sonuçlarını geliştirici makineleri ve CI arasında paylaşın."
    link="/guides/features/cache/struo"
/>
  <.home_card
    title="Kendi sunucunuzda barındırma"
    details="Önbellek düğümlerini CI'ya, ofislere veya bölgesel hesaplama kaynaklarına yakın konumlandırın ve bunları barındırılan veya kendi sunucunuzda barındırdığınız Tuist'e bağlayın."
    link="/guides/features/cache/self-hosting"
/>
</.home_cards>

> [!TIP]
> **Tuist Runners üzerinde en hızlı**
>
> <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> üzerinde, önbellek çalıştırıcının özel ağına yerleştirilir ve geliştirici makinelerinizin kullandığı aynı önbellekle paylaşılır; böylece CI işleri, ısınması gereken ayrı bir CI önbelleği olmadan kutudan çıkar çıkmaz sıcak isabetler alır.


## Yüklemeleri CI ile sınırla {#restrict-uploads-to-ci}

Hesap yöneticileri, geliştiricileri salt okunur yaparken CI'nın önbellek yapıtlarını yüklemesine izin verebilir. Tuist'te hesabın **Önbellek** ayarlarını açın ve **Önbellek yükleme erişimi** seçeneğini **Yalnızca CI ve hesap token'ları** olarak ayarlayın. Bundan sonra, oturum açma kimlik doğrulamasıyla giriş yapan üyeler hâlâ önbellekten indirebilir, ancak yüklemeler için CI OIDC kimlik doğrulaması veya `project:cache:write` ya da `ci` gibi önbellek yazma kapsamlarına sahip bir hesap token'ı gerekir.

CI güvenilir önbellek üreticisi olduğunda ve yerel makinelerin yalnızca önbelleği tüketmesi gerektiğinde bunu kullanın. Bu ayar yalnızca önbellek yükleme yetkilendirmesini etkiler.
