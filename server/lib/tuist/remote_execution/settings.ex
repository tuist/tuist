defmodule Tuist.RemoteExecution.Settings do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:account_id, :id, autogenerate: false}
  schema "remote_execution_settings" do
    field(:max_concurrency, :integer, default: 0)
    field(:warm_pool_size, :integer, default: 0)
    field(:node_names, {:array, :string}, default: [])
    field(:image_tag, :string)
    field(:cas_endpoint, :string)
    field(:executor_endpoint, :string)
    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:max_concurrency, :warm_pool_size, :node_names, :image_tag, :cas_endpoint, :executor_endpoint])
    |> validate_required([:max_concurrency, :warm_pool_size, :image_tag, :cas_endpoint, :executor_endpoint])
    |> validate_number(:max_concurrency, greater_than_or_equal_to: 0, less_than_or_equal_to: 128)
    |> validate_number(:warm_pool_size, greater_than_or_equal_to: 0, less_than_or_equal_to: 8)
    |> validate_length(:node_names, max: 100)
    |> validate_format(:image_tag, ~r/^sha-[a-f0-9]{12,40}$/)
    |> validate_change(:node_names, fn :node_names, names ->
      if Enum.all?(names, &(is_binary(&1) and byte_size(&1) in 1..253)),
        do: [],
        else: [node_names: "invalid node names"]
    end)
    |> validate_change(:cas_endpoint, &validate_endpoint/2)
    |> validate_change(:executor_endpoint, &validate_endpoint/2)
  end

  defp validate_endpoint(field, value) do
    case URI.new(value) do
      {:ok, %URI{scheme: scheme, host: host, userinfo: nil, query: nil, fragment: nil, path: path}}
      when scheme in ["grpc", "grpcs"] and is_binary(host) and host != "" and path in [nil, "", "/"] ->
        []

      _ ->
        [{field, "must be a grpc:// or grpcs:// endpoint without credentials or a path"}]
    end
  end
end
