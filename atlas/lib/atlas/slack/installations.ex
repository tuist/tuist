defmodule Atlas.Slack.Installations do
  @moduledoc """
  Completes Slack app installs and persists one row per workspace.
  """

  alias Atlas.Audit
  alias Atlas.Repo
  alias Atlas.Slack.Bot
  alias Atlas.Slack.Installation

  @slack_access_url "https://slack.com/api/oauth.v2.access"

  def authorize_url(redirect_uri, state, config \\ Bot.install_config()) do
    case config do
      nil ->
        {:error, :not_configured}

      %{client_id: client_id, scopes: scopes} = config ->
        query =
          %{
            "client_id" => client_id,
            "scope" => Enum.join(scopes, ","),
            "redirect_uri" => redirect_uri,
            "state" => state
          }
          |> put_single_team_hint(config)
          |> URI.encode_query()

        {:ok, "https://slack.com/oauth/v2/authorize?" <> query}
    end
  end

  def complete_install(code, redirect_uri, opts \\ []) when is_binary(code) do
    config = Keyword.get(opts, :config) || Bot.install_config()
    installed_by_user_id = Keyword.get(opts, :installed_by_user_id)

    case config do
      nil ->
        {:error, :not_configured}

      %{client_id: client_id, client_secret: client_secret} ->
        with {:ok, response} <- request_token(code, redirect_uri, client_id, client_secret),
             {:ok, attrs} <- parse_response(response, installed_by_user_id),
             :ok <- validate_allowed_team_id(attrs.team_id, Map.get(config, :allowed_team_ids, [])) do
          attrs
          |> Map.put(:app_key, :company)
          |> upsert(audit_opts(opts))
        end
    end
  end

  def disconnect(%Installation{} = installation, opts \\ []) do
    installation
    |> Installation.disconnect_changeset()
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        Audit.record("slack.installation.disconnected", audit_attrs(updated), audit_opts(opts))
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp request_token(code, redirect_uri, client_id, client_secret) do
    body =
      URI.encode_query(%{
        "code" => code,
        "redirect_uri" => redirect_uri
      })

    case Req.post(@slack_access_url,
           headers: [{"content-type", "application/x-www-form-urlencoded"}],
           auth: {:basic, client_id <> ":" <> client_secret},
           body: body
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:slack_install_http_error, status}}

      {:error, reason} ->
        {:error, {:slack_install_transport_error, reason}}
    end
  end

  defp parse_response(%{"ok" => true} = body, installed_by_user_id) do
    team = body["team"] || %{}
    bot_token = body["access_token"]

    if present?(bot_token) do
      {:ok,
       %{
         team_id: team["id"],
         team_name: team["name"],
         bot_user_id: body["bot_user_id"],
         bot_token: bot_token,
         scope: body["scope"],
         installed_at: DateTime.utc_now() |> DateTime.truncate(:second),
         disconnected_at: nil,
         installed_by_user_id: installed_by_user_id
       }}
    else
      {:error, :missing_access_token}
    end
  end

  defp parse_response(%{"ok" => false, "error" => error}, _installed_by_user_id),
    do: {:error, {:slack_install_error, error}}

  defp parse_response(_body, _installed_by_user_id), do: {:error, :invalid_slack_install_response}

  defp validate_allowed_team_id(team_id, allowed_team_ids) when is_binary(team_id) and team_id != "" do
    if allowed_team_ids == [] or team_id in allowed_team_ids,
      do: :ok,
      else: {:error, :workspace_not_allowed}
  end

  defp validate_allowed_team_id(_team_id, _allowed_team_ids), do: {:error, :missing_team_id}

  defp upsert(%{team_id: team_id, app_key: app_key} = attrs, audit_opts) when is_binary(team_id) do
    existing =
      Repo.get_by(Installation, team_id: team_id) ||
        Repo.get_by(Installation, app_key: app_key)

    (existing || %Installation{})
    |> Installation.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, installation} ->
        Audit.record("slack.installation.connected", audit_attrs(installation), audit_opts)
        {:ok, installation}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp put_single_team_hint(query, %{allowed_team_ids: [team_id]}) when is_binary(team_id),
    do: Map.put(query, "team", team_id)

  defp put_single_team_hint(query, _config), do: query

  defp audit_opts(opts) do
    opts
    |> Keyword.take([:actor, :interface])
    |> Keyword.put_new(:interface, "dashboard")
  end

  defp audit_attrs(%Installation{} = installation) do
    %{
      target_type: "slack_installation",
      target_id: installation.id,
      target_label: installation.team_name || installation.team_id,
      metadata: %{
        "slack_app" => Atom.to_string(installation.app_key),
        "team_id" => installation.team_id,
        "team_name" => installation.team_name
      }
    }
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
