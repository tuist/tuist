defmodule Tuist.Marketing.Attribution.Landing do
  @moduledoc """
  A visit that arrived on a marketing or documentation page from a campaign
  link on another site or app. Anonymous: no IP address, user agent or identifier.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "marketing_landings" do
    field :id, Ch, type: "UUID"
    field :source, Ch, type: "LowCardinality(String)"
    field :medium, Ch, type: "LowCardinality(String)"
    field :campaign, Ch, type: "String"
    field :content, Ch, type: "String"
    field :term, Ch, type: "String"
    field :referrer_host, Ch, type: "LowCardinality(String)"
    field :path, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
