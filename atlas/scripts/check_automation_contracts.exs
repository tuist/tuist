# No application, database, dependencies or credentials are needed by this release gate.
# Extract the base manifest with git before invoking this script; use an empty
# operations list when the base predates the registry.
Code.require_file("../lib/atlas/automations/contract_compatibility.ex", __DIR__)
[previous_path] = System.argv()
current_path = Path.expand("../priv/automation/contracts/v1.json", __DIR__)
previous = previous_path |> File.read!() |> JSON.decode!()
current = current_path |> File.read!() |> JSON.decode!()

case Atlas.Automations.ContractCompatibility.errors(previous, current) do
  [] ->
    IO.puts("Automation contracts preserve all operation versions in the base manifest.")

  errors ->
    Enum.each(errors, &IO.puts(:stderr, &1))
    System.halt(1)
end
