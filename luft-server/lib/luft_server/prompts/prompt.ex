defmodule LuftServer.Prompts.Prompt do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "organization_prompts" do
    field :organization_id, :integer
    field :name, :string
    field :title, :string
    field :body, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(prompt, attrs) do
    prompt
    |> cast(attrs, [:title, :body])
    |> validate_required([:title, :body])
    |> validate_length(:title, max: 80)
    |> validate_length(:body, max: 12_000, count: :bytes)
    |> unique_constraint([:organization_id, :name])
  end
end
