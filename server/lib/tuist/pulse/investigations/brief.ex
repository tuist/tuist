defmodule Tuist.Pulse.Investigations.Brief do
  @moduledoc """
  A stored version of a symptom's brief for one trigger
  (`Tuist.Pulse.Investigations.Investigation`). Existing versions and their
  steps remain readable; investigation triggers no longer generate them.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Pulse.Investigations.BriefStep
  alias Tuist.Pulse.Investigations.Investigation
  alias Tuist.Pulse.Symptom

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "pulse_briefs" do
    belongs_to :account, Account, type: :integer
    belongs_to :symptom, Symptom, type: Ecto.UUID
    belongs_to :investigation, Investigation, type: UUIDv7
    field :version, :integer
    has_many :steps, BriefStep

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
