defmodule TuistCommon.Git.AuthenticationTest do
  use ExUnit.Case, async: true

  alias TuistCommon.Git.Authentication

  test "does not expose the token in Git command arguments or environment" do
    token = "secret-token"
    tmp_dir = Path.join(System.tmp_dir!(), "tuist-git-auth-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    credentials_dir =
      Authentication.with_github_token(tmp_dir, token, fn credentials ->
        refute Enum.any?(Authentication.config_args(credentials), &String.contains?(&1, token))

        refute Enum.any?(Authentication.command_env(credentials), fn {_name, value} ->
                 String.contains?(value, token)
               end)

        assert File.read!(credentials.token_path) == token
        credentials.directory
      end)

    refute File.exists?(credentials_dir)
    File.rm_rf!(tmp_dir)
  end
end
