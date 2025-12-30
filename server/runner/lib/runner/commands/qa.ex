defmodule Runner.Commands.QA do
  @moduledoc """
  QA subcommand for running AI-powered tests on iOS app previews.
  """

  alias Runner.QA.Agent

  def run(args) do
    case parse_args(args) do
      {:ok, params} ->
        {anthropic_api_key, agent_params} = Map.pop(params, :anthropic_api_key)
        {openai_api_key, agent_params} = Map.pop(agent_params, :openai_api_key)
        opts = [anthropic_api_key: anthropic_api_key, openai_api_key: openai_api_key]
        Agent.test(agent_params, opts)

      {:error, :help} ->
        print_help()
        :ok

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        print_help()
        {:error, reason}
    end
  end

  defp parse_args(args) do
    {switches, _, _} =
      OptionParser.parse(args,
        switches: [
          preview_url: :string,
          bundle_identifier: :string,
          server_url: :string,
          run_id: :string,
          auth_token: :string,
          account_handle: :string,
          project_handle: :string,
          prompt: :string,
          launch_arguments: :string,
          app_description: :string,
          email: :string,
          password: :string,
          anthropic_api_key: :string,
          openai_api_key: :string,
          help: :boolean
        ],
        aliases: [h: :help]
      )

    if switches[:help] do
      {:error, :help}
    else
      validate_params(switches)
    end
  end

  defp validate_params(switches) do
    required_keys = [
      :preview_url,
      :bundle_identifier,
      :server_url,
      :run_id,
      :auth_token,
      :account_handle,
      :project_handle,
      :prompt,
      :anthropic_api_key
    ]

    missing_keys = required_keys -- Keyword.keys(switches)

    if missing_keys == [] do
      {:ok, Map.new(switches)}
    else
      {:error, "Missing required parameters: #{Enum.join(missing_keys, ", ")}"}
    end
  end

  defp print_help do
    IO.puts("""
    QA Command - Run AI-powered tests on iOS app previews

    Usage:
      runner qa [options]

    Required Options:
      --preview-url <url>           URL to download the iOS app preview
      --bundle-identifier <id>      Bundle identifier of the iOS app
      --server-url <url>           Tuist server URL for reporting results
      --run-id <id>                Unique identifier for this test run
      --auth-token <token>         Authentication token for the Tuist server
      --account-handle <handle>    Account handle on Tuist
      --project-handle <handle>    Project handle on Tuist
      --prompt "<prompt>"          Test prompt describing what to test
      --anthropic-api-key <key>    Anthropic API key for AI testing

    Optional:
      --launch-arguments "<args>"  Launch arguments to pass to the app
      --app-description "<desc>"   Description of the app to provide context to the QA agent
      --email "<email>"            Email for test account sign-in
      --password "<password>"      Password for test account sign-in
      --openai-api-key <key>       OpenAI API key (fallback if Anthropic fails)
      --help, -h                   Show this help message

    Example:
      runner qa --preview-url "https://example.com/app.zip" \\
                --bundle-identifier "com.example.app" \\
                --server-url "https://cloud.tuist.io" \\
                --run-id "abc123" \\
                --auth-token "token123" \\
                --account-handle "myaccount" \\
                --project-handle "myproject" \\
                --prompt "Test the login flow" \\
                --anthropic-api-key "sk-ant-..."
    """)
  end
end
