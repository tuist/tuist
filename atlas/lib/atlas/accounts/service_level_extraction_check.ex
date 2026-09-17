defmodule Atlas.Accounts.ServiceLevelExtractionCheck do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.ServiceLevel
  alias Atlas.Documents.Document

  @statuses ~w(pending processing completed no_service_level_found failed)

  def statuses, do: @statuses

  schema "account_service_level_extraction_checks" do
    field :agent_version, :string
    field :document_checksum_sha256, :string
    field :status, :string, default: "pending"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :last_error, :string
    field :result_summary, :string
    field :metadata, :map, default: %{}

    belongs_to :account, Account
    belongs_to :document, Document
    has_many :service_levels, ServiceLevel

    timestamps()
  end

  def changeset(check, attrs) do
    check
    |> cast(attrs, [
      :agent_version,
      :document_checksum_sha256,
      :status,
      :started_at,
      :completed_at,
      :last_error,
      :result_summary,
      :metadata
    ])
    |> validate_required([:account_id, :document_id, :agent_version, :document_checksum_sha256, :status])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:account)
    |> assoc_constraint(:document)
    |> unique_constraint([:document_id, :agent_version])
  end
end
