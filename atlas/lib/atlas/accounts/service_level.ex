defmodule Atlas.Accounts.ServiceLevel do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Documents.Document

  @categories ~w(availability response_time resolution_time support_hours maintenance backup data_retention security other)

  def categories, do: @categories

  schema "account_service_levels" do
    field :name, :string
    field :category, :string
    field :target, :string
    field :target_value, :decimal
    field :target_unit, :string
    field :measurement_window, :string
    field :applies_from, :date
    field :applies_until, :date
    field :service_credit, :string
    field :exclusions, :string
    field :source_page, :integer
    field :source_excerpt, :string
    field :confidence, :decimal
    field :metadata, :map, default: %{}

    belongs_to :account, Account
    belongs_to :document, Document

    belongs_to :extraction_check, ServiceLevelExtractionCheck, foreign_key: :service_level_extraction_check_id

    timestamps()
  end

  def changeset(service_level, attrs) do
    service_level
    |> cast(attrs, [
      :name,
      :category,
      :target,
      :target_value,
      :target_unit,
      :measurement_window,
      :applies_from,
      :applies_until,
      :service_credit,
      :exclusions,
      :source_page,
      :source_excerpt,
      :confidence,
      :metadata
    ])
    |> validate_required([:account_id, :document_id, :service_level_extraction_check_id, :name, :category, :target])
    |> validate_inclusion(:category, @categories)
    |> validate_number(:source_page, greater_than: 0)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> assoc_constraint(:account)
    |> assoc_constraint(:document)
    |> assoc_constraint(:extraction_check)
  end
end
