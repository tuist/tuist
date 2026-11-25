defmodule TuistEx.Analytics.TestSelectionTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.TestSelection

  @cart """
  defmodule CartTest do
    use ExUnit.Case, async: true

    test "totals the cart" do
      :ok
    end

    describe "add/2" do
      test "adds an item" do
        :ok
      end

      test "same name" do
        :ok
      end
    end

    test "built \#{1 + 1}" do
      :ok
    end
  end
  """

  @checkout """
  defmodule CheckoutTest do
    use ExUnit.Case

    describe "add/2" do
      test "same name" do
        :ok
      end
    end

    property "never charges twice" do
      :ok
    end
  end
  """

  @pair """
  defmodule PairOneTest do
    use ExUnit.Case
    test "one", do: :ok
  end

  defmodule PairTwoTest do
    use ExUnit.Case
    test "two", do: :ok
  end
  """

  setup do
    repo =
      Path.join(System.tmp_dir!(), "tuist-ex-selection-#{System.unique_integer([:positive])}")

    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(repo) end)
    git!(repo, ["init", "--quiet", "--initial-branch=main"])

    # The project lives in a directory of the repository, as in a monorepo.
    app = Path.join(repo, "app")
    write!(app, "lib/cart.ex", "defmodule Cart do\nend\n")
    write!(app, "test/cart_test.exs", @cart)
    write!(app, "test/checkout_test.exs", @checkout)
    write!(app, "test/pair_test.exs", @pair)
    write!(app, "test/support/factory.ex", "defmodule Factory do\nend\n")
    write!(app, "README.md", "# App\n")
    write!(repo, "other/lib/other.ex", "defmodule Other do\nend\n")
    baseline = commit!(repo, "baseline")

    files =
      Enum.map(~w(cart_test.exs checkout_test.exs pair_test.exs), &Path.join([app, "test", &1]))

    %{
      repo: repo,
      app: app,
      baseline: baseline,
      index: TestSelection.index(files),
      config: [app: :shop, elixirc_paths: ["lib", "test/support"], test_paths: ["test"]]
    }
  end

  defp git!(dir, args) do
    env = [
      {"GIT_AUTHOR_NAME", "Test"},
      {"GIT_AUTHOR_EMAIL", "test@tuist.dev"},
      {"GIT_COMMITTER_NAME", "Test"},
      {"GIT_COMMITTER_EMAIL", "test@tuist.dev"},
      {"GIT_CONFIG_GLOBAL", "/dev/null"}
    ]

    {output, 0} =
      System.cmd("git", ["-C", dir, "-c", "commit.gpgsign=false" | args],
        env: env,
        stderr_to_stdout: true
      )

    String.trim(output)
  end

  defp write!(dir, path, contents) do
    path = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp commit!(dir, message) do
    git!(dir, ["add", "-A"])
    git!(dir, ["commit", "--quiet", "-m", message])
    git!(dir, ["rev-parse", "HEAD"])
  end

  # A server answering the baseline request with `baseline` (a response or a
  # function of the request body) and the runs request with `run`, telling
  # the test what it was asked.
  defp server(baseline, run) do
    test_pid = self()

    fn :post, suffix, body, _options ->
      send(test_pid, {:request, suffix, body})

      case suffix do
        "/tests/selective-testing/coverage/baseline" when is_function(baseline) -> baseline.(body)
        "/tests/selective-testing/coverage/baseline" -> baseline
        "/tests/selective-testing/coverage/runs" -> run
      end
    end
  end

  defp decide(context, request, environment \\ %{}) do
    head = context[:head] || git!(context.repo, ["rev-parse", "HEAD"])
    environment = Map.merge(%{"GIT_COMMIT" => head, "GIT_BRANCH" => "feature"}, environment)

    TestSelection.decide(context.index,
      request: request,
      dir: context.app,
      config: context.config,
      scheme: "postgres",
      environment: &Map.get(environment, &1)
    )
  end

  defp requests do
    receive do
      {:request, suffix, body} -> [{Path.basename(suffix), body} | requests()]
    after
      0 -> []
    end
  end

  describe "decide/2" do
    test "selects from a baseline, sending the diff with each file's modules", context do
      write!(context.app, "lib/cart.ex", "defmodule Cart do\n  def total, do: 0\nend\n")
      write!(context.app, "test/cart_test.exs", @cart <> "\n")

      write!(
        context.app,
        "test/support/factory.ex",
        "defmodule Factory do\n  def build, do: nil\nend\n"
      )

      write!(context.app, "README.md", "# Shop\n")
      write!(context.repo, "other/lib/other.ex", "defmodule Other do\n  def x, do: 1\nend\n")
      head = commit!(context.repo, "change")

      run = %{
        "id" => "run-1",
        "outcome" => "selected",
        "counts" => %{"requested" => 6, "selected" => 2, "skipped" => 4},
        "skipped_tests" => [
          %{"module" => "PairOneTest"},
          %{"module" => "CartTest", "suite" => "add/2", "name" => "adds an item"}
        ]
      }

      assert {:selected, %{run_id: "run-1", counts: %{"selected" => 2}, skipped_tests: skipped}} =
               decide(
                 Map.put(context, :head, head),
                 server(
                   {:ok, %{"baseline_sha" => context.baseline, "diff_cached" => false}},
                   {:ok, run}
                 )
               )

      assert skipped == [
               %{module: "PairOneTest", suite: "", name: nil},
               %{module: "CartTest", suite: "add/2", name: "adds an item"}
             ]

      assert [{"baseline", baseline}, {"runs", body}] = requests()

      assert baseline == %{
               build_system: "mix",
               commit_sha: head,
               parent_shas: [context.baseline],
               mix: %{scheme: "postgres", app: "shop"}
             }

      all = ~w(CartTest CheckoutTest PairOneTest PairTwoTest)
      assert body.build_system == "mix"
      assert body.head_sha == head
      refute Map.has_key?(body, :commit_sha)
      assert body.baseline_sha == context.baseline
      assert body.dirty == false
      assert body.git_branch == "feature"
      assert body.mix == %{scheme: "postgres", app: "shop"}
      # No hashing step: every test module is in scope and none is skipped.
      assert body.modules == Enum.map(all, &%{name: &1, skipped: false})
      assert body.changed_files_count == 5

      assert Map.new(body.changed_files, &{&1.path, &1.affected_modules}) == %{
               # A test file affects the modules it defines; the project's
               # code and test support files every test module; anything
               # else in the project or the repository none.
               "app/README.md" => [],
               "app/lib/cart.ex" => all,
               "app/test/cart_test.exs" => ["CartTest"],
               "app/test/support/factory.ex" => all,
               "other/lib/other.ex" => []
             }

      assert Enum.all?(body.changed_files, &(&1.status == "M" and is_binary(&1.blob)))
    end

    test "sends no diff when the server has it and the checkout is clean", context do
      head = context.baseline
      run = {:ok, %{"id" => "run-2", "outcome" => "selected", "skipped_tests" => []}}

      assert {:selected, %{skipped_tests: []}} =
               decide(
                 Map.put(context, :head, head),
                 server({:ok, %{"baseline_sha" => context.baseline, "diff_cached" => true}}, run)
               )

      assert [{"baseline", _}, {"runs", body}] = requests()
      assert body.baseline_sha == context.baseline
      refute Map.has_key?(body, :changed_files)

      # A dirty checkout's diff is its own, so it is sent whatever the server has.
      write!(context.app, "lib/cart.ex", "defmodule Cart do\n  def dirty, do: true\nend\n")

      decide(
        Map.put(context, :head, head),
        server({:ok, %{"baseline_sha" => context.baseline, "diff_cached" => true}}, run)
      )

      assert [{"baseline", _}, {"runs", body}] = requests()
      assert body.dirty == true
      assert [%{path: "app/lib/cart.ex", status: "M"}] = body.changed_files
    end

    test "records the reason the baseline request gave, and runs everything", context do
      fallback = {:ok, %{"id" => "run-3", "outcome" => "fallback", "reason" => "no_baseline"}}

      assert {:fallback, %{run_id: "run-3", reason: "no_baseline"}} =
               decide(
                 context,
                 server(
                   {:ok,
                    %{"baseline_sha" => nil, "reason" => "no_baseline", "diff_cached" => false}},
                   fallback
                 )
               )

      assert [{"baseline", _}, {"runs", body}] = requests()
      assert body.fallback_reason == "no_baseline"
      refute Map.has_key?(body, :baseline_sha)
      refute Map.has_key?(body, :changed_files)
    end

    test "asks again with the checkout's ancestors when the server's history doesn't reach it",
         context do
      for n <- 1..3 do
        write!(context.app, "lib/n#{n}.ex", "#{n}")
        commit!(context.repo, "c#{n}")
      end

      fallback = {:ok, %{"id" => "run-4", "outcome" => "fallback", "reason" => "history_unknown"}}

      unknown =
        {:ok, %{"baseline_sha" => nil, "reason" => "history_unknown", "diff_cached" => false}}

      assert {:fallback, %{reason: "history_unknown"}} =
               decide(context, server(unknown, fallback))

      assert [{"baseline", first_ask}, {"baseline", retry}, {"runs", body}] = requests()
      refute Map.has_key?(first_ask, :ancestor_shas)
      ancestors = context.repo |> git!(["rev-list", "HEAD"]) |> String.split("\n") |> tl()
      assert retry.ancestor_shas == ancestors
      assert body.ancestor_shas == ancestors
      assert body.fallback_reason == "history_unknown"
    end

    test "a baseline the checkout can't reach is history_unavailable", context do
      missing = String.duplicate("a", 40)

      fallback =
        {:ok, %{"id" => "run-5", "outcome" => "fallback", "reason" => "history_unavailable"}}

      assert {:fallback, %{reason: "history_unavailable"}} =
               decide(
                 context,
                 server({:ok, %{"baseline_sha" => missing, "diff_cached" => false}}, fallback)
               )

      assert [{"baseline", _}, {"runs", body}] = requests()
      assert body.fallback_reason == "history_unavailable"
      refute Map.has_key?(body, :baseline_sha)
    end

    test "passes on the reasons the server applies no coverage for", context do
      for {reason, path} <- [
            {"tracked_file_changed", "app/mix.lock"},
            {"diff_too_large", nil},
            {"diff_unavailable", nil}
          ] do
        run =
          {:ok,
           %{"id" => "run", "outcome" => "fallback", "reason" => reason, "matched_path" => path}}

        assert {:fallback, %{reason: ^reason, matched_path: ^path}} =
                 decide(
                   context,
                   server(
                     {:ok, %{"baseline_sha" => context.baseline, "diff_cached" => true}},
                     run
                   )
                 )
      end

      # An outcome this client doesn't know runs everything.
      assert {:fallback, %{run_id: "run-6"}} =
               decide(
                 context,
                 server(
                   {:ok, %{"baseline_sha" => context.baseline, "diff_cached" => true}},
                   {:ok, %{"id" => "run-6", "outcome" => "partial"}}
                 )
               )
    end

    test "a project the server doesn't let select asks nothing more", context do
      assert :not_enabled =
               decide(
                 context,
                 server(
                   {:ok,
                    %{"baseline_sha" => nil, "reason" => "not_enabled", "diff_cached" => false}},
                   nil
                 )
               )

      assert [{"baseline", _}] = requests()
    end

    test "a request that fails is a failure, without an impact run", context do
      assert {:failed, {:http, 500, _}} =
               decide(context, server({:error, {:http, 500, %{}}}, nil))

      assert [{"baseline", _}] = requests()

      assert {:failed, :closed} =
               decide(
                 context,
                 server(
                   {:ok, %{"baseline_sha" => context.baseline, "diff_cached" => true}},
                   {:error, :closed}
                 )
               )

      assert {:failed, "No Tuist project configured"} =
               decide(context, server({:error, "No Tuist project configured"}, nil))
    end

    test "outside a repository there is nothing to diff" do
      dir = Path.join(System.tmp_dir!(), "tuist-ex-no-repo-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:failed, "the directory is not a Git repository"} =
               TestSelection.decide(%{files: %{}},
                 dir: dir,
                 config: [],
                 request: fn _, _, _, _ -> flunk("asked") end
               )
    end
  end

  describe "index/1" do
    test "reads the modules each test file defines", context do
      assert context.index.files[Path.join(context.app, "test/cart_test.exs")] == [
               %{module: "CartTest"}
             ]

      assert context.index.files[Path.join(context.app, "test/pair_test.exs")] == [
               %{module: "PairOneTest"},
               %{module: "PairTwoTest"}
             ]

      assert TestSelection.modules(context.index) ==
               ~w(CartTest CheckoutTest PairOneTest PairTwoTest)
    end
  end

  describe "selected_units/3" do
    test "keeps a file planned under one module while another of its modules has tests selected",
         context do
      # pair_test.exs is planned as PairOneTest, the first of its modules.
      {units, _concurrent} = TuistEx.Analytics.Shards.scan([Path.join(context.app, "test")])
      skip = fn modules -> Enum.map(modules, &%{module: &1, suite: "", name: nil}) end

      assert units
             |> TestSelection.selected_units(context.index, skip.(~w(CartTest PairOneTest)))
             |> Enum.sort() ==
               ~w(CheckoutTest PairOneTest)

      assert TestSelection.selected_units(
               units,
               context.index,
               skip.(~w(CartTest PairOneTest PairTwoTest))
             ) ==
               ["CheckoutTest"]
    end
  end

  describe "report/2" do
    defp output(outcome) do
      ExUnit.CaptureIO.capture_io(fn -> TestSelection.report(outcome, Mix.Shell.IO) end)
    end

    test "prints the counts and the modules with nothing selected" do
      selection = %{
        counts: %{"requested" => 6, "selected" => 0, "skipped" => 6},
        skipped_tests: [
          %{module: "B", suite: "", name: nil},
          %{module: "A", suite: "", name: nil}
        ]
      }

      assert output({:selected, selection}) ==
               "Tuist: coverage-based test selection: 0 of 6 tests selected, 6 skipped\n  Nothing selected in 2 modules: A, B\n"
    end

    test "prints why coverage wasn't applied, and warns only when a request failed" do
      assert output({:fallback, %{reason: "tracked_file_changed", matched_path: "mix.lock"}}) =~
               "not applied: tracked_file_changed (mix.lock), so every test runs."

      assert output({:failed, :timeout}) =~
               "warning: Tuist coverage-based test selection is unavailable (:timeout)"

      assert output({:failed, "No Tuist project configured"}) == ""
      assert output(:not_enabled) == ""
    end
  end
end
