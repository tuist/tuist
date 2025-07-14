defmodule QAAgentCLI do
  use Application

  @default_config %{
    base_url: "https://api.anthropic.com/v1/messages",
    model: "claude-3-5-sonnet-20241022"
  }

  def start(_, _) do
    [_, api_key, simulator_uuid, prompt, preview_url] = Burrito.Util.Args.get_arguments() |> dbg

    config =
      @default_config
      |> Map.put(:api_key, api_key)
      |> Map.put(:simulator_uuid, simulator_uuid)
      |> Map.put(:preview_url, preview_url)

    case Tuist.QAAgent.execute_task(config, prompt) do
      {:ok, output} ->
        IO.puts("Finished running agent ask")
        System.halt(0)

      {:error, reason} ->
        {:error, reason}
        IO.puts("Failed with: #{reason}")
        System.halt(1)
    end
  end


  def main(_args) do
    :ok
  end
end
