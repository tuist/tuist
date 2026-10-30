defmodule Atlas.Automations.ContractCompatibility do
  @moduledoc "Checks frozen operation identities and contracts, independently of runtime/database setup."

  @fields ~w(name version domain handler action source_tool input_schema output_schema permissions effect execution_mode requires_approval)

  def errors(previous, current) do
    old = previous["operations"] || []
    new = current["operations"] || []
    identities = Enum.map(new, &identity/1)
    duplicates = identities -- Enum.uniq(identities)
    duplicate_errors = Enum.map(duplicates, fn {name, version} -> "Duplicate operation #{name}@#{version}." end)

    changed =
      Enum.flat_map(old, fn entry ->
        case Enum.find(new, &(identity(&1) == identity(entry))) do
          nil ->
            ["Removed supported operation #{label(entry)}."]

          candidate ->
            if Map.take(entry, @fields) == Map.take(candidate, @fields),
              do: [],
              else: ["Changed frozen operation #{label(entry)}; preserve it and add a new version."]
        end
      end)

    duplicate_errors ++ changed
  end

  defp identity(entry), do: {entry["name"], entry["version"]}
  defp label(entry), do: "#{entry["name"]}@#{entry["version"]}"
end
