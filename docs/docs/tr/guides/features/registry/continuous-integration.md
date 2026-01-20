---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# Sürekli Entegrasyon (CI) {#continuous-integration-ci}

CI'nızda kayıt defterini kullanmak için, iş akışınızın bir parçası olarak `tuist
registry login` adresini çalıştırarak kayıt defterinde oturum açtığınızdan emin
olmanız gerekir.

::: info ONLY XCODE INTEGRATION
<!-- -->
Önceden kilidi açılmış yeni bir anahtar zinciri oluşturmak yalnızca paketlerin
Xcode entegrasyonunu kullanıyorsanız gereklidir.
<!-- -->
:::

Kayıt kimlik bilgileri bir anahtar zincirinde saklandığından, anahtar zincirine
CI ortamında erişilebildiğinden emin olmanız gerekir.
Fastlane](https://fastlane.tools/) gibi bazı CI sağlayıcılarının veya otomasyon
araçlarının zaten geçici bir anahtar zinciri oluşturduğunu veya nasıl
oluşturulacağına dair yerleşik bir yol sağladığını unutmayın. Bununla birlikte,
aşağıdaki kodla özel bir adım oluşturarak da bir tane oluşturabilirsiniz:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist kayıt login` daha sonra kimlik bilgilerini varsayılan anahtar zincirinde
saklayacaktır. _ ` tuist kayıt login` çalıştırılmadan önce varsayılan anahtar
zincirinizin oluşturulduğundan ve _kilidinin açıldığından emin olun.

Ayrıca, `TUIST_TOKEN` ortam değişkeninin ayarlandığından emin olmanız gerekir.
Buradaki <LocalizedLink href="/guides/server/authentication#as-a-project"> belgeleri takip ederek bir tane oluşturabilirsiniz</LocalizedLink>.

GitHub Eylemleri için örnek bir iş akışı şu şekilde olabilir:
```yaml
name: Build

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Create keychain
        run: |
        TMP_DIRECTORY=$(mktemp -d)
        KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
        KEYCHAIN_PASSWORD=$(uuidgen)
        security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
        security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
        security default-keychain -s $KEYCHAIN_PATH
        security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
      - name: Log in to the Tuist Registry
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
        run: tuist registry login
      - # Your build steps
```

### Ortamlar arasında artan çözünürlük {#incremental-resolution-across-environments}

Temiz/soğuk çözümlemeler kayıt defterimizle biraz daha hızlıdır ve çözümlenen
bağımlılıkları CI derlemeleri boyunca sürdürürseniz daha da büyük iyileştirmeler
yaşayabilirsiniz. Kayıt sayesinde, saklamanız ve geri yüklemeniz gereken dizinin
boyutunun kayıt defteri olmadan olduğundan çok daha küçük olduğunu ve önemli
ölçüde daha az zaman aldığını unutmayın. Varsayılan Xcode paket entegrasyonunu
kullanırken bağımlılıkları önbelleğe almak için en iyi yol, `xcodebuild`
aracılığıyla bağımlılıkları çözümlerken özel bir `clonedSourcePackagesDirPath`
belirtmektir. Bu, `Config.swift` dosyanıza aşağıdakileri ekleyerek yapılabilir:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

Ayrıca, `Package.resolved` adresinin yolunu bulmanız gerekecektir. Yolu `ls
**/Package.resolved` komutunu çalıştırarak bulabilirsiniz. Yol
`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` gibi
görünmelidir.

Swift paketi ve XcodeProj tabanlı entegrasyon için, projenin kök dizininde veya
`Tuist` dizininde bulunan varsayılan `.build` dizinini kullanabiliriz. Boru
hattınızı kurarken yolun doğru olduğundan emin olun.

Varsayılan Xcode paket entegrasyonunu kullanırken bağımlılıkları çözümlemek ve
önbelleğe almak için GitHub Actions'a yönelik örnek bir iş akışı aşağıda
verilmiştir:
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
