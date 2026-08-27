defmodule Tuist.Kura.PlacementProposal do
  @moduledoc """
  A placement change the placer wants, carried through every rollout phase as
  one record. Resolved proposals are the audit trail.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  # `:correct` is a relocation of a first placement, kept distinct from
  # `:relocate` so it does not spend the quarterly relocation budget: replacing
  # a guess is the system arriving at an answer, not changing its mind.
  @kinds [:relocate, :correct, :expand, :retire]
  @statuses [:open, :applied, :dismissed, :superseded]

  @derive {
    Flop.Schema,
    filterable: [:account_id],
    sortable: [:inserted_at],
    default_order: %{order_by: [:inserted_at], order_directions: [:desc]}
  }

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "kura_placement_proposals" do
    field :kind, Ecto.Enum, values: @kinds
    field :from_region, :string
    field :to_region, :string
    field :evidence, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :resolved_at, :utc_datetime
    field :resolved_by, :string

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [:account_id, :kind, :from_region, :to_region, :evidence, :status])
    |> validate_required([:account_id, :kind])
    |> validate_regions()
    |> foreign_key_constraint(:account_id)
    |> unique_constraint(:account_id,
      name: :kura_placement_proposals_one_open_per_account,
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

  # Each kind names the regions its apply needs and no others, so a proposal
  # cannot describe a transition its apply path has no way to perform.
  defp validate_regions(changeset) do
    case get_field(changeset, :kind) do
      kind when kind in [:relocate, :correct] -> validate_required(changeset, [:from_region, :to_region])
      :expand -> changeset |> validate_required([:to_region]) |> put_change(:from_region, nil)
      :retire -> changeset |> validate_required([:from_region]) |> put_change(:to_region, nil)
      _ -> changeset
    end
  end
end
