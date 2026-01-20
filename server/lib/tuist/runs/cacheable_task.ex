defmodule Tuist.Runs.CacheableTask do
  @moduledoc """
  A cacheable task represents a cache hit or miss for a compilation task in a build run.
  """
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:build_run_id, :type, :status, :key], sortable: [:inserted_at, :key, :description]
  }

  @primary_key false
  schema "cacheable_tasks" do
    field :type, Ch, type: "Enum8('clang' = 0, 'swift' = 1)"
    field :status, Ch, type: "Enum8('hit_local' = 0, 'hit_remote' = 1, 'miss' = 2)"
    field :key, Ch, type: "String"
    field :build_run_id, Ch, type: "UUID"
    field :inserted_at, Ch, type: "DateTime"
    field :read_duration, Ch, type: "Nullable(Float64)"
    field :write_duration, Ch, type: "Nullable(Float64)"
    field :description, Ch, type: "Nullable(String)"
    field :cas_output_node_ids, Ch, type: "Array(String)"
  end

  def changeset(build_run_id, attrs) do
    %__MODULE__{}
    |> Ecto.Changeset.cast(
      %{
        build_run_id: build_run_id,
        type: attrs[:type] && to_string(attrs[:type]),
        status: attrs[:status] && to_string(attrs[:status]),
        key: attrs[:key],
        read_duration: attrs[:read_duration],
        write_duration: attrs[:write_duration],
        description: attrs[:description],
        cas_output_node_ids: attrs[:cas_output_node_ids] || [],
        inserted_at: :second |> DateTime.utc_now() |> DateTime.to_naive()
      },
      [
        :build_run_id,
        :type,
        :status,
        :key,
        :read_duration,
        :write_duration,
        :description,
        :cas_output_node_ids,
        :inserted_at
      ]
    )
    |> Ecto.Changeset.validate_required([:build_run_id, :type, :status, :key])
  end
end
