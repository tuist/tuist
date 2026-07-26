defmodule Tuist.Runners.VolumeHead do
  @moduledoc """
  The current canonical version of an account's cache volume: "account X's
  warm set is at generation N with inventory digest D". See
  `Tuist.Runners.VolumeHeads` for the API and
  `priv/repo/migrations/*_create_runner_volume_heads.exs` for the rationale.

  A host's on-disk master is only as fresh as the last job that ran that
  account there; the HEAD is the single cross-host reference point every host
  converges toward, so a job materializes a near-current warm set instead of
  whatever that host last ran. Last-writer-wins, exactly like the volume's
  own promote semantics.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  schema "runner_volume_heads" do
    field :volume_name, :string, default: "tuist-cache"
    # Monotonic version counter, bumped on every promote report. Cheap "am I
    # behind" check; the digest is the authoritative content comparison.
    field :generation, :integer, default: 0
    # Inventory digest of the account's current warm set (the sorted cache
    # entry-name hash the guest already computes for its dirty marker).
    field :tree_digest, :string
    # Host that published this HEAD, for observability only.
    field :node_name, :string

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end
end
