defmodule Atlas.Automations.Approval do
  use Atlas.Schema

  alias Atlas.Automations.Run
  alias Atlas.Users.User

  schema "automation_approvals" do
    belongs_to :run, Run
    belongs_to :reviewer, User
    belongs_to :decided_by, User
    field :step_id, :string
    field :status, :string, default: "pending"
    field :payload, :map
    field :decided_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
