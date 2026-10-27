defmodule Atlas.Automations.Resources do
  @moduledoc "Authorized CRUD for editable primitives and read-only durable execution evidence."
  import Ecto.Query

  alias Atlas.Automations
  alias Atlas.Automations.Approval
  alias Atlas.Automations.Attempt
  alias Atlas.Automations.Behavior
  alias Atlas.Automations.Catalog
  alias Atlas.Automations.Contract
  alias Atlas.Automations.DomainAccess
  alias Atlas.Automations.Event
  alias Atlas.Automations.ListQuery
  alias Atlas.Automations.Revision
  alias Atlas.Automations.Run
  alias Atlas.Automations.Trigger
  alias Atlas.Automations.Workflow
  alias Atlas.Repo
  alias Oban.Cron.Expression

  def get(actor, "types", name) do
    with :ok <- Automations.authorize(actor, :read) do
      case Enum.find(Catalog.types(), &(&1.reference == name or (&1.name == name and &1.version == 1))) do
        nil -> {:error, :not_found}
        type -> {:ok, type}
      end
    end
  end

  def get(actor, "workflows", id), do: Automations.get_workflow(actor, id)
  def get(actor, "executions", id), do: Automations.get_run(actor, id)

  def get(actor, kind, id) do
    with :ok <- Automations.authorize(actor, :read), :ok <- identifier(id), {:ok, query} <- query(kind) do
      case Repo.get(DomainAccess.scope(query, actor), id) do
        nil -> {:error, :not_found}
        record -> {:ok, record}
      end
    end
  end

  def list(actor, "triggers", params) do
    with :ok <- Automations.authorize(actor, :read) do
      query = ListQuery.apply("triggers", params)
      {:ok, Flop.run(DomainAccess.scope(query, actor), %Flop{page: page(params["page"]), page_size: 20}, repo: Repo)}
    end
  end

  def list(actor, kind, params) when kind in ~w(revisions attempts events) do
    {parent, field, parent_schema} =
      if kind == "revisions", do: {"workflow_id", :workflow_id, Workflow}, else: {"run_id", :run_id, Run}

    id = params[parent]

    with :ok <- Automations.authorize(actor, :read), :ok <- identifier(id), {:ok, query} <- query(kind) do
      if Repo.exists?(from p in DomainAccess.scope(parent_schema, actor), where: p.id == ^id) do
        flop = %Flop{page: page(params["page"]), page_size: 20}
        query = from r in DomainAccess.scope(query, actor), where: field(r, ^field) == ^id
        order = if kind == "events", do: [desc: :sequence], else: [desc: :inserted_at, desc: :id]
        {:ok, Flop.run(order_by(query, ^order), flop, repo: Repo)}
      else
        {:error, :not_found}
      end
    end
  end

  def update_workflow(actor, id, attrs, opts) do
    locked(actor, Workflow, id, fn workflow ->
      saved = update!(Workflow.changeset(workflow, attrs))
      Automations.audit(actor, "workflow.updated", saved, "workflows", opts)
      Repo.preload(saved, :published_revision)
    end)
  end

  def delete_workflow(actor, id, opts) do
    locked(actor, Workflow, id, fn workflow ->
      owner!(workflow.created_by_id, actor)
      if Repo.exists?(from v in Revision, where: v.workflow_id == ^id), do: Repo.rollback(:workflow_in_use)
      deleted!(actor, workflow, "workflow.deleted", "workflows", opts)
    end)
  end

  def update_behavior(actor, id, attrs, opts) do
    locked(actor, Behavior, id, fn behavior ->
      owner!(behavior.created_by_id, actor)
      changeset = Behavior.changeset(behavior, Catalog.prepare_attributes(attrs, behavior.type))

      with {:ok, candidate} <- Ecto.Changeset.apply_action(changeset, :update),
           {:ok, _} <- Catalog.snapshot(candidate) do
        saved = update!(changeset)
        Automations.audit(actor, "behavior.updated", saved, "behaviors", opts)
        saved
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_behavior(actor, id, opts) do
    locked(actor, Behavior, id, fn behavior ->
      owner!(behavior.created_by_id, actor)
      deleted!(actor, behavior, "behavior.deleted", "behaviors", opts)
    end)
  end

  def update_trigger(actor, id, attrs, opts) do
    locked(actor, Trigger, id, fn trigger ->
      trigger_owner!(trigger, actor, attrs)
      fields = Map.take(attrs, ~w(name cron input enabled))
      changeset = trigger |> Trigger.changeset(fields) |> Ecto.Changeset.cast(fields, [:enabled])

      with {:ok, candidate} <- Ecto.Changeset.apply_action(changeset, :update), :ok <- trigger_input(candidate) do
        changeset =
          if candidate.kind == "schedule" && candidate.cron != trigger.cron do
            Ecto.Changeset.change(changeset, next_run_at: candidate.cron |> Expression.parse!() |> Expression.next_at())
          else
            changeset
          end

        saved = update!(changeset)
        Automations.audit(actor, "trigger.updated", saved, section(saved), opts)
        saved
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_trigger(actor, id, attrs, opts) do
    locked(actor, Trigger, id, fn trigger ->
      trigger_owner!(trigger, actor, attrs)
      deleted!(actor, trigger, "trigger.deleted", section(trigger), opts)
    end)
  end

  def rotate_trigger(actor, id, attrs, opts) do
    locked(actor, Trigger, id, fn trigger ->
      trigger_owner!(trigger, actor, attrs)
      if trigger.kind != "webhook", do: Repo.rollback(:invalid_trigger_kind)
      secret = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      saved = update!(Ecto.Changeset.change(trigger, token_hash: :crypto.hash(:sha256, secret)))
      Automations.audit(actor, "trigger.credential_rotated", saved, "webhooks", opts)
      %{trigger: saved, secret: secret}
    end)
  end

  defp query("workflows"), do: {:ok, Workflow}
  defp query("behaviors"), do: {:ok, Behavior}
  defp query("revisions"), do: {:ok, Revision}
  defp query("executions"), do: {:ok, Run}
  defp query("attempts"), do: {:ok, Attempt}
  defp query("events"), do: {:ok, Event}
  defp query("approvals"), do: {:ok, Approval}
  defp query("triggers"), do: {:ok, Trigger}
  defp query("schedules"), do: {:ok, from(t in Trigger, where: t.kind == "schedule")}
  defp query("webhooks"), do: {:ok, from(t in Trigger, where: t.kind == "webhook")}
  defp query(_), do: {:error, :invalid_kind}

  defp locked(actor, schema, id, fun) do
    with :ok <- Automations.authorize(actor, :write), :ok <- identifier(id) do
      Repo.transaction(fn ->
        record =
          Repo.one(from r in DomainAccess.scope(schema, actor), where: r.id == ^id, lock: "FOR UPDATE") ||
            Repo.rollback(:not_found)

        fun.(record)
      end)
    end
  end

  defp owner!(owner, actor), do: if(owner != actor.id, do: Repo.rollback(:forbidden))

  defp trigger_owner!(trigger, actor, attrs) do
    owner!(trigger.execution_user_id, actor)
    if attrs["kind"] && attrs["kind"] != trigger.kind, do: Repo.rollback(:not_found)
  end

  defp trigger_input(trigger) do
    schema =
      if trigger.kind == "schedule",
        do: Repo.get!(Revision, trigger.revision_id).input_schema,
        else: %{"type" => "object"}

    Contract.validate(schema, trigger.input)
  end

  defp update!(changeset) do
    case Repo.update(changeset) do
      {:ok, saved} -> saved
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp deleted!(actor, record, action, section, opts) do
    Repo.delete!(record)
    Automations.audit(actor, action, record, section, opts)
    %{id: record.id, deleted: true}
  end

  defp identifier(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> :ok
      _ -> {:error, :not_found}
    end
  end

  defp page(value) when is_integer(value) and value > 0 and value <= 100_000, do: value

  defp page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> page(n)
      _ -> 1
    end
  end

  defp page(_), do: 1
  defp section(%{kind: "schedule"}), do: "schedules"
  defp section(_), do: "webhooks"
end
