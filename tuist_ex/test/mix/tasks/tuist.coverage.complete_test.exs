defmodule Mix.Tasks.Tuist.Coverage.CompleteTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Mix.Tasks.Tuist.Coverage.Complete
  alias TuistEx.Analytics.HTTP

  @environment %{
    "TUIST_URL" => "https://tuist.dev",
    "TUIST_PROJECT" => nil,
    "GIT_COMMIT" => nil
  }

  setup do
    Mix.shell(Mix.Shell.Process)
    previous = Map.new(@environment, fn {name, _} -> {name, System.get_env(name)} end)
    put_env(@environment)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      put_env(previous)
    end)
  end

  defp put_env(variables) do
    Enum.each(variables, fn
      {name, nil} -> System.delete_env(name)
      {name, value} -> System.put_env(name, value)
    end)
  end

  test "signals the commit's coverage complete and links its coverage page" do
    expect(HTTP, :project_request, fn :post,
                                      "/tests/coverage/commits/abcdef123/complete",
                                      %{},
                                      options ->
      assert options[:project] == "acme/app"
      # Outlasts the server's 15 s wait for the commit's runs.
      assert options[:timeout] > 15_000
      {:ok, %{"coverage" => 81.5}}
    end)

    Complete.run(["--commit", "abcdef123", "--project", "acme/app"])

    assert_received {:mix_shell, :info, [message]}

    assert message ==
             "Coverage of commit abcdef1 is complete: 81.5%.\n" <>
               "  See the commit's coverage at https://tuist.dev/acme/app/tests/coverage/commits/abcdef123"
  end

  test "prints the figure the dashboard shows rather than what the runs measured" do
    stub(HTTP, :project_request, fn :post, _, %{}, _ ->
      {:ok,
       %{
         "coverage" => 70.0,
         "schemes" => [""],
         "partial_schemes" => [],
         "reported" => %{"kind" => "reported", "coverage" => 81.5, "gap_reasons" => []}
       }}
    end)

    Complete.run(["--commit", "abcdef123", "--project", "acme/app"])

    assert_received {:mix_shell, :info, [message]}

    assert message ==
             "Coverage of commit abcdef1 is complete: 81.5%.\n" <>
               "  See the commit's coverage at https://tuist.dev/acme/app/tests/coverage/commits/abcdef123"
  end

  test "says when the commit's figure is partial and names its partial variants" do
    stub(HTTP, :project_request, fn :post, _, %{}, _ ->
      {:ok,
       %{
         "coverage" => 60.0,
         "partial_schemes" => ["", "postgres", "mysql"],
         "reported" => %{
           "kind" => "partial",
           "coverage" => 64.2,
           "gap_reasons" => ["excluded_tests"]
         }
       }}
    end)

    Complete.run(["--commit", "abcdef123", "--project", "acme/app"])

    assert_received {:mix_shell, :info, [message]}

    assert message ==
             "Coverage of commit abcdef1 is complete: 64.2% (partial: postgres, mysql). " <>
               "The figure is incomplete, so the actual coverage may be higher.\n" <>
               "  See the commit's coverage at https://tuist.dev/acme/app/tests/coverage/commits/abcdef123"
  end

  test "says when runs from a dirty checkout don't count and how to keep them counting" do
    stub(HTTP, :project_request, fn :post, _, %{}, _ ->
      {:ok,
       %{
         "coverage" => 60.0,
         "partial_schemes" => [""],
         "reported" => %{
           "kind" => "partial",
           "coverage" => 55.0,
           "gap_reasons" => ["excluded_tests", "dirty_run_excluded"]
         }
       }}
    end)

    Complete.run(["--commit", "abcdef123", "--project", "acme/app"])

    assert_received {:mix_shell, :info, [message]}

    assert message ==
             "Coverage of commit abcdef1 is complete: 55.0%. " <>
               "Some runs came from a checkout with uncommitted changes and don't count, " <>
               "because they measured code that isn't the commit's, so the actual coverage may be higher.\n" <>
               "  Keep the checkout clean while the tests run, or keep the files the CI job writes out of it\n" <>
               "  See the commit's coverage at https://tuist.dev/acme/app/tests/coverage/commits/abcdef123"
  end

  test "says when no run reported coverage yet, how to signal another commit, and where the commits are" do
    stub(HTTP, :project_request, fn :post, _, %{}, _ -> {:ok, %{"message" => "pending"}} end)

    Complete.run(["--commit", "abcdef123", "--project", "acme/app"])

    assert_received {:mix_shell, :info, [message]}
    assert message =~ "No run of commit abcdef1 has reported coverage yet."
    assert message =~ "expected while its runs are still being processed"
    assert message =~ "`mix tuist.coverage.complete --commit <sha>`"

    assert String.ends_with?(
             message,
             "See the commits your runs reported coverage for at https://tuist.dev/acme/app/tests/coverage/commits"
           )
  end

  test "names the checkout's HEAD when no commit is passed" do
    {head, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    head = String.trim(head)

    expect(HTTP, :project_request, fn :post, path, %{}, _ ->
      assert path == "/tests/coverage/commits/#{head}/complete"
      {:ok, %{"message" => "pending"}}
    end)

    Complete.run(["--project", "acme/app"])

    assert_received {:mix_shell, :info, [message]}

    assert message =~
             "No run of commit #{String.slice(head, 0, 7)}, the checkout's HEAD, has reported coverage yet."
  end

  test "names GIT_COMMIT when it sets the commit" do
    System.put_env("GIT_COMMIT", "fedcba987")
    stub(HTTP, :project_request, fn :post, _, %{}, _ -> {:ok, %{"message" => "pending"}} end)

    Complete.run(["--project", "acme/app"])

    assert_received {:mix_shell, :info, [message]}
    assert message =~ "No run of commit fedcba9, from GIT_COMMIT, has reported coverage yet."
  end

  test "fails when the server refuses" do
    stub(HTTP, :project_request, fn :post, _, %{}, _ -> {:error, {:http, 404, %{}}} end)

    assert_raise Mix.Error, ~r/Could not mark the coverage of commit abcdef1 complete/, fn ->
      Complete.run(["--commit", "abcdef123"])
    end
  end
end
