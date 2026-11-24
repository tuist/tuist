defmodule Symptoms.Contrast do
  @moduledoc """
  The attribute contrast of a shared-cause root (README "Combining", step 5):
  when a shared-cause symptom opens or reopens, the evaluator asks Pulse for
  the top values of host, pod, version and region on the affected span
  entities' spans in the last 15 minutes, and how each value's share of the
  error spans compares with its share of all spans. A value that holds most
  of the errors but few of the spans (a lift well above 1) points at one
  host, pod, version or region.

  The result is written once, as an `annotated` revision whose
  `evidence.attribute_contrast` is

      [%{"attribute" => "pod", "column" => "...", "values" =>
        [%{"value", "errors", "spans", "error_share", "span_share", "lift"}]}]

  Attributes are `{name, column}` pairs in `config :symptoms,
  #{inspect(__MODULE__)}, attributes: [...]`, by default the OpenTelemetry
  resource attributes `host.name`, `k8s.pod.name`, `service.version` and
  `cloud.region` as Pulse flattens them. An attribute whose column Pulse
  rejects (not collected) is left out; a contrast with no attribute is not
  written. The contrast is evidence for people only; it never changes a
  score or a decision.
  """

  import Ecto.Query

  alias Symptoms.Log
  alias Symptoms.Repo
  alias Symptoms.Sources.Pulse
  alias Symptoms.Store.Entity
  alias Symptoms.Store.Symptom

  @lookback 900
  @top 5
  @attributes [
    {"host", "resource_attributes.host.name"},
    {"pod", "resource_attributes.k8s.pod.name"},
    {"version", "resource_attributes.service.version"},
    {"region", "resource_attributes.cloud.region"}
  ]

  @doc """
  Annotates the shared-cause roots among `symptom_ids` that have no contrast
  yet. Returns the ids annotated.
  """
  @spec annotate([String.t()], DateTime.t(), keyword()) :: [String.t()]
  def annotate(symptom_ids, now, opts \\ [])
  def annotate([], _now, _opts), do: []

  def annotate(symptom_ids, now, opts) do
    from(s in Symptom, where: s.id in ^symptom_ids and s.state == "open")
    |> Repo.all()
    |> Enum.filter(&shared_root?/1)
    |> Enum.flat_map(fn symptom ->
      case contrast(symptom, now, opts) do
        [] ->
          []

        contrast ->
          write(symptom.id, contrast, now)
          [symptom.id]
      end
    end)
  end

  defp shared_root?(%Symptom{id: id, document: %{"root" => %{"shared_cause" => true, "root_symptom_id" => id}} = doc}),
    do: is_nil(get_in(doc, ["evidence", "attribute_contrast"]))

  defp shared_root?(_symptom), do: false

  defp contrast(symptom, now, opts) do
    ids = [symptom.id | symptom.document["root"]["member_symptom_ids"] || []]

    entities =
      Repo.all(
        from(s in Symptom,
          join: e in Entity,
          on: e.id == s.entity_id,
          where: s.id in ^ids and like(e.kind, "span_%"),
          select: {e.service, e.key}
        )
      )

    if entities == [] do
      []
    else
      finish = DateTime.to_unix(now)
      range = {finish - @lookback, finish}

      case Pulse.query(totals_sql(entities, range), opts) do
        {:ok, [totals]} -> Enum.flat_map(attributes(), &attribute(&1, totals, entities, range, opts))
        _ -> []
      end
    end
  end

  defp attribute({name, column}, totals, entities, range, opts) do
    case Pulse.query(attribute_sql(column, entities, range), Keyword.put(opts, :limit, @top)) do
      {:ok, [_ | _] = rows} ->
        [%{"attribute" => name, "column" => column, "values" => Enum.map(rows, &value(&1, totals))}]

      _ ->
        []
    end
  end

  defp attributes, do: :symptoms |> Application.get_env(__MODULE__, []) |> Keyword.get(:attributes, @attributes)

  defp value(row, totals) do
    error_share = share(row["errors"], totals["errors"])
    span_share = share(row["spans"], totals["spans"])

    %{
      "value" => row["value"] && to_string(row["value"]),
      "errors" => row["errors"] || 0,
      "spans" => row["spans"] || 0,
      "error_share" => Float.round(error_share, 4),
      "span_share" => Float.round(span_share, 4),
      "lift" => if(span_share > 0, do: Float.round(error_share / span_share, 4))
    }
  end

  defp share(_part, total) when total in [nil, 0], do: 0.0
  defp share(part, total), do: (part || 0) / total

  @doc false
  def totals_sql(entities, range) do
    "SELECT count(*) AS spans, #{errors()} AS errors FROM opentelemetry_traces WHERE #{filter(entities, range)}"
  end

  @doc false
  def attribute_sql(column, entities, range) do
    "SELECT \"#{column}\" AS value, count(*) AS spans, #{errors()} AS errors FROM opentelemetry_traces " <>
      "WHERE #{filter(entities, range)} GROUP BY value ORDER BY errors DESC, spans DESC"
  end

  defp errors, do: "sum(CASE WHEN span_status_code = 'STATUS_CODE_ERROR' THEN 1 ELSE 0 END)"

  defp filter(entities, {start, finish}) do
    services = entities |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.map_join(", ", &Pulse.literal/1)
    names = entities |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.map_join(", ", &Pulse.literal/1)

    "#{Pulse.between("\"timestamp\"", start, finish)} AND service_name IN (#{services}) AND span_name IN (#{names})"
  end

  defp write(id, contrast, now) do
    Repo.transaction(fn ->
      # Read under the log lock, so a revision committed since `annotate/3`
      # read the symptom (a resolution) is the one annotated.
      Log.lock!()
      symptom = Repo.get!(Symptom, id)

      document =
        symptom.document
        |> Map.drop(~w(seq revision schema_version symptom_id))
        |> put_in(["evidence", "attribute_contrast"], contrast)
        |> Map.merge(%{"transition" => "annotated", "updated_at" => DateTime.to_iso8601(now)})

      Log.append!(symptom, document, now)
    end)
  end
end
