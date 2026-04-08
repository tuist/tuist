defmodule Cache.KeyValuePendingReplicationEntry do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "pending_replication_entries" do
    field :json_payload, :string
    field :source_node, :string
    field :source_updated_at, :utc_datetime_usec
    field :last_accessed_at, :utc_datetime_usec
    field :replication_enqueued_at, :utc_datetime_usec
  end
end
