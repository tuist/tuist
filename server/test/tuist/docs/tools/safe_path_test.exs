defmodule Tuist.Docs.Tools.SafePathTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs.Tools.SafePath

  setup do
    root = Path.join(System.tmp_dir!(), "safe_path_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "ok.txt"), "hi")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "resolves a simple relative path inside the root", %{root: root} do
    assert {:ok, path} = SafePath.resolve(root, "ok.txt")
    assert path == Path.join(root, "ok.txt")
  end

  test "rejects parent traversal", %{root: root} do
    assert {:error, :unsafe_path} = SafePath.resolve(root, "../etc/passwd")
    assert {:error, :unsafe_path} = SafePath.resolve(root, "foo/../../bar")
  end

  test "treats leading-slash inputs as relative to root", %{root: root} do
    assert {:ok, path} = SafePath.resolve(root, "/etc/passwd")
    assert String.starts_with?(path, Path.expand(root))
  end
end
