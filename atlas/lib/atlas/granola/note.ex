defmodule Atlas.Granola.Note do
  @moduledoc """
  Normalized Granola meeting note data used by routing agents.
  """

  alias Atlas.Accounts.EventRouting

  defstruct [
    :id,
    :object,
    :title,
    :owner,
    :created_at,
    :updated_at,
    :web_url,
    :calendar_event,
    :summary_text,
    :summary_markdown,
    :transcript,
    attendees: [],
    folder_membership: []
  ]

  def from_api(%{"id" => id} = attrs) when is_binary(id) do
    %__MODULE__{
      id: id,
      object: blank_to_nil(attrs["object"]),
      title: blank_to_nil(attrs["title"]),
      owner: normalize_person(attrs["owner"]),
      created_at: parse_datetime(attrs["created_at"]),
      updated_at: parse_datetime(attrs["updated_at"]),
      web_url: blank_to_nil(attrs["web_url"]),
      calendar_event: normalize_calendar_event(attrs["calendar_event"]),
      attendees: normalize_people(attrs["attendees"]),
      folder_membership: normalize_folder_membership(attrs["folder_membership"]),
      summary_text: blank_to_nil(attrs["summary_text"]),
      summary_markdown: blank_to_nil(attrs["summary_markdown"]),
      transcript: attrs["transcript"]
    }
  end

  def from_api(%__MODULE__{} = note), do: note

  def from_api(_attrs), do: nil

  def participant_emails(%__MODULE__{} = note) do
    note
    |> participant_metadata()
    |> Enum.map(& &1["email"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def participant_metadata(%__MODULE__{} = note) do
    []
    |> maybe_add_person(note.owner, "owner")
    |> add_people(note.attendees, "attendee")
    |> maybe_add_email(calendar_value(note, "organiser"), "organizer")
    |> add_people(calendar_value(note, "invitees") || [], "invitee")
    |> merge_participants()
  end

  def to_agent_context(%__MODULE__{} = note) do
    %{
      id: note.id,
      title: note.title,
      created_at: format_datetime(note.created_at),
      updated_at: format_datetime(note.updated_at),
      web_url: note.web_url,
      owner: note.owner,
      calendar_event: note.calendar_event,
      attendees: note.attendees,
      participants: participant_metadata(note),
      participant_emails: participant_emails(note),
      summary_text: truncate(note.summary_text, 8_000),
      summary_markdown: truncate(note.summary_markdown, 16_000)
    }
  end

  def meeting_started_at(%__MODULE__{} = note) do
    note
    |> calendar_value("scheduled_start_time")
    |> parse_datetime()
    |> Kernel.||(note.created_at)
  end

  def markdown(%__MODULE__{summary_markdown: markdown}) when is_binary(markdown), do: markdown

  def markdown(%__MODULE__{title: title, summary_text: summary_text}) do
    [title && "# #{title}", summary_text]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n\n")
  end

  def truncate(nil, _max), do: nil

  def truncate(value, max) when is_binary(value) do
    if String.length(value) > max do
      String.slice(value, 0, max) <> "\n\n[truncated]"
    else
      value
    end
  end

  def truncate(value, _max), do: value

  def format_datetime(nil), do: nil
  def format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp normalize_calendar_event(%{} = event) do
    %{
      "event_title" => blank_to_nil(event["event_title"]),
      "invitees" => normalize_people(event["invitees"]),
      "organiser" => EventRouting.normalize_email(event["organiser"]),
      "calendar_event_id" => blank_to_nil(event["calendar_event_id"]),
      "scheduled_start_time" => blank_to_nil(event["scheduled_start_time"]),
      "scheduled_end_time" => blank_to_nil(event["scheduled_end_time"])
    }
  end

  defp normalize_calendar_event(_event), do: nil

  defp normalize_people(people) when is_list(people) do
    people
    |> Enum.map(&normalize_person/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_people(_people), do: []

  defp normalize_person(%{} = person) do
    email = EventRouting.normalize_email(person["email"])

    if !is_nil(email) do
      %{
        "email" => email,
        "name" => blank_to_nil(person["name"])
      }
    end
  end

  defp normalize_person(_person), do: nil

  defp normalize_folder_membership(folders) when is_list(folders) do
    Enum.map(folders, fn folder ->
      %{
        "id" => folder["id"],
        "object" => folder["object"],
        "name" => folder["name"],
        "parent_folder_id" => folder["parent_folder_id"]
      }
    end)
  end

  defp normalize_folder_membership(_folders), do: []

  defp calendar_value(%__MODULE__{calendar_event: %{} = calendar_event}, key), do: calendar_event[key]
  defp calendar_value(_note, _key), do: nil

  defp maybe_add_person(participants, nil, _role), do: participants

  defp maybe_add_person(participants, person, role) do
    [Map.put(person, "roles", [role]) | participants]
  end

  defp maybe_add_email(participants, nil, _role), do: participants

  defp maybe_add_email(participants, email, role) do
    [%{"email" => email, "name" => nil, "roles" => [role]} | participants]
  end

  defp add_people(participants, people, role) do
    Enum.reduce(people, participants, fn person, acc -> maybe_add_person(acc, person, role) end)
  end

  defp merge_participants(participants) do
    participants
    |> Enum.reduce(%{}, fn participant, acc ->
      email = participant["email"]

      Map.update(acc, email, participant, fn existing ->
        %{
          existing
          | "name" => existing["name"] || participant["name"],
            "roles" => Enum.uniq(existing["roles"] ++ participant["roles"])
        }
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(& &1["email"])
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
