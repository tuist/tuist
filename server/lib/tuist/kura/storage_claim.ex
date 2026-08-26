defmodule Tuist.Kura.StorageClaim do
  @moduledoc """
  A per-account override of the plan-derived Kura disk claim.

  A plan predicts an account's cache working set poorly in both directions, so
  the ladder in `Tuist.Kura.Regions` cannot serve every account on it. A row
  here replaces the plan's claim for every storage-governed instance the account
  owns; no row means the plan's claim still applies.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Kura.Regions

  @claim_size_format ~r/\A[1-9][0-9]*(Ki|Mi|Gi|Ti)?\z/
  @claim_size_message "must be a Kubernetes storage quantity like 24Gi"

  schema "kura_storage_claims" do
    field :claim_size, :string

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(claim, attrs) do
    claim
    |> cast(attrs, [:account_id, :claim_size])
    |> validate_required([:account_id, :claim_size])
    |> validate_claim_size(:claim_size)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint(:account_id)
  end

  @doc """
  Validates that `field` holds a storage quantity at or above the floor every
  claim shares.

  The floor is set by fixed overhead rather than by how much cache an account
  needs: Kura carves a flat staging ceiling and one rotation segment out of any
  claim before it sizes the ring, so a claim below the floor leaves too little
  to derive a ring budget from at all and the runtime sizes one from the whole
  box instead. An override is the one claim a human types, so it is also the one
  that can land under the floor by hand.

  Shared with the ops form, which validates the same bound on a schemaless
  changeset before anything is written.
  """
  def validate_claim_size(changeset, field) do
    changeset
    |> validate_format(field, @claim_size_format, message: @claim_size_message)
    |> validate_change(field, fn ^field, value ->
      minimum = Regions.minimum_storage_claim()

      case Regions.parse_storage_quantity(value) do
        {:ok, bytes} ->
          {:ok, minimum_bytes} = Regions.parse_storage_quantity(minimum)

          if bytes >= minimum_bytes,
            do: [],
            else: [{field, "must be at least #{minimum}"}]

        :error ->
          []
      end
    end)
  end
end
