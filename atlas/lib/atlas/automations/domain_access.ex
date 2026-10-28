defmodule Atlas.Automations.DomainAccess do
  @moduledoc "Preserve domain read permissions on definitions, run payloads, approvals and evidence."
  import Ecto.Query

  alias Atlas.Automations.Approval
  alias Atlas.Automations.Attempt
  alias Atlas.Automations.DomainRegistry
  alias Atlas.Automations.Event
  alias Atlas.Automations.Revision
  alias Atlas.Automations.Run
  alias Atlas.Automations.Trigger
  alias Atlas.Automations.Workflow
  alias Atlas.Users

  def permissions(steps) do
    steps
    |> Enum.flat_map(fn step ->
      case step["behavior"] do
        %{"type" => name, "version" => version} ->
          case DomainRegistry.fetch(name, version) do
            {:ok, entry} -> Enum.map(entry["permissions"], &String.replace_suffix(&1, ":write", ":read"))
            _ -> []
          end

        _ ->
          []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def execution_permissions(steps) do
    steps
    |> Enum.flat_map(fn step ->
      case step["behavior"] do
        %{"type" => name, "version" => version} ->
          case DomainRegistry.fetch(name, version) do
            {:ok, entry} -> entry["permissions"]
            _ -> []
          end

        _ ->
          []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def authorize_execution(actor, plan) do
    if Enum.all?(execution_permissions(plan["steps"]), &Users.has_scope?(actor, &1)),
      do: :ok,
      else: {:error, :forbidden}
  end

  def scope(query, actor) do
    query = Ecto.Queryable.to_query(query)
    scopes = Users.scopes_for(actor)

    revisions =
      from v in Revision,
        where: fragment("COALESCE(?->'read_permissions', '[]'::jsonb) <@ to_jsonb(?::text[])", v.plan, ^scopes),
        select: v.id

    runs = from r in Run, where: r.revision_id in subquery(revisions), select: r.id

    case query.from.source do
      {_, Revision} ->
        from x in query, where: x.id in subquery(revisions)

      {_, Run} ->
        from x in query, where: x.id in subquery(runs)

      {_, schema} when schema in [Approval, Attempt, Event] ->
        from x in query, where: x.run_id in subquery(runs)

      {_, Trigger} ->
        from x in query, where: x.revision_id in subquery(revisions)

      {_, Workflow} ->
        from x in query, where: is_nil(x.published_revision_id) or x.published_revision_id in subquery(revisions)

      _ ->
        query
    end
  end
end
