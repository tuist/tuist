defmodule TuistEx.Cache.StoreTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.TempDir
  alias TuistEx.Cache.Key
  alias TuistEx.Cache.Store

  setup do
    dir = Path.join(System.tmp_dir!(), "tuist-cache-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    build = Path.join(dir, "build")
    source = Path.join(dir, "source")
    File.mkdir_p!(Path.join(build, "ebin"))
    File.mkdir_p!(Path.join(source, "priv"))
    File.write!(Path.join(build, "ebin/probe.beam"), "bytecode")
    File.write!(Path.join(build, "ebin/probe.app"), "application")
    File.mkdir_p!(Path.join(build, ".mix"))
    File.write!(Path.join(build, ".mix/compile.elixir_scm"), "manifest")
    File.ln_s!("../source/priv", Path.join(build, "priv"))

    %{
      dir: dir,
      build: build,
      source: source,
      root: Path.join(dir, "store"),
      key: Key.build(:probe)
    }
  end

  test "restores artifacts, manifests and source-relative links without sharing mutable files",
       context do
    %{root: root, key: key, build: build, source: source} = context
    assert :ok = Store.publish(root, key, build, source, 123)
    File.rm_rf!(build)
    assert {:ok, 123} = Store.restore(root, key, build, source)
    assert File.read!(Path.join(build, "ebin/probe.beam")) == "bytecode"
    assert File.read!(Path.join(build, ".mix/compile.elixir_scm")) == "manifest"
    assert File.read_link!(Path.join(build, "priv")) == "../source/priv"
    File.write!(Path.join(build, "ebin/probe.beam"), "changed")
    assert {:ok, 123} = Store.restore(root, key, build, source)
    assert File.read!(Path.join(build, "ebin/probe.beam")) == "bytecode"
  end

  test "measures copied payload bytes and timings, not linked resources or declared sizes",
       context do
    %{root: root, key: key, build: build, source: source} = context
    File.write!(Path.join(source, "priv/large"), String.duplicate("a", 10_000))
    assert {:ok, published} = Store.publish_with_metrics(root, key, build, source, 123)
    manifest_path = Path.join([root, key, "manifest.json"])
    assert published.write_bytes == byte_size(File.read!(manifest_path)) + 27
    assert published.write_duration_us >= 0
    manifest = JSON.decode!(File.read!(manifest_path))
    files = Enum.map(manifest["files"], &Map.put(&1, "size_bytes", 999_999))
    File.write!(manifest_path, JSON.encode!(Map.put(manifest, "files", files)))
    assert {:ok, 123, restored} = Store.restore_with_metrics(root, key, build, source)
    assert restored.read_bytes == byte_size(File.read!(manifest_path)) + 27
    assert restored.read_duration_us >= 0
    File.write!(Path.join([root, key, "files/ebin/probe.beam"]), "corrupt")
    assert :miss = Store.restore_with_metrics(root, key, build, source)
  end

  test "REAPI bundle round-trips into an independent store and preserves resource links",
       context do
    %{root: root, key: key, build: build, source: source, dir: dir} = context
    assert :ok = Store.publish(root, key, build, source, 123)
    assert {:ok, binary} = Store.export_bundle(root, key)
    File.rm_rf!(build)
    remote = Path.join(dir, "remote-store")
    assert {:ok, 123, _} = Store.restore_bundle(remote, key, binary, build, source)
    assert File.read!(Path.join(build, "ebin/probe.beam")) == "bytecode"
    assert File.read_link!(Path.join(build, "priv")) == "../source/priv"
    assert {:ok, 123} = Store.restore(remote, key, build, source)
  end

  test "materialized native priv resources round-trip without the producer source directory",
       context do
    %{root: root, key: key, build: build, source: source, dir: dir} = context
    File.mkdir_p!(Path.join(source, "priv/lib"))
    File.write!(Path.join(source, "priv/lib/library.so.1"), "native library")
    File.chmod!(Path.join(source, "priv/lib/library.so.1"), 0o755)
    File.ln_s!("library.so.1", Path.join(source, "priv/lib/library.so"))

    assert {:ok, metrics} =
             Store.publish_with_metrics(root, key, build, source, 123, fn _ -> true end,
               materialize_resources: true
             )

    assert metrics.write_bytes > byte_size("native library")
    assert {:ok, binary} = Store.export_bundle(root, key)
    File.rm_rf!(source)
    File.rm_rf!(build)
    remote = Path.join(dir, "remote-store")
    assert {:ok, 123, _} = Store.restore_bundle(remote, key, binary, build, source)
    assert File.lstat!(Path.join(build, "priv")).type == :directory
    assert File.read!(Path.join(build, "priv/lib/library.so")) == "native library"
    assert File.read_link!(Path.join(build, "priv/lib/library.so")) == "library.so.1"

    assert Bitwise.band(File.stat!(Path.join(build, "priv/lib/library.so.1")).mode, 0o777) ==
             0o755

    assert {:ok, 123} = Store.restore(remote, key, build, source)
  end

  test "audited builders also materialize source-backed include and src resources", context do
    %{root: root, key: key, build: build, source: source} = context

    for name <- ["include", "src"] do
      File.mkdir_p!(Path.join(source, name))
      File.write!(Path.join([source, name, "generated"]), "generated resource")
      File.ln_s!("generated", Path.join([source, name, "alias"]))
      File.ln_s!("../source/#{name}", Path.join(build, name))
    end

    assert {:ok, _} =
             Store.publish_with_metrics(root, key, build, source, 123, fn _ -> true end,
               materialize_resources: true
             )

    File.rm_rf!(source)
    File.rm_rf!(build)
    assert {:ok, 123} = Store.restore(root, key, build, source)

    for name <- ["include", "src"] do
      assert File.lstat!(Path.join(build, name)).type == :directory
      assert File.read!(Path.join([build, name, "alias"])) == "generated resource"
    end
  end

  test "materializing native resources rejects escaping, absolute and cyclic symlinks", context do
    %{root: root, key: key, build: build, source: source, dir: dir} = context
    File.write!(Path.join(dir, "outside"), "private")

    for target <- ["../../outside", Path.join(dir, "outside"), "link"] do
      File.ln_s!(target, Path.join(source, "priv/link"))

      assert {:error, :unsupported_outputs} =
               Store.publish_with_metrics(root, key, build, source, 123, fn _ -> true end,
                 materialize_resources: true
               )

      File.rm!(Path.join(source, "priv/link"))
    end

    refute File.exists?(Path.join(root, key))
  end

  test "invalid native link manifests never replace the existing build", context do
    %{root: root, key: key, build: build, source: source, dir: dir} = context

    assert {:ok, _} =
             Store.publish_with_metrics(root, key, build, source, 123, fn _ -> true end,
               materialize_resources: true
             )

    manifest_path = Path.join([root, key, "manifest.json"])
    manifest = manifest_path |> File.read!() |> JSON.decode!()
    File.write!(Path.join(dir, "outside"), "private")

    for link <- [
          %{path: "priv/escape", type: "symlink", target: "../../outside"},
          %{path: "ebin/escape", type: "symlink", target: "probe.beam"},
          %{path: "priv/cycle", type: "symlink", target: "cycle"},
          %{path: "priv/missing-target", type: "symlink"}
        ] do
      files = [link | manifest["files"]]
      File.write!(manifest_path, JSON.encode!(Map.put(manifest, "files", files)))
      assert :miss = Store.restore(root, key, build, source)
      assert {:ok, bundle} = Store.export_bundle(root, key)
      assert :miss = Store.restore_bundle(Path.join(dir, "other"), key, bundle, build, source)
      assert File.read!(Path.join(build, "ebin/probe.beam")) == "bytecode"
      assert File.read!(Path.join(dir, "outside")) == "private"
    end
  end

  test "REAPI bundle corruption, truncation, extra bytes and traversal never replace a build",
       context do
    %{root: root, key: key, build: build, source: source, dir: dir} = context
    :ok = Store.publish(root, key, build, source, 123)
    {:ok, binary} = Store.export_bundle(root, key)
    File.write!(Path.join(build, "ebin/probe.beam"), "keep")

    invalid = [
      binary_part(binary, 0, byte_size(binary) - 1),
      binary <> "extra",
      String.replace(binary, "bytecode", "corrupt!")
    ]

    for data <- invalid do
      assert :miss = Store.restore_bundle(Path.join(dir, "other"), key, data, build, source)
      assert File.read!(Path.join(build, "ebin/probe.beam")) == "keep"
    end

    <<size::unsigned-big-32, rest::binary>> = binary
    manifest = rest |> binary_part(0, size) |> JSON.decode!()
    files = Enum.map(manifest["files"], &Map.put(&1, "path", "../escape"))
    metadata = JSON.encode!(Map.put(manifest, "files", files))

    data =
      <<byte_size(metadata)::unsigned-big-32>> <>
        metadata <> binary_part(rest, size, byte_size(rest) - size)

    assert :miss = Store.restore_bundle(root, key, data, build, source)
    refute File.exists?(Path.join(dir, "escape"))
    assert File.read!(Path.join(build, "ebin/probe.beam")) == "keep"
  end

  test "corrupt artifacts fall back to a miss without replacing the existing build", context do
    %{root: root, key: key, build: build, source: source} = context
    :ok = Store.publish(root, key, build, source, 0)
    File.write!(Path.join([root, key, "files/ebin/probe.beam"]), "corrupt")
    assert :miss = Store.restore(root, key, build, source)
    assert File.read!(Path.join(build, "ebin/probe.beam")) == "bytecode"
  end

  test "corrupt entries are repaired by a successful publication", context do
    %{root: root, key: key, build: build, source: source} = context
    :ok = Store.publish(root, key, build, source, 123)
    File.write!(Path.join([root, key, "files/ebin/probe.beam"]), "corrupt")
    assert :miss = Store.restore(root, key, build, source)
    assert :ok = Store.publish(root, key, build, source, 123)
    assert {:ok, 123} = Store.restore(root, key, build, source)
  end

  test "a verified remote bundle repairs a corrupt local entry", context do
    %{root: root, key: key, build: build, source: source} = context
    :ok = Store.publish(root, key, build, source, 123)
    {:ok, bundle} = Store.export_bundle(root, key)
    File.write!(Path.join([root, key, "files/ebin/probe.beam"]), "corrupt")
    assert {:ok, 123, _} = Store.restore_bundle(root, key, bundle, build, source)
    assert {:ok, 123} = Store.restore(root, key, build, source)
    assert File.read!(Path.join(build, "ebin/probe.beam")) == "bytecode"
  end

  test "oversized manifest durations fail open locally and remotely", context do
    %{root: root, key: key, build: build, source: source, dir: dir} = context
    :ok = Store.publish(root, key, build, source, 123)
    path = Path.join([root, key, "manifest.json"])
    manifest = JSON.decode!(File.read!(path)) |> Map.put("compile_duration_ms", 4_294_967_296)
    File.write!(path, JSON.encode!(manifest))
    assert {:ok, bundle} = Store.export_bundle(root, key)
    assert :miss = Store.restore(root, key, build, source)
    assert :miss = Store.restore_bundle(Path.join(dir, "remote"), key, bundle, build, source)
    assert File.read!(Path.join(build, "ebin/probe.beam")) == "bytecode"
  end

  test "semantic validation happens before replacing or persisting a bundle", context do
    %{root: root, key: key, build: build, source: source, dir: dir} = context
    :ok = Store.publish(root, key, build, source, 123)
    {:ok, bundle} = Store.export_bundle(root, key)
    File.write!(Path.join(build, "ebin/probe.beam"), "keep")
    remote = Path.join(dir, "remote")
    assert :miss = Store.restore_bundle(remote, key, bundle, build, source, fn _ -> false end)
    assert File.read!(Path.join(build, "ebin/probe.beam")) == "keep"
    refute File.exists?(Path.join(remote, key))
  end

  test "large snapshots are rejected before publication", context do
    %{root: root, key: key, build: build, source: source} = context

    {:ok, file} =
      :file.open(String.to_charlist(Path.join(build, "ebin/large.beam")), [:write, :binary])

    :file.position(file, Store.max_bundle_bytes())
    :file.write(file, "x")
    :file.close(file)
    assert {:error, :unsupported_outputs} = Store.publish(root, key, build, source, 123)
    refute File.exists?(Path.join(root, key))
  end

  test "nested source directories named _build are still modeled", context do
    path = Path.join(context.source, "lib/_build")
    File.mkdir_p!(path)
    source = Path.join(path, "probe.ex")
    File.write!(source, "one")
    before = Key.tree(context.source)
    File.write!(source, "two")
    refute before == Key.tree(context.source)
  end

  test "rejects escaping output links", context do
    %{root: root, key: key, build: build, source: source} = context
    File.ln_s!("/etc/passwd", Path.join(build, "escape"))
    assert {:error, :unsupported_outputs} = Store.publish(root, key, build, source, 0)
    refute File.exists?(Path.join(root, key))
  end

  test "rejects traversal in an entry before replacing a build", context do
    %{root: root, key: key, build: build, source: source, dir: dir} = context
    :ok = Store.publish(root, key, build, source, 0)
    manifest = Path.join([root, key, "manifest.json"])
    data = JSON.decode!(File.read!(manifest))
    data = Map.put(data, "files", [%{path: "../escaped", type: "directory"}])
    File.write!(manifest, JSON.encode!(data))
    assert :miss = Store.restore(root, key, build, source)
    refute File.exists?(Path.join(dir, "escaped"))
    assert File.read!(Path.join(build, "ebin/probe.beam")) == "bytecode"
  end

  test "concurrent publication leaves a complete entry", context do
    %{root: root, key: key, build: build, source: source} = context

    results =
      1..4
      |> Task.async_stream(fn _ -> Store.publish(root, key, build, source, 123) end)
      |> Enum.to_list()

    assert Enum.all?(results, &(&1 == {:ok, :ok}))
    assert {:ok, 123} = Store.restore(root, key, build, source)
  end

  test "independent VMs can restore different bundles into a shared store concurrently",
       context do
    %{root: root, key: key, build: build, source: source, dir: dir} = context
    :ok = Store.publish(root, key, build, source, 123)
    other_key = Key.build(:other_probe)
    :ok = Store.publish(root, other_key, build, source, 123)
    ebin = :tuist_ex |> :code.lib_dir() |> to_string() |> Path.join("ebin")
    shared = Path.join(dir, "shared")
    ready = Path.join(dir, "ready")
    File.mkdir_p!(ready)

    tasks =
      for {entry_key, index} <- [{key, 1}, {other_key, 2}] do
        script = """
        {:ok, bundle} = TuistEx.Cache.Store.export_bundle(#{inspect(root)}, #{inspect(entry_key)})
        validate = fn _ ->
          File.write!(Path.join(#{inspect(ready)}, System.pid()), "ready")
          wait = fn wait, retries ->
            cond do
              length(File.ls!(#{inspect(ready)})) == 2 -> true
              retries == 0 -> raise "other restore did not reach staging"
              true -> Process.sleep(10); wait.(wait, retries - 1)
            end
          end
          wait.(wait, 1_000)
        end
        {:ok, 123, _} = TuistEx.Cache.Store.restore_bundle(#{inspect(shared)}, #{inspect(entry_key)}, bundle,
          #{inspect(Path.join(dir, "build-#{index}"))}, #{inspect(source)}, validate)
        """

        Task.async(fn ->
          System.cmd(System.find_executable("elixir"), ["-pa", ebin, "-e", script],
            stderr_to_stdout: true
          )
        end)
      end

    for task <- tasks do
      {output, status} = Task.await(task, 20_000)
      assert status == 0, output
    end

    for entry_key <- [key, other_key] do
      assert {:ok, 123} = Store.restore(shared, entry_key, build, source)
    end
  end

  test "keys observe contents, file names, modes, missing inputs and context" do
    TempDir.with_dir("tuist-cache-key", fn dir ->
      input = Path.join(dir, "input")
      before = Key.tree(input)
      File.write!(input, "a")
      first = Key.tree(input)
      File.write!(input, "b")
      second = Key.tree(input)
      File.chmod!(input, 0o755)
      third = Key.tree(input)
      assert length(Enum.uniq([before, first, second, third])) == 4
      refute Key.build({first, :dev}) == Key.build({first, :test})
      File.ln_s!(input, Path.join(dir, "link"))
      assert catch_throw(Key.tree(Path.join(dir, "link"))) == :unmodeled_input
    end)
  end
end
