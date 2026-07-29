defmodule TuistWeb.CodeReloaderTest do
  use ExUnit.Case, async: true

  alias TuistWeb.CodeReloader

  describe "stale_config_files/2" do
    test "ignores Mix compile.lock when it is newer than the compile manifest" do
      %{compile_lock: compile_lock, config: config, manifest: manifest} = stale_paths()

      assert CodeReloader.stale_config_files([compile_lock, config], [manifest]) == []
    end

    test "keeps real config files in the stale set" do
      %{compile_lock: compile_lock, config: config, manifest: manifest} = stale_paths()
      File.touch!(config, 300)

      assert CodeReloader.stale_config_files([compile_lock, config], [manifest]) == [config]
    end

    test "does not ignore unrelated files named compile.lock" do
      %{config: config, manifest: manifest} = stale_paths()
      unrelated_lock = Path.join(Path.dirname(config), "compile.lock")
      File.write!(unrelated_lock, "")
      File.touch!(unrelated_lock, 300)

      assert CodeReloader.stale_config_files([unrelated_lock, config], [manifest]) == [unrelated_lock]
    end
  end

  describe "normalize_mix_compile_lock_mtime/2" do
    test "moves a stale Mix compile.lock back to the compile manifest mtime" do
      %{compile_lock: compile_lock, config: config, manifest: manifest} = stale_paths()

      assert :ok = CodeReloader.normalize_mix_compile_lock_mtime([compile_lock, config], [manifest])

      assert Mix.Utils.last_modified(compile_lock) == Mix.Utils.last_modified(manifest)
    end

    test "moves compile.lock behind every reloadable app manifest" do
      %{compile_lock: compile_lock, config: config, manifest: manifest} = stale_paths()
      reloadable_app_manifest = Path.join(Path.dirname(manifest), "noora.compile.elixir")
      File.write!(reloadable_app_manifest, "")
      File.touch!(manifest, 150)
      File.touch!(reloadable_app_manifest, 100)

      assert :ok =
               CodeReloader.normalize_mix_compile_lock_mtime(
                 [compile_lock, config],
                 [[manifest], [reloadable_app_manifest]]
               )

      assert Mix.Utils.last_modified(compile_lock) == 100
      assert CodeReloader.stale_config_files([compile_lock, config], [reloadable_app_manifest]) == []
    end

    test "leaves compile.lock alone when a real config file is stale" do
      %{compile_lock: compile_lock, config: config, manifest: manifest} = stale_paths()
      File.touch!(config, 300)

      assert :ok = CodeReloader.normalize_mix_compile_lock_mtime([compile_lock, config], [manifest])

      assert Mix.Utils.last_modified(compile_lock) == 200
    end
  end

  defp stale_paths do
    root = Path.join(System.tmp_dir!(), "tuist-code-reloader-#{System.unique_integer([:positive])}")
    build_path = Path.join([root, "_build", "dev", "lib", "tuist", ".mix"])
    config_path = Path.join(root, "config")

    File.mkdir_p!(build_path)
    File.mkdir_p!(config_path)

    manifest = Path.join(build_path, "compile.elixir")
    compile_lock = Path.join(build_path, "compile.lock")
    config = Path.join(config_path, "dev.exs")

    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(manifest, "")
    File.write!(compile_lock, "")
    File.write!(config, "")

    File.touch!(manifest, 100)
    File.touch!(compile_lock, 200)
    File.touch!(config, 90)

    %{compile_lock: compile_lock, config: config, manifest: manifest}
  end
end
