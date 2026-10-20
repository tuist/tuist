defmodule Atlas.Accounts.IncidentContact do
  @moduledoc """
  A security-incident notification contact extracted from an account document.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Documents.Document

  schema "account_incident_contacts" do
    field :email, :string
    field :full_name, :string
    field :role, :string
    field :source_page, :integer
    field :source_excerpt, :string
    field :confidence, :decimal
    field :metadata, :map, default: %{}

    belongs_to :account, Account
    belongs_to :document, Document

    belongs_to :extraction_check, ServiceLevelExtractionCheck, foreign_key: :service_level_extraction_check_id

    timestamps()
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :email,
      :full_name,
      :role,
      :source_page,
      :source_excerpt,
      :confidence,
      :metadata
    ])
    |> normalize_email()
    |> normalize_optional_fields()
    |> validate_required([:account_id, :document_id, :service_level_extraction_check_id, :email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_number(:source_page, greater_than: 0)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> assoc_constraint(:account)
    |> assoc_constraint(:document)
    |> assoc_constraint(:extraction_check)
    |> unique_constraint([:document_id, :email])
  end

  defp normalize_email(changeset) do
    update_change(changeset, :email, fn
      nil ->
        nil

      email ->
        email
        |> String.trim()
        |> String.downcase()
    end)
  end

  defp normalize_optional_fields(changeset) do
    Enum.reduce([:full_name, :role, :source_excerpt], changeset, fn field, changeset ->
      update_change(changeset, field, &normalize_optional_string/1)
    end)
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end
end
