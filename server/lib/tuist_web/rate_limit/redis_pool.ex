defmodule TuistWeb.RateLimit.RedisPool do
  @moduledoc false

  def child_spec(name, opts) do
    %{id: name, start: {name, :start_link, [opts]}, type: :supervisor, shutdown: 5000}
  end

  def start_link(name, opts) do
    PartitionSupervisor.start_link(
      child_spec: %{id: Redix, start: {Hammer.Redis, :start_link, [Keyword.delete(opts, :name)]}},
      name: name,
      partitions: 4
    )
  end

  def connection(name) do
    PartitionSupervisor.whereis_name({name, self()})
  rescue
    ArgumentError -> exit({:noproc, {__MODULE__, :connection, [name]}})
  end
end
