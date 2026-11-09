---
title: Elixir önbelleği
titleTemplate: ":title · Önbellek · Kılavuzlar · Tuist"
description: Elixir projeniz için bağımlılık önbelleğini etkinleştirin ve Mix kullanmaya devam edin.
---

# Elixir önbelleği

Tuist, derlenmiş bağımlılıkları yerel olarak ve CI yapıları arasında yeniden kullanır. Bir kez etkinleştirin, ardından `mix compile` ve `mix test` kullanmaya devam edin.

## Kurulum

Bir kez <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixir ile başlayın</.localized_link> kılavuzunu izleyin. Paylaşılan kurulum, yapı ve test içgörülerinin yanı sıra bağımlılık önbellekleme özelliğini de sağlar; ek bir önbellek kurulumuna gerek yoktur.

`cache: true`, desteklenen Hex ve Git bağımlılıklarını otomatik olarak seçer; bunları listelemenize gerek yoktur. Yerel/özel derleme ve yerel bağımlılıklar Mix üzerinden normal şekilde devam eder. Uygulamanızın kaynak dosyaları önbelleğe alınmaz.

## Normal şekilde derleyin

```sh
mix compile
mix test
```

Bir bağımlılığın derlenmesi gerektiğinde, Tuist önce yerel önbelleği, ardından paylaşılan uzak önbelleği kontrol eder. Önbellekte bulunamayanlar normal şekilde derlenir ve sonuç gelecekteki yapılar için saklanır. Mix tarafından güncel kabul edilen seçili, desteklenen bağımlılıklar, derlenmiş çıktıları mevcut ve geçerli olduğunda yerel isabet olarak sayılır; önbellek aramasına gerek yoktur. Kimlik doğrulama veya önbellek kullanılamıyorsa, Mix yine de normal şekilde derler.

## Önbellek isabetlerinizi görün

İsabet oranlarını, aktarımları ve son yapıları görmek için projenizin panosundaki **Mix Önbelleği** bölümünü açın. Hangi görevlerin isabet ettiğini veya kaçırdığını görmek için bir yapının **Mix önbelleği** sekmesini seçin. **CAS Çıktıları**, gerçek uzak indirme ve yüklemeleri gösterir; yerel isabetler uzak aktarım kaydı oluşturmaz. Zaten güncel olan çıktıların yeniden kullanılması isabet oranına katkıda bulunur ancak aktarım baytı, geri yükleme gecikmesi veya tahmini zaman tasarrufu oluşturmaz.

Geri yüklemeyi denemek için, desteklenen bir bağımlılığın derlenmiş çıktısını temizleyin ve tekrar derleyin:

```sh
mix deps.clean nimble_options --build
mix compile
```

`nimble_options` yerine, projenizin kullandığı ve önbelleği zaten doldurmuş bir bağımlılığı yazın. Aynı Mix ortamını ve derleyici ayarlarını koruyun.

## Yalnızca gerektiğinde özelleştirin

Çoğu proje `cache: true` ayarını koruyabilir. İstisnalar için bir anahtar kelime listesi kullanın:

```elixir
tuist: [
  project: "your-account/your-project",
  cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
]
```

- **Ek derleme zamanı girdileri:** harici dosyaları `inputs: ["schemas"]` ile ve ortam değişkenlerini `env: ["COMPILER_OPTION"]` ile bildirin.
- **Yalnızca yerel:** `remote: false` olarak ayarlayın.
- **Uzak yükleme yok:** `upload: false` olarak ayarlayın. Sunucu izinleri erişimi yine de kontrol eder.
- **Önbellekleme devre dışı:** `cache: false` olarak ayarlayın.

> [!IMPORTANT]
> Derleme, rastgele Elixir kodunu yürütebilir. Ek girdileri bildirin ve zaman/ağ bağımlı kodu veya yan etkileri her yapıda çalışması gereken bağımlılıkları hariç tutun. Önbelleğe alınan artefaktlar gizli bilgileri içerebilir ve önbelleğe yazanlar güvenilir kod üreticileridir; güvenilmeyen işlere önbelleğe yazma kimlik bilgilerini vermeyin.

Bağımlılık seçimi, farklı checkout yolları arasında yeniden kullanım, sorun giderme ve uygulama ayrıntıları için <.localized_link href="/guides/features/cache/elixir-advanced">gelişmiş Elixir önbellek yapılandırması</.localized_link> sayfasına bakın.
