defmodule Tuist.Sandboxes.ProviderEnvironment do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sandbox_provider_environments" do
    belongs_to :account, Tuist.Accounts.Account
    field :external_key, :string
    field :generation, :integer, default: 0
    field :enabled, :boolean, default: false
    timestamps(type: :utc_datetime)
  end
end
