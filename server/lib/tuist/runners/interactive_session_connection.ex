defmodule Tuist.Runners.InteractiveSessionConnection do
  @moduledoc """
  Browser WebSocket connection tracked for a runner interactive session.

  Rows are transport lifecycle markers only. They let the server keep a VNC
  grant open while any browser is still connected, without storing VNC
  credentials or browser session tokens.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Runners.InteractiveSession

  schema "runner_interactive_session_connections" do
    field :connection_id, :string
    field :connected_at, :utc_datetime
    field :disconnected_at, :utc_datetime

    belongs_to :interactive_session, InteractiveSession

    timestamps(type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:interactive_session_id, :connection_id, :connected_at, :disconnected_at])
    |> validate_required([:interactive_session_id, :connection_id, :connected_at])
    |> foreign_key_constraint(:interactive_session_id)
    |> unique_constraint([:interactive_session_id, :connection_id],
      name: :runner_interactive_session_connections_session_connection_index
    )
  end
end
