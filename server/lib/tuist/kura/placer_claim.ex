defmodule Tuist.Kura.PlacerClaim do
  @moduledoc """
  The claim automatic sizing chose for an account. Resolution order is
  operator override, then this, then the plan constant: an operator row hides
  the account from sizing entirely, and clearing one falls back here rather
  than snapping to the plan.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Kura.Regions

  @claim_size_format ~r/\A[1-9][0-9]*(Ki|Mi|Gi|Ti)?\z/
  @claim_size_message "must be a Kubernetes storage quantity like 24Gi"

  schema "kura_placer_claims" do
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

  # Kura carves a flat staging ceiling and one rotation segment out of any claim
  # before sizing the ring, so a claim under the floor leaves nothing to derive
  # a budget from and the runtime sizes one from the whole box instead.
  def validate_claim_size(changeset, field) do
    changeset
    |> validate_format(field, @claim_size_format, message: @claim_size_message)
    |> validate_change(field, fn ^field, value ->
      minimum = Regions.minimum_storage_claim()

      case Regions.parse_storage_quantity(value) do
        {:ok, bytes} ->
          {:ok, minimum_bytes} = Regions.parse_storage_quantity(minimum)
          if bytes >= minimum_bytes, do: [], else: [{field, "must be at least #{minimum}"}]

        :error ->
          []
      end
    end)
  end
end
