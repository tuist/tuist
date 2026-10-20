defmodule Atlas.Slack.User do
  use Atlas.Schema

  import Ecto.Changeset

  schema "slack_users" do
    field :slack_app, Ecto.Enum, values: [:company, :community], default: :company
    field :slack_user_id, :string
    field :name, :string
    field :real_name, :string
    field :display_name, :string
    field :email, :string
    field :avatar_url, :string
    field :is_bot, :boolean, default: false
    field :is_external, :boolean, default: false
    field :last_synced_at, :utc_datetime

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :slack_user_id,
      :name,
      :real_name,
      :display_name,
      :email,
      :avatar_url,
      :is_bot,
      :is_external,
      :last_synced_at
    ])
    |> validate_required([:slack_app, :slack_user_id])
    |> unique_constraint(:slack_user_id, name: :slack_users_slack_app_slack_user_id_index)
  end

  def best_display_name(%__MODULE__{} = user) do
    [user.display_name, user.real_name, user.name, user.slack_user_id]
    |> Enum.find(user.slack_user_id, &(is_binary(&1) && String.trim(&1) != ""))
  end

  def best_display_name(_), do: nil
end
