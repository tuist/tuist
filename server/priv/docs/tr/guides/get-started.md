---
{
  "title": "Başlayın",
  "titleTemplate": ":title · Kılavuzlar · Tuist",
  "description": "Uygulamanızın bugün nasıl oluşturulduğuna uygun Tuist yolunu seçin: Xcode, oluşturulmuş Xcode projeleri, Gradle, Elixir, Rust, Bazel veya Once."
}
---
# Başlayın {#get-started}

Uygulamanızın bugün nasıl oluşturulduğuna uygun yolu seçin. Her biri, nelerin kurulacağını, önbellekleme, analizler ve test özelliklerinin nasıl etkinleştirileceğini ve kurulumun uçtan uca nasıl doğrulanacağını adım adım açıklar. Bunları bağımsız olarak benimseyebilir veya birden fazla platformda yazılım yayınlıyorsanız birleştirebilirsiniz.

Çoğu yol <.localized_link href="/guides/install-tuist">Tuist komut satırı arayüzünü</.localized_link> kullanır. Elixir Hex paketini kullanır ve Once yerel Tuist sağlayıcısı üzerinden bağlanır; ikisi de entegrasyon için Tuist CLI gerektirmez.

## Xcode projesi {#existing-xcode-project}

Mevcut Xcode projenizi veya çalışma alanınızı koruyun ve Tuist özelliklerini tek tek ekleyin. Proje oluşturma gerekmez.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## Oluşturulan Xcode projesi {#generated-xcode-project}

Tuist’in Swift manifest dosyalarından Xcode projenizi tanımlamasına ve oluşturmasına olanak tanıyın. Oluşturulan projeler, modüler Xcode projelerinin karmaşıklığını grafın öz ve bildirimsel bir tanımında sıkıştırır ve <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ile <.localized_link href="/guides/features/selective-testing/generated-xcode-project">seçici test</.localized_link> için zorunludur.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Gradle projesi {#gradle-project}

Bir Gradle projesini Tuist’in uzak önbelleğine, derleme analizlerine ve test analizlerine `dev.tuist` Gradle eklentisi aracılığıyla bağlayın.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Elixir projesi {#elixir-project}

Bir Elixir projesini Tuist’in derleme analizlerine, test analizlerine, kararsız test algılamasına ve test parçalama özelliğine `tuist_ex` Hex paketi aracılığıyla bağlayın.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Rust projesi {#rust-project}

Derlemeleri ve doctestler dahil olmak üzere bireysel test sonuçlarını bildirmek ve kararsız testleri incelemek için Cargo’yu Tuist CLI üzerinden çalıştırın.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Bazel projesi {#bazel-project}

Önbellek isabetlerini ve analizleri ekibiniz ve CI arasında paylaşmak için bir Bazel çalışma alanını Tuist’in Uzak Yürütme API önbelleğine ve Derleme Olayı Servisine yönlendirin.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Once projesi {#once-project}

Once’in önbellenebilir betiklerini ve derleme graflarını Tuist’e bağlayarak paylaşımlı önbellekleme, canlı derleme ve test analizleri, barındırılan test parçalama ve uygulama önizlemelerinden yararlanın.

<.localized_link href="/guides/get-started/once-project">Start with a Once project →</.localized_link>
