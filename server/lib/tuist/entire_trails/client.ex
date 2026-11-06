defmodule Tuist.EntireTrails.Client do
  @moduledoc """
  Entire's experimental repository Trail discussions API.
  Authentication and regional routing use the shared Entire plugin client.
  """

  alias Tuist.Entire.Client, as: Entire

  def trails(installation, repository) do
    list(installation, repository, path(repository) <> "/trails", params: [{"status", "open,draft"}])
  end

  def trail(installation, repository, number) do
    request(:get, installation, repository, trail_path(repository, number))
  end

  def find_summary(installation, repository, number, marker) do
    base = trail_path(repository, number) <> "/discussions"

    with {:ok, discussions} <- list(installation, repository, base) do
      discussions
      |> Enum.filter(&owned?(&1["created_by_identity"], installation))
      |> Enum.reduce_while({:ok, nil}, fn discussion, {:ok, nil} ->
        case summary_message(installation, repository, base <> "/" <> segment(discussion["id"]), marker) do
          {:ok, nil} -> {:cont, {:ok, nil}}
          {:ok, message} -> {:halt, {:ok, %{discussion_id: discussion["id"], message_id: message["id"]}}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  defp summary_message(installation, repository, path, marker) do
    with {:ok, %{"messages" => messages}} <- request(:get, installation, repository, path) do
      {:ok, Enum.find(messages, &(owned?(&1["identity"], installation) and String.contains?(&1["body"], marker)))}
    end
  end

  def create_summary(installation, repository, number, body) do
    case request(:post, installation, repository, trail_path(repository, number) <> "/discussions",
           json: %{title: "Tuist insights", body: body}
         ) do
      {:ok, %{"discussion" => %{"id" => discussion_id}, "message" => %{"id" => message_id}}} ->
        {:ok, %{discussion_id: discussion_id, message_id: message_id}}

      {:error, _} = error ->
        error
    end
  end

  def update_summary(installation, repository, number, summary, body) do
    request(
      :patch,
      installation,
      repository,
      trail_path(repository, number) <>
        "/discussions/#{segment(summary.discussion_id)}/messages/#{segment(summary.message_id)}",
      json: %{body: body}
    )
  end

  defp list(installation, repository, path, opts \\ [], items \\ []) do
    with {:ok, body} <- request(:get, installation, repository, path, opts) do
      items = items ++ (body["items"] || [])

      case body["next_cursor"] do
        cursor when is_binary(cursor) and cursor != "" ->
          opts = Keyword.update(opts, :params, [{"cursor", cursor}], &List.keystore(&1, "cursor", 0, {"cursor", cursor}))
          list(installation, repository, path, opts, items)

        _ ->
          {:ok, items}
      end
    end
  end

  defp request(method, installation, repository, path, opts \\ []) do
    with {:ok, token} <-
           Entire.access_token(installation, repository.id, %{"contents" => "read", "discussions" => "write"}) do
      Entire.region_request(method, repository, path, token, opts)
    end
  end

  defp owned?(%{"kind" => "automation", "automation" => %{"installation_id" => remote_id}}, installation),
    do: remote_id == installation.remote_id

  defp owned?(_, _), do: false
  defp path(repository), do: "/repos/" <> segment(repository.id)
  defp trail_path(repository, number), do: path(repository) <> "/trails/" <> segment(to_string(number))
  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
