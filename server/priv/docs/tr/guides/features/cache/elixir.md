---
title: Elixir önbelleği
titleTemplate: ":title · Önbellek · Kılavuzlar · Tuist"
description: Elixir projeniz için bağımlılık önbelleğini etkinleştirin ve Mix kullanmaya devam edin.
---

# Elixir önbelleği

Tuist, derlenmiş bağımlılıkları yerel olarak ve CI derlemeleri arasında yeniden kullanır. Bir kez etkinleştirin, ardından `mix compile` ve `mix test` komutlarını kullanmaya devam edin.

## Kurulum

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixir ile başlangıç</.localized_link> kılavuzunu bir kez takip edin. Paylaşılan kurulum, derleme ve test içgörülerinin yanı sıra bağımlılık önbelleğe almayı etkinleştirir; ek bir önbellek kurulumuna gerek yoktur.

`cache: true`, desteklenen Hex ve Git bağımlılıklarını otomatik olarak seçer; bunları listelemenize gerek yoktur. Yerel/özel derleme ve yerel bağımlılıklar Mix üzerinden normal şekilde devam eder. Uygulamanızın kaynak dosyaları önbelleğe alınmaz.

## Normal şekilde derleyin

```sh
mix compile
mix test
```

Bir bağımlılığın derlenmesi gerektiğinde, Tuist önce yerel önbelleği, ardından paylaşılan uzak önbelleği kontrol eder. Önbellekte bulunmaması durumunda normal derleme yapılır ve sonuç gelecekteki derlemeler için saklanır. Mix tarafından güncel kabul edilen seçili, desteklenen bağımlılıklar, derlenmiş çıktıları mevcut ve geçerli olduğunda yerel isabet olarak sayılır; önbellek aramasına gerek yoktur. Kimlik doğrulama veya önbellek kullanılamıyorsa, Mix yine de normal şekilde derleme yapar.

## Önbellek isabetlerinizi görüntüleyin

İsabet oranları, aktarımlar ve son derlemeler için projenizin panosundaki **Mix Önbelleği** bölümünü açın. Hangi görevlerin isabet ettiğini veya ıskaladığını görmek için bir derlemenin **Mix önbelleği** sekmesini seçin. **CAS Çıktıları**, gerçek uzak indirme ve yüklemeleri gösterir; yerel isabetler uzak aktarım kaydı oluşturmaz. Zaten güncel olan çıktıların yeniden kullanılması isabet oranına katkıda bulunur ancak aktarım baytı, geri yükleme gecikmesi veya tahmini kazanılan süre oluşturmaz.

Geri yüklemeyi denemek için, desteklenen bir bağımlılığın derlenmiş çıktısını temizleyin ve tekrar derleyin:

```sh
mix deps.clean nimble_options --build
mix compile
```

`nimble_options` yerine, projenizin kullandığı ve önbelleği zaten doldurmuş olan bir bağımlılığı yazın. Aynı Mix ortamını ve derleyici ayarlarını koruyun.

## Yalnızca gerektiğinde özelleştirin

Çoğu proje `cache: true` ayarını koruyabilir. İstisnalar için bir anahtar kelime listesi kullanın:

```elixir
tuist: [
  project: "your-account/your-project",
  cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
]
```

- **Ek derleme zamanı girdileri:** harici dosyaları `inputs: ["schemas"]` ile, ortam değişkenlerini `env: ["COMPILER_OPTION"]` ile bildirin.
- **Yalnızca yerel:** `remote: false` olarak ayarlayın.
- **Uzak yükleme yok:** `upload: false` olarak ayarlayın. Sunucu izinleri erişimi yine de kontrol eder.
- **Önbelleğe almayı devre dışı bırak:** `cache: false` olarak ayarlayın.

> [!IMPORTANT]
> Derleme, rastgele Elixir kodu çalıştırabilir. Ek girdileri bildirin ve zaman/ağ bağımlı kodu veya yan etkileri her derlemede çalışması gereken bağımlılıkları hariç tutun. Önbelleğe alınan yapıtlar gizli bilgileri içerebilir ve önbelleğe yazanlar güvenilir kod üreticileridir; güvenilmeyen işlere önbelleğe yazma kimlik bilgilerini vermeyin.

Bağımlılık seçimi, farklı checkout yolları arasında yeniden kullanım, sorun giderme ve uygulama ayrıntıları için <.localized_link href="/guides/features/cache/elixir-advanced">gelişmiş Elixir önbellek yapılandırması</.localized_link> kılavuzuna bakın.
