---
{
  "title": "Önizlemeleri macOS uygulamasıyla çalıştır",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Cihazlarda ve simülatörlerde uyumlu Apple önizlemelerini çalıştırmak için Tuist macOS menü çubuğu uygulamasını kullanın."
}
---
# macOS uygulamasıyla ön izlemeleri çalıştırın

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Apple ön izlemeleri için, Tuist macOS menü çubuğu uygulaması CLI’ye bir alternatiftir; derleme Xcode, Bazel veya Once üzerinden gelmiş olabilir. Yayınlama iş akışının imzalama ve uygunluk gereksinimleri hâlâ geçerlidir.

## Kurulum {#install}

[Uygulamayı indirin](https://tuist.dev/download) veya `brew install --cask tuist/tuist/tuist` ile kurun.

## Derleme çalıştırma {#run-a-build}

Menü çubuğu uygulamasında uyumlu bir cihaz veya simülatör seçin, ardından ön izleme sayfasında **Çalıştır** düğmesine tıklayın.

macOS uygulaması önce uygulama başına en son uyumlu ön izlemeyi ister. Platform filtrelerini uygulamadan önce farklı uygulamaları seçen eski sunucularda, mevcut bir derlemeyi gizleyebilecek bir kesme sınırı koymadan sayfalı geçmişe geri döner.

Erişim ve düzenleme için <.localized_link href="/guides/features/previews#visibility">görünürlük ve track’ler</.localized_link> bölümüne bakın.
