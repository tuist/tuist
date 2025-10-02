---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about Tuist's hashing logic upon which features like binary caching and selective testing are built."
}
---
# Hashing {#hashing}

Recursos como
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink> ou execução
seletiva de testes exigem uma maneira de determinar se um alvo foi alterado. O
Tuist calcula um hash para cada alvo no gráfico de dependência para determinar
se um alvo foi alterado. O hash é calculado com base nos seguintes atributos:

- Os atributos do alvo (por exemplo, nome, plataforma, produto, etc.)
- Os ficheiros do alvo
- O hash das dependências do alvo

### Atributos da cache {#cache-attributes}

Adicionalmente, ao calcular o hash para
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink>, também
fazemos o hash dos seguintes atributos.

#### Versão do Swift {#swift-version}

Colocamos em hash a versão do Swift obtida a partir da execução do comando
`/usr/bin/xcrun swift --version` para evitar erros de compilação devido a
incompatibilidades de versão do Swift entre os alvos e os binários.

> [NOTA] ESTABILIDADE DO MÓDULO As versões anteriores do cache binário dependiam
> da configuração de compilação `BUILD_LIBRARY_FOR_DISTRIBUTION` para ativar a
> [estabilidade do
> módulo](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)
> e permitir o uso de binários com qualquer versão do compilador. No entanto,
> isso causou problemas de compilação em projetos com alvos que não suportam a
> estabilidade do módulo. Os binários gerados são vinculados à versão do Swift
> usada para compilá-los, e a versão do Swift deve corresponder àquela usada
> para compilar o projeto.

#### Configuração {#configuração}

A ideia por detrás da flag `-configuration` era assegurar que os binários de
depuração não eram utilizados em compilações de lançamento e vice-versa. No
entanto, ainda nos falta um mecanismo para remover as outras configurações dos
projectos para evitar que sejam utilizadas.

## Depuração {#debugging}

Se você notar comportamentos não determinísticos ao usar o armazenamento em
cache entre ambientes ou invocações, isso pode estar relacionado a diferenças
entre os ambientes ou a um bug na lógica de hashing. Recomendamos seguir estas
etapas para depurar o problema:

1. Certifique-se de que é utilizada a mesma [configuração](#configuration) e
   [versão Swift](#swift-version) em todos os ambientes.
2. Verifique se existem diferenças entre os projectos Xcode gerados por duas
   invocações consecutivas de `tuist generate` ou entre ambientes. Você pode
   usar o comando `diff` para comparar os projetos. Os projetos gerados podem
   incluir **caminhos absolutos** fazendo com que a lógica de hashing não seja
   determinística.

> [!NOTE] PLANEJA-SE UMA MELHOR EXPERIÊNCIA DE DEBUGGING Melhorar a nossa
> experiência de debugging está no nosso roadmap. O comando print-hashes, que
> não tem contexto para entender as diferenças, será substituído por um comando
> mais amigável que usa uma estrutura em forma de árvore para mostrar as
> diferenças entre os hashes.
