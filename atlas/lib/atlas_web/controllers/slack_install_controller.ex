defmodule AtlasWeb.SlackInstallController do
  use AtlasWeb, :controller

  alias Atlas.Slack.Bot
  alias Atlas.Slack.Installations
  alias Atlas.Users
  alias Atlas.Users.User

  require Logger

  @state_salt "slack_install"
  @state_max_age_seconds 30 * 60
  @fallback_path "/admin/identities"

  def new(conn, _params) do
    case require_executive(conn) do
      {:ok, user} -> start_install(conn, user)
      {:halt, conn} -> conn
    end
  end

  def callback(conn, params) do
    with {:ok, user} <- require_executive(conn),
         {:ok, code} <- validate_callback(conn, user, params) do
      complete_install(conn, user, code)
    else
      {:halt, conn} -> conn
      {:error, message} when is_binary(message) -> bail(conn, message)
    end
  end

  defp require_executive(%{assigns: %{current_user: %User{} = user}} = conn) do
    if Users.executive?(user) do
      {:ok, user}
    else
      {:halt,
       conn
       |> put_flash(:error, gettext("You do not have access to manage Slack installs."))
       |> redirect(to: ~p"/commercial/sales")}
    end
  end

  defp require_executive(conn) do
    {:halt,
     conn
     |> put_flash(:error, gettext("Log in to manage Slack installs."))
     |> redirect(to: ~p"/login")}
  end

  defp start_install(conn, user) do
    state = generate_state(conn, user)
    redirect_uri = redirect_uri(conn)

    case Installations.authorize_url(redirect_uri, state, Bot.install_config()) do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, :not_configured} ->
        conn
        |> put_flash(:error, gettext("Slack install is not configured for this Atlas instance."))
        |> redirect(to: @fallback_path)
    end
  end

  defp validate_callback(conn, user, params) do
    with :ok <- validate_state(conn, user, params["state"]),
         :ok <- validate_slack_response(params["error"]) do
      validate_code(params["code"])
    end
  end

  defp validate_state(conn, user, state) when is_binary(state) and state != "" do
    case Phoenix.Token.verify(conn, @state_salt, state, max_age: @state_max_age_seconds) do
      {:ok, %{user_id: user_id}} when user_id == user.id ->
        :ok

      {:ok, _payload} ->
        {:error, gettext("The Slack install link was created for a different Atlas session. Try again.")}

      {:error, _reason} ->
        {:error, gettext("The Slack install link expired. Try again.")}
    end
  end

  defp validate_state(_conn, _user, _state), do: {:error, gettext("The Slack install link expired. Try again.")}

  defp validate_slack_response(error) when error in [nil, ""], do: :ok
  defp validate_slack_response("access_denied"), do: {:error, gettext("Slack install was cancelled.")}

  defp validate_slack_response(error) when is_binary(error) do
    {:error, gettext("Slack rejected the install: %{reason}.", reason: format_slack_error(error))}
  end

  defp validate_code(code) when is_binary(code) and code != "", do: {:ok, code}

  defp validate_code(_code), do: {:error, gettext("Slack did not return an authorization code.")}

  defp complete_install(conn, user, code) do
    case Installations.complete_install(code, redirect_uri(conn), installed_by_user_id: user.id, actor: user) do
      {:ok, installation} ->
        conn
        |> put_flash(
          :info,
          gettext("Connected %{workspace} to Atlas.",
            workspace: installation.team_name || installation.team_id
          )
        )
        |> redirect(to: @fallback_path)

      {:error, :workspace_not_allowed} ->
        bail(conn, gettext("That Slack workspace is not allowed on this Atlas instance."))

      {:error, reason} ->
        Logger.warning("[SlackInstall] install failed: #{inspect(reason)}")
        bail(conn, gettext("Slack rejected the install. Try again."))
    end
  end

  defp bail(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: @fallback_path)
  end

  defp generate_state(conn, user) do
    nonce =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    Phoenix.Token.sign(conn, @state_salt, %{nonce: nonce, user_id: user.id})
  end

  defp redirect_uri(conn) do
    "#{scheme(conn)}://#{host(conn)}/slack/install/callback"
  end

  defp scheme(conn) do
    case Application.get_env(:atlas, AtlasWeb.Endpoint, [])[:url] do
      [scheme: scheme] when is_binary(scheme) -> scheme
      url when is_list(url) -> url[:scheme] || Atom.to_string(conn.scheme)
      _ -> Atom.to_string(conn.scheme)
    end
  end

  defp host(conn) do
    case Application.get_env(:atlas, AtlasWeb.Endpoint, [])[:url] do
      url when is_list(url) ->
        case url[:host] do
          nil -> conn.host
          host -> append_port(host, url[:port])
        end

      _ ->
        case conn.port do
          80 -> conn.host
          443 -> conn.host
          port -> "#{conn.host}:#{port}"
        end
    end
  end

  defp append_port(host, port) when port in [nil, 80, 443], do: host
  defp append_port(host, port), do: "#{host}:#{port}"

  defp format_slack_error(error) do
    error
    |> String.replace("_", " ")
    |> String.trim()
  end
end
