defmodule Atlas.Documents.Correspondent do
  @moduledoc """
  The person or organization a document is from or addressed to.

  Inferred by the classifier during ingest and normalized so documents can be
  filtered and counted by correspondent, like Paperless.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Documents.Document

  schema "document_correspondents" do
    field :name, :string

    has_many :documents, Document

    timestamps()
  end

  def changeset(correspondent, attrs) do
    correspondent
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> unique_constraint(:name, name: :document_correspondents_lower_name_index)
  end
end
