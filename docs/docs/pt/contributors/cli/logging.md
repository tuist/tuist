---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Registo {#logging}

A CLI abraça a interface [swift-log](https://github.com/apple/swift-log) para
logging. O pacote abstrai os detalhes de implementação de logging, permitindo
que a CLI seja agnóstica ao backend de logging. O registrador é injetado na
dependência usando locals de tarefas e pode ser acessado em qualquer lugar
usando:

```bash
Logger.current
```

> [NOTA] Os locais da tarefa não propagam o valor quando se utiliza `Dispatch`
> ou tarefas separadas, por isso, se os utilizar, terá de o obter e passá-lo
> para a operação assíncrona.

## O que registar {#o que registar}

Os registos não são a interface de utilizador do CLI. Eles são uma ferramenta
para diagnosticar problemas quando eles surgem. Portanto, quanto mais
informações você fornecer, melhor. Ao criar novos recursos, coloque-se no lugar
de um desenvolvedor que se depara com um comportamento inesperado e pense em
quais informações seriam úteis para ele. Certifique-se de que utiliza o [nível
de
registo](https://www.swift.org/documentation/server/guides/libraries/log-levels.html)
correto. Caso contrário, os programadores não serão capazes de filtrar o ruído.
