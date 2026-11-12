---
{
  "title": "Sürekli entegrasyon",
  "titleTemplate": ":title · Swift · Paket Kayıt Defterleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Registry'yi sürekli entegrasyonda nasıl kullanacağınızı öğrenin."
}
---
# Sürekli Entegrasyon (CI) {#continuous-integration-ci}

Kayıt defteri, ek kimlik doğrulama kurulumuna gerek kalmadan CI üzerinde kutudan çıkar çıkmaz çalışır. Varsayılan olarak, kimliği doğrulanmamış istekler IP adresi başına **dakikada 1.000 istek** ile hız sınırlamasına tabidir.

**Dakikada 20.000 istek** gibi daha yüksek bir hız sınırına ihtiyacınız varsa, `tuist registry login` komutunu çalıştırarak kimlik doğrulaması yapabilirsiniz. Bunun için `TUIST_TOKEN` ortam değişkeninin ayarlanmış olması gerekir. Bir hesap jetonu oluşturmak için <.localized_link href="/guides/server/authentication#account-tokens">kimlik doğrulama kılavuzunu</.localized_link> takip edebilirsiniz.

> [!NOTE]
> Aşağıdaki anahtar zinciri kurulumu yalnızca daha yüksek hız sınırları elde etmek için `tuist registry login` kullanıyorsanız gereklidir. Çoğu durumda, varsayılan kimliği doğrulanmamış hız sınırı yeterlidir ve bu adımı tamamen atlayabilirsiniz.
>
> Ayrıca, yeni bir önceden kilidi açılmış anahtar zinciri oluşturmak yalnızca paketlerin Xcode entegrasyonunu kullanırken gereklidir.


`tuist registry login` kimlik bilgilerini anahtar zincirinde depoladığından, CI ortamında anahtar zincirine erişilebildiğinden emin olmanız gerekir. Bazı CI sağlayıcılarının veya [Fastlane](https://fastlane.tools/) gibi otomasyon araçlarının zaten geçici bir anahtar zinciri oluşturduğunu veya bunu oluşturmak için yerleşik bir yol sunduğunu unutmayın. Ancak, aşağıdaki kodla özel bir adım oluşturarak da bir tane oluşturabilirsiniz:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

Varsayılan anahtar zincirinizin oluşturulduğundan ve `tuist registry login` komutunu çalıştırmadan _önce_ kilidinin açıldığından emin olun.

## Ortamlar arasında artımlı çözümleme {#incremental-resolution-across-environments}

Temiz/soğuk çözümlemeler kayıt defterimizle biraz daha hızlıdır ve çözülen bağımlılıkları CI derlemeleri arasında kalıcı hale getirirseniz çok daha büyük iyileştirmeler yaşayabilirsiniz. Kayıt defteri sayesinde, depolamanız ve geri yüklemeniz gereken dizinin boyutunun kayıt defteri olmadan duruma göre çok daha küçük olduğunu ve önemli ölçüde daha az zaman aldığını unutmayın. Varsayılan Xcode paket entegrasyonunu kullanırken bağımlılıkları önbelleğe almanın en iyi yolu, `xcodebuild` aracılığıyla bağımlılıkları çözerken özel bir `clonedSourcePackagesDirPath` belirtmektir. Bunu, `Tuist.swift` dosyanıza aşağıdakileri ekleyerek yapabilirsiniz:

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

Ayrıca, `Package.resolved` dosyasının yolunu bulmanız gerekecektir. Yolu almak için `ls **/Package.resolved` komutunu çalıştırabilirsiniz. Yol yaklaşık olarak `App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` şeklinde görünmelidir.

Swift paketleri ve XcodeProj tabanlı entegrasyon için, projenin kökünde veya `Tuist` dizininde bulunan varsayılan `.build` dizinini kullanabiliriz. Boru hattınızı kurarken yolun doğru olduğundan emin olun.

Varsayılan Xcode paket entegrasyonunu kullanırken bağımlılıkları çözmek ve önbelleğe almak için GitHub Actions örnek iş akışı aşağıdadır:
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
