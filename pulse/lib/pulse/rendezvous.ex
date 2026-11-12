defmodule Pulse.Rendezvous do
  @moduledoc """
  Stateless rendezvous hashing for work identified by a list of binary fields.

  Membership and eligibility belong to the caller. Equal membership views select
  the same node regardless of order or duplicate entries. Empty views have no
  owner. This is an assignment optimization, never an exclusive lease.

  Tenant work uses `[purpose, tenant, signal]`; future rule evaluation can include
  the rule identifier as another field without introducing a second algorithm.
  """

  @spec owner([binary()], [node()]) :: node() | nil
  def owner(key, members) do
    members
    |> Enum.uniq()
    |> Enum.max_by(&score(key, &1), fn -> nil end)
  end

  # Length prefixes distinguish field boundaries; node name breaks digest ties.
  defp score(key, member) do
    name = Atom.to_string(member)
    fields = Enum.map(key ++ [name], fn field -> [<<byte_size(field)::unsigned-big-32>>, field] end)
    {:crypto.hash(:sha256, fields), name}
  end
end
