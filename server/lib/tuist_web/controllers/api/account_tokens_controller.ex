defmodule TuistWeb.API.AccountTokensController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Authorization
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.LoaderPlug)

  tags ["Account tokens"]

  operation(:create,
    summary: "Create a new account token.",
    description: "This endpoint returns a new account token.",
    operation_id: "createAccountToken",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The account handle."
      ]
    ],
    request_body:
      {"Create account token params", "application/json",
       %Schema{
         title: "CreateAccountToken",
         description: "The request to create a new account token.",
         type: :object,
         properties: %{
           scopes: %Schema{
             type: :array,
             items: %Schema{
               title: "AccountTokenScope",
               type: :string,
               description: "The scope of the token.",
               enum: Ecto.Enum.values(AccountToken, :scopes)
             },
             description: "The scopes for the new account token."
           }
         },
         required: [:scopes]
       }},
    responses: %{
      ok: {
        "An account token was generated",
        "application/json",
        %Schema{
          title: "AccountToken",
          description: "A new account token.",
          type: :object,
          properties: %{
            token: %Schema{
              type: :string,
              description: "The generated account token."
            }
          },
          required: [:token]
        }
      },
      unauthorized: {"You need to be authenticated to issue new tokens", "application/json", Error},
      forbidden: {"You need to be authorized to issue new tokens", "application/json", Error},
      not_found: {"The account was not found", "application/json", Error}
    }
  )

  def create(%{params: %{"scopes" => scopes}, assigns: %{selected_account: selected_account}} = conn, _opts) do
    current_user = Authentication.current_user(conn)

    with :ok <- Authorization.authorize(:account_token_create, current_user, selected_account),
         {:ok, {_token_record, token}} <-
           Accounts.create_account_token(%{
             account: selected_account,
             scopes: Enum.map(scopes, &String.to_atom/1)
           }) do
      json(conn, %{token: token})
    end
  end
end
