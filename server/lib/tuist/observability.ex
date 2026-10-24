defmodule Tuist.Observability do
  @moduledoc """
  Process-local, allowlisted observability attribution. A selected resource is the
  target; authentication describes the caller, not necessarily that target.

  Background work must explicitly bind an authoritative, loaded resource with
  `set_selection/1`. Use `with_context/2` for shorter scopes in reused processes,
  not whole jobs that report errors after unwinding. Job arguments and flag actors
  never establish a target.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias Tuist.Projects.Project

  require Logger

  @key {__MODULE__, :context}
  @job_span_key {__MODULE__, :job_span}
  @identity_keys ~w(auth_user_id auth_project_id auth_account_id auth_account_handle selected_account_id selected_account_handle selected_project_id selected_project_handle selected_account_customer_id)a
  @selection_keys ~w(selected_account_id selected_account_handle selected_project_id selected_project_handle selected_account_customer_id)a
  @log_keys @identity_keys -- [:selected_account_customer_id]
  @max_flags 32

  def attach_oban do
    :telemetry.attach_many(
      {__MODULE__, :oban},
      [[:oban, :job, :start], [:oban, :job, :stop], [:oban, :job, :exception]],
      &__MODULE__.handle_job_event/4,
      nil
    )
  end

  def handle_job_event([:oban, :job, :start], _measurements, %{job: job}, _config) do
    clear()

    span =
      :otel_tracer.start_span(%{}, :opentelemetry.get_tracer(__MODULE__), "oban.job", %{
        kind: :consumer,
        attributes: %{"oban.worker" => job.worker, "oban.queue" => job.queue}
      })

    Process.put(@job_span_key, span)
    :otel_tracer.set_current_span(span)
  end

  def handle_job_event([:oban, :job, event], _measurements, _metadata, _config) when event in [:stop, :exception] do
    if span = Process.delete(@job_span_key) do
      :otel_tracer.set_current_span(span)
      refresh()
      if event == :exception, do: :otel_span.set_status(span, :error)
      :otel_span.end_span(span)
    end

    # Keep process attribution (including the span ID) through every exception
    # reporter, regardless of telemetry handler order. Oban owns this process's
    # lifetime; the next job's start resets context if an inline executor reuses it.
    :ok
  end

  def set_authenticated_subject(subject) do
    replace(%{identity: auth_identity(subject), feature_flags: %{}})
  end

  def set_selection(assigns) do
    context = current()
    identity = context.identity |> Map.drop(@selection_keys) |> Map.merge(selection_identity(assigns))
    replace_identity(context, identity)
  end

  def set_context(subject, assigns) do
    identity = Map.merge(auth_identity(subject), selection_identity(assigns))
    replace_identity(current(), identity)
  end

  def clear, do: replace(%{identity: %{}, feature_flags: %{}})

  def refresh do
    context = current()
    project(context, context)
  end

  def snapshot do
    # Propagate tracing, not arbitrary baggage or other request context values.
    %{context: current(), otel_context: :otel_tracer.set_current_span(%{}, :otel_tracer.current_span_ctx())}
  end

  @doc "Installs a safe snapshot for a new task's entire lifetime, including crash reporting."
  def attach(snapshot) do
    token = :otel_ctx.attach(snapshot.otel_context)
    replace(snapshot.context)
    token
  end

  def with_snapshot(snapshot, fun) do
    previous = current()
    token = attach(snapshot)

    try do
      fun.()
    after
      :otel_ctx.detach(token)
      replace(previous)
    end
  end

  def with_context(assigns, fun) do
    previous = current()

    try do
      replace(%{identity: selection_identity(assigns), feature_flags: %{}})
      fun.()
    after
      replace(previous)
    end
  end

  # The value is the effective helper result, including environment overrides,
  # inversions and compound gates. Recording must not perform another flag read.
  def feature_flag_evaluated(flag, actor, enabled) when is_atom(flag) and is_boolean(enabled) do
    {actor_type, actor_id} = actor_identity(actor)

    evaluation = %{
      flag: Atom.to_string(flag),
      enabled: enabled,
      actor_type: actor_type,
      actor_id: actor_id
    }

    :telemetry.execute([:tuist, :feature_flag, :evaluation], %{count: 1}, evaluation)

    Logger.debug("Feature flag evaluated",
      feature_flag: evaluation.flag,
      feature_flag_enabled: enabled,
      feature_flag_actor_type: actor_type,
      feature_flag_actor_id: actor_id
    )

    context = current()

    if matches_target?(evaluation, context.identity) do
      flags = Map.put(context.feature_flags, evaluation.flag, evaluation)

      if map_size(flags) <= @max_flags do
        replace(%{context | feature_flags: flags})
      end
    end

    enabled
  end

  defp current, do: Process.get(@key, %{identity: %{}, feature_flags: %{}})

  defp replace_identity(context, identity) do
    flags =
      Map.filter(context.feature_flags, fn {_flag, evaluation} -> matches_target?(evaluation, identity) end)

    replace(%{context | identity: identity, feature_flags: flags})
  end

  defp replace(context) do
    previous = current()
    Process.put(@key, context)
    project(context, previous)
  end

  defp project(context, previous) do
    identity = Map.take(context.identity, @log_keys)
    flags = flag_tags(context.feature_flags)
    previous_flags = flag_tags(previous.feature_flags)

    Logger.metadata(Enum.map(@log_keys, &{&1, identity[&1]}))
    Logger.metadata(feature_flags: if(flags == %{}, do: nil, else: JSON.encode!(flags)))

    attributes = Map.new(identity, fn {key, value} -> {Atom.to_string(key), value} end)
    old_attributes = Map.new(Map.take(previous.identity, @log_keys), fn {key, value} -> {Atom.to_string(key), value} end)

    # OTel has no public attribute deletion API. Clear removed attribution on
    # a reused span rather than leaving the previous tenant's ID or decision.
    old_attributes
    |> Map.merge(previous_flags)
    |> Map.keys()
    |> Enum.reject(&(Map.has_key?(attributes, &1) or Map.has_key?(flags, &1)))
    |> Enum.each(&OpenTelemetry.Tracer.set_attribute(&1, ""))

    Enum.each(Map.merge(attributes, flags), fn {key, value} -> OpenTelemetry.Tracer.set_attribute(key, value) end)
    project_sentry(context, flags)
    :ok
  end

  defp project_sentry(context, tags) do
    # SDK setters merge. Selectively remove our keys first, preserving request
    # scrubbing, breadcrumbs, attachments and other integrations' context. The
    # SDK's public metadata-key accessor avoids hard-coding its storage key.
    key = Sentry.Context.__logger_metadata_key__()
    sentry = Logger.metadata()[key] || %{}
    extra = Map.drop(Map.get(sentry, :extra, %{}), @identity_keys ++ [:feature_flags])

    clean_tags =
      Map.reject(Map.get(sentry, :tags, %{}), fn {key, _value} ->
        key in @identity_keys or key in Enum.map(@identity_keys, &Atom.to_string/1) or
          (is_binary(key) and String.starts_with?(key, "feature_flag."))
      end)

    Logger.metadata([{key, sentry |> Map.put(:extra, extra) |> Map.put(:tags, clean_tags)}])

    if Environment.error_tracking_enabled?() do
      extra =
        if context.feature_flags == %{},
          do: context.identity,
          else:
            Map.put(context.identity, :feature_flags, context.feature_flags |> Map.values() |> Enum.sort_by(& &1.flag))

      if extra != %{}, do: Sentry.Context.set_extra_context(extra)

      tags = Map.merge(Map.take(context.identity, @log_keys), tags)
      if tags != %{}, do: Sentry.Context.set_tags_context(tags)
    end
  end

  defp flag_tags(flags) do
    Map.new(flags, fn {name, evaluation} -> {"feature_flag.#{name}", to_string(evaluation.enabled)} end)
  end

  defp matches_target?(%{actor_type: "global"}, _identity), do: true

  defp matches_target?(%{actor_type: "account", actor_id: id}, identity),
    do: not is_nil(id) and id == identity[:selected_account_id]

  defp matches_target?(%{actor_type: "project", actor_id: id}, identity),
    do: not is_nil(id) and id == identity[:selected_project_id]

  defp matches_target?(_, _), do: false

  defp actor_identity(nil), do: {"global", nil}
  defp actor_identity(%Account{id: id}), do: {"account", id}
  defp actor_identity(%Project{id: id}), do: {"project", id}
  defp actor_identity(%User{id: id}), do: {"user", id}
  defp actor_identity(_), do: {"unknown", nil}

  defp auth_identity(%User{id: id, account: %Account{} = account}),
    do: %{auth_user_id: id, auth_account_id: account.id, auth_account_handle: account.name}

  defp auth_identity(%Project{id: id, account: %Account{} = account}),
    do: %{auth_project_id: id, auth_account_id: account.id, auth_account_handle: account.name}

  defp auth_identity(%AuthenticatedAccount{account: %Account{} = account}),
    do: %{auth_account_id: account.id, auth_account_handle: account.name}

  defp auth_identity(_), do: %{}

  defp selection_identity(assigns) do
    project = assigns[:selected_project]
    account = selection_account(project, assigns[:selected_account])

    identity =
      case account do
        %Account{} ->
          %{
            selected_account_id: account.id,
            selected_account_handle: account.name,
            selected_account_customer_id: account.customer_id
          }

        _ ->
          %{}
      end

    identity =
      case project do
        %Project{} ->
          Map.merge(identity, %{
            selected_project_id: project.id,
            selected_project_handle: project.name,
            selected_account_id: project.account_id || identity[:selected_account_id]
          })

        _ ->
          identity
      end

    Map.reject(identity, fn {_key, value} -> is_nil(value) end)
  end

  defp selection_account(%Project{account: %Account{id: id} = account, account_id: account_id}, _selected)
       when is_nil(account_id) or account_id == id, do: account

  defp selection_account(%Project{account_id: id}, %Account{id: id} = account), do: account
  defp selection_account(%Project{}, _selected), do: nil
  defp selection_account(_project, account), do: account
end
