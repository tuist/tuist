---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# Edição {#edição}

Ao contrário dos projetos Xcode tradicionais ou Pacotes Swift, onde as
alterações são feitas através da interface do usuário do Xcode, os projetos
gerenciados pelo Tuist são definidos no código Swift contido nos arquivos de
manifesto **** . Se estiver familiarizado com Swift Packages e o arquivo
`Package.swift`, a abordagem é muito semelhante.

Pode editar estes ficheiros utilizando qualquer editor de texto, mas
recomendamos a utilização do fluxo de trabalho fornecido pelo Tuist, `tuist
edit`. O fluxo de trabalho cria um projeto Xcode que contém todos os ficheiros
de manifesto e permite-lhe editá-los e compilá-los. Graças à utilização do
Xcode, obtém todas as vantagens de **conclusão de código, realce de sintaxe e
verificação de erros**.

## Editar o projeto {#edit-the-project}

Para editar o seu projeto, pode executar o seguinte comando num diretório de
projeto Tuist ou num sub-diretório:

```bash
tuist edit
```

O comando cria um projeto Xcode em um diretório global e o abre no Xcode. O
projeto inclui um diretório `Manifests` que pode construir para garantir que
todos os seus manifestos são válidos.

> [!INFO] MANIFESTOS RESOLVIDOS POR GLOBO `tuist edit` resolve os manifestos a
> serem incluídos usando o glob `**/{Manifest}.swift` do diretório raiz do
> projeto (aquele que contém o arquivo `Tuist.swift` ). Certifique-se de que
> haja um `Tuist.swift` válido na raiz do projeto.

## Editar e gerar fluxo de trabalho {#editar-e-gerar-fluxo-de-trabalho}

Como você deve ter notado, a edição não pode ser feita a partir do projeto Xcode
gerado. Isso é feito para evitar que o projeto gerado tenha uma dependência do
Tuist, garantindo que você possa sair do Tuist no futuro com pouco esforço.

Ao iterar num projeto, recomendamos a execução de `tuist edit` a partir de uma
sessão de terminal para obter um projeto Xcode para editar o projeto e utilizar
outra sessão de terminal para executar `tuist generate`.
