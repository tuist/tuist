---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# Reunir conhecimentos {#gather-insights}

O Tuist pode integrar-se a um servidor para ampliar seus recursos. Uma dessas
capacidades é a recolha de informações sobre o seu projeto e as suas
construções. Tudo o que precisa é de ter uma conta com um projeto no servidor.

Em primeiro lugar, tem de se autenticar executando:

```bash
tuist auth login
```

## Criar um projeto {#criar um projeto}

Pode então criar um projeto executando:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

Copiar `my-handle/MyApp`, que representa o identificador completo do projeto.

## Ligar projectos {#connect-projects}

Depois de criar o projeto no servidor, terá de o ligar ao seu projeto local.
Execute `tuist edit` e edite o arquivo `Tuist.swift` para incluir o
identificador completo do projeto:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

Pronto! Agora você está pronto para reunir informações sobre seu projeto e
compilações. Execute `tuist test` para executar os testes que reportam os
resultados ao servidor.

> [NOTA] O Tuist coloca os resultados em fila de espera localmente e tenta
> enviá-los sem bloquear o comando. Portanto, eles podem não ser enviados
> imediatamente após o término do comando. No CI, os resultados são enviados
> imediatamente.


![Uma imagem que mostra uma lista de execuções no
servidor](/images/guides/quick-start/runs.png)

Ter dados dos seus projectos e construções é crucial para tomar decisões
informadas. O Tuist continuará a alargar as suas capacidades e você beneficiará
delas sem ter de alterar a configuração do seu projeto. Mágico, não é? 🪄
