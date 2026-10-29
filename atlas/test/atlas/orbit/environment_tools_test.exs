defmodule Atlas.Orbit.EnvironmentToolsTest do
  use Atlas.DataCase, async: true

  import Atlas.EnvironmentFixtures

  alias Atlas.Environments
  alias Atlas.Orbit.EnvironmentTools
  alias Atlas.Orbit.Tools
  alias Atlas.Repo

  setup do
    environment_fixture()
  end

  test "only root private runs with a frozen project can offer device tools", c do
    assert names(c) == EnvironmentTools.names()
    assert EnvironmentTools.available(c.thread, c.run, Ecto.UUID.generate()) == []
    assert EnvironmentTools.available(%{c.thread | kind: "shared"}, c.run, nil) == []
    assert EnvironmentTools.available(c.thread, %{c.run | project_id: nil}, nil) == []
    assert EnvironmentTools.available(c.thread, %{c.run | environment_id: nil}, nil) == []
    assert {:error, _} = Tools.call(c.run.id, 0, "environment_terminal", %{"command" => "pwd"}, Ecto.UUID.generate())

    assert {:error, _} =
             Tools.call(c.run.id, 0, "environment_read_file", %{"path" => "file", "project_id" => c.project_id})
  end

  test "terminal is an explicit permission, display never adds a tool", c do
    {:ok, _} =
      Environments.register(c.user, c.client_id, c.environment.id, %{
        registration(c.project_id)
        | "terminal" => false,
          "display" => true
      })

    assert names(c) == ~w(environment_list_directory environment_read_file)
    {:ok, _} = Environments.disable(c.user, c.client_id, c.environment.id)
    assert names(c) == []
    assert Enum.all?(Tools.build(Repo.reload!(c.run)), &(not String.starts_with?(&1.name, "environment_")))
  end

  test "terminal shares the native 8,000 UTF-8 byte limit and describes its unsandboxed authority", c do
    assert EnvironmentTools.valid_args?("environment_terminal", %{"command" => String.duplicate("é", 4_000)})
    refute EnvironmentTools.valid_args?("environment_terminal", %{"command" => String.duplicate("x", 8_001)})
    refute EnvironmentTools.valid_args?("environment_terminal", %{"command" => "pwd", "approved" => true})
    refute EnvironmentTools.valid_args?("environment_terminal", %{"command" => "pwd" <> <<0>>})

    terminal = Enum.find(EnvironmentTools.available(c.thread, c.run, nil), &(&1["name"] == "environment_terminal"))
    assert terminal["description"] =~ "as the macOS user"
    assert terminal["description"] =~ "without a folder sandbox"
    assert terminal["description"] =~ "no per-command approval"
    assert terminal["description"] =~ "promptly return"
  end

  defp names(c), do: Enum.map(EnvironmentTools.available(c.thread, c.run, nil), & &1["name"])
end
