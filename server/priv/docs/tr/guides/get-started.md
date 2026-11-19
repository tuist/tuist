---
{
  "title": "Başlangıç",
  "titleTemplate": ":title · Kılavuzlar · Tuist",
  "description": "Uygulamanızın bugün nasıl oluşturulduğuna en uygun Tuist yolunu seçin: Xcode, oluşturulan Xcode projeleri, Gradle, Elixir, Rust, Bazel veya Struo."
}
---
# Başlarken {#get-started}

Uygulamanızın bugün nasıl oluşturulduğuna uygun yolu seçin. Her biri, nelerin kurulacağını, önbellekleme, içgörüler ve test özelliklerinin nasıl etkinleştirileceğini ve kurulumun uçtan uca nasıl doğrulanacağını adım adım açıklar. Bunları bağımsız olarak benimseyebilir veya birden fazla platformda yazılım yayınlıyorsanız birleştirebilirsiniz.

Çoğu yol <.localized_link href="/guides/install-tuist">Tuist komut satırı arayüzünü</.localized_link> kullanır. Elixir Hex paketini kullanır ve Struo yerel Tuist sağlayıcısı üzerinden bağlanır; hiçbiri entegrasyonu için Tuist CLI gerektirmez.

## Xcode projesi {#existing-xcode-project}

Mevcut Xcode projenizi veya çalışma alanınızı koruyun ve Tuist özelliklerini tek tek ekleyin. Proje oluşturma gerekmez.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## Oluşturulan Xcode projesi {#generated-xcode-project}

Tuist’in Swift bildirimlerinden Xcode projenizi tanımlamasına ve oluşturmasına izin verin. Oluşturulan projeler, modüler Xcode projelerinin karmaşıklığını grafın öz ve bildirimsel bir tanımında yoğunlaştırır ve <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ile <.localized_link href="/guides/features/selective-testing/generated-xcode-project">seçici test</.localized_link> için kesin bir gerekliliktir.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle projesi {#gradle-project}

Bir Gradle projesini Tuist’in uzak önbelleğine, derleme içgörülerine ve test içgörülerine `dev.tuist` Gradle eklentisi aracılığıyla bağlayın.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir projesi {#elixir-project}

Bir Elixir projesini Tuist’in derleme içgörülerine, test içgörülerine, kararsız test algılamasına ve test parçalama özelliğine `tuist_ex` Hex paketi aracılığıyla bağlayın.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust projesi {#rust-project}

Derlemeleri ve doctestler dahil bireysel test sonuçlarını raporlamak ve kararsız testleri incelemek için Cargo’yu Tuist CLI üzerinden çalıştırın.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel projesi {#bazel-project}

Bir Bazel çalışma alanını Tuist’in Uzak Yürütme API önbelleğine ve Derleme Olay Hizmetine yönlendirerek ekip ve CI arasında önbellek isabetlerini ve içgörüler paylaşın.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Struo projesi {#struo-project}

<a id="once-project"></a>

Struo’nun önbellenebilir betiklerini ve derleme graflarını paylaşımlı önbellekleme, canlı derleme ve test içgörileri, barındırılan test parçalama ve uygulama önizlemeleri için Tuist’e bağlayın.

<.localized_link href="/guides/get-started/struo-project">Start with a Struo project →</.localized_link>
