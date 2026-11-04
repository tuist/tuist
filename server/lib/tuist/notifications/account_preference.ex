defmodule Tuist.Notifications.AccountPreference do
  @moduledoc """
  A user's own choice for one notification kind across one account's projects
  (their personal account or an organization). A missing row means enabled.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User

  schema "notification_account_preferences" do
    belongs_to :user, User
    belongs_to :account, Account
    field :kind, :string
    field :enabled, :boolean

    timestamps(type: :utc_datetime)
  end
end
