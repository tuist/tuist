defmodule TuistWeb.API.AccountController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Authorization
  alias TuistWeb.API.Schemas.Account, as: AccountSchema
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.ValidationError

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

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
      bad_request: {"Validation errors occurred", "application/json", ValidationError},
      unauthorized: {"You need to be authenticated to update your account.", "application/json", Error},
      forbidden: {"You don't have permission to update this account.", "application/json", Error},
      not_found: {"An account with this handle was not found.", "application/json", Error}
    }
  )

  def update_account(%{path_params: %{"account_handle" => handle}, body_params: params} = conn, _params) do
    with {:ok, account} <- get_account(handle),
         :ok <-
           Authorization.authorize(
             :organization_update,
             conn.assigns.current_user,
             account
           ),
         # The field is called `handle` in the public API, but `name` in our domain.
         {handle, params} = Map.pop(params, :handle),
         params = Map.put(params, :name, handle),
         {:ok, account} <- Accounts.update_account(account, params) do
      conn
      |> put_status(:ok)
      |> json(%{id: account.id, handle: account.name})
    end
  end

  operation(:delete_account,
    summary: "Deletes an account",
    description: "Deletes the account with the given handle.",
    operation_id: "deleteAccount",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account to delete."
      ]
    ],
    responses: %{
      no_content: "The account was deleted",
      not_found: {"The account with the given handle was not found", "application/json", Error},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
    }
  )

  def delete_account(%{path_params: %{"account_handle" => handle}} = conn, _params) do
    with {:ok, account} <- get_account(handle),
         :ok <- Authorization.authorize(:account_delete, conn.assigns.current_user, account) do
      Accounts.delete_account!(account)

      conn
      |> put_status(:no_content)
      |> json(%{})
    else
      {:error, :not_found, "account"} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Account #{handle} not found."})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})
    end
  end

  defp get_account(handle) do
    case Accounts.get_account_by_handle(handle) do
      %Account{} = account -> {:ok, account}
      nil -> {:error, :not_found, "account"}
    end
  end
end
