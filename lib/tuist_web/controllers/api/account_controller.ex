defmodule TuistWeb.API.AccountController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller
  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias TuistWeb.API.Schemas.Account, as: AccountSchema
  import Tuist.Authorization

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  defmodule Error do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      type: :object,
      properties: %{
        message: %Schema{
          type: :string
        }
      }
    })
  end

  tags ["Account"]

  operation(:update_account,
    summary: "Update account",
    description: "Updates the given account",
    operation_id: "updateAccount",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ]
    ],
    request_body:
      {"Change account", "application/json",
       %Schema{
         type: :object,
         properties: %{
           handle: %Schema{
             type: :string,
             description: "The new account handle."
           }
         },
         required: []
       }},
    responses: %{
      ok: {"Account successfully updated", "application/json", AccountSchema},
      bad_request: {"An error occurred while updating the account.", "application/json", Error},
      unauthorized:
        {"You need to be authenticated to update your account.", "application/json", Error},
      forbidden: {"You don't have permission to update this account.", "application/json", Error},
      not_found: {"An account with this handle was not found.", "application/json", Error}
    }
  )

  def update_account(
        %{path_params: %{"account_handle" => handle}, body_params: params} = conn,
        _params
      ) do
    with %Account{} = account <- Accounts.get_account_by_handle(handle),
         true <- can(conn.assigns.current_user, :update, account, :organization),
         # The field is called `handle` in the public API, but `name` in our domain.
         {handle, params} = Map.pop(params, :handle),
         params = Map.put(params, :name, handle),
         {:ok, account} <- Accounts.update_account(account, params) do
      conn
      |> put_status(:ok)
      |> json(%{id: account.id, handle: account.name})
    else
      {:error, _changeset} ->
        conn |> put_status(:bad_request) |> json(%{message: "Error updating account."})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "You don't have permission to update the #{handle} account."})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "An account with this handle was not found."})
    end
  end
end
