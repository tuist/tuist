defmodule Tuist.QA.Agent do
  @moduledoc """
  Tuist QA agent module.
  """

  alias Tuist.Simulators
  alias Tuist.Zip

  def test(%{preview_url: preview_url, bundle_identifier: bundle_identifier}) do
    run_preview(preview_url, bundle_identifier)
  end

  defp run_preview(preview_url, bundle_identifier) do
    with {:ok, preview_path} <- download_preview(preview_url),
         {:ok, device} <- simulator_device(),
         {:ok, app_path} <- extract_app_from_preview(preview_path, bundle_identifier),
         :ok <- Simulators.boot_simulator(device),
         :ok <- Simulators.install_app(app_path, device) do
      Simulators.launch_app(bundle_identifier, device)
    end
  end

  defp simulator_device do
    case Simulators.devices(
           runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-5",
           name: "iPhone 16"
         ) do
      {:ok, []} ->
        {:error, "No simulator found with name 'iPhone 16' for runtime 'com.apple.CoreSimulator.SimRuntime.iOS-18-5'"}

      {:ok, [device | _]} ->
        {:ok, device}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp download_preview(preview_url) do
    with {:ok, preview_path} <- Briefly.create(extname: ".zip"),
         {:ok, _response} <- Req.get(preview_url, into: File.stream!(preview_path)) do
      {:ok, preview_path}
    else
      {:error, reason} ->
        {:error, "Failed to download preview: #{reason}"}
    end
  end

  defp extract_app_from_preview(preview_path, _bundle_identifier) do
    with {:ok, extract_dir} <- Briefly.create(directory: true),
         {:ok, _extracted_files} <-
           Zip.extract(String.to_charlist(preview_path), [{:cwd, String.to_charlist(extract_dir)}]),
         {:ok, files} <- File.ls(extract_dir),
         app_name when not is_nil(app_name) <- Enum.find(files, &String.ends_with?(&1, ".app")) do
      {:ok, Path.join(extract_dir, app_name)}
    else
      {:error, reason} ->
        {:error, "Failed to extract app from preview: #{reason}"}

      nil ->
        {:error, "No .app bundle found in the preview"}
    end
  end
end
