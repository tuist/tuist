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

  test "keys are stable across VMs, large-map insertion order and filesystem timestamps", %{
    root: root
  } do
    for name <- ["z/source.ex", "a/source.ex"] do
      path = Path.join(root, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, name)
    end

    ebin = Key |> :code.which() |> to_string() |> Path.dirname()

    script = """
    [root, direction] = System.argv()
    entries = for i <- 1..128, do: {i, %{value: Integer.to_string(i)}}
    entries = if direction == "reverse", do: Enum.reverse(entries), else: entries
    IO.puts(TuistEx.Cache.Key.build({Map.new(entries), TuistEx.Cache.Key.tree(root)}))
    """

    key = fn direction ->
      {output, 0} =
        System.cmd(
          System.find_executable("elixir"),
          ["-pa", ebin, "-e", script, "--", root, direction],
          env: [{"ERL_FLAGS", "+S 2:2"}],
          stderr_to_stdout: true
        )

      String.trim(output)
    end

    first = key.("forward")
    File.touch!(Path.join(root, "a/source.ex"), {{2010, 1, 1}, {0, 0, 0}})
    assert key.("reverse") == first
    assert byte_size(first) == 64
  end

  test "upstream fingerprints include ordinary resources and custom output directories", %{
    root: root
  } do
    source = Path.join(root, "source")
    build = Path.join(root, "build")
    File.mkdir_p!(Path.join(source, "priv"))
    File.mkdir_p!(Path.join(build, "bin"))
    File.mkdir_p!(Path.join(build, ".mix"))
    File.ln_s!(Path.join(source, "priv"), Path.join(build, "priv"))
    File.write!(Path.join(source, "priv/template"), "first")
    File.write!(Path.join(build, "bin/tool"), "first tool")
    dep = %{opts: [build: build, dest: source]}
    first = TuistEx.Cache.Compiler.artifacts(dep, [])
    File.write!(Path.join(build, ".mix/compile.elixir"), "volatile state")
    assert TuistEx.Cache.Compiler.artifacts(dep, []) == first
    File.write!(Path.join(source, "priv/template"), "second")
    second = TuistEx.Cache.Compiler.artifacts(dep, [])
    refute first == second
    File.write!(Path.join(build, "bin/tool"), "second tool")
    refute TuistEx.Cache.Compiler.artifacts(dep, []) == second
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

  test "subdirectory enumeration preserves checkout-relative names and nested metadata", %{
    root: root
  } do
    for name <- ["src/.git/parser.xrl", "src/_build/parser.yrl", "docs/ignored.xrl"] do
      path = Path.join(root, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "grammar")
    end

    expected = Enum.filter(Key.paths(root), &(&1 == "src" or String.starts_with?(&1, "src/")))
    assert Key.paths_in(root, "src") == expected
    assert Key.paths_in(root, ".") == Key.paths(root)
    assert catch_throw(Key.paths_in(root, "../outside")) == :unmodeled_input
    assert catch_throw(Key.paths_in(root, "_build")) == :unmodeled_input
    File.ln_s!(root, Path.join(root, "src/link"))
    assert catch_throw(Key.paths_in(root, "src")) == :unmodeled_input
    File.ln_s!("src", Path.join(root, "source-alias"))
    assert catch_throw(Key.paths_in(root, "source-alias/_build")) == :unmodeled_input
    assert catch_throw(Key.paths_in(Path.join(root, "source-alias"), ".")) == :unmodeled_input
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

  test "declared generated outputs and newly created parent directories are not source inputs", %{
    root: root
  } do
    File.write!(Path.join(root, "source.c"), "source")
    generated = ["priv/native/library.so"]
    before = Key.tree(root, generated)
    File.mkdir_p!(Path.join(root, "priv/native"))
    File.write!(Path.join(root, "priv/native/library.so"), "generated")
    assert Key.tree(root, generated) == before
    assert Key.paths(root, generated) == Enum.map(before, &elem(&1, 0))
    File.write!(Path.join(root, "priv/resource.txt"), "original resource")
    refute Key.tree(root, generated) == before
    File.write!(Path.join(root, "source.c"), "changed source")
    refute Key.tree(root, generated) == before
  end

  test "artifact trees retain only contained relative symlinks", %{root: root} do
    File.write!(Path.join(root, "library.so.1"), "native library")
    File.ln_s!("library.so.1", Path.join(root, "library.so"))
    assert {"library.so", :symlink, "library.so.1"} in Key.tree(root, [], true)
    assert catch_throw(Key.tree(root)) == :unmodeled_input
    before = Key.tree(root, [], true)
    File.write!(Path.join(root, "library.so.1"), "changed native library")
    refute Key.tree(root, [], true) == before
    File.ln_s!("../outside", Path.join(root, "escape"))
    assert catch_throw(Key.tree(root, [], true)) == :unmodeled_input
  end

  test "path-only traversal preserves missing inputs", %{root: root} do
    assert Key.paths(Path.join(root, "missing")) == [""]
  end
end
