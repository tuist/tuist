defmodule Atlas.Documents.DocumentPage do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Documents.Document

  # Page chunking is offset-based and ordered by the query. Flop owns the
  # pagination metadata exposed by document page readers.
  @derive {Flop.Schema, filterable: [], sortable: [:page_number], default_limit: 10, max_limit: 25}

  schema "document_pages" do
    field :page_number, :integer
    field :content, :string
    field :embedding_model, :string
    field :embedded_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :document, Document

    timestamps()
  end

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:document_id, :page_number, :content, :embedding_model, :embedded_at, :metadata])
    |> validate_required([:document_id, :page_number, :content])
    |> validate_number(:page_number, greater_than: 0)
    |> unique_constraint([:document_id, :page_number])
  end
end
