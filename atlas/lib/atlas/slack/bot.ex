defmodule Atlas.Slack.Bot do
  @moduledoc """
  Runtime configuration for the Atlas-owned Slack app.

  Atlas keeps the company Slack app. The app-wide credentials live in
  environment configuration, while the company workspace bot token can be
  captured through the install flow and stored as a Slack installation.
  Tests stub these accessors via Mimic.
  """

  import Ecto.Query

  alias Atlas.Repo
  alias Atlas.Slack.Installation

  @app_keys [:company]
  @legacy_app_keys [:company, :community]
  @default_scopes [
    "app_mentions:read",
    "assistant:write",
    "channels:history",
    "channels:read",
    "chat:write",
    "chat:write.public",
    "commands",
    "groups:history",
    "groups:read",
    "links:read",
    "links:write",
    "users:read",
    "users:read.email"
  ]

  def app_keys, do: @app_keys

  def apps do
    Enum.map(app_keys(), &app/1)
  end

  def app(app_key) do
    app_key = normalize_app_key!(app_key)
    app_config = config()

    %{
      key: app_key,
      key_string: Atom.to_string(app_key),
      name: app_config[:bot_name] || default_name(app_key),
      bot_token: bot_token(app_key),
      signing_secret: signing_secret()
    }
  end

  def signing_secret_apps do
    Enum.filter(apps(), &present?(&1.signing_secret))
  end

  def bot_token(app_key) do
    case normalize_app_key!(app_key) do
      :company -> installed_bot_token(:company) || Keyword.get(config(), :bot_token)
      _legacy_app_key -> nil
    end
  end

  def signing_secret, do: Keyword.get(config(), :signing_secret)

  @doc """
  Workspace team ids allowed to install and use the app during rollout,
  from `ATLAS_SLACK_ALLOWED_TEAM_IDS`. An empty list means no restriction.
  """
  def allowed_team_ids, do: list_value(Keyword.get(config(), :allowed_team_ids))

  def signing_secret(app_key), do: app_key |> normalize_app_key!() |> then(fn _ -> signing_secret() end)

  def name(app_key) do
    app(app_key).name
  end

  def configured?(app_key) do
    not external_clients_disabled?() and
      app_key
      |> bot_token()
      |> present?()
  end

  def signing_secret_configured?(app_key) do
    not external_clients_disabled?() and
      app_key |> signing_secret() |> present?()
  end

  def install_config(conf \\ config()) do
    with client_id when is_binary(client_id) and client_id != "" <- Keyword.get(conf, :client_id),
         client_secret when is_binary(client_secret) and client_secret != "" <- Keyword.get(conf, :client_secret),
         signing_secret when is_binary(signing_secret) and signing_secret != "" <- Keyword.get(conf, :signing_secret) do
      %{
        client_id: client_id,
        client_secret: client_secret,
        signing_secret: signing_secret,
        scopes: scopes_value(Keyword.get(conf, :scopes)),
        allowed_team_ids: list_value(Keyword.get(conf, :allowed_team_ids))
      }
    else
      _ -> nil
    end
  end

  def normalize_app_key(app_key) when app_key in @legacy_app_keys, do: {:ok, app_key}

  def normalize_app_key(app_key) when is_binary(app_key) do
    case app_key do
      "company" -> {:ok, :company}
      "community" -> {:ok, :community}
      _ -> :error
    end
  end

  def normalize_app_key(_app_key), do: :error

  def normalize_app_key!(app_key) do
    case normalize_app_key(app_key) do
      {:ok, normalized} -> normalized
      :error -> raise ArgumentError, "unknown Slack app #{inspect(app_key)}"
    end
  end

  defp config do
    Application.get_env(:atlas, :slack, [])
  end

  defp installed_bot_token(app_key) do
    Installation
    |> where([installation], installation.app_key == ^app_key)
    |> where([installation], is_nil(installation.disconnected_at))
    |> where([installation], not is_nil(installation.bot_token))
    |> select([installation], installation.bot_token)
    |> Repo.one()
  end

  defp default_name(:company), do: "Tuist Atlas"
  defp default_name(_app_key), do: "Tuist Atlas"

  defp external_clients_disabled?, do: Application.get_env(:atlas, :disable_external_clients, false)

  defp scopes_value(nil), do: @default_scopes
  defp scopes_value(""), do: @default_scopes

  defp scopes_value(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> @default_scopes
      scopes -> scopes
    end
  end

  defp scopes_value(value) when is_list(value), do: value
  defp scopes_value(_value), do: @default_scopes

  defp list_value(nil), do: []
  defp list_value(""), do: []

  defp list_value(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp list_value(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp list_value(_value), do: []

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
