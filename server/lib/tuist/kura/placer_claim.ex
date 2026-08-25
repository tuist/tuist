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
  alias Tuist.Kura.StorageClaim

  schema "kura_placer_claims" do
    field :claim_size, :string

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(claim, attrs) do
    claim
    |> cast(attrs, [:account_id, :claim_size])
    |> validate_required([:account_id, :claim_size])
    |> StorageClaim.validate_claim_size(:claim_size)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint(:account_id)
  end
end
