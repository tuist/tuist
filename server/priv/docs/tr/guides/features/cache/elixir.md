---
title: Elixir önbelleği
titleTemplate: ":title · Önbellek · Kılavuzlar · Tuist"
description: Elixir projeniz için bağımlılık önbelleğini etkinleştirin ve Mix kullanmaya devam edin.
---

# Elixir önbelleği

Tuist, derlenmiş bağımlılıkları yerel olarak ve CI yapılarında yeniden kullanır. Bir kez etkinleştirin, ardından `mix compile` ve `mix test` komutlarını kullanmaya devam edin.

## Kurulum

Bir kez <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixir ile başlayın</.localized_link> kılavuzunu takip edin. Paylaşılan kurulum, yapı ve test içgörülerinin yanı sıra bağımlılık önbelleğini de etkinleştirir; ek bir önbellek kurulumuna gerek yoktur.

`cache: true`, desteklenen Hex ve Git bağımlılıklarını otomatik olarak seçer; bunları listelemenize gerek yoktur. Yerel/özel derleme ve yerel bağımlılıklar Mix üzerinden normal şekilde çalışmaya devam eder. Uygulamanızın kaynak dosyaları önbelleğe alınmaz.

## Normal şekilde derleyin

```sh
mix compile
mix test
```

Bir bağımlılığın derlenmesi gerektiğinde, Tuist önce yerel önbelleği, ardından paylaşılan uzak önbelleği kontrol eder. Önbellekte bulunmama durumunda derleme normal şekilde yapılır ve sonuç gelecekteki yapılar için saklanır. Mix’in güncel kabul ettiği seçili, desteklenen bağımlılıklar, derlenmiş çıktıları mevcut ve geçerli olduğunda yerel isabet olarak sayılır; önbellek aramasına gerek yoktur. Kimlik doğrulama veya önbellek kullanılamıyorsa, Mix yine de normal şekilde derler.

## Önbellek isabetlerinizi görün

İsabet oranlarını, aktarımları ve son yapıları görmek için projenizin panosundaki **Mix Önbelleği** bölümünü açın. Hangi görevlerin isabet ettiğini veya kaçırdığını görmek için bir yapının **Mix önbelleği** sekmesini seçin. **CAS Çıktıları**, gerçek uzak indirmeleri ve yüklemeleri gösterir; yerel isabetler uzak aktarım kaydı oluşturmaz. Zaten güncel olan çıktıların yeniden kullanılması isabet oranına katkıda bulunur ancak aktarım baytı, geri yükleme gecikmesi veya tahmini zaman tasarrufu oluşturmaz.

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

- **Ek derleme zamanı girdileri:** harici dosyaları `inputs: ["schemas"]` ile, ortam değişkenlerini ise `env: ["COMPILER_OPTION"]` ile bildirin.
- **Yalnızca yerel:** `remote: false` olarak ayarlayın.
- **Uzak yükleme yok:** `upload: false` olarak ayarlayın. Sunucu izinleri erişimi yine de kontrol eder.
- **Önbelleği devre dışı bırak:** `cache: false` olarak ayarlayın.

> [!IMPORTANT]
> Derleme, rastgele Elixir kodu çalıştırabilir. Ek girdileri bildirin ve her yapıda çalışması gereken zamana/ağa bağlı kodu veya yan etkileri olan bağımlılıkları hariç tutun. Önbelleğe alınmış yapıtlar gizli bilgileri içerebilir ve önbellek yazarları güvenilir kod üreticileridir: güvenilmeyen işlere önbellek yazma kimlik bilgilerini vermeyin.

Bağımlılık seçimi, farklı checkout yollarında yeniden kullanım, sorun giderme ve uygulama ayrıntıları için <.localized_link href="/guides/features/cache/elixir-advanced">gelişmiş Elixir önbellek yapılandırması</.localized_link> kılavuzuna bakın.
