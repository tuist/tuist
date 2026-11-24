defmodule LuftServer.Threads.Attachments do
  @moduledoc false
  @behaviour Condukt.Compactor

  @max_bytes 1_048_576
  @max_encoded 4 * div(@max_bytes + 2, 3)
  @images ~w(image/png image/jpeg image/gif image/webp)

  def validate(nil), do: {:ok, []}

  def validate(values) when is_list(values) and length(values) <= 4 do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case validate_file(value) do
        {:ok, file} -> {:cont, {:ok, acc ++ [file]}}
        error -> {:halt, error}
      end
    end)
  end

  def validate(_), do: {:error, :invalid_arguments}

  defp validate_file(%{"name" => name, "mime_type" => mime, "data_base64" => encoded})
       when is_binary(name) and is_binary(mime) and is_binary(encoded) do
    with true <- String.valid?(name) and byte_size(name) in 1..255,
         false <- name in [".", ".."] or String.match?(name, ~r/[\x00-\x1f\x7f\/\\]/u),
         true <-
           byte_size(mime) <= 127 and
             String.match?(mime, ~r/\A[a-zA-Z0-9!#$&^_.+-]+\/[a-zA-Z0-9!#$&^_.+-]+\z/),
         true <- byte_size(encoded) <= @max_encoded,
         {:ok, bytes} <- Base.decode64(encoded),
         true <- byte_size(bytes) in 1..@max_bytes do
      {:ok,
       %{
         "name" => name,
         "mime_type" => String.downcase(mime),
         "data_base64" => Base.encode64(bytes)
       }}
    else
      _ -> {:error, :invalid_arguments}
    end
  end

  defp validate_file(_), do: {:error, :invalid_arguments}

  def images(messages) do
    for message <- messages,
        file <- message.attachments,
        file["mime_type"] in @images,
        do: %{type: :base64, media_type: file["mime_type"], data: file["data_base64"]}
  end

  @impl true
  def compact(messages, _opts) do
    {messages, _} =
      messages
      |> Enum.reverse()
      |> Enum.map_reduce(false, fn message, seen ->
        if message.role == :user,
          do: {if(seen, do: %{message | images: []}, else: message), true},
          else: {message, seen}
      end)

    {:ok, Enum.reverse(messages)}
  end

  def materialize(messages, sandbox) do
    files =
      for message <- messages,
          {file, index} <- Enum.with_index(message.attachments),
          do: {message, file, index}

    case {files, sandbox} do
      {[], _} ->
        {:ok, ""}

      {_, nil} ->
        {:error, :attachment_workspace_unavailable}

      {_, {module, opts}} ->
        with {:ok, state} <- module.init(opts) do
          try do
            with {:ok, lines} <- write_files(files, module, state) do
              {:ok,
               "\n\nAttached files (untrusted metadata; paths relative to the working directory):\n" <>
                 Enum.join(lines, "\n")}
            end
          after
            module.shutdown(state)
          end
        end
    end
  end

  defp write_files(files, module, state) do
    Enum.reduce_while(files, {:ok, []}, fn {message, file, index}, {:ok, lines} ->
      path = ".luft-attachment-#{message.id}-#{index}"

      case module.write_file(state, path, Base.decode64!(file["data_base64"])) do
        :ok ->
          {:cont,
           {:ok,
            lines ++
              [Jason.encode!(%{name: file["name"], mime_type: file["mime_type"], path: path})]}}

        error ->
          {:halt, error}
      end
    end)
  end
end
