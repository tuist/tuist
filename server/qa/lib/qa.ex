defmodule QA do
  @moduledoc """
  This module is a CLI for running QA tests on macOS.
  """
  use Application

  alias QA.Agent

  def start(_, _) do
    params = parse_arguments()

    opts = [
      anthropic_api_key: params.anthropic_api_key
    ]

    case Agent.test(params, opts) do
      :ok ->
        IO.puts("Finished running QA test")
        System.halt(0)

      {:error, reason} ->
        IO.puts("Failed with: #{inspect(reason)}")
        System.halt(1)
    end
  end

  def main(_args) do
    :ok
  end

  defp parse_arguments do
    {opts, _, _} =
      OptionParser.parse(Burrito.Util.Args.get_arguments(),
        switches: [
          preview_url: :string,
          bundle_identifier: :string,
          server_url: :string,
          run_id: :string,
          auth_token: :string,
          account_handle: :string,
          project_handle: :string,
          prompt: :string,
          anthropic_api_key: :string
        ],
        aliases: []
      )

    Map.new(opts)
  end
end
