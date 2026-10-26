defmodule Atlas.Automations.InterfacesTest do
  use Atlas.MCP.ToolCase
  use Mimic

  import Atlas.AutomationsFixtures

  alias Atlas.Automations
  alias Atlas.Automations.Contract
  alias Atlas.Automations.Interface
  alias Atlas.Automations.Interfaces
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias AtlasWeb.AutomationController
  alias AtlasWeb.Router

  test "every operation has a unique routed API, registered MCP tool and the same schema" do
    stub(Proxy, :list_hoisted_tools, fn _ -> [] end)
    actor = insert_user!(%{scopes: ["automation:write"]})
    result = Server.handle_message(mcp_conn(actor), %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
    names = Enum.map(result["result"]["tools"], & &1["name"])
    operations = Interfaces.operations()
    assert length(operations) == length(Enum.uniq_by(operations, & &1.operation))
    assert length(operations) == length(Enum.uniq_by(operations, &{&1.method, &1.path}))

    for operation <- operations do
      assert operation.access == if(operation.method == :get, do: :read, else: :write)
      assert operation.mcp in names
      assert operation.tool.name() == operation.mcp
      assert operation.tool.input_schema() == Interface.schema(operation.operation)
      assert :ok = Contract.validate_schema(operation.tool.input_schema())
      path = String.replace(operation.path, ~r/:[a-z_]+/, Ecto.UUID.generate())

      info =
        Phoenix.Router.route_info(Router, operation.method |> Atom.to_string() |> String.upcase(), path, "localhost")

      assert info.plug == AutomationController
      assert info.plug_opts == operation.operation
    end
  end

  test "all primitive collections have API reads and declared lifecycle rules" do
    for primitive <- Interfaces.primitives() do
      info = Phoenix.Router.route_info(Router, "GET", "/api/automation/#{primitive.collection}", "localhost")
      assert info.plug == AutomationController
      assert info.plug_opts in [:catalog, :list]
      assert primitive.lifecycle != ""

      if primitive.mutable do
        for {method, suffix} <- [
              {"POST", ""},
              {"PATCH", "/#{Ecto.UUID.generate()}"},
              {"DELETE", "/#{Ecto.UUID.generate()}"}
            ] do
          mutation =
            Phoenix.Router.route_info(Router, method, "/api/automation/#{primitive.collection}" <> suffix, "localhost")

          assert mutation.plug == AutomationController
          refute mutation.plug_opts == :unsupported
          assert Interfaces.access(mutation.plug_opts) == :write
        end
      end
    end
  end

  test "every declared primitive has functioning list/detail dispatch, not just a matching route" do
    actor = insert_user!(%{scopes: ["automation:write"]})
    {workflow, _} = workflow_fixture(actor)
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})

    for primitive <- Interfaces.primitives() do
      args = %{"kind" => primitive.kind, "workflow_id" => workflow.id, "run_id" => run.id}
      assert {:ok, %{data: %{items: items}}} = Interface.execute(:list, actor, args)
      assert is_list(items)
      id = if primitive.kind == "types", do: "not-a-registered-type", else: Ecto.UUID.generate()
      assert {:error, :not_found} = Interface.execute(:get_record, actor, %{"kind" => primitive.kind, "id" => id})
    end
  end

  test "the shared boundary denies every operation without its current grant" do
    unprivileged = insert_user!(%{})
    reader = insert_user!(%{scopes: ["automation:read"]})

    for operation <- Interfaces.operations() do
      assert {:error, :forbidden} = Interface.execute(operation.operation, unprivileged, %{})

      if operation.access == :write do
        assert {:error, :forbidden} = Interface.execute(operation.operation, reader, %{})
      end
    end
  end
end
