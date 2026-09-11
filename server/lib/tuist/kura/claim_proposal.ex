defmodule Tuist.Kura.ClaimProposal do
  @moduledoc """
  A claim change the sizing sweep wants, carried through every rollout phase
  as one record. Resolved proposals are the audit trail.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @statuses [:open, :applied, :dismissed, :superseded]

  @derive {
    Flop.Schema,
    filterable: [:account_id],
    sortable: [:inserted_at],
    default_order: %{order_by: [:inserted_at], order_directions: [:desc]}
  }

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "kura_claim_proposals" do
    field :region, :string
    field :direction, Ecto.Enum, values: [:grow, :shrink]
    field :current_claim_size, :string
    field :recommended_claim_size, :string
    field :evidence, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :resolved_at, :utc_datetime
    field :resolved_by, :string

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [
      :account_id,
      :region,
      :direction,
      :current_claim_size,
      :recommended_claim_size,
      :evidence,
      :status
    ])
    |> validate_required([
      :account_id,
      :region,
      :direction,
      :current_claim_size,
      :recommended_claim_size
    ])
    |> foreign_key_constraint(:account_id)
    |> unique_constraint(:account_id,
      name: :kura_claim_proposals_one_open_per_account,
      message: "already has an open proposal"
    )
  end

  def resolve_changeset(proposal, status, resolved_by) when status in [:applied, :dismissed, :superseded] do
    change(proposal,
      status: status,
      resolved_at: DateTime.truncate(DateTime.utc_now(), :second),
      resolved_by: resolved_by
    )
  end
end
