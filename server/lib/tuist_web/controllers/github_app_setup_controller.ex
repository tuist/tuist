defmodule TuistWeb.GitHubAppSetupController do
  @moduledoc "Completes Tuist- and provider-initiated GitHub App installations."
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.GitHub.InstallationAuthorization
  alias Tuist.GitHub.Installations
  alias Tuist.VCS
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.BadRequestError
  alias TuistWeb.IntegrationInstallationController

  def setup(conn, %{"installation_id" => installation_id} = params)
      when is_binary(installation_id) and not is_map_key(params, "state") do
    start_authorization(conn, installation_id)
  end

  def setup(conn, params) do
    with {:ok, installation_id} <- extract_installation_id(params),
         {:ok, %{account_id: account_id, client_url: client_url}} <- extract_state(params),
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         :ok <- Authorization.authorize(:account_update, Authentication.current_user(conn), account) do
      if client_url == VCS.default_client_url() do
        start_authorization(conn, installation_id, account.id)
      else
        complete_setup(conn, account, client_url, installation_id)
      end
    else
      {:error, :missing_installation_id} ->
        raise BadRequestError, dgettext("dashboard", "Invalid GitHub app installation. Please try again.")

      _ ->
        invalid_request!()
    end
  end

  def authorize(conn, %{"code" => code, "state" => state}) when is_binary(code) and is_binary(state) do
    user = Authentication.current_user(conn)

    with %{state: ^state, installation_id: installation_id, user_id: user_id, issued_at: issued_at} = pending <-
           get_session(conn, :github_installation_authorization),
         true <- user.id == user_id and (System.system_time(:second) - issued_at) in -60..600,
         :ok <- InstallationAuthorization.verify(code, installation_id, authorization_callback_url()) do
      conn = delete_session(conn, :github_installation_authorization)

      case pending[:account_id] do
        nil ->
          IntegrationInstallationController.select(conn, :github, installation_id)

        account_id ->
          with {:ok, account} <- Accounts.get_account_by_id(account_id),
               :ok <- Authorization.authorize(:account_update, user, account) do
            complete_setup(conn, account, VCS.default_client_url(), installation_id)
          else
            _ -> invalid_request!()
          end
      end
    else
      _ -> invalid_request!()
    end
  end

  def authorize(_conn, _params), do: invalid_request!()

  defp start_authorization(conn, installation_id, account_id \\ nil) do
    with {id, ""} when id > 0 <- Integer.parse(installation_id),
         client_id when is_binary(client_id) and client_id != "" <- Environment.github_app_client_id() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      user = Authentication.current_user(conn)
      query = URI.encode_query(%{client_id: client_id, redirect_uri: authorization_callback_url(), state: state})

      conn
      |> put_session(:github_installation_authorization, %{
        state: state,
        installation_id: installation_id,
        account_id: account_id,
        user_id: user.id,
        issued_at: System.system_time(:second)
      })
      |> redirect(external: "https://github.com/login/oauth/authorize?" <> query)
    else
      _ -> invalid_request!()
    end
  end

  defp complete_setup(conn, account, client_url, installation_id) do
    case Installations.attach(account, client_url, installation_id) do
      {:ok, _installation} ->
        redirect(conn, to: ~p"/#{account.name}/settings/integrations")

      {:error, :installation_already_connected} ->
        raise BadRequestError, dgettext("dashboard", "This GitHub app installation is already connected.")

      {:error, :github_host_conflict} ->
        raise BadRequestError,
              dgettext("dashboard", "This account already has a GitHub App registered for a different GitHub host.")

      {:error, :ghes_setup_without_manifest} ->
        raise BadRequestError,
              dgettext(
                "dashboard",
                "GitHub Enterprise Server installations must go through the App registration flow first."
              )

      _ ->
        invalid_request!()
    end
  end

  defp extract_installation_id(%{"installation_id" => installation_id}) when is_binary(installation_id) do
    case Integer.parse(installation_id) do
      {id, ""} when id > 0 -> {:ok, installation_id}
      _ -> {:error, :missing_installation_id}
    end
  end

  defp extract_installation_id(_params), do: {:error, :missing_installation_id}

  defp extract_state(%{"state" => state_token}) when is_binary(state_token) do
    case VCS.verify_github_state_token(state_token) do
      {:ok, %{account_id: _, client_url: _} = payload} -> {:ok, payload}
      _ -> {:error, :invalid_state_token}
    end
  end

  defp extract_state(_params), do: {:error, :missing_state}
  defp authorization_callback_url, do: Environment.app_url() <> "/integrations/github/authorize"

  defp invalid_request! do
    raise BadRequestError, dgettext("dashboard", "Invalid installation request. Please try again.")
  end
end
