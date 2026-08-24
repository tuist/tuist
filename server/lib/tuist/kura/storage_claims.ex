defmodule Tuist.Kura.StorageClaims do
  @moduledoc """
  Per-account overrides of the plan-derived Kura disk claim.

  `Tuist.Kura.Regions.storage_profile/1` sizes an instance from its account's
  plan, which is the right default and a weak predictor of any individual
  account. Measured across the provisioned account-regions, the spread inside a
  single plan reaches two orders of magnitude in both directions: most accounts
  on the largest plan never fill a fraction of the ring it buys them, while
  accounts on the smallest plan can move more cache per day than the largest
  plan's ring holds. No choice of plan constant serves both ends, so the ends
  get a row here.

  An override replaces the plan's claim wherever the plan's claim would have
  applied — the storage-governed regions — and is read on every path that builds
  an instance's volumes. Writing one also re-pins the account's running
  instances, which is what makes a changed claim reach a cluster at all; see
  `Tuist.Kura.update_storage_claim_override/2`.
  """

  import Ecto.Query, only: [where: 3]

  alias Ecto.Changeset
  alias Tuist.Accounts.Account
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.Regions
  alias Tuist.Kura.StorageClaim
  alias Tuist.Repo

  @form_field :kura_storage_claim_size
  @form_types %{@form_field => :string}

  @doc """
  The claim an account's storage-governed instances are built at: its override
  when it has one, its plan's claim otherwise.
  """
  def effective_claim_size(%Account{} = account) do
    override_for(account) || plan_claim_size(account)
  end

  @doc """
  The claim the account's plan gives it, ignoring any override.

  Shown to an operator as the value an empty override falls back to.
  """
  def plan_claim_size(%Account{} = account) do
    %{claim_size: claim_size} = Regions.storage_profile(AccountPolicies.sizing_plan(account))

    claim_size
  end

  @doc """
  The account's override claim, or `nil` when its plan still decides.
  """
  def override_for(%Account{id: account_id}) do
    case Repo.get_by(StorageClaim, account_id: account_id) do
      nil -> nil
      %StorageClaim{claim_size: claim_size} -> claim_size
    end
  end

  @doc """
  Builds a changeset for the ops override form.

  A blank value is how an override is removed, so the field is deliberately not
  required: clearing it hands the account back to its plan.
  """
  def change_override(%Account{} = account, attrs \\ %{}) do
    {%{@form_field => override_for(account)}, @form_types}
    |> Changeset.cast(attrs, [@form_field])
    |> StorageClaim.validate_claim_size(@form_field)
  end

  @doc """
  The claim the form is asking for: a quantity, or `nil` to drop the override.

  Returns `{:error, changeset}` when the form does not validate, so the caller
  can put it back in front of the operator before anything is written.
  """
  def cast_override(%Account{} = account, attrs) when is_map(attrs) do
    account
    |> change_override(attrs)
    |> Changeset.apply_action(:update)
    |> case do
      {:ok, values} -> {:ok, Map.get(values, @form_field)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Writes `claim_size` as the account's override, or removes the override when it
  is `nil`. Runs inside the caller's transaction.
  """
  def put_override(%Account{id: account_id}, nil) do
    Repo.delete_all(from_account(account_id))
    :ok
  end

  def put_override(%Account{id: account_id}, claim_size) when is_binary(claim_size) do
    %StorageClaim{}
    |> StorageClaim.changeset(%{account_id: account_id, claim_size: claim_size})
    |> Repo.insert(
      on_conflict: {:replace, [:claim_size, :updated_at]},
      conflict_target: :account_id
    )
    |> case do
      {:ok, _claim} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp from_account(account_id) do
    where(StorageClaim, [claim], claim.account_id == ^account_id)
  end
end
