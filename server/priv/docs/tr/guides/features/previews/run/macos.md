---
{
  "title": "Önizlemeleri macOS uygulamasıyla çalıştır",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Cihazlarda ve simülatörlerde uyumlu Apple önizlemelerini çalıştırmak için Tuist macOS menü çubuğu uygulamasını kullanın."
}
---
# macOS uygulamasıyla önizlemeleri çalıştırın

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Apple önizlemeleri için, Tuist macOS menü çubuğu uygulaması CLI'ye bir alternatiftir; derleme Xcode, Bazel veya Once'dan gelmiş olabilir. Yayınlama iş akışının imzalama ve uygunluk gereksinimleri yine de geçerlidir.

## Yükleme {#install}

[Uygulamayı indirin](https://tuist.dev/download) veya `brew install --cask tuist/tuist/tuist` ile yükleyin.

## Derleme çalıştırma {#run-a-build}

Menü çubuğu uygulamasında uyumlu bir cihaz veya simülatör seçin, ardından önizleme sayfasında **Çalıştır** düğmesine tıklayın.

macOS uygulaması öncelikle uygulama başına en son uyumlu önizlemeyi ister. Platform filtrelerini uygulamadan önce farklı uygulamaları seçen eski sunucularda, mevcut bir derlemeyi gizleyebilecek bir kesim uygulamaksızın sayfalandırılmış geçmişe geri döner.

Erişim ve düzenleme için bkz. <.localized_link href="/guides/features/previews#visibility">görünürlük ve izler</.localized_link>.
