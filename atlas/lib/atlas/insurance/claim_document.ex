defmodule Atlas.Insurance.ClaimDocument do
  @moduledoc """
  Join between an insurance claim and an Atlas document (damage photos,
  insurer correspondence, repair invoices, adjuster reports).
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Documents.Document
  alias Atlas.Insurance.Claim
  alias Atlas.Insurance.ClaimDocument

  @kinds ~w(photo insurer_correspondence repair_invoice report other)

  schema "insurance_claim_documents" do
    belongs_to :claim, Claim, foreign_key: :claim_id
    belongs_to :document, Document, foreign_key: :document_id

    field :kind, :string, default: "other"
    field :notes, :string

    timestamps()
  end

  def kinds, do: @kinds

  def create_changeset(%ClaimDocument{} = link, attrs) do
    link
    |> cast(attrs, [:claim_id, :document_id, :kind, :notes])
    |> validate_required([:claim_id, :document_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> foreign_key_constraint(:claim_id)
    |> foreign_key_constraint(:document_id)
    |> unique_constraint([:claim_id, :document_id, :kind])
    |> check_constraint(:kind,
      name: :insurance_claim_documents_kind_check,
      message: "is not a valid document kind"
    )
  end
end
