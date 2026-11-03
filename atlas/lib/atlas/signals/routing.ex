defmodule Atlas.Signals.Routing do
  @moduledoc "Explainable routing from explicitly shared business profiles, never private Pip descriptions."
  import Ecto.Query

  alias Atlas.Orbit.Access
  alias Atlas.Repo
  alias Atlas.Users.User

  def candidates(source, envelope) do
    from(user in User, where: user.id in ^source.reader_ids and user.id != ^source.owner_id, order_by: user.id)
    |> Repo.all()
    |> Enum.filter(&Access.holds_all?(&1, source.required_scopes))
    |> Enum.flat_map(fn user ->
      profile = user.business_profile

      if profile["enabled"] == true do
        subjects = Enum.filter(profile["responsibilities"] || [], &(&1 in (envelope["subjects"] || [])))
        expertise = matches(profile["expertise"], envelope["topics"])
        roles = matches([profile["role"]], source.routing_roles)

        cond do
          subjects != [] -> [candidate(user, 3, "responsibility", subjects)]
          expertise != [] -> [candidate(user, 2, "expertise", expertise)]
          roles != [] -> [candidate(user, 1, "business_role", roles)]
          true -> []
        end
      else
        []
      end
    end)
    |> Enum.sort_by(&{-&1.rank, &1.id})
    |> Enum.take(3)
  end

  defp candidate(user, rank, reason, matches),
    do: %{id: user.id, name: user.name, rank: rank, reason: reason, matches: Enum.take(matches, 3)}

  defp matches(left, right) do
    left = left |> List.wrap() |> Enum.filter(&is_binary/1) |> Enum.map(&String.downcase/1)
    right = right |> List.wrap() |> Enum.filter(&is_binary/1) |> Enum.map(&String.downcase/1)
    left |> Enum.filter(&(&1 in right)) |> Enum.uniq() |> Enum.sort()
  end
end
