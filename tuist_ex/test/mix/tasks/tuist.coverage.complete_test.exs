defmodule Mix.Tasks.Tuist.Coverage.CompleteTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Mix.Tasks.Tuist.Coverage.Complete
  alias TuistEx.Analytics.HTTP

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "signals the commit's coverage complete" do
    expect(HTTP, :project_request, fn :post,
                                      "/tests/coverage/commits/abcdef123/complete",
                                      %{},
                                      options ->
      assert options[:project] == "tuist/server"
      {:ok, %{"coverage" => 81.5}}
    end)

    Complete.run(["--commit", "abcdef123", "--project", "tuist/server"])

    assert_received {:mix_shell, :info, ["Coverage of commit abcdef1 is complete: 81.5%."]}
  end

  test "says when no run reported coverage yet" do
    stub(HTTP, :project_request, fn :post, _, %{}, _ -> {:ok, %{"message" => "pending"}} end)

    Complete.run(["--commit", "abcdef123"])

    assert_received {:mix_shell, :info,
                     ["No run of commit abcdef1 has reported coverage yet." <> _]}
  end

  test "fails when the server refuses" do
    stub(HTTP, :project_request, fn :post, _, %{}, _ -> {:error, {:http, 404, %{}}} end)

    assert_raise Mix.Error, ~r/Could not mark the coverage of commit abcdef1 complete/, fn ->
      Complete.run(["--commit", "abcdef123"])
    end
  end
end
