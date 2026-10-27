defmodule Tuist.Entire.InstallRequest do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:state, :string, autogenerate: false}
  schema "ci_install_requests" do
    belongs_to :account, Tuist.Accounts.Account
    field :expires_at, :utc_datetime
  end
end
