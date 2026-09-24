defmodule Atlas.Memory.Tools do
  @moduledoc """
  Condukt tools for the Slack conversation agent.

  The agent decides what to remember by calling `memory_save` during a thread
  and pulls relevant context with `memory_recall`. Tools are only mounted on
  internal company channels: the calling channel and user are captured at
  mount time and stamped on every save.

  `memory_save` always creates a *pending* proposal. It posts a confirmation
  message into the thread and stamps the message timestamp on the node so a
  teammate's ✅ or ❌ reaction can promote or discard the proposal later.
  Pending nodes are excluded from recall and from the bulletin until they
  are confirmed.
  """

  alias Atlas.Memory
  alias Atlas.Memory.Node
  alias Atlas.Slack.API, as: SlackAPI
  alias Atlas.Slack.Channel, as: SlackChannel
  alias Atlas.Slack.User, as: SlackUser

  require Logger

  @recall_limit_default 6
  @recall_limit_max 20

  @doc """
  Returns the `memory_save` and `memory_recall` tools bound to the calling
  channel, slack user, and thread. Pass `nil` for slack_user when not yet
  resolved and `nil` for thread_ts when no thread context is available
  (saves will fail without it). The scope must come from the resolved agent
  identity before mounting these tools.
  """
  def tools(%SlackChannel{} = channel, slack_user, thread_ts, opts) do
    scope = fetch_scope!(opts)
    [memory_save_tool(channel, slack_user, thread_ts, scope: scope), memory_recall_tool(channel, scope: scope)]
  end

  def memory_save_tool(%SlackChannel{} = channel, slack_user, thread_ts, opts) do
    slack_user_id = slack_user_id(slack_user)
    slack_app = channel.slack_app
    scope = fetch_scope!(opts)

    Condukt.tool(
      name: "memory_save",
      description: """
      Propose a durable memory drawn from this conversation. The proposal is
      *not* saved yet: Atlas posts a confirmation message in the thread and
      waits for a teammate to react ✅ to save or ❌ to discard. Use for
      facts, preferences, decisions, identities, events, observations, goals,
      and todos that are worth remembering beyond the current thread.
      #{scope_description(scope)} Do not propose private,
      sensitive, or short-lived information. After calling this tool, do not
      announce the proposal in your reply — the confirmation message speaks
      for itself.
      """,
      parameters: %{
        type: "object",
        required: ["kind", "body"],
        properties: %{
          kind: %{
            type: "string",
            enum: Enum.map(Node.kinds(), &Atom.to_string/1),
            description: """
            One of: fact (objective info), preference (likes/dislikes),
            decision (a choice with reasoning), identity (durable persona
            info), event (a point-in-time occurrence), observation (a
            pattern noticed by the system), goal (a future objective),
            todo (an actionable reminder).
            """
          },
          body: %{
            type: "string",
            minLength: 1,
            maxLength: 4_000,
            description: "A single, self-contained sentence or short paragraph."
          },
          importance: %{
            type: "number",
            minimum: 0.0,
            maximum: 1.0,
            description: "Optional. Omit to use the default importance for the kind."
          }
        }
      },
      call: fn params, _ctx ->
        with {:ok, kind} <- parse_kind(params["kind"]),
             {:ok, body} <- parse_body(params["body"]),
             {:ok, importance} <- parse_importance(params["importance"]),
             {:ok, thread_ts} <- require_thread_ts(thread_ts),
             {:ok, proposal_ts} <- post_proposal(slack_app, channel, thread_ts, kind, body) do
          attrs =
            %{
              kind: kind,
              body: body,
              scope: scope,
              slack_app: slack_app,
              slack_channel_id: channel.id,
              slack_user_id: slack_user_id,
              confirmation: :pending,
              proposal_slack_ts: proposal_ts
            }
            |> map_put_some(:importance, importance)

          case Memory.create_node(attrs) do
            {:ok, node} ->
              {:ok,
               %{
                 saved: :pending,
                 memory: %{
                   id: node.id,
                   kind: Atom.to_string(node.kind),
                   importance: node.importance,
                   confirmation: Atom.to_string(node.confirmation)
                 }
               }}

            {:error, %Ecto.Changeset{} = changeset} ->
              {:error, Atlas.ChangesetErrors.format(changeset)}
          end
        else
          {:error, reason} when is_binary(reason) ->
            {:error, reason}

          {:error, reason} ->
            {:error, format_post_error(reason)}
        end
      end
    )
  end

  defp require_thread_ts(ts) when is_binary(ts) and ts != "", do: {:ok, ts}
  defp require_thread_ts(_), do: {:error, "memory_save needs an active Slack thread."}

  defp post_proposal(slack_app, %SlackChannel{} = channel, thread_ts, kind, body) do
    kind_label = kind |> Atom.to_string() |> String.replace("_", " ")

    text =
      "Atlas wants to remember this as a *#{kind_label}*:\n> #{escape_quote(body)}\n" <>
        "React :white_check_mark: to save, :x: to discard."

    blocks = [
      %{
        "type" => "section",
        "text" => %{
          "type" => "mrkdwn",
          "text" => text
        }
      }
    ]

    case SlackAPI.post_message(slack_app, channel.channel_id, text, blocks, thread_ts: thread_ts) do
      {:ok, %{"ts" => ts}} when is_binary(ts) ->
        {:ok, ts}

      {:ok, response} ->
        Logger.warning("Memory proposal post missing ts: #{inspect(response)}")
        {:error, :missing_proposal_ts}

      {:error, reason} ->
        Logger.warning("Memory proposal post failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp escape_quote(body) do
    body
    |> String.replace("\n", " ")
    |> String.slice(0, 500)
  end

  defp format_post_error(:missing_proposal_ts), do: "Slack did not return a proposal timestamp."
  defp format_post_error(reason), do: "Could not post proposal: #{inspect(reason)}"

  def memory_recall_tool(%SlackChannel{} = channel, opts) do
    scope = fetch_scope!(opts)

    Condukt.tool(
      name: "memory_recall",
      description: """
      Search the Atlas memory store for context relevant to the current
      conversation. Use this when answering questions about teammates,
      ongoing decisions, recent observations, or open goals where prior
      threads may already have captured the answer.
      """,
      parameters: %{
        type: "object",
        required: ["query"],
        properties: %{
          query: %{
            type: "string",
            minLength: 1,
            description: ~s(Free-text query, e.g. "Acme renewal" or "how do we onboard customers".)
          },
          kind: %{
            type: "string",
            enum: Enum.map(Node.kinds(), &Atom.to_string/1),
            description: "Optional. Restrict results to a single memory kind."
          },
          max_results: %{
            type: "integer",
            minimum: 1,
            maximum: @recall_limit_max,
            description: "Optional. Defaults to #{@recall_limit_default}."
          }
        }
      },
      call: fn params, _ctx ->
        with {:ok, query} <- parse_body(params["query"]),
             {:ok, kind} <- parse_optional_kind(params["kind"]) do
          limit =
            params
            |> Map.get("max_results", @recall_limit_default)
            |> clamp_limit(@recall_limit_max)

          opts =
            [scope: scope, limit: limit]
            |> maybe_scope_to_channel(scope, channel)
            |> keyword_put_some(:kind, kind)

          matches = Memory.search_nodes(query, opts)

          {:ok,
           %{
             memories: Enum.map(matches, &serialize_node/1),
             memory_count: length(matches)
           }}
        end
      end
    )
  end

  defp serialize_node(%Node{} = node) do
    %{
      id: node.id,
      kind: Atom.to_string(node.kind),
      body: node.body,
      importance: node.importance,
      access_count: node.access_count,
      inserted_at: iso8601(node.inserted_at),
      last_accessed_at: iso8601(node.last_accessed_at)
    }
  end

  defp parse_kind(value) when is_binary(value) do
    case Enum.find(Node.kinds(), &(Atom.to_string(&1) == value)) do
      nil -> {:error, "kind must be one of #{Enum.map_join(Node.kinds(), ", ", &Atom.to_string/1)}."}
      kind -> {:ok, kind}
    end
  end

  defp parse_kind(_), do: {:error, "kind is required."}

  defp parse_optional_kind(nil), do: {:ok, nil}
  defp parse_optional_kind(""), do: {:ok, nil}
  defp parse_optional_kind(value), do: parse_kind(value)

  defp fetch_scope!(opts) do
    opts
    |> Keyword.fetch!(:scope)
    |> normalize_scope!()
  end

  defp normalize_scope!(scope) when scope in [:global, :channel], do: scope
  defp normalize_scope!("global"), do: :global
  defp normalize_scope!("channel"), do: :channel

  defp normalize_scope!(scope) do
    raise ArgumentError, "expected :scope to be :global or :channel, got: #{inspect(scope)}"
  end

  defp scope_description(:global), do: "Memory is shared across the company Slack workspace."
  defp scope_description(:channel), do: "Memory is scoped to this Slack channel."

  defp maybe_scope_to_channel(opts, :channel, %SlackChannel{id: channel_id}) when is_binary(channel_id) do
    Keyword.put(opts, :slack_channel_id, channel_id)
  end

  defp maybe_scope_to_channel(opts, _scope, _channel), do: opts

  defp parse_body(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, "body is required."}
      body -> {:ok, body}
    end
  end

  defp parse_body(_), do: {:error, "body is required."}

  defp parse_importance(nil), do: {:ok, nil}

  defp parse_importance(value) when is_number(value) and value >= 0.0 and value <= 1.0, do: {:ok, value * 1.0}

  defp parse_importance(_), do: {:error, "importance must be a number between 0 and 1."}

  defp clamp_limit(value, ceiling) when is_integer(value), do: value |> Kernel.max(1) |> Kernel.min(ceiling)

  defp clamp_limit(_, ceiling), do: Kernel.min(@recall_limit_default, ceiling)

  defp slack_user_id(%SlackUser{id: id}), do: id
  defp slack_user_id(_), do: nil

  defp map_put_some(map, _key, nil), do: map
  defp map_put_some(map, key, value), do: Map.put(map, key, value)

  defp keyword_put_some(opts, _key, nil), do: opts
  defp keyword_put_some(opts, key, value), do: Keyword.put(opts, key, value)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp iso8601(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()
end
