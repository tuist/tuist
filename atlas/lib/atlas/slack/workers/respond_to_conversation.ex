defmodule Atlas.Slack.Workers.RespondToConversation do
  @moduledoc """
  Runs one Slack reply workflow for a single thread message.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Atlas.LLMs.Errors, as: LLMErrors
  alias Atlas.Repo
  alias Atlas.Slack
  alias Atlas.Slack.API
  alias Atlas.Slack.Bot
  alias Atlas.Slack.Channel
  alias Atlas.Slack.ConversationResponder
  alias Oban.Job

  require Logger

  @duplicate_window_seconds 300
  @queued_states ~w(available scheduled retryable)

  def start_or_replace(event, app_key, _channel) when is_map(event) do
    case build_job_args(event, app_key) do
      {:ok, args} ->
        if superseded?(args["slack_app"], args["channel_id"], args["thread_ts"], args["message_ts_micros"]) do
          :ok
        else
          cancel_queued_superseded_jobs(args)
          insert_job(args)
        end

      :error ->
        :ok
    end
  end

  def superseded?(app_key, channel_id, thread_ts, message_ts_micros)
      when is_binary(channel_id) and is_binary(thread_ts) and is_integer(message_ts_micros) do
    app_key = Bot.normalize_app_key!(app_key)

    latest_message_ts_micros(app_key, channel_id, thread_ts) > message_ts_micros
  end

  def superseded?(_app_key, _channel_id, _thread_ts, _message_ts_micros), do: false

  @impl true
  def perform(%Oban.Job{} = job), do: perform(job, [])

  def perform(
        %Oban.Job{
          args: %{
            "event" => event,
            "slack_app" => slack_app,
            "channel_id" => channel_id,
            "thread_ts" => thread_ts,
            "message_ts_micros" => message_ts_micros
          },
          attempt: attempt,
          max_attempts: max_attempts
        },
        _opts
      ) do
    current? = fn ->
      not superseded?(slack_app, channel_id, thread_ts, message_ts_micros)
    end

    if current?.() do
      app_key = Bot.normalize_app_key!(slack_app)
      channel = resolve_channel(app_key, channel_id)
      # Drives whether the responder posts the user-facing "I could not complete that
      # request" fallback in Slack. On non-final attempts the error bubbles back to
      # Oban for retry without notifying the user.
      final? = attempt >= max_attempts

      case ConversationResponder.respond(event, app_key, channel, current?: current?, final?: final?) do
        :ok -> :ok
        :ignored -> {:cancel, :ignored}
        {:error, :superseded} -> {:cancel, :superseded}
        {:error, :llm_not_configured} -> {:cancel, :llm_not_configured}
        {:error, reason} -> LLMErrors.oban_error(reason)
      end
    else
      {:cancel, :superseded}
    end
  end

  defp insert_job(args) do
    args
    |> new(unique: duplicate_unique_options())
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp cancel_queued_superseded_jobs(args) do
    query =
      Job
      |> where([job], job.worker == ^worker_name())
      |> where([job], job.state in ^@queued_states)
      |> where([job], fragment("? @> ?", job.args, type(^thread_identity(args), :map)))
      |> where([job], fragment("(?->>'message_ts_micros')::bigint < ?", job.args, ^args["message_ts_micros"]))

    _ = Oban.cancel_all_jobs(query)
    :ok
  end

  defp build_job_args(%{"channel" => channel_id, "ts" => message_ts} = event, app_key)
       when is_binary(channel_id) and is_binary(message_ts) do
    case parse_slack_ts(message_ts) do
      {:ok, message_ts_micros} ->
        slack_app = Bot.normalize_app_key!(app_key)
        thread_ts = event["thread_ts"] || message_ts

        {:ok,
         %{
           "event" => event,
           "slack_app" => Atom.to_string(slack_app),
           "channel_id" => channel_id,
           "thread_ts" => thread_ts,
           "message_ts" => message_ts,
           "message_ts_micros" => message_ts_micros
         }}

      :error ->
        :error
    end
  end

  defp build_job_args(_event, _app_key), do: :error

  defp resolve_channel(app_key, channel_id) do
    Slack.find_channel(app_key, channel_id) || fetch_channel(app_key, channel_id)
  end

  defp fetch_channel(app_key, channel_id) do
    case API.get_channel_info(app_key, channel_id) do
      {:ok, channel} ->
        %Channel{
          slack_app: app_key,
          channel_id: channel.slack_channel_id,
          channel_name: channel.name,
          is_shared: channel.is_shared,
          is_ext_shared: channel.is_ext_shared
        }

      {:error, reason} ->
        Logger.warning("Failed to fetch Slack channel #{channel_id}: #{inspect(reason)}")
        nil
    end
  end

  defp latest_message_ts_micros(app_key, channel_id, thread_ts) do
    query =
      from job in Job,
        where: job.worker == ^worker_name(),
        where:
          fragment(
            "? @> ?",
            job.args,
            type(^thread_identity(app_key, channel_id, thread_ts), :map)
          ),
        select: max(fragment("(?->>'message_ts_micros')::bigint", job.args))

    Repo.one(query) || -1
  end

  defp parse_slack_ts(ts) when is_binary(ts) do
    case String.split(ts, ".", parts: 2) do
      [seconds, micros] ->
        with {seconds, ""} <- Integer.parse(seconds),
             micros = micros |> String.pad_trailing(6, "0") |> String.slice(0, 6),
             {micros, ""} <- Integer.parse(micros) do
          {:ok, seconds * 1_000_000 + micros}
        else
          _ -> :error
        end

      [seconds] ->
        case Integer.parse(seconds) do
          {seconds, ""} -> {:ok, seconds * 1_000_000}
          _ -> :error
        end

      _parts ->
        :error
    end
  end

  defp duplicate_unique_options do
    [
      period: @duplicate_window_seconds,
      fields: [:worker, :args],
      keys: [:slack_app, :channel_id, :thread_ts, :message_ts_micros],
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]
  end

  defp thread_identity(args) when is_map(args) do
    %{
      "slack_app" => args["slack_app"],
      "channel_id" => args["channel_id"],
      "thread_ts" => args["thread_ts"]
    }
  end

  defp thread_identity(app_key, channel_id, thread_ts) do
    %{
      "slack_app" => Atom.to_string(Bot.normalize_app_key!(app_key)),
      "channel_id" => channel_id,
      "thread_ts" => thread_ts
    }
  end

  defp worker_name, do: Oban.Worker.to_string(__MODULE__)
end
