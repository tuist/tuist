defmodule Atlas.Slack.Installation do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Encrypted.Binary
  alias Atlas.Users.User

  schema "slack_installations" do
    field :app_key, Ecto.Enum, values: [:company], default: :company
    field :team_id, :string
    field :team_name, :string
    field :bot_user_id, :string
    field :bot_token, Binary
    field :scope, :string
    field :installed_at, :utc_datetime
    field :disconnected_at, :utc_datetime

    belongs_to :installed_by_user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(installation, attrs) do
    {installed_by_user_id, attrs} = pop_installed_by_user_id(attrs)

    installation
    |> cast(attrs, [
      :app_key,
      :team_id,
      :team_name,
      :bot_user_id,
      :bot_token,
      :scope,
      :installed_at,
      :disconnected_at
    ])
    |> put_installed_by_user_id(installed_by_user_id)
    |> validate_required([:app_key, :team_id])
    |> unique_constraint(:team_id)
    |> unique_constraint(:app_key)
  end

  def disconnect_changeset(installation) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    change(installation, %{bot_token: nil, disconnected_at: now})
  end

  def connected?(%__MODULE__{bot_token: token, disconnected_at: nil}) when is_binary(token) and token != "", do: true

  def connected?(_installation), do: false

  defp pop_installed_by_user_id(attrs) when is_map(attrs) do
    case Map.pop(attrs, :installed_by_user_id, :missing) do
      {:missing, attrs} -> Map.pop(attrs, "installed_by_user_id", :missing)
      result -> result
    end
  end

  defp put_installed_by_user_id(changeset, :missing), do: changeset
  defp put_installed_by_user_id(changeset, value), do: put_change(changeset, :installed_by_user_id, value)
end
