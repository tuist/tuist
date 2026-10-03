defmodule Atlas.Documents.DocumentType do
  @moduledoc """
  A normalized document type (contract, invoice, policy, ...), the Paperless
  equivalent of a document type. Replaces the old free-text `category` string.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Documents.Document

  schema "document_types" do
    field :name, :string

    has_many :documents, Document

    timestamps()
  end

  def changeset(document_type, attrs) do
    document_type
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> unique_constraint(:name, name: :document_types_lower_name_index)
  end
end
