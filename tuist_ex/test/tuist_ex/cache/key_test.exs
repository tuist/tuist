defmodule TuistEx.Cache.KeyTest do
  use ExUnit.Case, async: true

  alias TuistEx.Cache.Key

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "tuist-key-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "path-only traversal follows the same boundaries and ordering as input trees", %{
    root: root
  } do
    for name <- [
          ".git/ignored",
          "_build/ignored",
          "lib/source.ex",
          "nested/.git/modeled",
          "nested/_build/modeled"
        ] do
      path = Path.join(root, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "content")
    end

    assert Key.paths(root) == Enum.map(Key.tree(root), &elem(&1, 0))
    refute ".git" in Key.paths(root)
    refute "_build" in Key.paths(root)
    assert "nested/.git/modeled" in Key.paths(root)
    assert "nested/_build/modeled" in Key.paths(root)
  end

  test "path-only traversal does not need source read permission", %{root: root} do
    path = Path.join(root, "source.ex")
    File.write!(path, "private contents")
    File.chmod!(path, 0o000)
    on_exit(fn -> File.chmod(path, 0o644) end)
    assert Key.paths(root) == ["", "source.ex"]
  end

  test "path-only traversal rejects source symlinks", %{root: root} do
    File.ln_s!(root, Path.join(root, "external"))
    assert catch_throw(Key.paths(root)) == :unmodeled_input
  end

  test "path-only traversal preserves missing inputs", %{root: root} do
    assert Key.paths(Path.join(root, "missing")) == [""]
  end
end
