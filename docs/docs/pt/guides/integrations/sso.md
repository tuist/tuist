---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

## Google {#google}

Se tiver uma organização do Google Workspace e pretender que qualquer
programador que inicie sessão com o mesmo domínio alojado no Google seja
adicionado à sua organização Tuist, pode configurá-lo com:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

> [IMPORTANTE] Tem de estar autenticado no Google utilizando um e-mail associado
> à organização cujo domínio está a configurar.

## Okta {#okta}

O SSO com Okta está disponível apenas para clientes empresariais. Se estiver
interessado em configurá-lo, contacte-nos através de
[contact@tuist.dev](mailto:contact@tuist.dev).

Durante o processo, ser-lhe-á atribuído um ponto de contacto para o ajudar a
configurar o Okta SSO.

Em primeiro lugar, é necessário criar uma aplicação Okta e configurá-la para
funcionar com o Tuist:
1. Aceder ao painel de administração do Okta
2. Aplicações > Aplicações > Criar integração de aplicações
3. Selecione "OIDC - OpenID Connect" e "Aplicação Web"
4. Introduza o nome de apresentação da aplicação, por exemplo, "Tuist". Carregue
   um logótipo Tuist localizado em [este
   URL](https://tuist.dev/images/tuist_dashboard.png).
5. Deixar os URIs de redireccionamento de início de sessão como estão por agora
6. Em "Assignments" (Atribuições), escolha o controlo de acesso pretendido para
   a aplicação SSO e guarde.
7. Depois de guardar, as definições gerais da aplicação estarão disponíveis.
   Copie o "Client ID" e o "Client Secret" - terá de os partilhar em segurança
   com o seu ponto de contacto.
8. A equipa Tuist terá de reimplementar o servidor Tuist com o ID e o segredo do
   cliente fornecidos. Isso pode levar até um dia útil.
9. Depois de o servidor ser implementado, clique no botão "Editar" das
   definições gerais.
10. Cole o seguinte URL de redireccionamento:
    `https://tuist.dev/users/auth/okta/callback`
13. Altere "Login iniciado por" para "Okta ou App".
14. Selecione "Apresentar o ícone da aplicação aos utilizadores"
15. Actualize o "URL de início de sessão" com
    `https://tuist.dev/users/auth/okta?organization_id=1`. O `organization_id`
    será fornecido pelo seu ponto de contacto.
16. Clique em "Guardar".
17. Inicie o login do Tuist a partir do seu painel Okta.
18. Dê acesso automático à sua organização Tuist aos utilizadores assinados a
    partir do seu domínio Okta, executando o seguinte comando:
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

> [IMPORTANTE] Os utilizadores têm de iniciar sessão através do seu painel Okta,
> uma vez que o Tuist não suporta atualmente o aprovisionamento e
> desprovisionamento automático de utilizadores da sua organização Okta. Uma vez
> que eles se conectem através do painel Okta, eles serão automaticamente
> adicionados à sua organização Tuist.
