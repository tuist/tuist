defmodule Atlas.Evidence do
  @moduledoc """
  Typed, queryable evidence references shared by domain proposals and briefs.

  Domain records remain authoritative. Evidence links only describe which
  records justified a proposal, claim, decision, or suggested next step.
  """

  import Ecto.Query

  alias Atlas.Evidence.Link
  alias Atlas.Evidence.Resolver
  alias Atlas.Repo

  @sensitivity_rank %{"public" => 0, "internal" => 1, "restricted" => 2}

  def source_classes, do: Link.source_classes()
  def record_types, do: Link.record_types()

  def sensitivity_for(evidence, declared_sensitivity) when is_list(evidence) do
    Enum.reduce_while(evidence, {:ok, declared_sensitivity}, fn item, {:ok, sensitivity} ->
      record_type = value(item, :record_type)
      record_id = value(item, :record_id)

      case Resolver.resolve(record_type, record_id) do
        {:ok, resolved} -> {:cont, {:ok, most_sensitive(sensitivity, resolved.sensitivity)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def link(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    with :ok <- validate_derivation(attrs),
         {:ok, resolved} <- Resolver.resolve(attrs["record_type"], attrs["record_id"]) do
      attrs =
        attrs
        |> Map.put("sensitivity", most_sensitive(attrs["sensitivity"] || "internal", resolved.sensitivity))
        |> Map.put_new("occurred_at", resolved.occurred_at)

      result =
        %Link{}
        |> Link.changeset(attrs)
        |> Repo.insert(
          on_conflict: :nothing,
          conflict_target: [:subject_type, :subject_id, :record_type, :record_id],
          returning: true
        )

      fetch_existing_link(result, attrs)
    end
  end

  def link_all(subject_type, subject_id, evidence) when is_list(evidence) do
    Repo.transaction(fn ->
      evidence
      |> Enum.with_index()
      |> Enum.map(fn {attrs, position} ->
        attrs =
          attrs
          |> Map.new()
          |> Map.put(:subject_type, subject_type)
          |> Map.put(:subject_id, subject_id)
          |> Map.put_new(:position, position)

        case link(attrs) do
          {:ok, link} -> link
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
  end

  @doc """
  Links the evidence whose records still resolve and reports the rest.

  Use where the subject must be recorded even when a reference has gone stale,
  such as approving a proposal that outlived the event it cited. Linking
  through `link_all/3` there would roll back the surrounding transaction and
  lose the decision itself over a broken pointer.
  """
  def link_resolvable(subject_type, subject_id, evidence) when is_list(evidence) do
    {resolvable, unresolvable} =
      Enum.split_with(evidence, fn attrs ->
        match?({:ok, _resolved}, Resolver.resolve(value(attrs, :record_type), value(attrs, :record_id)))
      end)

    with {:ok, links} <- link_all(subject_type, subject_id, resolvable) do
      {:ok, links, unresolvable}
    end
  end

  def for_subject(subject_type, subject_id) do
    Link
    |> where([link], link.subject_type == ^subject_type and link.subject_id == ^subject_id)
    |> order_by([link], asc: link.position, asc: link.inserted_at)
    |> Repo.all()
  end

  def justified_by(record_type, record_id) do
    Link
    |> where([link], link.record_type == ^record_type and link.record_id == ^record_id)
    |> order_by([link], desc: link.inserted_at)
    |> Repo.all()
  end

  def most_sensitive(left, right) do
    if Map.get(@sensitivity_rank, left, 1) >= Map.get(@sensitivity_rank, right, 1), do: left, else: right
  end

  def permits?(ceiling, sensitivity) do
    Map.get(@sensitivity_rank, ceiling, -1) >= Map.get(@sensitivity_rank, sensitivity, 99)
  end

  defp validate_derivation(%{"record_type" => "brief_item", "source_class" => source_class})
       when source_class not in ["decided", "action_result"] do
    {:error, :derived_content_is_not_evidence}
  end

  defp validate_derivation(_attrs), do: :ok

  defp stringify_keys(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp fetch_existing_link({:ok, %Link{}}, attrs) do
    {:ok,
     Repo.get_by!(Link,
       subject_type: attrs["subject_type"],
       subject_id: attrs["subject_id"],
       record_type: attrs["record_type"],
       record_id: attrs["record_id"]
     )}
  end

  defp fetch_existing_link({:error, changeset}, _attrs), do: {:error, changeset}
end
