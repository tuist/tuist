defmodule QAAgentCLI do
  use Application

  @default_config %{
    base_url: "https://api.anthropic.com/v1/messages",
    model: "claude-3-5-sonnet-20241022"
  }

  def start(_, _) do
    [api_key, simulator_uuid, prompt, preview_url] = Burrito.Util.Args.get_arguments() |> dbg

    # Download the preview
    preview_path = download_preview(preview_url)

    config =
      @default_config
      |> Map.put(:api_key, api_key)
      |> Map.put(:simulator_uuid, simulator_uuid)
      |> Map.put(:preview_url, preview_url)
      |> Map.put(:preview_path, preview_path)

    case QAAgent.execute_task(config, prompt) do
      {:ok, output} ->
        IO.puts("Finished running agent ask")
        System.halt(0)

      {:error, reason} ->
        {:error, reason}
        IO.puts("Failed with: #{reason}")
        System.halt(1)
    end
  end

  defp download_preview(preview_url) do
    IO.puts("Downloading preview from: #{preview_url}")
    
    # Create a temporary file path
    temp_dir = System.tmp_dir!()
    preview_path = Path.join(temp_dir, "preview_#{:os.system_time(:second)}.zip")
    
    # Download the file
    case Req.get(preview_url, into: File.stream!(preview_path)) do
      {:ok, _response} ->
        IO.puts("Preview downloaded successfully to: #{preview_path}")
        preview_path
        
      {:error, reason} ->
        IO.puts("Failed to download preview: #{inspect(reason)}")
        raise "Failed to download preview: #{inspect(reason)}"
    end
  end

  def main(_args) do
    :ok
  end
end
