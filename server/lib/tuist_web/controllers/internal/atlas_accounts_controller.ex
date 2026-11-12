defmodule TuistWeb.Internal.AtlasAccountsController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Ops.RunnerConcurrencyLimits

  # Resolves an organization or user handle to the account ID that feature
  # flag gates (`account:<id>`) and runner limits are keyed by. An
  # organization's own ID is a different number.
  def lookup(conn, %{"handle" => handle}) when is_binary(handle) and byte_size(handle) in 1..255 do
    case Accounts.get_account_by_handle(handle) do
      %Account{} = account ->
        json(conn, %{
          account_id: account.id,
          handle: account.name,
          type: if(is_nil(account.organization_id), do: "user", else: "organization"),
          organization_id: account.organization_id,
          user_id: account.user_id
        })

      nil ->
        respond(conn, {:error, :resource_not_found})
    end
  end

  def lookup(conn, _params), do: respond(conn, {:error, :invalid_request})

  def runner_concurrency_limits(conn, %{"account_id" => account_id}) do
    respond(conn, RunnerConcurrencyLimits.get(account_id))
  end

  def update_runner_concurrency_limits(conn, %{"account_id" => account_id}) do
    respond(conn, RunnerConcurrencyLimits.update(account_id, conn.body_params, conn.assigns.atlas_principal))
  end

  defp respond(conn, {:ok, result}), do: json(conn, result)

  defp respond(conn, {:error, reason}) do
    status =
      case reason do
        :resource_not_found -> :not_found
        reason when reason in [:stale_revision, :change_id_conflict] -> :conflict
        _ -> :unprocessable_entity
      end

    conn |> put_status(status) |> json(%{error: Atom.to_string(reason)})
  end
end
