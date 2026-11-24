defmodule Tuist.Pulse.Investigations.Investigation do
  @moduledoc """
  One investigation request on a symptom at board or page tier. Recording
  the request does not generate a brief or steps. Symptoms merged into a root
  join the root's latest one through `member_symptom_ids`. `change_seq` orders
  it among the state changes the evaluator reads back as `investigations`.
  See `Tuist.Pulse.Investigations`.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Pulse.Symptom

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "pulse_investigations" do
    belongs_to :account, Account, type: :integer
    belongs_to :symptom, Symptom, type: Ecto.UUID
    field :member_symptom_ids, {:array, Ecto.UUID}, default: []

    field :trigger, Ecto.Enum, values: [:opened_page, :escalated_page, :reopened, :board_top_two, :person, :brief]

    field :trigger_seq, :integer
    field :request_id, Ecto.UUID
    belongs_to :requested_by, User, type: :integer
    field :change_seq, :integer

    timestamps(type: :utc_datetime)
  end
end
