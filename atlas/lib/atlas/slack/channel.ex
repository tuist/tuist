defmodule Atlas.Slack.Channel do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Slack.Message

  schema "slack_channels" do
    field :slack_app, Ecto.Enum, values: [:company, :community], default: :company
    field :channel_id, :string
    field :channel_name, :string
    field :is_shared, :boolean, default: false
    field :is_ext_shared, :boolean, default: false

    belongs_to :account, Account
    has_many :messages, Message, foreign_key: :slack_channel_id

    timestamps()
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:channel_id, :channel_name, :is_shared, :is_ext_shared])
    |> validate_required([:slack_app, :channel_id, :channel_name])
    |> unique_constraint(:channel_id, name: :slack_channels_slack_app_channel_id_index)
  end

  @doc """
  Changeset that updates only the `account_id` foreign key. Used by the
  account-link flow so the FK never goes through `cast` and cannot be
  set from arbitrary user params.
  """
  def account_changeset(channel, account_id) do
    Ecto.Changeset.change(channel, account_id: account_id)
  end
end
