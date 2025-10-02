---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# Antevisões {#previews}

> REQUISITOS [!IMPORTANTE]
> - Uma conta e um projeto
>   <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>

Ao criar uma aplicação, poderá querer partilhá-la com outras pessoas para obter
feedback. Tradicionalmente, isto é algo que as equipas fazem ao criar, assinar e
enviar as suas aplicações para plataformas como o
[TestFlight](https://developer.apple.com/testflight/) da Apple. No entanto, este
processo pode ser incómodo e lento, especialmente quando se pretende apenas
obter um feedback rápido de um colega ou amigo.

Para tornar este processo mais simples, o Tuist fornece uma forma de gerar e
partilhar pré-visualizações das suas aplicações com qualquer pessoa.

> [IMPORTANTE] AS CONSTRUÇÕES PARA DISPOSITIVOS PRECISAM DE SER ASSINADAS Ao
> construir para um dispositivo, é atualmente da sua responsabilidade garantir
> que a aplicação é assinada corretamente. Planeamos simplificar este processo
> no futuro.

:::grupo de códigos
```bash [Tuist Project]
tuist build App # Build the app for the simulator
tuist build App -- -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
:::

O comando irá gerar uma ligação que pode partilhar com qualquer pessoa para
executar a aplicação - num simulador ou num dispositivo real. Tudo o que
precisam de fazer é executar o comando abaixo:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

Ao partilhar um ficheiro `.ipa`, pode transferir a aplicação diretamente do
dispositivo móvel utilizando a ligação Pré-visualização. As ligações para `.ipa`
pré-visualizações são, por predefinição, _públicas_. No futuro, terá a opção de
os tornar privados, de modo a que o destinatário da ligação tenha de se
autenticar com a sua conta Tuist para descarregar a aplicação.

`tuist run` também lhe permite executar uma pré-visualização mais recente com
base num especificador como `latest`, nome do ramo ou um hash de confirmação
específico:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

> [IMPORTANTE] VISIBILIDADE DAS VISUALIZAÇÕES Apenas as pessoas com acesso à
> organização a que o projeto pertence podem aceder às visualizações. Estamos a
> planear adicionar suporte para ligações que expiram.

## Aplicação Tuist para macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Para tornar a execução das Visualizações prévias do Tuist ainda mais fácil,
desenvolvemos um aplicativo da barra de menu do Tuist para macOS. Em vez de
executar as Pré-visualizações através do Tuist CLI, pode
[descarregar](https://tuist.dev/download) a aplicação macOS. Também é possível
instalar o aplicativo executando `brew install --cask tuist/tuist/tuist`.

Quando clicar em "Executar" na página Pré-visualização, a aplicação macOS será
automaticamente iniciada no dispositivo atualmente selecionado.

> REQUISITOS [!IMPORTANTE]
> 
> É necessário ter o Xcode instalado localmente e estar no macOS 14 ou
> posterior.

## Aplicação Tuist para iOS {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

Tal como a aplicação macOS, as aplicações Tuist para iOS simplificam o acesso e
a execução das pré-visualizações.

## Comentários do pedido pull/merge {#pullmerge-request-comments}

> [!IMPORTANTE] É NECESSÁRIA A INTEGRAÇÃO COM A PLATAFORMA GIT Para obter
> comentários automáticos de pedidos de pull/merge, integre o seu projeto
> <LocalizedLink href="/guides/server/accounts-and-projects">remoto</LocalizedLink>
> com uma plataforma
> <LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>.

O teste de novas funcionalidades deve fazer parte de qualquer revisão de código.
Mas ter de construir uma aplicação localmente acrescenta fricção desnecessária,
levando muitas vezes os programadores a não testarem a funcionalidade no seu
dispositivo. Mas *e se cada pull request contivesse um link para a compilação
que executaria automaticamente a aplicação num dispositivo selecionado na
aplicação Tuist macOS?*

Quando o seu projeto Tuist estiver ligado à sua plataforma Git, tal como
[GitHub](https://github.com), adicione um
<LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink> ao seu
fluxo de trabalho CI. O Tuist publicará um link de visualização diretamente nos
seus pull requests: ![Comentário do aplicativo GitHub com um link de
visualização do Tuist](/images/guides/features/github-app-with-preview.png)

## Crachá README {#readme-badge}

Para tornar as Prévias do Tuist mais visíveis no seu repositório, você pode
adicionar um emblema ao seu arquivo `README` que aponta para a última Prévia do
Tuist:

[![Tuist
Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Para adicionar o emblema ao seu `README`, use a seguinte marcação e substitua os
identificadores de conta e projeto pelos seus próprios:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Se o seu projeto contiver várias aplicações com diferentes identificadores de
pacotes, pode especificar a que pré-visualização da aplicação deve ligar,
adicionando um parâmetro de consulta `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Automatizações {#automations}

Pode utilizar o sinalizador `--json` para obter uma saída JSON do comando `tuist
share`:
```
tuist share --json
```

A saída JSON é útil para criar automações personalizadas, como postar uma
mensagem do Slack usando seu provedor de CI. O JSON contém uma chave `url` com o
link de visualização completo e uma chave `qrCodeURL` com o URL para a imagem do
código QR para facilitar o download de visualizações de um dispositivo real.
Segue-se um exemplo de uma saída JSON:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
