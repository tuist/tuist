---
{
  "title": "Sürekli entegrasyon",
  "titleTemplate": ":title · Swift · Paket Kayıtları · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Registry'nin sürekli entegrasyonda nasıl kullanılacağını öğrenin."
}
---
# Sürekli Entegrasyon (CI) {#continuous-integration-ci}

Kayıt defteri, ek bir kimlik doğrulama kurulumu gerektirmeden CI ortamında hazır olarak çalışır. Varsayılan olarak, kimliği doğrulanmamış istekler IP adresi başına dakikada **1.000 istek** ile sınırlanır.

Dakikada **20.000 istek** gibi daha yüksek bir hız sınırı gerekiyorsa, `tuist registry login` komutunu çalıştırarak kimlik doğrulaması yapabilirsiniz. Bu işlem, `TUIST_TOKEN` ortam değişkeninin ayarlanmış olmasını gerektirir. Bir hesap jetonu oluşturmak için <.localized_link href="/guides/server/authentication#account-tokens">kimlik doğrulama kılavuzunu</.localized_link> takip edebilirsiniz.

> [!NOTE]
> Aşağıdaki anahtar zinciri kurulumu yalnızca daha yüksek hız sınırları elde etmek için `tuist registry login` kullanıyorsanız gereklidir. Çoğu durumda varsayılan kimliği doğrulanmamış hız sınırı yeterlidir ve bu adımı tamamen atlayabilirsiniz.
>
> Ek olarak, önceden kilidi açılmış yeni bir anahtar zinciri oluşturmak yalnızca paketlerin Xcode entegrasyonu kullanılırken gereklidir.


`tuist registry login` kimlik bilgilerini bir anahtar zincirinde sakladığından, anahtar zincirine CI ortamından erişilebildiğinden emin olmanız gerekir. Bazı CI sağlayıcılarının veya [Fastlane](https://fastlane.tools/) gibi otomasyon araçlarının zaten geçici bir anahtar zinciri oluşturduğunu veya bunun nasıl yapılacağına dair yerleşik bir yol sunduğunu unutmayın. Yine de aşağıdaki kodla özel bir adım oluşturarak kendiniz de bir anahtar zinciri oluşturabilirsiniz:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

Varsayılan anahtar zincirinizin _öncesinde_ oluşturulduğundan ve kilidinin açıldığından emin olun; ardından `tuist registry login` komutunu çalıştırın.

## Ortamlar arasında artımlı çözümleme {#incremental-resolution-across-environments}

Temiz/soğuk çözümlemeler kayıt defterimizle biraz daha hızlıdır ve çözülen bağımlılıkları CI derlemeleri arasında kalıcı hale getirirseniz çok daha büyük iyileştirmeler yaşayabilirsiniz. Kayıt defteri sayesinde, depolamanız ve geri yüklemeniz gereken dizinin boyutu kayıt defteri olmadan duruma kıyasla çok daha küçüktür ve bu da önemli ölçüde daha az zaman alır. Varsayılan Xcode paket entegrasyonunu kullanırken bağımlılıkları önbelleğe almanın en iyi yolu, bağımlılıkları `xcodebuild` aracılığıyla çözerken özel bir `clonedSourcePackagesDirPath` belirtmektir. Bunu `Tuist.swift` dosyanıza aşağıdakileri ekleyerek yapabilirsiniz:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
        )
    )
)
```

Ek olarak, `Package.resolved` dosyasının yolunu bulmanız gerekecektir. `ls **/Package.resolved` komutunu çalıştırarak yolu alabilirsiniz. Yol genellikle `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` gibi görünür.

Swift paketleri ve XcodeProj tabanlı entegrasyon için projenin kök dizininde veya `Tuist` dizininde bulunan varsayılan `.build` dizinini kullanabiliriz. Boru hattınızı kurarken yolun doğru olduğundan emin olun.

Varsayılan Xcode paket entegrasyonunu kullanırken bağımlılıkları çözmek ve önbelleğe almak için GitHub Actions üzerinde örnek bir iş akışı:
```yaml
- name: Restore cache
  id: cache-restore
  uses: actions/cache/restore@v4
  with:
    path: .build
    key: ${{ runner.os }}-${{ hashFiles('App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
- name: Resolve dependencies
  if: steps.cache-restore.outputs.cache-hit != 'true'
  run: xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath .build
- name: Save cache
  id: cache-save
  uses: actions/cache/save@v4
  with:
    path: .build
    key: ${{ steps.cache-restore.outputs.cache-primary-key }}
```
