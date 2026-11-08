defmodule Tuist.Notifications.Events.PreviewPublished do
  @moduledoc """
  A new preview of a project finished uploading (`Tuist.Push.notify_new_preview/1`).

  Conditions, all optional:

  - `track` and `git_branch`: `%{"operator" => "is" | "contains", "value" => text}`.
    `is` matches the value exactly; `contains` matches text anywhere in it,
    ignoring case, for patterns such as `release/`.
  - `published_by`: `"anyone"` (the default) or `"me"`, the preview's creator.
  """
  @behaviour Tuist.Notifications.Event

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.AppBuilds.Preview
  alias Tuist.Repo

  @value_fields ["track", "git_branch"]
  @operators ["is", "contains"]
  @publishers ["anyone", "me"]
  @max_value_length 255
  @options_window_seconds 90 * 24 * 60 * 60

  @impl true
  def id, do: "preview_published"

  @impl true
  def title, do: "Preview published"

  @impl true
  def description, do: "A new preview of a project is published."

  @impl true
  def authorization_action, do: :notification_preview_published

  @impl true
  def conditions_schema do
    value_match = %{
      "type" => ["object", "null"],
      "properties" => %{
        "operator" => %{"type" => "string", "enum" => @operators},
        "value" => %{"type" => "string", "minLength" => 1, "maxLength" => @max_value_length}
      },
      "required" => ["operator", "value"],
      "additionalProperties" => false
    }

    %{
      "type" => "object",
      "properties" => %{
        "track" => Map.put(value_match, "description", "The preview's track, for example `beta`."),
        "git_branch" => Map.put(value_match, "description", "The Git branch the preview was built from."),
        "published_by" => %{
          "type" => "string",
          "enum" => @publishers,
          "description" => "`me` only matches previews the user published. Defaults to `anyone`."
        }
      },
      "additionalProperties" => false
    }
  end

  @impl true
  def cast_conditions(conditions) when is_map(conditions) do
    conditions = Map.new(conditions, fn {key, value} -> {to_string(key), value} end)

    with [] <- Map.keys(conditions) -- ["published_by" | @value_fields],
         {:ok, matches} <- cast_value_matches(conditions),
         {:ok, publisher} <- cast_publisher(Map.get(conditions, "published_by")) do
      {:ok, if(publisher == "me", do: Map.put(matches, "published_by", "me"), else: matches)}
    else
      [_ | _] = unknown -> {:error, "has unknown conditions: #{Enum.join(unknown, ", ")}"}
      {:error, _message} = error -> error
    end
  end

  def cast_conditions(_conditions), do: {:error, "must be an object"}

  defp cast_value_matches(conditions) do
    Enum.reduce_while(@value_fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case cast_value_match(Map.get(conditions, field)) do
        {:ok, nil} ->
          {:cont, {:ok, acc}}

        {:ok, match} ->
          {:cont, {:ok, Map.put(acc, field, match)}}

        :error ->
          {:halt,
           {:error, "#{field} must be an operator (is or contains) and a value up to #{@max_value_length} characters"}}
      end
    end)
  end

  defp cast_value_match(nil), do: {:ok, nil}

  defp cast_value_match(match) when is_map(match) do
    match = Map.new(match, fn {key, value} -> {to_string(key), value} end)

    with [] <- Map.keys(match) -- ["operator", "value"],
         operator when operator in @operators <- Map.get(match, "operator"),
         value when is_binary(value) <- Map.get(match, "value"),
         value = String.trim(value),
         true <- value != "" and String.length(value) <= @max_value_length do
      {:ok, %{"operator" => operator, "value" => value}}
    else
      _ -> :error
    end
  end

  defp cast_value_match(_match), do: :error

  defp cast_publisher(nil), do: {:ok, "anyone"}
  defp cast_publisher(publisher) when publisher in @publishers, do: {:ok, publisher}
  defp cast_publisher(_publisher), do: {:error, "published_by must be anyone or me"}

  @impl true
  def matches?(conditions, %Preview{} = preview, user_id) do
    value_matches?(conditions["track"], preview.track) and
      value_matches?(conditions["git_branch"], preview.git_branch) and
      (conditions["published_by"] != "me" or published_by?(preview, user_id))
  end

  defp value_matches?(nil, _value), do: true
  defp value_matches?(_match, value) when not is_binary(value), do: false
  defp value_matches?(%{"operator" => "is", "value" => expected}, value), do: value == expected

  defp value_matches?(%{"operator" => "contains", "value" => text}, value),
    do: String.contains?(String.downcase(value), String.downcase(text))

  defp published_by?(%Preview{created_by_account_id: nil}, _user_id), do: false

  defp published_by?(%Preview{created_by_account_id: account_id}, user_id) do
    Account |> where([a], a.id == ^account_id and a.user_id == ^user_id) |> Repo.exists?()
  end

  @doc """
  The tracks and branches of the project's previews from the last 90 days,
  each sorted and without duplicates, for clients to offer as `is` values.
  """
  @impl true
  def condition_options(project) do
    since = DateTime.add(DateTime.utc_now(), -@options_window_seconds)

    previews =
      Preview
      |> where([p], p.project_id == ^project.id and p.inserted_at > ^since)
      |> order_by([p], desc: p.inserted_at)
      |> limit(1000)
      |> select([p], %{track: p.track, git_branch: p.git_branch})
      |> Repo.all()

    %{
      "track" => distinct_sorted(previews, :track),
      "git_branch" => distinct_sorted(previews, :git_branch)
    }
  end

  defp distinct_sorted(previews, field) do
    previews |> Enum.map(&Map.get(&1, field)) |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq() |> Enum.sort()
  end
end
