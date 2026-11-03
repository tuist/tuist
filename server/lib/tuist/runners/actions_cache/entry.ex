defmodule Tuist.Runners.ActionsCache.Entry do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "runner_actions_cache_entries" do
    belongs_to(:account, Tuist.Accounts.Account)
    field(:repository_id, :integer)
    field(:scope, :string)
    field(:key, :string)
    field(:version, :string)
    field(:size_bytes, :integer)
    field(:node_name, :string)
    field(:committed_at, :utc_datetime_usec)
    field(:stored_at, :utc_datetime_usec)
    field(:last_used_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime)
  end
end
