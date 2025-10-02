---
{
  "title": "Issue reporting",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reporting bugs"
}
---
# Relatórios de problemas {#relatórios de problemas}

Como utilizador do Tuist, poderá deparar-se com erros ou comportamentos
inesperados. Se isso acontecer, encorajamo-lo a comunicá-los para que os
possamos corrigir.

## GitHub issues é a nossa plataforma de emissão de bilhetes {#github-issues-is-our-ticketing-platform}

Os problemas devem ser reportados no GitHub como [GitHub
issues](https://github.com/tuist/tuist/issues) e não no Slack ou noutras
plataformas. O GitHub é melhor para rastrear e gerenciar problemas, está mais
próximo da base de código e nos permite acompanhar o progresso do problema. Além
disso, incentiva uma descrição longa do problema, o que força o relator a pensar
sobre o problema e a fornecer mais contexto.

## O contexto é crucial {#context-is-crucial}

Uma questão sem contexto suficiente será considerada incompleta e o autor será
solicitado a fornecer contexto adicional. Se não for fornecido, o problema será
fechado. Pense da seguinte forma: quanto mais contexto você fornecer, mais fácil
será para nós entender o problema e corrigi-lo. Por isso, se quiser que o seu
problema seja resolvido, forneça o máximo de contexto possível. Tente responder
às seguintes perguntas:

- O que é que estava a tentar fazer?
- Qual é o aspeto do seu gráfico?
- Que versão do Tuist está a utilizar?
- Isto está a bloquear-vos?

Também solicitamos que forneça um projeto mínimo **reproduzível**.

## Projeto reprodutível {#reproducible-project}

### O que é um projeto reprodutível? {o que é um projeto reproduzível}

Um projeto reprodutível é um pequeno projeto Tuist para demonstrar um problema -
frequentemente este problema é causado por um bug no Tuist. O seu projeto
reprodutível deve conter as caraterísticas mínimas necessárias para demonstrar
claramente o bug.

### Porque é que se deve criar um caso de teste reprodutível? {Porque é que deve criar um caso de teste reprodutível}

Um projeto reproduzível permite-nos isolar a causa de um problema, que é o
primeiro passo para o corrigir! A parte mais importante de qualquer relatório de
erro é descrever os passos exactos necessários para reproduzir o erro.

Um projeto reproduzível é uma excelente forma de partilhar um ambiente
específico que causa um erro. O seu projeto reproduzível é a melhor forma de
ajudar as pessoas que o querem ajudar.

### Passos para criar um projeto reprodutível {#passos-para-criar-um-projeto-reprodutível}

- Criar um novo repositório git.
- Inicializar um projeto utilizando `tuist init` no diretório do repositório.
- Adicione o código necessário para recriar o erro que viu.
- Publique o código (a sua conta do GitHub é um bom local para o fazer) e, em
  seguida, ligue-se a ele quando criar um problema.

### Benefícios dos projectos reprodutíveis {#benefits-of-reproducible-projects}

- **Área de superfície mais pequena:** Ao remover tudo exceto o erro, não é
  necessário escavar para encontrar o erro.
- **Não precisa de publicar o código secreto:** Pode não ser possível publicar o
  seu sítio principal (por muitas razões). Recriar uma pequena parte do mesmo
  como um caso de teste reproduzível permite-lhe demonstrar publicamente um
  problema sem expor qualquer código secreto.
- **Prova do erro:** Algumas vezes um bug é causado por alguma combinação de
  configurações em sua máquina. Um caso de teste reproduzível permite que os
  contribuidores baixem sua compilação e testem-na em suas máquinas também. Isto
  ajuda a verificar e a reduzir a causa de um problema.
- **Obtenha ajuda para resolver o seu erro:** Se outra pessoa conseguir
  reproduzir o seu problema, terá muitas vezes uma boa hipótese de o resolver. É
  quase impossível corrigir um erro sem primeiro o conseguir reproduzir.
