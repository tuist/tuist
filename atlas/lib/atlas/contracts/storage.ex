defmodule Atlas.Contracts.Storage do
  @moduledoc """
  Reads and writes contract `.docx` templates from either the on-disk
  `priv/contracts/templates/` tree (dev, test) or the `contracts/templates/`
  prefix in the shared Atlas object storage bucket (prod).

  The source is picked by `config :atlas, Atlas.Contracts, source: :disk | :s3`,
  defaulting to `:disk` so the checked-in placeholder stubs keep working with no
  extra ceremony in dev and test.
  """

  alias Atlas.ObjectStorage

  @s3_prefix "contracts/templates"

  def s3_prefix, do: @s3_prefix

  def source do
    Application.get_env(:atlas, Atlas.Contracts, [])
    |> Keyword.get(:source, :disk)
  end

  def read(template_set, filename) when is_binary(template_set) and is_binary(filename) do
    read_from(source(), template_set, filename)
  end

  def stat(template_set, filename) when is_binary(template_set) and is_binary(filename) do
    stat_from(source(), template_set, filename)
  end

  def put(template_set, filename, body, opts \\ [])
      when is_binary(template_set) and is_binary(filename) and is_binary(body) do
    put_to(Keyword.get(opts, :source, source()), template_set, filename, body, opts)
  end

  defp read_from(:disk, template_set, filename) do
    File.read(disk_path(template_set, filename))
  end

  defp read_from(:s3, template_set, filename) do
    with {:ok, %{body: body}} <- ObjectStorage.get_object(s3_key(template_set, filename)) do
      {:ok, body}
    end
  end

  defp stat_from(:disk, template_set, filename) do
    case File.stat(disk_path(template_set, filename)) do
      {:ok, %{size: size}} -> {:ok, size}
      {:error, _reason} = error -> error
    end
  end

  defp stat_from(:s3, template_set, filename) do
    case ObjectStorage.head_object(s3_key(template_set, filename)) do
      {:ok, response} -> {:ok, content_length(response)}
      {:error, _reason} = error -> error
    end
  end

  defp put_to(:disk, template_set, filename, body, _opts) do
    path = disk_path(template_set, filename)
    File.mkdir_p!(Path.dirname(path))
    File.write(path, body)
  end

  defp put_to(:s3, template_set, filename, body, opts) do
    put_opts =
      [content_type: Keyword.get(opts, :content_type, "application/octet-stream")]
      |> maybe_put_config(opts)

    case ObjectStorage.put_object(s3_key(template_set, filename), body, put_opts) do
      {:ok, _response} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp maybe_put_config(put_opts, opts) do
    case Keyword.get(opts, :config) do
      nil -> put_opts
      config -> Keyword.put(put_opts, :config, config)
    end
  end

  defp disk_path(template_set, filename) do
    Path.join([Application.app_dir(:atlas, "priv/contracts/templates"), template_set, filename])
  end

  defp s3_key(template_set, filename), do: "#{@s3_prefix}/#{template_set}/#{filename}"

  defp content_length(response) do
    response
    |> Map.get(:headers, %{})
    |> find_header("content-length")
    |> parse_content_length()
  end

  defp find_header(headers, name) when is_map(headers) do
    Enum.find_value(headers, fn
      {key, value} when is_binary(key) ->
        if String.downcase(key) == name, do: value

      _other ->
        nil
    end)
  end

  defp find_header(headers, name) when is_list(headers) do
    Enum.find_value(headers, fn
      {key, value} when is_binary(key) ->
        if String.downcase(key) == name, do: value

      _other ->
        nil
    end)
  end

  defp find_header(_headers, _name), do: nil

  defp parse_content_length(nil), do: 0
  defp parse_content_length([value | _rest]), do: parse_content_length(value)

  defp parse_content_length(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> 0
    end
  end

  defp parse_content_length(value) when is_integer(value), do: value
  defp parse_content_length(_other), do: 0
end
