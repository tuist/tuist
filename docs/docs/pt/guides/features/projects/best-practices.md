---
{
  "title": "Best practices",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the best practices for working with Tuist and Xcode projects."
}
---
# Melhores práticas {#best-practices}

Ao longo dos anos em que trabalhamos com diferentes equipas e projectos,
identificámos um conjunto de práticas recomendadas que recomendamos seguir
quando trabalhamos com projectos Tuist e Xcode. Estas práticas não são
obrigatórias, mas podem ajudá-lo a estruturar os seus projectos de uma forma que
os torne mais fáceis de manter e escalar.

## Xcode {#xcode}

### Padrões desencorajados {#discouraged-patterns}

#### Configurações para modelar ambientes remotos {#configurações-para-modelar-ambientes-remotos}

Muitas organizações utilizam configurações de compilação para modelar diferentes
ambientes remotos (por exemplo, `Debug-Production` ou `Release-Canary`), mas
esta abordagem tem algumas desvantagens:

- **Inconsistências:** Se houver inconsistências de configuração em todo o
  gráfico, o sistema de compilação pode acabar usando a configuração errada para
  alguns alvos.
- **Complexidade:** Os projectos podem acabar com uma longa lista de
  configurações locais e ambientes remotos que são difíceis de analisar e
  manter.

As configurações de compilação foram concebidas para incorporar diferentes
definições de compilação, e os projectos raramente precisam de mais do que
apenas `Debug` e `Release`. A necessidade de modelar diferentes ambientes pode
ser alcançada de forma diferente:

- **Em compilações de depuração:** Você pode incluir todas as configurações que
  devem estar acessíveis no desenvolvimento do aplicativo (por exemplo, pontos
  de extremidade) e alterná-las em tempo de execução. A troca pode acontecer
  usando variáveis de ambiente de inicialização de esquema ou com uma interface
  do usuário dentro do aplicativo.
- **Em compilações de lançamento:** Em caso de lançamento, só pode incluir a
  configuração à qual a compilação de lançamento está ligada e não incluir a
  lógica de tempo de execução para mudar de configuração utilizando diretivas do
  compilador.

::: info Configurações não-padrão Embora o Tuist suporte configurações
não-padrão e as torne mais fáceis de gerenciar em comparação com os projetos
Xcode comuns, você receberá avisos se as configurações não forem consistentes em
todo o gráfico de dependências. Isso ajuda a garantir a confiabilidade da
compilação e evita problemas relacionados à configuração ::::

## Generated projects

### Pastas edificáveis

O Tuist 4.62.0 adicionou suporte para **pastas compiláveis** (grupos
sincronizados do Xcode), um recurso introduzido no Xcode 16 para reduzir
conflitos de mesclagem.

Enquanto os padrões curinga do Tuist (por exemplo, `Sources/**/*.swift`) já
eliminam conflitos de mesclagem em projetos gerados, as pastas compiláveis
oferecem benefícios adicionais:

- **Sincronização automática**: A estrutura do seu projeto mantém-se
  sincronizada com o sistema de ficheiros - sem necessidade de regeneração ao
  adicionar ou remover ficheiros
- **Fluxos de trabalho compatíveis com IA**: Os assistentes e agentes de
  codificação podem modificar a sua base de código sem desencadear a regeneração
  do projeto
- **Configuração mais simples**: Definir caminhos de pastas em vez de gerir
  listas de ficheiros explícitas

Recomendamos a adoção de pastas compiláveis em vez dos tradicionais atributos
`Target.sources` e `Target.resources` para uma experiência de desenvolvimento
mais simplificada.

:::grupo de códigos

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
:::
