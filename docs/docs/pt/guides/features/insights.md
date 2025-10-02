---
{
  "title": "Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your projects to maintain a product developer environment."
}
---
# Insights {#insights}

> REQUISITOS [!IMPORTANTE]
> - Uma conta e um projeto
>   <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>

Trabalhar em grandes projectos não deve ser uma tarefa árdua. De facto, deveria
ser tão agradável como trabalhar num projeto que começou há apenas duas semanas.
Uma das razões pelas quais não é, é porque à medida que o projeto cresce, a
experiência do programador sofre. Os tempos de construção aumentam e os testes
tornam-se lentos e instáveis. Muitas vezes é fácil ignorar estes problemas até
chegar a um ponto em que se tornam insuportáveis - no entanto, nesse ponto, é
difícil resolvê-los. O Tuist Insights fornece-lhe as ferramentas para
monitorizar a saúde do seu projeto e manter um ambiente de desenvolvimento
produtivo à medida que o seu projeto cresce.

Por outras palavras, o Tuist Insights ajuda-o a responder a perguntas como:
- O tempo de construção aumentou significativamente na última semana?
- Os meus testes tornaram-se mais lentos? Quais?

> [NOTA] As percepções dos tuítes estão em fase inicial de desenvolvimento.

## Construções {#construções}

Embora provavelmente tenha algumas métricas para o desempenho dos fluxos de
trabalho de CI, poderá não ter a mesma visibilidade do ambiente de
desenvolvimento local. No entanto, os tempos de construção local são um dos
factores mais importantes que contribuem para a experiência do programador.

Para começar a acompanhar os tempos de construção locais, pode aproveitar o
comando `tuist inspect build` adicionando-o ao post-action do seu esquema:

![Pós-ação de inspeção de
construções](/images/guides/features/insights/inspect-build-scheme-post-action.png)

> [Recomendamos definir a opção "Provide build settings from" (Fornecer
> configurações de compilação de) para o executável ou seu alvo principal de
> compilação para permitir que o Tuist rastreie a configuração de compilação.

> [NOTA] Se não estiver a utilizar projectos
> <LocalizedLink href="/guides/features/projects"> gerados</LocalizedLink>, a
> ação pós-esquema não é executada caso a construção falhe.
> 
> Um recurso não documentado no Xcode permite que você o execute mesmo nesse
> caso. Defina o atributo `runPostActionsOnFailure` para `YES` no seu esquema
> `BuildAction` no arquivo relevante `project.pbxproj` da seguinte forma:
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

Se estiver a utilizar [Mise](https://mise.jdx.dev/), o seu script terá de ativar
`tuist` no ambiente pós-ação:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"

tuist inspect build
```


As suas construções locais são agora monitorizadas desde que tenha sessão
iniciada na sua conta Tuist. Agora pode aceder aos seus tempos de construção no
painel de controlo do Tuist e ver como evoluem ao longo do tempo:


> [!TIP] Para aceder rapidamente ao painel de controlo, execute `tuist project
> show --web` a partir do CLI.

![Painel de controlo com informações sobre a
construção](/images/guides/features/insights/builds-dashboard.png)

## Projectos gerados {#projectos gerados}

> [NOTA] Os esquemas gerados automaticamente incluem o `tuist inspect build`
> post-action.
> 
> Se não estiver interessado em rastrear informações de construção nos seus
> esquemas gerados automaticamente, desactive-os utilizando a opção de geração
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>.

Se estiver a utilizar projectos gerados, pode configurar uma pós-ação
personalizada
<LocalizedLink href="references/project-description/structs/buildaction#postactions">build</LocalizedLink>
utilizando um esquema personalizado, como por exemplo:

```swift
let project = Project(
    name: "MyProject",
    targets: [
        // Your targets
    ],
    schemes: [
        .scheme(
            name: "MyApp",
            shared: true,
            buildAction: .buildAction(
                targets: ["MyApp"],
                postActions: [
                    .executionAction(
                        name: "Inspect Build",
                        scriptText: """
                        eval \"$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)\"
                        tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                runPostActionsOnFailure: true
            ),
            testAction: .testAction(targets: ["MyAppTests"]),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Se não estiver a utilizar o Mise, o seu guião pode ser simplificado para apenas:

```swift
.postAction(
    name: "Inspect Build",
    script: "tuist inspect build",
    execution: .always
)
```

## Integração contínua {#continuous-integration}

Para acompanhar os tempos de construção também no IC, terá de garantir que o seu
IC é
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">autenticado</LocalizedLink>.

Para além disso, terá de:
- Utilize o comando
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> quando invocar as acções `xcodebuild`.
- Adicione `-resultBundlePath` à sua invocação `xcodebuild`.

Quando `xcodebuild` constrói o seu projeto sem `-resultBundlePath`, o ficheiro
`.xcactivitylog` não é gerado. Mas o `tuist inspect build` post-action requer
que esse ficheiro seja gerado para analisar a sua compilação.
