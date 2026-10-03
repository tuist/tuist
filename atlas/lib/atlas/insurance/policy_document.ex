defmodule Atlas.Insurance.PolicyDocument do
  @moduledoc """
  Join between an insurance policy and an Atlas document with a `kind` label
  so a policy can carry the quote, the bound policy PDF, AVB terms, and any
  renewals or endorsements side by side.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Documents.Document
  alias Atlas.Insurance.Policy
  alias Atlas.Insurance.PolicyDocument

  @kinds ~w(quote policy avb renewal endorsement other)

  schema "insurance_policy_documents" do
    belongs_to :policy, Policy, foreign_key: :policy_id
    belongs_to :document, Document, foreign_key: :document_id

    field :kind, :string, default: "other"
    field :notes, :string

    timestamps()
  end

  def kinds, do: @kinds

  def create_changeset(%PolicyDocument{} = link, attrs) do
    link
    |> cast(attrs, [:policy_id, :document_id, :kind, :notes])
    |> validate_required([:policy_id, :document_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> foreign_key_constraint(:policy_id)
    |> foreign_key_constraint(:document_id)
    |> unique_constraint([:policy_id, :document_id, :kind])
    |> check_constraint(:kind,
      name: :insurance_policy_documents_kind_check,
      message: "is not a valid document kind"
    )
  end
end
