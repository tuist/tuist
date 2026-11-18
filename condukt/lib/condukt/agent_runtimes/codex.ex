defmodule Condukt.AgentRuntimes.Codex do
  @moduledoc """
  Runtime adapter for the Codex CLI non-interactive SDK mode.

  The adapter shells out to `codex exec` with `MuonTrap`, passes the session's
  composed system prompt as part of the task, and returns the final Codex
  response as the Condukt agent result.
  """

  @behaviour Condukt.AgentRuntime

  alias Condukt.AgentRuntimes.CLI

  @impl true
  def run(prompt, context, opts) do
    output_path = Path.join(System.tmp_dir!(), "condukt-codex-#{context.session_id}.txt")

    args =
      context
      |> base_args(output_path)
      |> maybe_put_model(context.runtime_opts)
      |> maybe_put_profile(context.runtime_opts)
      |> Kernel.++(Keyword.get(context.runtime_opts, :extra_args, []))
      |> Kernel.++([compose_prompt(context.system_prompt, prompt)])

    try do
      with {:ok, raw_output} <- CLI.run(command(context.runtime_opts), args, context, opts) do
        CLI.final_output(raw_output, output_path)
      end
    after
      File.rm(output_path)
    end
  end

  defp base_args(context, output_path) do
    [
      "--sandbox",
      Keyword.get(context.runtime_opts, :sandbox, "workspace-write"),
      "--ask-for-approval",
      Keyword.get(context.runtime_opts, :approval_policy, "never"),
      "exec",
      "--skip-git-repo-check",
      "--color",
      "never",
      "-C",
      context.cwd,
      "-o",
      output_path
    ]
  end

  defp maybe_put_model(args, opts) do
    case Keyword.get(opts, :model) do
      nil -> args
      model -> args ++ ["--model", model]
    end
  end

  defp maybe_put_profile(args, opts) do
    case Keyword.get(opts, :profile) do
      nil -> args
      profile -> args ++ ["--profile", profile]
    end
  end

  defp command(opts), do: Keyword.get(opts, :command, "codex")

  defp compose_prompt(nil, prompt), do: prompt

  defp compose_prompt(system_prompt, prompt) do
    """
    #{String.trim(system_prompt)}

    Task:
    #{prompt}
    """
    |> String.trim()
  end
end
