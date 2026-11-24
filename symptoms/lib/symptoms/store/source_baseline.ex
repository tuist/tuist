defmodule Symptoms.Store.SourceBaseline do
  @moduledoc """
  A source's latest `baselines/2` result, `:erlang.term_to_binary/1` of
  `%{entity_tuple => baseline}`. See `Symptoms.Baselines`.
  """
  use Ecto.Schema

  @primary_key {:source, :string, autogenerate: false}
  schema "source_baselines" do
    field :data, :binary
    field :entities, :integer
    field :computed_at, :utc_datetime_usec
  end
end
