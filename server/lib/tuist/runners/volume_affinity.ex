defmodule Tuist.Runners.VolumeAffinity do
  @moduledoc """
  Dispatch-time volume affinity record (spec #76): "account X last ran a
  job on host `node_name` at `last_run_at`, so that host likely holds X's
  cache volume." See
  `priv/repo/migrations/20260710190000_create_runner_volume_affinities.exs`
  for the rationale and `Tuist.Runners.VolumeAffinities` for the query API.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  schema "runner_volume_affinities" do
    field :node_name, :string
    field :volume_name, :string, default: "tuist-cache"
    field :last_run_at, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end
end
