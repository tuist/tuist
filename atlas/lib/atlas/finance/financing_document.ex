defmodule Atlas.Finance.FinancingDocument do
  @moduledoc """
  A typed relationship between a financing arrangement and a document.

  The kind keeps the supplier-side commercial agreement distinct from the
  financing agreement, guarantees, invoices, acceptance records, schedules,
  and later amendments while connecting all of them to the same assets through
  the parent financing.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Documents.Document
  alias Atlas.Finance.Financing
  alias Atlas.Finance.FinancingDocument

  @kinds ~w(
    supplier_contract
    financing_agreement
    guarantee
    invoice
    acceptance
    schedule
    amendment
    other
  )

  schema "financing_documents" do
    belongs_to :financing, Financing
    belongs_to :document, Document

    field :kind, :string, default: "other"
    field :notes, :string

    timestamps()
  end

  def kinds, do: @kinds

  def create_changeset(%FinancingDocument{} = link, attrs) do
    link
    |> cast(attrs, [:financing_id, :document_id, :kind, :notes])
    |> validate_required([:financing_id, :document_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> foreign_key_constraint(:financing_id)
    |> foreign_key_constraint(:document_id)
    |> unique_constraint([:financing_id, :document_id, :kind])
    |> check_constraint(:kind,
      name: :financing_documents_kind_check,
      message: "is not a valid document kind"
    )
  end
end
