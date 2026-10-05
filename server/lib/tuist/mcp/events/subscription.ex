defmodule Tuist.MCP.Events.Subscription do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project
  alias Tuist.Vault.Binary

  @primary_key {:id, :string, autogenerate: false}
  schema "mcp_event_subscriptions" do
    belongs_to :user, User
    belongs_to :account_token, AccountToken, type: Ecto.UUID
    field :oauth_client_id, Ecto.UUID
    belongs_to :account, Account
    belongs_to :project, Project
    field :event_name, :string
    field :callback_url, Binary
    field :signing_secret, Binary
    field :refresh_before, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :id,
      :user_id,
      :account_token_id,
      :oauth_client_id,
      :account_id,
      :project_id,
      :event_name,
      :callback_url,
      :signing_secret,
      :refresh_before
    ])
    |> validate_required([
      :id,
      :user_id,
      :account_id,
      :event_name,
      :callback_url,
      :signing_secret,
      :refresh_before
    ])
  end
end
