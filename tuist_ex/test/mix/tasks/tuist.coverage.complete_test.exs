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
      {:ok, %{"coverage" => 81.5}}
    end)

    Complete.run(["--commit", "abcdef123", "--project", "acme/app"])

    assert_received {:mix_shell, :info, [message]}

    assert message ==
             "Coverage of commit abcdef1 is complete: 81.5%.\n" <>
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
