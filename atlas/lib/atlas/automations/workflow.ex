defmodule Atlas.Automations.Workflow do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Automations.Revision
  alias Atlas.Users.User

  schema "automation_workflows" do
    field :name, :string
    field :description, :string
    field :language, :string, default: "json"
    field :source, :string
    field :input_schema, :map, default: %{"type" => "object"}
    belongs_to :created_by, User
    belongs_to :published_revision, Revision
    timestamps(type: :utc_datetime)
  end

  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:name, :description, :language, :source, :input_schema])
    |> validate_required([:name, :language, :source, :input_schema])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 2000)
    |> validate_length(:source, max: 65_536)
    |> validate_inclusion(:language, ["json", "javascript"])
  end
end
