defmodule Atlas.Automations.DomainRegistryTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Authorization
  alias Atlas.Automations.Catalog
  alias Atlas.Automations.Contract
  alias Atlas.Automations.ContractCompatibility
  alias Atlas.Automations.DomainRegistry
  alias Atlas.Automations.DomainRuntime
  alias Atlas.Automations.LocalOperations
  alias Atlas.MCP.Server

  test "every domain is classified and every MCP operation is explicitly included or excluded" do
    entries = DomainRegistry.entries()
    assert length(entries) > 200
    assert length(entries) == length(Enum.uniq_by(entries, &{&1["name"], &1["version"]}))
    policies = Enum.map(DomainRegistry.domain_policies(), & &1["domain"])
    assert Authorization.area_slugs() -- policies == []
    assert Authorization.area_slugs() -- Enum.map(Catalog.types(), & &1.domain) == []
    supported = entries |> Enum.map(& &1["source_tool"]) |> Enum.reject(&is_nil/1)
    classified = Enum.sort(supported ++ Map.keys(DomainRegistry.exclusions()))
    assert classified == Enum.sort(Enum.map(Server.static_tools(), & &1.name()))
    assert Enum.all?(DomainRegistry.exclusions(), fn {_name, reason} -> byte_size(reason) > 20 end)
  end

  test "frozen adapters and local contracts cannot silently drift" do
    local = Map.new(LocalOperations.contracts(), &{&1["name"], &1})

    for entry <- DomainRegistry.entries() do
      assert :ok = DomainRegistry.validate_entry(entry)
      assert entry["permissions"] -- Authorization.all_scopes() == []
      assert entry["effect"] in ~w(read write)
      assert entry["execution_mode"] == "local_transaction"
      assert is_boolean(entry["requires_approval"])

      if entry["source_tool"] do
        module = DomainRegistry.adapter(entry)
        assert module.name() == entry["source_tool"]
        assert entry["input_schema"] == Map.put(module.input_schema(), "additionalProperties", false)
        assert entry["output_schema"] == module.output_schema()
        assert Server.workflow_tool_scopes(module) -- entry["permissions"] == []
      else
        assert entry == local[entry["name"]]
      end

      assert {:error, _} = Contract.validate(entry["input_schema"], %{"__unexpected_argument__" => true})
    end
  end

  test "automation grants never imply another domain's permissions" do
    actor = insert_user!(%{scopes: ["automation:write"]})

    for entry <- DomainRegistry.entries(), entry["permissions"] != [] do
      assert {:error, _} = DomainRuntime.authorize(entry, actor)
      assert {:error, _} = DomainRuntime.authorize(entry, nil)
    end
  end

  test "version lookup is exact and snapshots reject contract/configuration tampering" do
    actor = insert_user!(%{scopes: ["automation:write", "notes:write"]})
    {:ok, entry} = DomainRegistry.fetch("notes.create@1")
    snapshot = DomainRegistry.snapshot(entry)
    assert {:ok, ^snapshot} = Catalog.builtin("notes.create")
    assert {:error, _} = Catalog.builtin("notes.create@999")
    assert {:error, _} = Catalog.execute(%{snapshot | "version" => 999}, %{}, actor)
    assert {:error, _} = Catalog.execute(%{snapshot | "input_schema" => %{"type" => "object"}}, %{}, actor)
    assert {:error, _} = Catalog.execute(%{snapshot | "configuration" => %{"host_module" => "anything"}}, %{}, actor)
    {:ok, old} = Catalog.builtin("tasks.create")
    {:ok, new} = Catalog.builtin("tasks.create@2")
    assert old["version"] == 1
    assert new["version"] == 2
    assert old["output_schema"] != new["output_schema"]
  end

  test "release compatibility forbids changing/removing supported contracts but allows a new version" do
    entry = hd(DomainRegistry.entries())
    previous = %{"operations" => [entry]}
    changed = Map.put(entry, "input_schema", %{"type" => "object"})
    assert [_] = ContractCompatibility.errors(previous, %{"operations" => [changed]})
    assert [_] = ContractCompatibility.errors(previous, %{"operations" => []})
    assert [] = ContractCompatibility.errors(previous, %{"operations" => [entry, Map.put(changed, "version", 2)]})
    assert [_] = ContractCompatibility.errors(previous, %{"operations" => [entry, entry]})
  end
end
