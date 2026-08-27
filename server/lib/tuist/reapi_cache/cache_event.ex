defmodule Tuist.ReapiCache.CacheEvent do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "reapi_cache_events" do
    field :id, Ch, type: "UUID"
    field :client_kind, Ch, type: "LowCardinality(String)"
    field :operation, Ch, type: "Enum8('action_cache' = 0)"
    field :outcome, Ch, type: "Enum8('hit' = 0, 'miss' = 1, 'write' = 2)"
    field :action_digest, Ch, type: "String"
    field :size, Ch, type: "UInt64"
    field :duration_ms, Ch, type: "UInt64"
    field :invocation_id, Ch, type: "String"
    field :action_mnemonic, Ch, type: "String"
    field :target_label, Ch, type: "String"
    field :configuration_id, Ch, type: "String"
    field :project_id, Ch, type: "Int64"
    field :account_handle, Ch, type: "String"
    field :project_handle, Ch, type: "String"
    field :cache_endpoint, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime"
  end
end
