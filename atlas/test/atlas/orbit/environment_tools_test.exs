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
    assert names(c) == ~w(environment_list_directory environment_read_file environment_terminal)
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

  test "legacy native terminal retains its byte limit and explicit execution authority", c do
    assert EnvironmentTools.valid_args?("environment_terminal", %{"command" => String.duplicate("é", 4_000)})
    refute EnvironmentTools.valid_args?("environment_terminal", %{"command" => String.duplicate("x", 8_001)})
    refute EnvironmentTools.valid_args?("environment_terminal", %{"command" => "pwd", "approved" => true})
    refute EnvironmentTools.valid_args?("environment_terminal", %{"command" => "pwd" <> <<0>>})

    terminal = Enum.find(EnvironmentTools.available(c.thread, c.run, nil), &(&1["name"] == "environment_terminal"))
    assert terminal["description"] =~ "macOS user"
    assert terminal["description"] =~ "without a folder sandbox"
    assert terminal["description"] =~ "no per-command approval"
    assert terminal["description"] =~ "promptly return"
  end

  test "hosted environments retain legacy tools and their Linux execution contract", c do
    c.environment
    |> Ecto.Changeset.change(
      provider: "tuist",
      provider_state: "ready",
      projects: [%{"id" => c.project_id, "name" => "Workspace", "coding" => true}]
    )
    |> Repo.update!()

    assert names(c) == ~w(environment_list_directory environment_read_file environment_terminal)
    terminal = Enum.find(EnvironmentTools.available(c.thread, c.run, nil), &(&1["name"] == "environment_terminal"))
    assert terminal["description"] =~ "Linux"
    assert terminal["description"] =~ "/workspace"
    assert terminal["description"] =~ "600 seconds"
    refute terminal["description"] =~ "macOS"
  end

  test "coding requires an advertised Git project and terminal consent and never reaches children", c do
    params = %{registration(c.project_id) | "projects" => [%{"id" => c.project_id, "name" => "Code", "coding" => true}]}
    assert {:ok, _} = Environments.register(c.user, c.client_id, c.environment.id, params)
    assert names(c) == ~w(read bash edit write)
    assert EnvironmentTools.available(c.thread, c.run, Ecto.UUID.generate()) == []
    assert EnvironmentTools.available(%{c.thread | kind: "shared"}, c.run, nil) == []

    assert {:error, _} =
             Tools.call(c.run.id, 0, "write", %{"path" => "file", "content" => "text"}, Ecto.UUID.generate())

    assert {:ok, _} = Environments.register(c.user, c.client_id, c.environment.id, %{params | "terminal" => false})
    assert names(c) == ~w(environment_list_directory environment_read_file)
    assert {:error, _} = Tools.call(c.run.id, 0, "read", %{"path" => "README.md"})
  end

  test "coding arguments are bounded and cannot override frozen thread or project identity" do
    assert EnvironmentTools.valid_args?("write", %{"path" => "empty", "content" => ""})
    assert EnvironmentTools.valid_args?("read", %{"path" => "file", "offset" => 2, "limit" => 1})
    assert EnvironmentTools.valid_args?("edit", %{"path" => "file", "edits" => [%{"oldText" => "é", "newText" => ""}]})
    assert EnvironmentTools.valid_args?("bash", %{"command" => "pwd", "timeout" => 1_800})

    for {tool, args} <- [
          {"read", %{"path" => "file", "offset" => 0}},
          {"read", %{"path" => "file", "limit" => 2_001}},
          {"bash", %{"command" => "pwd", "timeout" => 1_801}},
          {"write", %{"path" => "file", "content" => String.duplicate("é", 32_769)}},
          {"write", %{"path" => "file", "content" => "text", "thread_id" => Ecto.UUID.generate()}},
          {"edit", %{"path" => "file", "edits" => [%{"oldText" => "", "newText" => "text"}]}},
          {"edit", %{"path" => "file", "edits" => []}}
        ],
        do: refute(EnvironmentTools.valid_args?(tool, args))
  end

  defp names(c), do: Enum.map(EnvironmentTools.available(c.thread, c.run, nil), & &1["name"])
end
