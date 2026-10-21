defmodule TuistWeb.Helpers.BuildEntityLabelsTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Helpers.BuildEntityLabels

  test "uses native terminology for every supported build system" do
    assert BuildEntityLabels.plural(:gradle, "task") == "Tasks"
    assert BuildEntityLabels.plural(:xcode, "module") == "Modules"
    assert BuildEntityLabels.plural(:once, "action") == "Actions"
    assert BuildEntityLabels.plural(:mix, "file") == "Files"
    assert BuildEntityLabels.plural(:mix, "module") == "Modules"
  end

  test "inventory fields use native scope without repeating the primary task, file or module identifier" do
    assert BuildEntityLabels.inventory_fields(:gradle, "task") == ~w(root_project_name build_path task_type)
    assert BuildEntityLabels.inventory_fields(:xcode, "module") == []
    assert BuildEntityLabels.inventory_fields(:once, "action") == ~w(target_id capability action_index)
    assert BuildEntityLabels.inventory_fields(:mix, "file") == []
    assert BuildEntityLabels.inventory_fields(:mix, "module") == []
  end

  test "formats a reported root build without inventing missing scope or dropping zero indices" do
    assert BuildEntityLabels.identity_value(%{"build_path" => ":"}, "build_path") == "Root build"
    assert BuildEntityLabels.identity_value(%{"build_path" => ":included"}, "build_path") == ":included"
    assert BuildEntityLabels.identity_value(%{"build_path" => ""}, "build_path") == "Not reported"
    assert BuildEntityLabels.identity_value(%{}, "build_path") == "Not reported"
    assert BuildEntityLabels.identity_value(%{"action_index" => "0"}, "action_index") == "0"
  end

  test "preserves differing primary identifiers as sublabels but omits duplicates" do
    row = %{name: ":app:test", identity: %{"task_path" => ":app:test"}}
    assert BuildEntityLabels.inventory_sublabel(:gradle, "task", row) == nil
    assert BuildEntityLabels.inventory_sublabel(:gradle, "task", %{row | name: "Run tests"}) == ":app:test"

    assert BuildEntityLabels.inventory_sublabel(:mix, "module", %{name: "Application", identity: %{"module" => "App"}}) ==
             "App"

    assert BuildEntityLabels.inventory_sublabel(:mix, "file", %{name: "lib/app.ex", identity: %{"path" => "lib/app.ex"}}) ==
             nil

    assert BuildEntityLabels.inventory_sublabel(:xcode, "module", %{name: "App", identity: %{}}) == "Not reported"

    assert BuildEntityLabels.inventory_sublabel(:xcode, "module", %{
             name: "App",
             identity: %{"target" => "App", "project" => "Workspace"}
           }) == "Workspace"

    assert BuildEntityLabels.inventory_sublabel(:xcode, "module", %{
             name: "Display",
             identity: %{"target" => "App", "project" => "Workspace"}
           }) == "App · Workspace"
  end

  test "parent columns match the native build runs human-readable context" do
    assert BuildEntityLabels.parent(:gradle, "task") == "Project"
    assert BuildEntityLabels.parent(:xcode, "module") == "Command"
    assert BuildEntityLabels.parent(:once, "action") == "Run"
    assert BuildEntityLabels.parent(:mix, "file") == "Command"
    assert BuildEntityLabels.parent(:mix, "module") == "Command"
  end

  test "does not conflate file compilation time with module work" do
    assert BuildEntityLabels.duration(:mix, "module") == "File compilation duration"
    assert BuildEntityLabels.history(:mix, "file") == "Compilation history"
    assert BuildEntityLabels.history(:gradle, "task") == "Execution history"
  end
end
