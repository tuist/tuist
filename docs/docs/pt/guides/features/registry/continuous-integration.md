---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# Integração contínua (CI) {#continuous-integration-ci}

Para utilizar o registo no seu IC, tem de garantir que iniciou sessão no
registo, executando `tuist registry login` como parte do seu fluxo de trabalho.

> [NOTA] APENAS INTEGRAÇÃO XCODE A criação de um novo chaveiro pré-desbloqueado
> só é necessária se estiver a utilizar a integração de pacotes Xcode.

Uma vez que as credenciais do registo são armazenadas num chaveiro, é necessário
garantir que o chaveiro pode ser acedido no ambiente de CI. Observe que alguns
provedores de CI ou ferramentas de automação como
[Fastlane](https://fastlane.tools/) já criam um chaveiro temporário ou fornecem
uma maneira integrada de criar um. No entanto, você também pode criar um criando
uma etapa personalizada com o seguinte código:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist registry login` irá armazenar as credenciais no conjunto de chaves
predefinido. Certifique-se de que o conjunto de chaves predefinido é criado e
desbloqueado _antes de executar_ `tuist registry login`.

Além disso, é necessário garantir que a variável de ambiente
`TUIST_CONFIG_TOKEN` está definida. Pode criar uma seguindo a documentação
<LocalizedLink href="/guides/features/automate/continuous-integration#authentication">aqui</LocalizedLink>.

Um exemplo de fluxo de trabalho para GitHub Actions poderia então ter o seguinte
aspeto:
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
          TUIST_CONFIG_TOKEN: ${{ secrets.TUIST_CONFIG_TOKEN }}
        run: tuist registry login
      - # Your build steps
```

### Resolução incremental entre ambientes {#resolução incremental-entre-ambientes}

As resoluções limpas/frias são ligeiramente mais rápidas com o nosso registo, e
pode experimentar melhorias ainda maiores se persistir as dependências
resolvidas através de compilações CI. Observe que, graças ao registro, o tamanho
do diretório que você precisa armazenar e restaurar é muito menor do que sem o
registro, levando muito menos tempo. Para armazenar dependências em cache ao
usar a integração de pacotes padrão do Xcode, a melhor maneira é especificar um
diretório personalizado `clonedSourcePackagesDirPath` ao resolver dependências
via `xcodebuild`. Isso pode ser feito adicionando o seguinte ao seu arquivo
`Config.swift`:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

Além disso, terá de encontrar um caminho do `Package.resolved`. Pode obter o
caminho executando `ls **/Package.resolved`. O caminho deve ser semelhante a
`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Para pacotes Swift e a integração baseada no XcodeProj, podemos usar o diretório
padrão `.build` localizado na raiz do projeto ou no diretório `Tuist`.
Certifique-se de que o caminho esteja correto ao configurar o pipeline.

Aqui está um exemplo de fluxo de trabalho para GitHub Actions para resolver e
armazenar em cache dependências ao usar a integração de pacote padrão do Xcode:
```yaml
- name: Restore cache
  id: cache-restore
  uses: actions/cache/restore@v4
  with:
    path: .build
    key: ${{ runner.os }}-${{ hashFiles('App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
    restore-keys: .build
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
