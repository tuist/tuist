defmodule Tuist.Runners.CacheVolumes.Volume do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "runner_cache_volumes" do
    belongs_to(:account, Tuist.Accounts.Account)
    field(:repository_id, :integer)
    field(:repository, :string)
    field(:key, :string)
    field(:architecture, :string)
    field(:uid, :integer)
    field(:generation, :integer, default: 1)
    field(:head_id, :binary_id)
    field(:last_used_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime)
  end
end
