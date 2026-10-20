defmodule Atlas.Granola do
  @moduledoc """
  Coordinates Granola meeting-note ingestion into account timeline events.
  """

  alias Atlas.Accounts.Agents.GranolaMeetingAgent
  alias Atlas.Accounts.Event
  alias Atlas.Audit
  alias Atlas.Granola.API
  alias Atlas.Granola.Note
  alias Atlas.Granola.NoteIngestion
  alias Atlas.Repo
  alias Atlas.Search

  require Logger

  @default_sync_lookback_days 7
  @max_markdown_bytes 32_000

  @doc """
  Syncs recently updated Granola notes and routes each note into an account.
  """
  def sync_notes(opts \\ []) do
    list_notes = Keyword.get(opts, :list_notes, &API.list_notes/1)
    get_note = Keyword.get(opts, :get_note, &API.get_note/1)
    run_agent = Keyword.get(opts, :run_agent, &GranolaMeetingAgent.run/1)

    sync_mode = Keyword.get(opts, :sync_mode, :incremental)
    list_opts = list_opts(opts, sync_mode)

    result =
      case list_notes.(list_opts) do
        :disabled ->
          :disabled

        {:ok, notes} ->
          Enum.reduce_while(notes, {:ok, %{captured: 0, ignored: 0, skipped: 0}}, fn listed_note, {:ok, counts} ->
            case ingest_listed_note(listed_note, get_note, run_agent) do
              {:ok, _event} ->
                {:cont, {:ok, %{counts | captured: counts.captured + 1}}}

              {:ignored, reason} ->
                Logger.info("Ignoring Granola note #{note_id(listed_note)}: #{reason}")
                {:cont, {:ok, %{counts | ignored: counts.ignored + 1}}}

              :skipped ->
                {:cont, {:ok, %{counts | skipped: counts.skipped + 1}}}

              :disabled ->
                {:halt, :disabled}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end)

        {:error, reason} ->
          {:error, reason}
      end

    audit_sync(sync_mode, result)
    result
  end

  @doc """
  Backfills all accessible Granola notes from the beginning.
  """
  def backfill_notes(opts \\ []) do
    opts
    |> Keyword.put(:sync_mode, :backfill)
    |> sync_notes()
  end

  @doc """
  Fetches and routes a single Granola note by ID.
  """
  def ingest_note(note_or_id, opts \\ [])

  def ingest_note(note_id, opts) when is_binary(note_id) do
    get_note = Keyword.get(opts, :get_note, &API.get_note/1)

    with {:ok, %Note{} = note} <- get_note.(note_id) do
      ingest_note(note, opts)
    end
  end

  def ingest_note(%Note{} = note, opts) do
    run_agent = Keyword.get(opts, :run_agent, &GranolaMeetingAgent.run/1)

    case run_agent.(note) do
      {:ok, result} ->
        handle_agent_result(note, result)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stores a Granola note as a meeting timeline event.
  """
  def store_meeting_event(%Note{} = note, params) when is_map(params) do
    occurred_at = resolve_occurred_at(note, params)
    summary = resolve_summary(note, params)
    markdown = Note.truncate(param(params, "markdown", :markdown) || Note.markdown(note), @max_markdown_bytes)

    attrs = %{
      "external_id" => note.id,
      "source" => "granola",
      "kind" => "meeting",
      "title" => resolve_title(note, params),
      "body" => markdown,
      "occurred_at" => occurred_at,
      "url" => note.web_url,
      "account_id" => param(params, "account_id", :account_id),
      "metadata" => metadata(note, params, summary, markdown)
    }

    upsert_meeting_event(attrs)
  end

  defp ingest_listed_note(listed_note, get_note, run_agent) do
    with id when is_binary(id) <- note_id(listed_note),
         false <- current_note_ingestion?(id, listed_note),
         {:ok, %Note{} = note} <- get_note.(id) do
      ingest_note(note, run_agent: run_agent)
    else
      nil -> {:error, :invalid_note_id}
      true -> :skipped
      {:error, reason} -> {:error, reason}
      :disabled -> :disabled
    end
  end

  defp current_note_ingestion?(id, %Note{} = note) do
    case {note.updated_at, Repo.get_by(NoteIngestion, external_id: id)} do
      {%DateTime{} = note_updated_at, %NoteIngestion{note_updated_at: %DateTime{} = stored_updated_at}} ->
        DateTime.compare(stored_updated_at, DateTime.truncate(note_updated_at, :second)) == :eq

      {_note_updated_at, nil} ->
        current_note_event?(id, note)

      _other ->
        false
    end
  end

  defp current_note_ingestion?(_id, _note), do: false

  defp current_note_event?(id, %Note{} = note) do
    updated_at = Note.format_datetime(note.updated_at)

    is_binary(updated_at) and
      case Repo.get_by(Event, source: "granola", external_id: id) do
        %Event{metadata: %{"updated_at" => stored_updated_at}} -> stored_updated_at == updated_at
        _event -> false
      end
  end

  defp handle_agent_result(note, result) do
    case param(result, "status", :status) do
      "captured" ->
        maybe_log_invalid_captured_ids(result)

        case Repo.get_by(Event, source: "granola", external_id: note.id) do
          %Event{} = event ->
            with {:ok, _ingestion} <- record_note_ingestion(note, "captured", nil, event) do
              {:ok, event}
            end

          nil ->
            {:error, {:invalid_agent_result, result}}
        end

      "ignored" ->
        reason =
          case param(result, "reason", :reason) do
            "internal_meeting" -> :internal_meeting
            "not_account" -> :not_account
            _ -> :no_matching_account
          end

        with {:ok, ingestion} <- record_note_ingestion(note, "ignored", Atom.to_string(reason), nil) do
          audit_ignored_note(ingestion)
          {:ignored, reason}
        end

      _ ->
        {:error, {:invalid_agent_result, result}}
    end
  end

  defp resolve_occurred_at(note, params) do
    parse_occurred_at(param(params, "occurred_at", :occurred_at)) ||
      Note.meeting_started_at(note) ||
      DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp record_note_ingestion(%Note{} = note, status, ignore_reason, event) do
    attrs = %{
      "external_id" => note.id,
      "note_updated_at" => note.updated_at,
      "status" => status,
      "ignore_reason" => ignore_reason,
      "account_event_id" => event && event.id,
      "metadata" => %{
        "title" => note.title,
        "web_url" => note.web_url
      }
    }

    %NoteIngestion{}
    |> NoteIngestion.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:note_updated_at, :status, :ignore_reason, :account_event_id, :metadata, :updated_at]},
      conflict_target: [:external_id],
      returning: true
    )
  end

  defp resolve_title(note, params) do
    param(params, "title", :title) ||
      calendar_value(note, "event_title") ||
      note.title ||
      "Granola meeting"
  end

  defp resolve_summary(note, params) do
    param(params, "summary", :summary) ||
      note.summary_text ||
      "Granola meeting notes captured for this account."
  end

  defp metadata(note, params, summary, markdown) do
    %{
      "granola_note_id" => note.id,
      "owner" => note.owner,
      "calendar_event" => note.calendar_event,
      "attendees" => note.attendees,
      "participants" => Note.participant_metadata(note),
      "agent_participants" => param(params, "participants", :participants) || [],
      "folder_membership" => note.folder_membership,
      "summary" => summary,
      "summary_text" => note.summary_text,
      "summary_markdown" => markdown,
      "matched_on" => param(params, "matched_on", :matched_on),
      "created_at" => Note.format_datetime(note.created_at),
      "updated_at" => Note.format_datetime(note.updated_at)
    }
  end

  defp upsert_meeting_event(attrs) do
    result =
      %Event{}
      |> Event.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:account_id, :title, :body, :occurred_at, :url, :metadata]},
        conflict_target: [:source, :external_id],
        returning: true
      )

    case result do
      {:ok, event} = success ->
        Search.index_account_event(event)
        audit_meeting_event(event)
        success

      error ->
        error
    end
  end

  defp list_opts(opts, :backfill) do
    Keyword.take(opts, [:created_before, :created_after, :page_size])
  end

  defp list_opts(opts, _sync_mode) do
    opts
    |> Keyword.take([:created_before, :created_after, :updated_after, :page_size])
    |> Keyword.put_new(:updated_after, default_updated_after())
  end

  defp default_updated_after do
    days =
      :atlas
      |> Application.get_env(:granola, [])
      |> Keyword.get(:sync_lookback_days, @default_sync_lookback_days)

    DateTime.utc_now()
    |> DateTime.add(-days * 24 * 60 * 60, :second)
    |> DateTime.truncate(:second)
  end

  defp note_id(%Note{id: id}), do: id
  defp note_id(%{"id" => id}) when is_binary(id), do: id
  defp note_id(_note), do: nil

  defp calendar_value(%Note{calendar_event: %{} = calendar_event}, key), do: calendar_event[key]
  defp calendar_value(_note, _key), do: nil

  defp param(params, string_key, atom_key) do
    Map.get(params, string_key) || Map.get(params, atom_key)
  end

  defp parse_occurred_at(nil), do: nil

  defp parse_occurred_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end

  defp parse_occurred_at(_value), do: nil

  defp maybe_log_invalid_captured_ids(result) do
    invalid_ids =
      [event_id: param(result, "event_id", :event_id), account_id: param(result, "account_id", :account_id)]
      |> Enum.reject(fn {_key, value} -> valid_uuid?(value) end)

    if invalid_ids != [] do
      details =
        invalid_ids
        |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{inspect(value)}" end)

      Logger.warning("granola_meeting_agent returned invalid captured identifiers: #{details}")
    end
  end

  defp valid_uuid?(nil), do: true
  defp valid_uuid?(value) when is_binary(value), do: match?({:ok, _}, Atlas.UUIDv7.cast(value))
  defp valid_uuid?(_value), do: false

  defp audit_sync(_sync_mode, :disabled), do: :ok

  defp audit_sync(sync_mode, {:ok, summary}) do
    Audit.record(
      "granola.sync_completed",
      %{
        target_type: "granola_sync",
        target_label: Atom.to_string(sync_mode),
        metadata: %{
          "sync_mode" => Atom.to_string(sync_mode),
          "captured" => summary.captured,
          "ignored" => summary.ignored,
          "skipped" => summary.skipped
        }
      },
      interface: "worker"
    )
  end

  defp audit_sync(sync_mode, {:error, _reason}) do
    Audit.record(
      "granola.sync_failed",
      %{
        target_type: "granola_sync",
        target_label: Atom.to_string(sync_mode),
        metadata: %{"sync_mode" => Atom.to_string(sync_mode)}
      },
      interface: "worker"
    )
  end

  defp audit_meeting_event(%Event{} = event) do
    Audit.record(
      "account_event.synced_from_granola",
      %{
        target_type: "account_event",
        target_id: event.id,
        target_label: event.title,
        metadata: %{
          "path" => "/commercial/sales/accounts/#{event.account_id}",
          "account_id" => event.account_id,
          "source" => event.source,
          "external_id" => event.external_id
        }
      },
      interface: "worker"
    )
  end

  defp audit_ignored_note(%NoteIngestion{} = ingestion) do
    Audit.record(
      "granola_note.ignored",
      %{
        target_type: "granola_note",
        target_id: ingestion.external_id,
        target_label: ingestion.metadata["title"],
        metadata: %{
          "note_updated_at" => ingestion.note_updated_at,
          "reason" => ingestion.ignore_reason
        }
      },
      interface: "worker"
    )
  end
end
