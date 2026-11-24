defmodule TuistEx.HTTP do
  @moduledoc false

  alias TuistEx.CertificateTrust

  defmodule JSONFile do
    @moduledoc false
    # A JSON value kept in a file, such as a report's coverage evidence,
    # which a request body reads as it's built rather than holding it.
    defstruct [:path]
  end

  def request(method, url, body \\ nil, headers \\ [], timeouts \\ []) do
    start()

    headers =
      [
        {~c"accept", ~c"application/json"}
        | Enum.map(headers, fn {name, value} ->
            {String.to_charlist(name), String.to_charlist(value)}
          end)
      ]

    request =
      if body do
        {encoding, encoded} = encode(body)
        {String.to_charlist(url), encoding ++ headers, ~c"application/json", encoded}
      else
        {String.to_charlist(url), headers}
      end

    options =
      options(
        url,
        Keyword.get(timeouts, :timeout, 15_000),
        Keyword.get(timeouts, :connect_timeout, 10_000)
      )

    case :httpc.request(method, request, options, body_format: :binary) do
      {:ok, {{_, status, _}, _, response}} ->
        decoded =
          case JSON.decode(response) do
            {:ok, value} -> value
            _ -> %{}
          end

        {:ok, status, decoded}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A map body holding a `JSONFile` at its top level is deflated as it's
  # built, the file read in chunks, so only the compressed body is held.
  # The server inflates `Content-Encoding: deflate` (raw DEFLATE) bodies.
  defp encode(%{} = body) when not is_struct(body) do
    case Enum.split_with(body, &match?({_key, %JSONFile{}}, &1)) do
      {[], _rest} -> {[], JSON.encode!(body)}
      {files, rest} -> {[{~c"content-encoding", ~c"deflate"}], deflate(rest, files)}
    end
  end

  defp encode(body), do: {[], JSON.encode!(body)}

  defp deflate(rest, files) do
    z = :zlib.open()

    try do
      :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
      encoded = JSON.encode!(Map.new(rest))
      prefix = binary_part(encoded, 0, byte_size(encoded) - 1)
      separator = if rest == [], do: "", else: ","

      {chunks, _separator} =
        Enum.reduce(files, {[:zlib.deflate(z, prefix)], separator}, fn
          {key, %JSONFile{path: path}}, {chunks, separator} ->
            head = :zlib.deflate(z, [separator, JSON.encode!(to_string(key)), ":"])
            value = path |> File.stream!(1_048_576) |> Enum.map(&:zlib.deflate(z, &1))
            {[value, head | chunks], ","}
        end)

      IO.iodata_to_binary(Enum.reverse([:zlib.deflate(z, "}", :finish) | chunks]))
    after
      :zlib.close(z)
    end
  end

  @doc """
  Uploads `binary` to a pre-signed URL and returns the `ETag` the storage
  answered with.
  """
  def put_binary(url, binary) do
    start()
    request = {String.to_charlist(url), [], ~c"application/octet-stream", binary}

    case :httpc.request(:put, request, options(url, 600_000), body_format: :binary) do
      {:ok, {{_, status, _}, headers, _body}} when status in 200..299 ->
        case List.keyfind(headers, ~c"etag", 0) do
          {_, etag} -> {:ok, List.to_string(etag)}
          nil -> {:error, :missing_etag}
        end

      {:ok, {{_, status, _}, _headers, _body}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Downloads a URL straight to `path`, without holding the body in memory.
  """
  def download(url, path) do
    start()
    request = {String.to_charlist(url), []}

    case :httpc.request(:get, request, options(url, 600_000), stream: String.to_charlist(path)) do
      {:ok, :saved_to_file} -> :ok
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # While Mix compiles dependencies it prunes the OTP code paths, and an
  # application that is already running does not get its path back from
  # `Application.ensure_all_started/1`. `:httpc` loads modules lazily, so
  # restore the paths first.
  defp start do
    if Code.ensure_loaded?(Mix), do: Enum.each([:inets, :ssl], &Mix.ensure_application!/1)
    {:ok, _} = Application.ensure_all_started([:inets, :ssl])
  end

  defp options(url, timeout, connect_timeout \\ 10_000) do
    options = [timeout: timeout, connect_timeout: connect_timeout, autoredirect: false]

    if URI.parse(url).scheme == "https" do
      Keyword.put(options, :ssl, CertificateTrust.ssl_options())
    else
      options
    end
  end
end
