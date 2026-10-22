defmodule Atlas.Orbit.Message do
  @moduledoc false
  use Atlas.Schema

  alias Atlas.Encrypted.Binary
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Thread
  alias Atlas.Users.User

  @kinds ~w(human agent tool system)
  @tool_statuses ~w(running succeeded failed cancelled)

  schema "orbit_messages" do
    field :kind, :string
    field :body, :string, default: ""
    field :author_name, :string, default: ""
    field :client_id, Ecto.UUID
    field :address_agent, :boolean, default: false
    field :tool_name, :string
    field :tool_status, :string
    field :tool_input, :string, default: ""
    field :tool_output, :string, default: ""
    field :tool_call_key, :string
    field :tool_result, Binary, redact: true
    field :position, :integer
    field :seq, :integer

    belongs_to :thread, Thread
    belongs_to :run, Run
    belongs_to :author, User

    timestamps(type: :utc_datetime_usec)
  end

  def kinds, do: @kinds
  def tool_statuses, do: @tool_statuses
end
