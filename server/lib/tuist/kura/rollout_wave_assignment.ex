defmodule Tuist.Kura.RolloutWaveAssignment do
  @moduledoc """
  One account's wave in a rollout, frozen at rollout creation.

  Wave assignment is grouped by account so all of an account's servers
  update in the same wave: an account mesh spans regions (plus self-hosted
  peers), and splitting it across waves would hold cross-version skew open
  inside one mesh for the whole rollout instead of one wave.

  Wave 0 is the canary (Tuist-owned accounts only); waves 1..3 order
  accounts by recent Kura usage ascending, so lower-traffic accounts absorb
  earlier exposure.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Kura.Rollout

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_rollout_wave_assignments" do
    field :wave, :integer

    belongs_to :rollout, Rollout, foreign_key: :kura_rollout_id, type: :binary_id
    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def create_changeset(assignment \\ %__MODULE__{}, attrs) do
    assignment
    |> cast(attrs, [:kura_rollout_id, :account_id, :wave])
    |> validate_required([:kura_rollout_id, :account_id, :wave])
    |> validate_number(:wave, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:kura_rollout_id)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:kura_rollout_id, :account_id])
  end
end
