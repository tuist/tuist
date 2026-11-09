---
{
  "title": "Başlarken",
  "titleTemplate": ":title · Başlarken · Kılavuzlar · Tuist",
  "description": "Uygulamanızın bugün nasıl oluşturulduğuna uygun Tuist yolunu seçin: Xcode, üretilen Xcode projeleri, Gradle, Elixir, Rust, Bazel veya Once."
}
---
# Başlarken {#get-started}

Uygulamanızın bugün nasıl oluşturulduğuna uygun yolu seçin. Her biri, nelerin kurulacağını, önbellekleme, analizler ve test özelliklerinin nasıl etkinleştirileceğini ve kurulumun uçtan uca nasıl doğrulanacağını adım adım açıklar. Bunları bağımsız olarak benimseyebilir veya birden fazla platformda yazılım yayınlıyorsanız birleştirebilirsiniz.

Çoğu yol <.localized_link href="/guides/install-tuist">Tuist komut satırı arayüzünü</.localized_link> kullanır. Elixir, Hex paketini kullanır; Once ise yerel Tuist sağlayıcısı üzerinden bağlanır; ikisi de entegrasyon için Tuist CLI gerektirmez.

## Xcode projesi {#existing-xcode-project}

Mevcut Xcode projenizi veya çalışma alanınızı koruyun ve Tuist yeteneklerini tek tek ekleyin. Proje oluşturma gerekmez.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## Oluşturulan Xcode projesi {#generated-xcode-project}

Tuist’in Swift manifest dosyalarından Xcode projenizi tanımlayıp oluşturmasına olanak verin. Oluşturulan projeler, modüler Xcode projelerinin karmaşıklığını grafın öz ve bildirimsel bir tanımında yoğunlaştırır ve <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ile <.localized_link href="/guides/features/selective-testing/generated-xcode-project">seçici test</.localized_link> için zorunludur.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle projesi {#gradle-project}

Bir Gradle projesini, `dev.tuist` Gradle eklentisi aracılığıyla Tuist’in uzak önbelleğine, derleme analizlerine ve test analizlerine bağlayın.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir projesi {#elixir-project}

Bir Elixir projesini, `tuist_ex` Hex paketi aracılığıyla Tuist’in derleme analizlerine, test analizlerine, kararsız test algılamasına ve test parçalama özelliğine bağlayın.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust projesi {#rust-project}

Derlemeleri ve doctestler dahil bireysel test sonuçlarını bildirmek ve kararsız testleri incelemek için Cargo’yu Tuist CLI üzerinden çalıştırın.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel projesi {#bazel-project}

Bir Bazel çalışma alanını Tuist’in Uzak Yürütme API önbelleğine ve Derleme Olay Hizmeti’ne yönlendirerek ekip ve CI genelinde önbellek isabetlerini ve analizleri paylaşın.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Once projesi {#once-project}

Once’in önbellenebilir betiklerini ve derleme graflarını, paylaşılan önbellekleme, canlı derleme ve test analizleri, barındırılan test parçalama ve uygulama önizlemeleri için Tuist’e bağlayın.

<.localized_link href="/guides/get-started/once-project">Start with a Once project →</.localized_link>
