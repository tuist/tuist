defmodule Atlas.Documents.Tag do
  @moduledoc """
  A colored label attached to documents. Inferred by the classifier during
  ingest and shared across documents, like Paperless tags.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Documents.Document

  # Colors map onto the Noora badge palette so tags render within the design system.
  @colors ~w(success warning attention information focus primary secondary destructive)

  schema "document_tags" do
    field :name, :string
    field :color, :string, default: "neutral"

    many_to_many :documents, Document, join_through: "documents_tags"

    timestamps()
  end

  def colors, do: @colors

  @doc """
  Picks a stable color from the palette based on the tag name, so a given tag
  always renders the same color without storing a hand-picked value.
  """
  def color_for(name) when is_binary(name) do
    index = :erlang.phash2(String.downcase(String.trim(name)), length(@colors))
    Enum.at(@colors, index)
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :color])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :color])
    |> validate_inclusion(:color, @colors ++ ["neutral"])
    |> unique_constraint(:name, name: :document_tags_lower_name_index)
  end
end
