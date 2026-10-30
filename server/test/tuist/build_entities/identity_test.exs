defmodule Tuist.BuildEntities.IdentityTest do
  use ExUnit.Case, async: true

  alias Tuist.BuildEntities.Identity

  @gradle_task %{
    "root_project_name" => "app",
    "build_path" => ":",
    "task_path" => ":app:compileJava",
    "task_type" => "org.gradle.api.tasks.compile.JavaCompile"
  }

  test "entity IDs are pinned to the versioned, length-prefixed encoding" do
    entity_id = Identity.id(42, :gradle, "task", @gradle_task)

    assert entity_id == "11f55276-204f-8fc1-ab66-45353de3f537"
    assert Identity.observation_id(entity_id, "build-1", 0) == "a8530d8e-953b-8ddd-9943-879aaa4b916e"
  end

  test "IDs depend on the project, system and kind" do
    id = Identity.id(42, :mix, "file", %{"path" => "lib/a.ex"})

    refute id == Identity.id(43, :mix, "file", %{"path" => "lib/a.ex"})
    refute id == Identity.id(42, :mix, "module", %{"module" => "lib/a.ex"})
  end

  test "values containing separators cannot collide" do
    refute Identity.id(1, :xcode, "module", %{"project" => "a:b", "target" => "c"}) ==
             Identity.id(1, :xcode, "module", %{"project" => "a", "target" => "b:c"})
  end

  test "identity order comes from the contract, not the map, and missing values are empty" do
    assert Identity.encode(:gradle, "task", %{"task_path" => ":a", "root_project_name" => "r"}) ==
             ~s({"root_project_name":"r","build_path":"","task_path":":a","task_type":""})

    assert Identity.id(1, :gradle, "task", %{"task_path" => ":a"}) ==
             Identity.id(1, :gradle, "task", %{"task_path" => ":a", "build_path" => nil, "extra" => "ignored"})
  end

  test "resolves only declared system and kind pairs" do
    assert {:ok, {:xcode, "module", ["project", "target"]}} = Identity.resolve(:xcode, "module")
    assert {:ok, {:mix, "module", ["module"]}} = Identity.resolve("mix", "module")
    assert :error == Identity.resolve(:mix, "task")
    assert :error == Identity.resolve("not_a_system_#{System.unique_integer([:positive])}", "task")
    assert :error == Identity.resolve(:gradle, :task)
  end

  test "Bazel output and mnemonic distinguish actions within one target and retain configured paths" do
    identity = %{"target_label" => "//app:lib", "mnemonic" => "CppCompile", "primary_output" => "bazel-out/debug/lib.o"}
    id = Identity.id(1, :bazel, "action", identity)

    for changes <- [
          %{"target_label" => "//other:lib"},
          %{"mnemonic" => "CppLink"},
          %{"primary_output" => "bazel-out/release/lib.o"},
          %{"primary_output" => "bazel-out/debug/other.o"}
        ] do
      refute id == Identity.id(1, :bazel, "action", Map.merge(identity, changes))
    end

    assert id == Identity.id(1, :bazel, "action", Map.put(identity, "action_digest", "changing-input-hash"))
  end

  test "exact-key Xcode and Bazel cache actions have no identity contract" do
    assert :error == Identity.resolve(:xcode, "cache_action")
    assert :error == Identity.resolve(:bazel, "cache_action")
    assert Identity.fields(:bazel, "action") == ["target_label", "mnemonic", "primary_output"]
  end
end
