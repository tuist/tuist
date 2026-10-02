defmodule TuistEx.Analytics.ShardsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Tuist.Test.Build
  alias TuistEx.Analytics.Shards

  setup do
    directory =
      Path.join(System.tmp_dir!(), "tuist-ex-shards-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  defp environment(variables), do: fn name -> Map.get(variables, name) end

  test "takes the reference from the flag, then the environment, then the pipeline run" do
    github = %{"GITHUB_RUN_ID" => "42", "GITHUB_RUN_ATTEMPT" => "3"}

    assert Shards.reference([shard_reference: "mine"], environment(github)) == {:ok, "mine"}

    assert Shards.reference([], environment(Map.put(github, "TUIST_SHARD_REFERENCE", "env"))) ==
             {:ok, "env"}

    assert Shards.reference([], environment(github)) == {:ok, "github-42-3"}
    assert Shards.reference([], environment(%{"CI_PIPELINE_ID" => "7"})) == {:ok, "gitlab-7"}
    assert {:error, message} = Shards.reference([], environment(%{}))
    assert message =~ "TUIST_SHARD_REFERENCE"
  end

  test "a run is sharded only when a shard index is given" do
    assert Shards.index([], environment(%{})) == nil
    assert Shards.index([shard_index: 0], environment(%{})) == 0
    assert Shards.index([], environment(%{"TUIST_SHARD_INDEX" => "3"})) == 3

    assert_raise Mix.Error, ~r/expects a shard number/, fn ->
      Shards.index([], environment(%{"TUIST_SHARD_INDEX" => "x"}))
    end
  end

  test "plans each test file as one unit, read without loading it", %{directory: directory} do
    File.mkdir_p!(Path.join(directory, "test/orders"))

    File.write!(Path.join(directory, "test/orders/order_test.exs"), """
    defmodule Demo.Orders.OrderTest do
      use ExUnit.Case
      raise "never evaluated"
    end

    defmodule Demo.Orders.LineItemTest do
      use ExUnit.Case
    end
    """)

    File.write!(
      Path.join(directory, "test/accounts_test.exs"),
      "defmodule Demo.AccountsTest do\nend\n"
    )

    # Its modules come from a macro, so the file is planned under its path.
    File.write!(
      Path.join(directory, "test/generated_test.exs"),
      "Demo.Generator.define_tests()\n"
    )

    # Not a test file.
    File.write!(Path.join(directory, "test/test_helper.exs"), "defmodule Demo.Helper do\nend\n")

    test_path = Path.join(directory, "test")
    generated = Path.join(test_path, "generated_test.exs")

    assert Shards.test_units([test_path]) == %{
             "Demo.AccountsTest" => Path.join(test_path, "accounts_test.exs"),
             # The first of the file's modules, by name, stands for the file.
             "Demo.Orders.LineItemTest" => Path.join(test_path, "orders/order_test.exs"),
             generated => generated
           }
  end

  test "refuses to plan around a test file that does not parse", %{directory: directory} do
    File.mkdir_p!(Path.join(directory, "test"))
    File.write!(Path.join(directory, "test/broken_test.exs"), "defmodule Demo.BrokenTest do")

    assert_raise Mix.Error, ~r/broken_test.exs could not be read or parsed/, fn ->
      Shards.test_units([Path.join(directory, "test")])
    end
  end

  test "a shard runs the files of the units it was assigned" do
    units = %{
      "AccountsTest" => "test/accounts_test.exs",
      "Orders.LineItemTest" => "test/orders_test.exs"
    }

    assert Shards.files(["Orders.LineItemTest", "AccountsTest"], units) == [
             "test/accounts_test.exs",
             "test/orders_test.exs"
           ]

    assert Shards.files(["Unknown"], units) == []
    assert Shards.files([], units) == []
  end

  test "paths given on the command line narrow a shard instead of widening it", %{
    directory: directory
  } do
    File.mkdir_p!(Path.join(directory, "test/orders"))
    accounts = Path.join(directory, "test/accounts_test.exs")
    order = Path.join(directory, "test/orders/order_test.exs")
    elsewhere = Path.join(directory, "test/billing_test.exs")
    for file <- [accounts, order, elsewhere], do: File.write!(file, "")

    shard = [accounts, order]

    # No paths: the shard as planned, the options untouched and in order.
    assert Shards.restrict(["--include", "a", "--include", "b"], shard) ==
             {["--include", "a", "--include", "b"], shard}

    # A directory keeps the shard's files below it; the directory itself is not forwarded.
    assert Shards.restrict([Path.join(directory, "test/orders"), "--trace"], shard) ==
             {["--trace"], [order]}

    # A file of another shard selects nothing here.
    assert Shards.restrict([elsewhere], shard) == {[], []}
    # A line selection of a file in the shard stays as given.
    assert Shards.restrict([accounts <> ":12"], shard) == {[], [accounts <> ":12"]}
  end

  describe "the build archive" do
    setup %{directory: directory} do
      # Links are only recreated inside the checkout, which is the working directory.
      checkout =
        Path.relative_to_cwd(
          Path.join(File.cwd!(), "tmp_shards_#{System.unique_integer([:positive])}")
        )

      on_exit(fn -> File.rm_rf!(checkout) end)

      build = Path.join(directory, "_build/test")
      File.mkdir_p!(Path.join(build, "lib/demo/ebin"))
      File.write!(Path.join(build, "lib/demo/ebin/Elixir.Demo.beam"), "beam")

      %{checkout: checkout, build: build, archive: Path.join(directory, "build.tar.gz")}
    end

    test "survives the round trip, links included", %{
      checkout: checkout,
      build: build,
      archive: archive
    } do
      File.ln_s!("../../../../deps/dep/priv", Path.join(build, "lib/demo/priv"))
      File.ln_s!("/etc", Path.join(build, "lib/demo/outside"))
      assert :ok = Shards.archive(build, archive)

      restored = Path.join(checkout, "_build/test")
      File.mkdir_p!(restored)
      File.write!(Path.join(restored, "stale"), "from an earlier build")
      assert :ok = Shards.extract(archive, restored)

      assert File.read!(Path.join(restored, "lib/demo/ebin/Elixir.Demo.beam")) == "beam"
      # The link into the checkout's `deps/` is back; the one leaving the checkout is not.
      assert File.read_link!(Path.join(restored, "lib/demo/priv")) == "../../../../deps/dep/priv"
      assert File.lstat(Path.join(restored, "lib/demo/outside")) == {:error, :enoent}
      # The downloaded build replaces the directory rather than mixing with it.
      refute File.exists?(Path.join(restored, "stale"))
      refute File.exists?(Path.join(restored, ".tuist-links"))
      refute File.exists?(restored <> ".tuist-download")
    end

    test "a crafted link list cannot reach outside the build through a link it just created", %{
      checkout: checkout,
      directory: directory,
      archive: archive
    } do
      outside = Path.join(directory, "outside")
      File.mkdir_p!(outside)
      File.write!(Path.join(outside, "victim"), "untouched")
      # Inside the checkout, a directory that links out of it.
      File.mkdir_p!(Path.join(checkout, "deps"))
      File.ln_s!(Path.expand(outside), Path.join(checkout, "deps/external"))

      links = [{"lib/gate", "../../../deps/external"}, {"lib/gate/victim", "../../../../inside"}]

      :ok =
        :erl_tar.create(
          String.to_charlist(archive),
          [{~c".tuist-links", :erlang.term_to_binary(links)}, {~c"lib/keep", "kept"}],
          [:compressed]
        )

      restored = Path.join(checkout, "_build/test")
      assert :ok = Shards.extract(archive, restored)

      assert File.read!(Path.join(outside, "victim")) == "untouched"
      assert {:ok, %File.Stat{type: :regular}} = File.lstat(Path.join(outside, "victim"))
      assert File.read!(Path.join(restored, "lib/keep")) == "kept"
    end

    test "an archive without a usable link list is refused and leaves the build alone", %{
      checkout: checkout,
      archive: archive
    } do
      restored = Path.join(checkout, "_build/test")
      File.mkdir_p!(restored)
      File.write!(Path.join(restored, "existing"), "still here")

      :ok =
        :erl_tar.create(String.to_charlist(archive), [{~c".tuist-links", "not a term"}], [
          :compressed
        ])

      assert Shards.extract(archive, restored) == {:error, :invalid_link_manifest}
      assert File.read!(Path.join(restored, "existing")) == "still here"
      refute File.exists?(restored <> ".tuist-download")
    end
  end

  test "a plan without a build tells the shard to compile for itself" do
    assert Shards.download_build(nil, "/nowhere") == {:error, :no_build}
  end

  test "writes the shard matrix where GitHub Actions reads job outputs", %{directory: directory} do
    output = Path.join(directory, "github_output")
    File.write!(output, "previous=1\n")
    shards = [%{"index" => 0, "test_targets" => ["A"]}, %{"index" => 1, "test_targets" => ["B"]}]

    ExUnit.CaptureIO.capture_io(fn ->
      Build.write_matrix("ref", shards, environment(%{"GITHUB_OUTPUT" => output}))
    end)

    assert File.read!(output) == "previous=1\nmatrix={\"shard\":[0,1]}\n"
  end
end
