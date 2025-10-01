---
{
  "title": "From v3 to v4",
  "titleTemplate": ":title · Migrations · References · Tuist",
  "description": "This page documents how to migrate the Tuist CLI from the version 3 to version 4."
}
---
# De Tuist v3 para v4 {#from-tuist-v3-to-v4}

Com o lançamento do [Tuist
4](https://github.com/tuist/tuist/releases/tag/4.0.0), aproveitamos a
oportunidade para introduzir algumas mudanças significativas no projeto, que
acreditamos que tornariam o projeto mais fácil de usar e manter a longo prazo.
Este documento descreve as mudanças que você precisará fazer no seu projeto para
atualizar do Tuist 3 para o Tuist 4.

### Gestão de versões abandonada através de `tuistenv` {#dropped-version-management-through-tuistenv}

Antes do Tuist 4, o script de instalação instalava uma ferramenta, `tuistenv`,
que seria renomeada para `tuist` no momento da instalação. A ferramenta cuidaria
da instalação e ativação das versões do Tuist, garantindo o determinismo entre
ambientes. Com o objetivo de reduzir a superfície de recursos do Tuist,
decidimos abandonar `tuistenv` em favor de [Mise](https://mise.jdx.dev/), uma
ferramenta que faz o mesmo trabalho, mas é mais flexível e pode ser usada em
diferentes ferramentas. Se estava a usar `tuistenv`, terá de desinstalar a
versão atual do Tuist executando `curl -Ls https://uninstall.tuist.io | bash` e
depois instalá-lo usando o método de instalação da sua escolha. Nós recomendamos
fortemente o uso do Mise porque ele é capaz de instalar e ativar versões de
forma determinística em todos os ambientes.

::: grupo de códigos

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
:::

> [!IMPORTANTE] MISE EM AMBIENTES CI E PROJETOS XCODE Se você decidir abraçar o
> determinismo que o Mise traz em toda a linha, nós recomendamos verificar a
> documentação de como usar o Mise em [ambientes
> CI](https://mise.jdx.dev/continuous-integration.html) e [projetos
> Xcode](https://mise.jdx.dev/ide-integration.html#xcode).

> [Note que ainda é possível instalar o Tuist usando o Homebrew, que é um
> gerenciador de pacotes popular para macOS. Pode encontrar as instruções sobre
> como instalar o Tuist utilizando o Homebrew no
> <LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">guia
> de instalação</LocalizedLink>.

### Eliminado `init` constructors from `ProjectDescription` models {#dropped-init-constructors-from-projectdescription-models}

Com o objetivo de melhorar a legibilidade e a expressividade das APIs, decidimos
remover os construtores `init` de todos os modelos `ProjectDescription`. Cada
modelo agora fornece um construtor estático que pode ser usado para criar
instâncias dos modelos. Se estava a utilizar os construtores `init`, terá de
atualizar o seu projeto para utilizar os construtores estáticos.

> [CONVENÇÃO DE NOMEAÇÃO A convenção de nomeação que seguimos é usar o nome do
> modelo como o nome do construtor estático. Por exemplo, o construtor estático
> para o modelo `Target` é `Target.target`.

### Renomeado `--no-cache` para `--no-binary-cache` {#renamed-nocache-to-nobinarycache}

Como a flag `--no-cache` era ambígua, decidimos renomeá-la para
`--no-binary-cache` para deixar claro que ela se refere ao cache binário. Se
estava a utilizar a flag `--no-cache`, terá de atualizar o seu projeto para
utilizar a flag `--no-binary-cache`.

### Renomeado `tuist fetch` para `tuist install` {#renamed-tuist-fetch-to-tuist-install}

Renomeámos o comando `tuist fetch` para `tuist install` para nos alinharmos com
a convenção do sector. Se estava a utilizar o comando `tuist fetch`, terá de
atualizar o seu projeto para utilizar o comando `tuist install`.

### [Adotar `Package.swift` como a DSL para dependências](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Antes do Tuist 4, era possível definir dependências em um arquivo
`Dependencies.swift`. Este formato proprietário quebrou o suporte em ferramentas
como [Dependabot](https://github.com/dependabot) ou
[Renovatebot](https://github.com/renovatebot/renovate) para atualizar
automaticamente as dependências. Além disso, introduzia indirecções
desnecessárias para os utilizadores. Portanto, decidimos adotar `Package.swift`
como a única forma de definir dependências no Tuist. Se estava a utilizar o
ficheiro `Dependencies.swift`, terá de mover o conteúdo do seu
`Tuist/Dependencies.swift` para um `Package.swift` na raiz e utilizar a diretiva
`#if TUIST` para configurar a integração. Você pode ler mais sobre como integrar
as dependências do Pacote Swift
<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">aqui</LocalizedLink>

### Renomeado `tuist cache warm` para `tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

Por uma questão de brevidade, decidimos renomear o comando `tuist cache warm`
para `tuist cache`. Se estava a utilizar o comando `tuist cache warm`, terá de
atualizar o seu projeto para utilizar o comando `tuist cache`.


### Renomeado `tuist cache print-hashes` para `tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

Decidimos renomear o comando `tuist cache print-hashes` para `tuist cache
--print-hashes` para tornar claro que é uma bandeira do comando `tuist cache`.
Se estava a utilizar o comando `tuist cache print-hashes`, terá de atualizar o
seu projeto para utilizar a bandeira `tuist cache --print-hashes`.

### Perfis de cache removidos {#removed-caching-profiles}

Antes do Tuist 4, era possível definir perfis de cache em `Tuist/Config.swift`
que continha uma configuração para o cache. Decidimos remover esse recurso
porque ele poderia levar a confusão ao usá-lo no processo de geração com um
perfil diferente daquele que foi usado para gerar o projeto. Além disso, poderia
levar a que os utilizadores utilizassem um perfil de depuração para criar uma
versão de lançamento da aplicação, o que poderia levar a resultados inesperados.
Em seu lugar, introduzimos a opção `--configuration`, que pode ser usada para
especificar a configuração que deseja usar ao gerar o projeto. Se estava a
utilizar perfis de cache, terá de atualizar o seu projeto para utilizar a opção
`--configuration`.

### Removido `--skip-cache` a favor dos argumentos {#removed-skipcache-in-favor-of-arguments}

Nós removemos a flag `--skip-cache` do comando `generate` em favor de controlar
para quais alvos o cache binário deve ser ignorado usando os argumentos. Se
estava a utilizar a flag `--skip-cache`, terá de atualizar o seu projeto para
utilizar os argumentos.

::: grupo de códigos

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
:::

### [Capacidades de assinatura eliminadas](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

A assinatura já é resolvida por ferramentas da comunidade como
[Fastlane](https://fastlane.tools/) e o próprio Xcode, que fazem um trabalho
muito melhor nisso. Nós sentimos que a assinatura era um objetivo extenso para o
Tuist, e que era melhor focar nos recursos principais do projeto. Se você estava
usando os recursos de assinatura do Tuist, que consistia em criptografar os
certificados e perfis no repositório e instalá-los nos lugares certos no momento
da geração, você pode querer replicar essa lógica em seus próprios scripts que
são executados antes da geração do projeto. Em particular:
  - Um script que desencripta os certificados e perfis utilizando uma chave
    armazenada no sistema de ficheiros ou numa variável de ambiente e instala os
    certificados no chaveiro e os perfis de aprovisionamento no diretório
    `~/Library/MobileDevice/Provisioning\ Profiles`.
  - Um script que pode pegar em perfis e certificados existentes e encriptá-los.

> [REQUISITOS DE ASSINATURA A assinatura requer que os certificados corretos
> estejam presentes no chaveiro e que os perfis de aprovisionamento estejam
> presentes no diretório `~/Library/MobileDevice/Provisioning\ Profiles`. Pode
> utilizar a ferramenta de linha de comandos `security` para instalar
> certificados no chaveiro e o comando `cp` para copiar os perfis de
> aprovisionamento para o diretório correto.

### Integração de Cartago abandonada através de `Dependencies.swift` {#dropped-carthage-integration-via-dependenciesswift}

Antes do Tuist 4, as dependências do Carthage podiam ser definidas em um arquivo
`Dependencies.swift`, que os usuários podiam buscar executando `tuist fetch`.
Nós também sentimos que este era um objetivo maior para o Tuist, especialmente
considerando um futuro onde o Swift Package Manager seria a maneira preferida de
gerenciar dependências. Se você estava usando as dependências do Carthage, você
terá que usar `Carthage` diretamente para puxar os frameworks pré-compilados e
XCFrameworks para o diretório padrão do Carthage, e então referenciar esses
binários dos seus tagets usando os casos `TargetDependency.xcframework` e
`TargetDependency.framework`.

> [NOTA] O CARTHAGE AINDA É SUPORTADO Alguns utilizadores entenderam que
> deixámos de suportar o Carthage. Nós não o fizemos. O contrato entre o Tuist e
> a saída do Carthage é para frameworks armazenados no sistema e XCFrameworks. A
> única coisa que mudou é quem é responsável por buscar as dependências. Antes
> era o Tuist através do Carthage, agora é o Carthage.

### Eliminou o `TargetDependency.packagePlugin` API {#dropped-the-targetdependencypackageplugin-api}

Antes do Tuist 4, era possível definir uma dependência de plugin de pacote
usando o caso `TargetDependency.packagePlugin`. Depois de ver o Swift Package
Manager introduzindo novos tipos de pacotes, decidimos iterar na API para algo
que seria mais flexível e preparado para o futuro. Se você estava usando
`TargetDependency.packagePlugin`, você terá que usar `TargetDependency.package`
em vez disso, e passar o tipo de pacote que você quer usar como um argumento.

### [APIs obsoletas abandonadas](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Removemos as APIs que estavam marcadas como obsoletas no Tuist 3. Se estava a
utilizar alguma das APIs obsoletas, terá de atualizar o seu projeto para
utilizar as novas APIs.
