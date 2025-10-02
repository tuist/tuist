---
{
  "title": "Get started",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Get started contributing to Tuist by following this guide."
}
---
# Começar {#get-started}

Se tem experiência na criação de aplicações para plataformas Apple, como o iOS,
adicionar código ao Tuist não deve ser muito diferente. Há duas diferenças em
relação ao desenvolvimento de aplicações que vale a pena mencionar:

- **As interações com as CLIs acontecem através do terminal.** O utilizador
  executa o Tuist, que realiza a tarefa pretendida, e depois regressa com
  sucesso ou com um código de estado. Durante a execução, o utilizador pode ser
  notificado através do envio de informação de saída para o standard output e
  standard error. Não existem gestos ou interações gráficas, apenas a intenção
  do utilizador.

- **Não existe um runloop que mantenha o processo vivo à espera de entradas**,
  como acontece numa aplicação iOS quando a aplicação recebe eventos do sistema
  ou do utilizador. As CLIs são executadas em seu processo e terminam quando o
  trabalho é feito. O trabalho assíncrono pode ser feito usando APIs do sistema
  como
  [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)
  ou [structured
  concurrency](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency),
  mas é preciso garantir que o processo esteja em execução enquanto o trabalho
  assíncrono estiver sendo executado. Caso contrário, o processo encerrará o
  trabalho assíncrono.

Se não tem qualquer experiência com Swift, recomendamos [o livro oficial da
Apple](https://docs.swift.org/swift-book/) para se familiarizar com a linguagem
e os elementos mais utilizados da API da Fundação.

## Requisitos mínimos {#requisitos mínimos}

Para contribuir para o Tuist, os requisitos mínimos são

- macOS 14.0+
- Xcode 16.3+

## Configurar o projeto localmente {#set-up-the-project-locally}

Para começar a trabalhar no projeto, podemos seguir os passos abaixo:

- Clone o repositório executando: `git clone git@github.com:tuist/tuist.git`
- [Instalar](https://mise.jdx.dev/getting-started.html) Mise para aprovisionar o
  ambiente de desenvolvimento.
- Execute `mise install` para instalar as dependências do sistema necessárias ao
  Tuist
- Execute `tuist install` para instalar as dependências externas necessárias ao
  Tuist
- (Opcional) Execute `tuist auth login` para obter acesso à
  <LocalizedLink href="/guides/features/cache">Cache Tuist</LocalizedLink>
- Execute `tuist generate` para gerar o projeto Tuist Xcode utilizando o próprio
  Tuist

**O projeto gerado abre-se automaticamente**. Se precisar de o abrir novamente
sem o gerar, execute `e abra Tuist.xcworkspace` (ou utilize o Finder).

> [!NOTE] XED . Se você tentar abrir o projeto usando `xed .`, ele abrirá o
> pacote, e não o projeto gerado pelo Tuist. Recomendamos a utilização do
> projeto gerado pelo Tuist para fazer o dog-food da ferramenta.

## Editar o projeto {#edit-the-project}

Se precisar de editar o projeto, por exemplo para adicionar dependências ou
ajustar alvos, pode utilizar o comando
<LocalizedLink href="/guides/features/projects/editing">`tuist edit`
</LocalizedLink>. Este é pouco utilizado, mas é bom saber que existe.

## Run Tuist {#run-tuist}

### A partir do Xcode {#from-xcode}

Para executar `tuist` a partir do projeto Xcode gerado, edite o esquema `tuist`
e defina os argumentos que gostaria de passar para o comando. Por exemplo, para
executar o comando `tuist generate`, você pode definir os argumentos para
`generate --no-open` para evitar que o projeto seja aberto após a geração.

![Um exemplo de uma configuração de esquema para executar o comando generate com
Tuist](/images/contributors/scheme-arguments.png)

Terá também de definir o diretório de trabalho para a raiz do projeto que está a
ser gerado. Pode fazê-lo utilizando o argumento `--path`, que todos os comandos
aceitam, ou configurando o diretório de trabalho no esquema como mostrado
abaixo:


![Um exemplo de como definir o diretório de trabalho para executar o
Tuist](/images/contributors/scheme-working-directory.png)

> [!WARNING] PROJECTDESCRIPTION COMPILATION A CLI `tuist` depende da presença da
> estrutura `ProjectDescription` no diretório de produtos construído. Se o
> `tuist` não for executado porque não consegue encontrar a estrutura
> `ProjectDescription`, compile primeiro o esquema `Tuist-Workspace`.

### Do terminal {#do-terminal}

Pode executar `tuist` utilizando o próprio Tuist através do comando `run`:

```bash
tuist run tuist generate --path /path/to/project --no-open
```

Em alternativa, também é possível executá-lo diretamente através do Gestor de
Pacotes Swift:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
