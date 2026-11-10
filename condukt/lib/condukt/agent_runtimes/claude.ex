defmodule Condukt.AgentRuntimes.Claude do
  @moduledoc """
  Runtime adapter for Claude Code non-interactive SDK mode.

  The adapter shells out to `claude --print` with `MuonTrap`, passes the
  session's composed system prompt with `--system-prompt`, and returns Claude's
  printed response as the Condukt agent result.
  """

  @behaviour Condukt.AgentRuntime

  alias Condukt.AgentRuntimes.CLI

  @impl true
  def run(prompt, context, opts) do
    args =
      context
      |> base_args()
      |> maybe_put_system_prompt(context.system_prompt)
      |> maybe_put_model(context.runtime_opts)
      |> Kernel.++(Keyword.get(context.runtime_opts, :extra_args, []))
      |> Kernel.++([prompt])

    with {:ok, raw_output} <- CLI.run(command(context.runtime_opts), args, context, opts) do
      CLI.final_output(raw_output, nil)
    end
  end

  defp base_args(context) do
    [
      "--print",
      "--output-format",
      Keyword.get(context.runtime_opts, :output_format, "text"),
      "--permission-mode",
      Keyword.get(context.runtime_opts, :permission_mode, "acceptEdits"),
      "--no-session-persistence"
    ]
  end

  defp maybe_put_system_prompt(args, nil), do: args
  defp maybe_put_system_prompt(args, ""), do: args
  defp maybe_put_system_prompt(args, system_prompt), do: args ++ ["--system-prompt", system_prompt]

  defp maybe_put_model(args, opts) do
    case Keyword.get(opts, :model) do
      nil -> args
      model -> args ++ ["--model", model]
    end
  end

  defp command(opts), do: Keyword.get(opts, :command, "claude")
end
