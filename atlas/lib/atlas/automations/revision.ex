defmodule Atlas.Automations.Revision do
  use Atlas.Schema

  alias Atlas.Automations.Workflow
  alias Atlas.Users.User

  schema "automation_revisions" do
    belongs_to :workflow, Workflow
    belongs_to :published_by, User
    field :number, :integer
    field :plan, :map
    field :source, :string
    field :language, :string
    field :input_schema, :map
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
