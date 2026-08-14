defmodule Tuist.Runners.VolumeMasterOrphan do
  @moduledoc """
  A cache-volume master object a runner uploaded but whose fast-forward promote
  the server rejected — an orphan with no HEAD pointing at it. See
  `Tuist.Runners.VolumeMasterOrphans` for the API and the
  `*_create_runner_volume_master_orphans.exs` migration for the rationale.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  schema "runner_volume_master_orphans" do
    field :volume_name, :string, default: "tuist-cache"
    field :tree_digest, :string

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end
end
