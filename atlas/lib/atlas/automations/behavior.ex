defmodule Atlas.Automations.Behavior do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Automations.Catalog
  alias Atlas.Users.User

  schema "automation_behaviors" do
    field :name, :string
    field :description, :string
    field :type, :string
    field :configuration, :map, default: %{}
    field :input_schema, :map, default: %{"type" => "object"}
    field :output_schema, :map, default: %{"type" => "object"}
    belongs_to :created_by, User
    timestamps(type: :utc_datetime)
  end

  def changeset(behavior, attrs) do
    behavior
    |> cast(attrs, [:name, :description, :type, :configuration, :input_schema, :output_schema])
    |> validate_required([:name, :type, :configuration, :input_schema, :output_schema])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 2000)
    |> validate_change(:type, fn :type, value ->
      if Catalog.valid_type?(value), do: [], else: [type: "is not a registered behavior reference"]
    end)
  end
end
