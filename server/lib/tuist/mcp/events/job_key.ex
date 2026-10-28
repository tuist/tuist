defmodule Tuist.MCP.Events.JobKey do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "mcp_event_job_keys" do
    field :inserted_at, :utc_datetime
  end
end
