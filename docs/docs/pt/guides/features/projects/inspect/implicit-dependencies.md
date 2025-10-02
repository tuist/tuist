---
{
  "title": "Implicit imports",
  "titleTemplate": ":title · Inspect · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to find implicit imports."
}
---
# Importações implícitas {#implicit-imports}

Para aliviar a complexidade de manter um gráfico de projeto Xcode com um projeto
Xcode bruto, a Apple projetou o sistema de compilação de uma forma que permite
que as dependências sejam definidas implicitamente. Isto significa que um
produto, por exemplo uma aplicação, pode depender de uma estrutura, mesmo sem
declarar a dependência explicitamente. Em pequena escala, isso é bom, mas à
medida que o gráfico do projeto cresce em complexidade, a implicação pode se
manifestar como compilações incrementais não confiáveis ou recursos baseados em
editor, como visualizações prévias ou conclusão de código.

O problema é que não se pode evitar que dependências implícitas aconteçam.
Qualquer desenvolvedor pode adicionar uma declaração `import` ao seu código
Swift, e a dependência implícita será criada. É aqui que o Tuist entra em cena.
O Tuist fornece um comando para inspecionar as dependências implícitas
analisando estaticamente o código em seu projeto. O comando a seguir mostrará as
dependências implícitas do seu projeto:

```bash
tuist inspect implicit-imports
```

Se o comando detetar quaisquer importações implícitas, sai com um código de
saída diferente de zero.

> [Recomendamos vivamente que execute este comando como parte do seu comando
> <LocalizedLink href="/guides/features/automate/continuous-integration">continuous
> integration</LocalizedLink> sempre que o novo código é enviado para o sistema.

> [IMPORTANTE] NEM TODOS OS CASOS IMPLÍCITOS SÃO DETECTADOS Como o Tuist se
> baseia na análise de código estático para detetar dependências implícitas, ele
> pode não detetar todos os casos. Por exemplo, o Tuist não é capaz de
> compreender as importações condicionais através de diretivas do compilador no
> código.
