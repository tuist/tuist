---
{
  "title": "Tuist nedir?",
  "description": "Tuist, mühendislik ekipleri ve kodlama ajanları için bir derleme platformudur. Xcode, Gradle, Bazel, Elixir ve Rust üzerinde derleme ve test iş akışlarını destekler; Once desteği canary aşamasındadır. Özellikler araç zincirine göre değişir ve Rust derleme önbellekleme deneyseldir."
}
---

# Ekipler ve kodlama ajanları için bir derleme platformu

**Tuist, mühendislik ekipleri ve onların kodlama ajanları için bir derleme platformudur.** Xcode, Gradle, Bazel, Elixir ve Rust üzerinde derleme ve test iş akışlarını destekler; Once desteği canary aşamasındadır. Mevcut derleme sistemlerinizi değiştirmek yerine onlarla birlikte çalışır. Kullanılabilir özellikler araç zincirinize bağlıdır: Rust projeleri, doctest'ler, kararsız test tespiti ve deneysel derleme önbellekleme dahil olmak üzere Cargo derleme ve test içgörülerine erişir. Once, paylaşımlı önbellekleme, derleme ve test içgörileri, parçalama ve desteklenen uygulama önizlemeleri için yerel olarak bağlanır.

Derleme sisteminiz için <.localized_link href="/guides/get-started">Başlangıç yollarından</.localized_link> birini takip edin. Once, Tuist CLI olmadan doğrudan bağlanır; diğer yollar hangi Tuist araçlarının kurulacağını açıklar.

<br/>

<.home_cards>
  <.home_card
    title="Önbellek"
    details="Derleme çıktılarınızı ekibiniz ve CI arasında paylaşın. Xcode'un derleme önbelleği, Tuist'in modül önbelleği, Gradle'ın derleme önbelleği, Bazel'in uzak önbelleği, Elixir'in bağımlılık önbelleği, Rust'ın deneysel derleme önbelleği ve Once'in paylaşımlı eylem önbelleği ile çalışır."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="Derleme ve test içgörileri"
    details="Xcode, Gradle, Bazel, Elixir, Rust ve Once projelerinde derleme ve test sürelerini, hataları, kararsızlığı ve gerilemeleri izleyin."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="Seçici test"
    details="Oluşturulan Xcode projelerindeki bir değişiklikten etkilenen testleri yalnızca çalıştırın, böylece geri bildirim saniyeler içinde ulaşsın."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="Çalıştırıcılar"
    details="CI'yı yönetilen macOS ve Linux çalıştırıcılarında, geliştirici makinelerinizin kullandığı önbelleğe yakın bir konumda çalıştırın."
    link="/guides/features/runners"
/>
  <.home_card
    title="Önizlemeler"
    details="Uygulamanızı anında bir URL ile paylaşın. Mağaza inceleme gecikmesi yok, karmaşık kurulum yok."
    link="/guides/features/previews"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="Xcode projelerini Swift ile tanımlayın ve tutarlı bir şekilde oluşturun. Birleştirme çakışmalarını ortadan kaldırın ve modül önbelleğinin kilidini açın."
    link="/guides/features/projects"
/>
  <.home_card
    title="Paket Kaydı"
    details="Tuist'in önbellek ağıyla desteklenen bir kayıt defteri sayesinde Swift paketlerini dakikalar yerine saniyeler içinde çözün."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="Paket boyutu"
    details="Uygulamanızı analiz edin ve hafif tutun, böylece kullanıcılar daha hızlı indirmeler elde eder ve siz mağaza yönergelerini karşılamış olursunuz."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## Büyük ölçekte ürün yayınlayan ekipler tarafından güveniliyor

**[Trendyol](https://www.trendyol.com/), [Etsy](https://www.etsy.com/), [Bumble](https://bumble.com/), [Monzo](https://monzo.com/), [Bending Spoons](https://bendingspoons.com/) ve 100'den fazla başka şirketteki ekipler**, iOS ve Android kod tabanlarında Tuist ile daha hızlı ürün yayınlıyor.
