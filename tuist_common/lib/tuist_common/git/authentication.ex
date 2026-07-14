defmodule TuistCommon.Git.Authentication do
  @moduledoc """
  Helpers for authenticated Git commands that avoid placing tokens in remotes
  or process arguments.
  """

  @github_rewrite_config ["-c", "url.https://github.com/.insteadOf=git@github.com:"]
  @no_prompt_env [{"GIT_TERMINAL_PROMPT", "0"}]

  def with_github_token(tmp_dir, token, function)
      when is_binary(tmp_dir) and is_binary(token) and is_function(function, 1) do
    case write_credentials(tmp_dir, token) do
      {:ok, credentials} ->
        try do
          function.(credentials)
        after
          cleanup(credentials)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def config_args(nil), do: @github_rewrite_config

  def config_args(%{helper_path: helper_path}) do
    ["-c", "credential.helper=", "-c", "credential.helper=#{helper_path}"] ++
      @github_rewrite_config
  end

  def command_env(nil), do: @no_prompt_env

  def command_env(%{token_path: token_path}),
    do: [{"GIT_TOKEN_FILE", token_path} | @no_prompt_env]

  defp write_credentials(tmp_dir, token) do
    directory = Path.join(tmp_dir, "git-auth")
    token_path = Path.join(directory, "token")
    helper_path = Path.join(directory, "credential-helper")

    with :ok <- File.mkdir_p(directory),
         :ok <- File.write(token_path, token),
         :ok <- File.chmod(token_path, 0o600),
         :ok <- File.write(helper_path, helper_script()),
         :ok <- File.chmod(helper_path, 0o700) do
      {:ok, %{directory: directory, helper_path: helper_path, token_path: token_path}}
    else
      {:error, reason} -> {:error, {:git_authentication_setup_failed, reason}}
    end
  end

  defp cleanup(%{directory: directory}) do
    File.rm_rf(directory)
    :ok
  end

  defp helper_script do
    """
    #!/bin/sh
    if [ "$1" = "get" ]; then
      cat >/dev/null
      printf 'username=x-access-token\\n'
      printf 'password=%s\\n' "$(cat "$GIT_TOKEN_FILE")"
    fi
    """
  end
end
