defmodule Atlas.Finance.CostDigestNotifier do
  @moduledoc """
  Posts agent-generated cost digests to the configured company Slack channel.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Slack.API

  require Logger

  @app_key :company

  def maybe_post(digest, opts \\ [])

  def maybe_post(%{fallback_text: fallback_text, blocks: blocks}, opts)
      when is_binary(fallback_text) and is_list(blocks) do
    with {:ok, channel_id} <- slack_channel_id(opts) do
      post(channel_id, fallback_text, blocks, opts)
    end
  end

  def maybe_post(_digest, _opts), do: {:error, :invalid_cost_digest}

  defp post(channel, fallback_text, blocks, opts) do
    poster = Keyword.get(opts, :poster, &API.post_message/4)

    blocks =
      blocks
      |> ensure_body(fallback_text)
      |> append_dashboard_action()

    case poster.(@app_key, channel, fallback_text, blocks) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to post finance cost digest to Slack: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_body(blocks, fallback_text) do
    if Enum.any?(blocks, &body_block?/1) do
      blocks
    else
      blocks ++
        [
          %{
            "type" => "section",
            "text" => %{"type" => "plain_text", "text" => fallback_text, "emoji" => false}
          }
        ]
    end
  end

  defp body_block?(%{"type" => "section", "text" => %{"text" => text}}), do: present_text?(text)

  defp body_block?(%{"type" => "section", "fields" => fields}) when is_list(fields),
    do: Enum.any?(fields, &text_object?/1)

  defp body_block?(%{"type" => "rich_text", "elements" => elements}) when is_list(elements), do: elements != []

  defp body_block?(_block), do: false

  defp text_object?(%{"text" => text}), do: present_text?(text)
  defp text_object?(_object), do: false

  defp present_text?(text) when is_binary(text), do: String.trim(text) != ""
  defp present_text?(_text), do: false

  defp append_dashboard_action(blocks) do
    case finance_url() do
      nil -> blocks
      url -> blocks ++ [dashboard_action(url)]
    end
  end

  defp dashboard_action(url) do
    %{
      "type" => "actions",
      "elements" => [
        %{
          "type" => "button",
          "text" => %{"type" => "plain_text", "text" => "Review vendor costs", "emoji" => true},
          "url" => url,
          "style" => "primary"
        }
      ]
    }
  end

  defp finance_url do
    url(~p"/finance/vendors")
  rescue
    _error -> nil
  end

  defp slack_channel_id(opts) do
    opts
    |> Keyword.get(:channel_id)
    |> case do
      channel_id when is_binary(channel_id) and channel_id != "" ->
        {:ok, channel_id}

      _channel_id ->
        finance_config(opts)
        |> configured_channel_id()
    end
  end

  defp configured_channel_id(config) do
    channel_id =
      Keyword.get(config, :cost_digest_slack_channel_id) ||
        Keyword.get(config, :weekly_summary_slack_channel_id)

    case channel_id do
      channel_id when is_binary(channel_id) and channel_id != "" -> {:ok, channel_id}
      _channel_id -> {:error, :missing_cost_digest_slack_channel_id}
    end
  end

  defp finance_config(opts) do
    Keyword.get(opts, :finance_config) || Application.get_env(:atlas, :finance, [])
  end
end
