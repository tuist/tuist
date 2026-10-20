defmodule Atlas.Engineering.Postmortems.Embedding do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Postmortems.Postmortem

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "postmortem_embeddings" do
    belongs_to :postmortem, Postmortem, type: :binary_id
    field :content_hash, :string
    field :status, Ecto.Enum, values: [:pending, :indexed, :failed]
    field :embedding, {:array, :float}
    field :failure_reason, :string
    field :indexed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(embedding, attrs) do
    embedding
    |> cast(attrs, [
      :postmortem_id,
      :content_hash,
      :status,
      :embedding,
      :failure_reason,
      :indexed_at
    ])
    |> validate_required([:postmortem_id, :content_hash, :status])
    |> foreign_key_constraint(:postmortem_id)
    |> unique_constraint(:postmortem_id)
  end
end
