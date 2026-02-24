defmodule Tuist.Registry.DownloadEvent do
  @moduledoc """
  Ecto schema for registry download events stored in ClickHouse.
  """
  use Ecto.Schema

  @primary_key false
  schema "registry_download_events" do
    field :id, Ch, type: "UUID"
    field :scope, Ch, type: "String"
    field :name, Ch, type: "String"
    field :version, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime"
  end
end
