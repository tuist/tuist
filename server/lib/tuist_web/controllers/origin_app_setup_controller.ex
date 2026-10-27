defmodule TuistWeb.OriginAppSetupController do
  @moduledoc "Browser-bound Origin installation consent and verified setup callback."
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.Origin
  alias Tuist.Origin.Client
  alias Tuist.Origin.Signatures
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.BadRequestError
  alias TuistWeb.IntegrationInstallationController

  require Logger

  def start(conn, %{"account_id" => account_id}) when is_binary(account_id) do
    user = Authentication.current_user(conn)

    with true <- Client.configured?(),
         user when not is_nil(user) <- user,
         {account_id, ""} <- Integer.parse(account_id),
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         :ok <- Authorization.authorize(:account_update, user, account) do
      state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      callback = Environment.app_url() <> "/integrations/origin/setup"

      query =
        URI.encode_query(%{
          client_id: Environment.origin_app_id(),
          scope: Enum.join(Client.scopes(), " "),
          redirect_uri: callback,
          state: state,
          include_granted_scopes: "true",
          summary: "Post Tuist build, test, preview, and bundle reports on pull requests."
        })

      conn
      |> put_session(:origin_installation, %{
        state: state,
        account_id: account.id,
        user_id: user.id,
        issued_at: System.system_time(:second)
      })
      |> redirect(external: "https://cursor.com/codebase/apps/install?" <> query)
    else
      _ -> invalid_request!()
    end
  end

  def start(_conn, _params), do: invalid_request!()

  def setup(conn, %{"installation_receipt" => receipt}) do
    user = Authentication.current_user(conn)

    case get_session(conn, :origin_installation) do
      nil -> select_account(conn, receipt)
      pending -> complete_setup(conn, receipt, user, pending)
    end
  end

  def setup(_conn, _params), do: invalid_request!()

  defp select_account(conn, receipt, setup_failure \\ nil) do
    case Signatures.verify_receipt(receipt, nil) do
      {:ok, _claims} ->
        conn
        |> delete_session(:origin_installation)
        |> IntegrationInstallationController.select(:origin, receipt)

      _ ->
        log_setup_failure(setup_failure)
        invalid_request!()
    end
  end

  defp complete_setup(conn, receipt, user, pending) do
    with %{state: state, account_id: account_id, user_id: user_id, issued_at: issued_at} <- pending,
         true <- (System.system_time(:second) - issued_at) in -60..600,
         %{id: ^user_id} <- user,
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         :ok <- Authorization.authorize(:account_update, user, account),
         {:ok, claims} <- Signatures.verify_receipt(receipt, state),
         {:ok, _installation} <- Origin.attach_installation(account, claims) do
      conn
      |> delete_session(:origin_installation)
      |> redirect(to: ~p"/#{account.name}/settings/integrations")
    else
      failure -> select_account(conn, receipt, failure)
    end
  end

  defp log_setup_failure(nil), do: :ok

  defp log_setup_failure({:error, reason}) when is_atom(reason) do
    Logger.warning("Origin installation could not complete the pending Tuist setup", reason: reason)
  end

  defp log_setup_failure(_failure) do
    Logger.warning("Origin installation could not complete the pending Tuist setup", reason: :invalid_setup_state)
  end

  defp invalid_request! do
    raise BadRequestError,
          dgettext("dashboard", "Invalid Origin installation request. Please try again.")
  end
end
