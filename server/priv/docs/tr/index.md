---
{
  "title": "Tuist nedir?",
  "description": "Tuist, mühendislik ekipleri ve kodlama ajanları için bir derleme platformudur. Xcode, Gradle, Bazel, Elixir ve Rust üzerinde derleme ve test iş akışlarını destekler; Once desteği canary aşamasındadır. Özellikler araç zincirine göre değişir ve Rust derleme önbelleğe alma deneyseldir."
}
---

# Takımlar ve kodlama ajanları için bir derleme platformu

**Tuist, mühendislik ekipleri ve onların kodlama ajanları için bir derleme platformudur.** Xcode, Gradle, Bazel, Elixir ve Rust üzerindeki derleme ve test iş akışlarını destekler; Once desteği canary aşamasındadır. Mevcut kullandığınız derleme sistemlerinin yerine geçmek yerine onlarla uyumlu çalışır. Kullanılabilir özellikler araç zincirinize bağlıdır: Rust projeleri, doctest'ler, kararsız test tespiti ve deneysel derleme önbellekleme dahil olmak üzere Cargo derleme ve test içgörülerine erişir. Once; paylaşılan önbellekleme, derleme ve test içgörüleri, parçalama (sharding) ve desteklenen uygulama önizlemeleri için yerel olarak bağlanır.

Derleme sisteminiz için <.localized_link href="/guides/get-started">Başlangıç yollarından</.localized_link> birini izleyin. Once, Tuist CLI olmadan doğrudan bağlanır; diğer yollar hangi Tuist araçlarının kurulacağını açıklar.

<br/>

<.home_cards>
  <.home_card
    title="Önbellek"
    details="Derleme çıktılarınızı ekibiniz ve CI arasında paylaşın. Xcode'un derleme önbelleği, Tuist'in modül önbelleği, Gradle'ın derleme önbelleği, Bazel'ın uzak önbelleği, Elixir'in bağımlılık önbelleği, Rust'ın deneysel derleme önbelleği ve Once'ın paylaşılan eylem önbelleği ile çalışır."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="Derleme ve test içgörüleri"
    details="Xcode, Gradle, Bazel, Elixir, Rust ve Once projelerinde derleme ve test sürelerini, hataları, kararsızlığı ve gerilemeleri takip edin."
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="Seçici test"
    details="Oluşturulan Xcode projelerinde değişmemiş test hedeflerini atlayın; bireysel XCTest/XCUITest seçimi için erken erişim kapsam stratejisi sunar."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="Çalıştırıcılar"
    details="CI'yı yönetilen macOS ve Linux çalıştırıcılarında, geliştirici makinelerinizin kullandığı önbelleğe yakın konumda çalıştırın."
    link="/guides/features/runners"
/>
  <.home_card
    title="Önizlemeler"
    details="Desteklenen mobil uygulamaları, macOS uygulamalarını ve macOS/Linux komut satırı araçlarını bir URL üzerinden paylaşın. Derleme, imzalama ve alıcı uyumluluğu gereksinimleri geçerlidir."
    link="/guides/features/previews"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="Xcode projelerini Swift ile tanımlayın ve tutarlı bir şekilde oluşturun. Proje dosyası çakışmalarını azaltın ve modül önbelleğinin kilidini açın."
    link="/guides/features/projects"
/>
  <.home_card
    title="Paket Kaydı"
    details="Desteklenen Swift paketlerini Git depolarını klonlamak yerine kayıt defteri protokolü üzerinden alın."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="Paket boyutu"
    details="Desteklenen Apple ve Android paket boyutlarını zaman içinde takip edin ve boyut gerilemelerini inceleyin."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## Büyük ölçekte yazılım yayınlayan ekipler tarafından güveniliyor

Ekiplerin benimsediği iş akışlarını ve bildirdikleri sonuçları görmek için [müşteri hikayelerini](https://tuist.dev/customers) okuyun.
