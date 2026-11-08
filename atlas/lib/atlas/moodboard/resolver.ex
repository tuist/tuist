defmodule Atlas.Moodboard.Resolver do
  @moduledoc false

  def resolve(host) do
    task =
      Task.async(fn ->
        for family <- [:inet, :inet6],
            {:ok, addresses} <- [:inet.getaddrs(String.to_charlist(host), family)],
            address <- addresses,
            do: address
      end)

    case Task.yield(task, 2_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, [_ | _] = addresses} -> {:ok, Enum.uniq(addresses)}
      _ -> {:error, :dns_unavailable}
    end
  end
end
