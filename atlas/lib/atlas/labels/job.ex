defmodule Atlas.Labels.Job do
  @moduledoc false
  use Atlas.Schema

  alias Atlas.Labels.Session

  schema "label_jobs" do
    belongs_to :session, Session
    field :action, :string, default: "print"
    field :state, :string, default: "preview-only"
    field :data, :map, default: %{}, redact: true
    field :png, :binary, redact: true
    timestamps(type: :utc_datetime_usec)
  end
end
