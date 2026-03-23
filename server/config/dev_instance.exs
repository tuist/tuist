defmodule Tuist.Config.DevInstance do
  @moduledoc false

  @instance_file ".tuist-dev-instance"

  def suffix do
    case System.get_env("TUIST_DEV_INSTANCE") do
      nil -> read_or_create_suffix()
      "" -> read_or_create_suffix()
      value -> normalize_suffix!(value)
    end
  end

  def port(base_port) when is_integer(base_port) do
    base_port + suffix()
  end

  def database_name(base_name) when is_binary(base_name) do
    "#{base_name}_#{suffix()}"
  end

  def app_url(base_port \\ 8080) do
    "http://localhost:#{port(base_port)}"
  end

  defp read_or_create_suffix do
    path = instance_file_path()

    case File.read(path) do
      {:ok, value} ->
        value |> String.trim() |> normalize_suffix!()

      {:error, :enoent} ->
        create_suffix(path)

      {:error, reason} ->
        raise "Unable to read #{path}: #{:file.format_error(reason)}"
    end
  end

  defp create_suffix(path) do
    suffix = generate_suffix()

    case File.write(path, Integer.to_string(suffix), [:write, :exclusive]) do
      :ok -> suffix
      {:error, :eexist} -> read_or_create_suffix()
      {:error, reason} -> raise "Unable to write #{path}: #{:file.format_error(reason)}"
    end
  end

  defp generate_suffix do
    :rand.seed(:exsss, {System.system_time(), :erlang.unique_integer(), :erlang.phash2(node())})
    :rand.uniform(899) + 100
  end

  defp normalize_suffix!(value) do
    case Integer.parse(value) do
      {suffix, ""} when suffix >= 1 and suffix <= 999 ->
        suffix

      _ ->
        raise """
        Invalid dev instance suffix #{inspect(value)}.
        Expected an integer between 1 and 999.
        """
    end
  end

  defp instance_file_path do
    Path.expand(Path.join(project_root(), @instance_file))
  end

  defp project_root do
    Path.expand("../..", __DIR__)
  end
end
