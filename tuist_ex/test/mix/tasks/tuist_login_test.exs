defmodule Mix.Tasks.Tuist.LoginTest do
  use ExUnit.Case, async: false
  use Mimic

  test "forwards the command line options" do
    expect(TuistEx.Auth, :login, fn options ->
      assert options == [
               email: "person@example.com",
               password: "secret",
               url: "https://tuist.example"
             ]

      :ok
    end)

    assert :ok =
             Mix.Tasks.Tuist.Login.run([
               "--email",
               "person@example.com",
               "--password",
               "secret",
               "--url",
               "https://tuist.example"
             ])
  end

  test "rejects unknown options" do
    assert_raise Mix.Error, ~r/Usage: mix tuist.login/, fn ->
      Mix.Tasks.Tuist.Login.run(["--unknown"])
    end
  end
end
