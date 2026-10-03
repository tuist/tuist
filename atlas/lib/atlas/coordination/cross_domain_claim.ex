defmodule Atlas.Coordination.CrossDomainClaim do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account

  @claim_kinds ~w(account_engagement_gap account_delivery_dependency account_renewal_exposure)
  @domains ~w(finance accounts outreach product company)
  @link_precisions ~w(exact verified)
  @sensitivities ~w(public internal restricted)

  schema "cross_domain_claims" do
    field :claim_kind, :string
    field :domains, {:array, :string}, default: []
    field :version, :integer, default: 1
    field :statement, :string
    field :confidence, :decimal
    field :sensitivity, :string
    field :link_precision, :string
    field :link_basis, :string
    field :generated_by_agent, :string
    field :valid_from, :utc_datetime
    field :valid_until, :utc_datetime

    belongs_to :subject_account, Account
    belongs_to :superseded_by, __MODULE__

    timestamps()
  end

  def claim_kinds, do: @claim_kinds

  def changeset(claim, attrs) do
    claim
    |> cast(attrs, [
      :claim_kind,
      :domains,
      :subject_account_id,
      :version,
      :superseded_by_id,
      :statement,
      :confidence,
      :sensitivity,
      :link_precision,
      :link_basis,
      :generated_by_agent,
      :valid_from,
      :valid_until
    ])
    |> normalize_strings()
    |> validate_required([
      :claim_kind,
      :domains,
      :subject_account_id,
      :version,
      :statement,
      :confidence,
      :sensitivity,
      :link_precision,
      :link_basis,
      :generated_by_agent,
      :valid_from
    ])
    |> validate_inclusion(:claim_kind, @claim_kinds)
    |> validate_inclusion(:link_precision, @link_precisions)
    |> validate_inclusion(:sensitivity, @sensitivities)
    |> validate_subset(:domains, @domains)
    |> validate_length(:domains, min: 2)
    |> validate_number(:version, greater_than: 0)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.8, less_than_or_equal_to: 1)
    |> foreign_key_constraint(:subject_account_id)
    |> foreign_key_constraint(:superseded_by_id)
    |> unique_constraint([:claim_kind, :subject_account_id, :version])
    |> check_constraint(:claim_kind, name: :cross_domain_claims_kind_check)
    |> check_constraint(:domains, name: :cross_domain_claims_domains_check)
    |> check_constraint(:link_precision, name: :cross_domain_claims_precision_check)
    |> check_constraint(:confidence, name: :cross_domain_claims_confidence_check)
    |> check_constraint(:sensitivity, name: :cross_domain_claims_sensitivity_check)
  end

  defp normalize_strings(changeset) do
    Enum.reduce(
      [
        :claim_kind,
        :statement,
        :sensitivity,
        :link_precision,
        :link_basis,
        :generated_by_agent
      ],
      changeset,
      fn field, changeset -> update_change(changeset, field, &normalize_string/1) end
    )
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value), do: value
end
