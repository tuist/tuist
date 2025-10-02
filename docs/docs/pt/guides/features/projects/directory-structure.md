---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# Estrutura do diretório {#diretory-structure}

Embora os projetos do Tuist sejam comumente usados para substituir os projetos
do Xcode, eles não estão limitados a esse caso de uso. Os projetos do Tuist
também são usados para gerar outros tipos de projetos, como pacotes SPM,
modelos, plug-ins e tarefas. Este documento descreve a estrutura dos projetos
Tuist e como organizá-los. Em secções posteriores, abordaremos como definir
modelos, plug-ins e tarefas.

## Projectos Tuist standard {#standard-tuist-projects}

Os projetos Tuist são **o tipo mais comum de projeto gerado pelo Tuist.** Eles
são usados para criar aplicativos, estruturas e bibliotecas, entre outros. Ao
contrário dos projetos do Xcode, os projetos do Tuist são definidos em Swift, o
que os torna mais flexíveis e fáceis de manter. Os projetos do Tuist também são
mais declarativos, o que os torna mais fáceis de entender e raciocinar. A
estrutura a seguir mostra um projeto Tuist típico que gera um projeto Xcode:

```bash
Tuist.swift
Tuist/
  Package.swift
  ProjectDescriptionHelpers/
Projects/
  App/
    Project.swift
  Feature/
    Project.swift
Workspace.swift
```

- **Diretório Tuist:** Esta diretoria tem dois objectivos. Primeiro, ele
  sinaliza para **onde a raiz do projeto é**. Isto permite construir caminhos
  relativos à raiz do projeto, e também executar comandos Tuist a partir de
  qualquer diretório dentro do projeto. Em segundo lugar, é o contentor para os
  seguintes ficheiros:
  - **ProjectDescriptionHelpers:** Este diretório contém código Swift que é
    partilhado por todos os ficheiros de manifesto. Os ficheiros de manifesto
    podem `importar ProjectDescriptionHelpers` para utilizar o código definido
    neste diretório. A partilha de código é útil para evitar duplicações e
    garantir a consistência entre os projectos.
  - **Package.swift:** Este arquivo contém as dependências do Swift Package para
    que o Tuist as integre usando projetos e destinos do Xcode (como
    [CocoaPods](https://cococapods)) que são configuráveis e otimizáveis. Saiba
    mais
    <LocalizedLink href="/guides/features/projects/dependencies">aqui</LocalizedLink>.

- **Diretório raiz**: O diretório de raiz do seu projeto que também contém o
  diretório `Tuist`.
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>
    Este ficheiro contém a configuração do Tuist que é partilhada por todos os
    projectos, espaços de trabalho e ambientes. Por exemplo, pode ser utilizado
    para desativar a geração automática de esquemas ou para definir o destino de
    implementação dos projectos.
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>
    Este manifesto representa um espaço de trabalho do Xcode. É utilizado para
    agrupar outros projectos e pode também adicionar ficheiros e esquemas
    adicionais.
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink>
    Este manifesto representa um projeto do Xcode. Ele é usado para definir os
    alvos que fazem parte do projeto e suas dependências.

Ao interagir com o projeto acima, os comandos esperam encontrar um arquivo
`Workspace.swift` ou um `Project.swift` no diretório de trabalho ou no diretório
indicado pelo sinalizador `--path`. O manifesto deve estar em um diretório ou
subdiretório de um diretório contendo um diretório `Tuist`, que representa a
raiz do projeto.

> [DICA] Os espaços de trabalho do Xcode permitiam dividir projetos em múltiplos
> projetos do Xcode para reduzir a probabilidade de conflitos de mesclagem. Se
> era para isso que você estava usando os espaços de trabalho, você não precisa
> deles no Tuist. O Tuist gera automaticamente um espaço de trabalho contendo um
> projeto e os projetos de suas dependências.

## Pacote Swift <Badge type="warning" text="beta" /> (*) O pacote Swift é um pacote de proteção de texto.

O Tuist também suporta projectos de pacotes SPM. Se estiver a trabalhar num
pacote SPM, não deverá precisar de atualizar nada. O Tuist pega automaticamente
na sua raiz `Package.swift` e todos os recursos do Tuist funcionam como se fosse
um manifesto `Project.swift`.

Para começar, execute `tuist install` e `tuist generate` no seu pacote SPM. Seu
projeto deve agora ter todos os mesmos esquemas e arquivos que você veria na
integração SPM do Xcode. No entanto, agora também pode executar
<LocalizedLink href="/guides/features/cache">`tuist cache`</LocalizedLink> e ter
a maioria das suas dependências e módulos SPM pré-compilados, tornando as
compilações subsequentes extremamente rápidas.
