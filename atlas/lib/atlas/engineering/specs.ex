defmodule Atlas.Engineering.Specs do
  @moduledoc """
  Editable engineering proposals belonging to an engineering project.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Engineering.Domains.Domain
  alias Atlas.Engineering.Projects.Project
  alias Atlas.Engineering.Projects.ProjectDomain
  alias Atlas.Engineering.Specs.Comment
  alias Atlas.Engineering.Specs.Revision
  alias Atlas.Engineering.Specs.Spec
  alias Atlas.Engineering.Specs.View
  alias Atlas.Repo
  alias Atlas.Users.User
  alias AtlasWeb.Markdown
  alias Ecto.Changeset

  @spec_number_lock_namespace 0x41544C53
  @spec_number_lock_key 0x53504353
  @write_lock_timeout_ms 10_000

  # Atlas has no per-user gating like Hive's Auth.member?: any authenticated
  # user is a member of the operator team, so create/edit/delete are gated
  # only on the presence of a %User{}.
  def can_create?(%User{}), do: true
  def can_create?(_user), do: false

  def can_edit?(%Spec{}, %User{}), do: true
  def can_edit?(_spec, _user), do: false

  def can_delete?(%Spec{} = spec, user), do: can_edit?(spec, user)

  def can_comment?(spec, %User{} = user), do: can_view?(spec, user)
  def can_comment?(_spec, _user), do: false

  def can_edit_comment?(%Comment{user_id: user_id}, %User{id: user_id}) when is_binary(user_id), do: true

  def can_edit_comment?(_comment, _user), do: false

  def can_view?(%Spec{visibility: :public}, _user), do: true
  def can_view?(%Spec{}, %User{}), do: true
  def can_view?(%Spec{}, _user), do: false

  def list_specs(opts \\ []) do
    status = Keyword.get(opts, :status)
    user = Keyword.get(opts, :user)

    specs =
      Spec
      |> maybe_filter_by_status(status)
      |> apply_visibility(user)
      |> order_by([spec], desc: spec.updated_at)
      |> preload([:engineering_project, :created_by_user, :updated_by_user, :domains])
      |> Repo.all()

    decorate_with_activity(specs, user)
  end

  def title(%Spec{body: body, title: fallback}) do
    body
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^\s*#\s+(.+)\s*$/, line) do
        [_, title] -> Markdown.preview(title, 100)
        _no_heading -> nil
      end
    end)
    |> case do
      "" -> fallback
      nil -> fallback
      title -> title
    end
  end

  def mark_viewed(%Spec{id: spec_id}, %User{id: user_id}) when is_binary(spec_id) and is_binary(user_id) do
    now = DateTime.utc_now()

    %View{}
    |> Changeset.cast(
      %{spec_id: spec_id, user_id: user_id, last_viewed_at: now},
      [:spec_id, :user_id, :last_viewed_at]
    )
    |> Repo.insert(
      on_conflict: [set: [last_viewed_at: now, updated_at: DateTime.truncate(now, :second)]],
      conflict_target: [:user_id, :spec_id]
    )

    :ok
  end

  def mark_viewed(_spec, _user), do: :ok

  def last_viewed_at(%Spec{id: spec_id}, %User{id: user_id}) when is_binary(spec_id) and is_binary(user_id) do
    Repo.one(
      from view in View,
        where: view.user_id == ^user_id and view.spec_id == ^spec_id,
        select: view.last_viewed_at
    )
  end

  def last_viewed_at(_spec, _user), do: nil

  def has_new_activity_for_user?(%User{id: user_id}) when is_binary(user_id) do
    from(view in View,
      as: :view,
      join: spec in Spec,
      on: spec.id == view.spec_id,
      where: view.user_id == ^user_id,
      where:
        spec.updated_at > view.last_viewed_at or
          exists(
            from(comment in Comment,
              where:
                comment.spec_id == parent_as(:view).spec_id and
                  comment.inserted_at > parent_as(:view).last_viewed_at
            )
          )
    )
    |> Repo.exists?()
  end

  def has_new_activity_for_user?(_user), do: false

  defp decorate_with_activity(specs, _user) when specs == [], do: []

  defp decorate_with_activity(specs, user) do
    spec_ids = Enum.map(specs, & &1.id)
    last_comment_at = last_comment_inserted_at(spec_ids)
    last_viewed_at = last_viewed_at_by_user(spec_ids, user)

    Enum.map(specs, fn spec ->
      last_activity_at = latest_datetime(spec.updated_at, Map.get(last_comment_at, spec.id))
      viewed_at = Map.get(last_viewed_at, spec.id)

      has_new_activity =
        not is_nil(viewed_at) and
          DateTime.after?(last_activity_at, viewed_at)

      %{spec | last_activity_at: last_activity_at, has_new_activity: has_new_activity}
    end)
  end

  defp last_comment_inserted_at(spec_ids) do
    from(comment in Comment,
      where: comment.spec_id in ^spec_ids,
      group_by: comment.spec_id,
      select: {comment.spec_id, max(comment.inserted_at)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp last_viewed_at_by_user(spec_ids, %User{id: user_id}) when is_binary(user_id) do
    from(view in View,
      where: view.user_id == ^user_id and view.spec_id in ^spec_ids,
      select: {view.spec_id, view.last_viewed_at}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp last_viewed_at_by_user(_spec_ids, _user), do: %{}

  defp latest_datetime(nil, nil), do: nil
  defp latest_datetime(a, nil), do: a
  defp latest_datetime(nil, b), do: b

  defp latest_datetime(a, b) do
    if DateTime.before?(a, b), do: b, else: a
  end

  defp maybe_filter_by_status(query, nil), do: query

  defp maybe_filter_by_status(query, {:not, status}) do
    if status in Spec.statuses(),
      do: where(query, [spec], spec.status != ^status),
      else: query
  end

  defp maybe_filter_by_status(query, status) do
    if status in Spec.statuses(),
      do: where(query, [spec], spec.status == ^status),
      else: query
  end

  defp apply_visibility(query, %User{}), do: query
  defp apply_visibility(query, _user), do: where(query, [spec], spec.visibility == :public)

  def get_spec!(id) do
    Spec
    |> preload_spec()
    |> Repo.get!(id)
  end

  def get_spec(id) do
    Spec
    |> preload_spec()
    |> Repo.get(id)
  end

  def get_spec_by_number!(number) when is_integer(number) do
    Spec
    |> preload_spec()
    |> Repo.get_by!(number: number)
  end

  def get_spec_by_number!(number) when is_binary(number) do
    case Integer.parse(number) do
      {number, ""} -> get_spec_by_number!(number)
      _invalid -> raise Ecto.NoResultsError, queryable: Spec
    end
  end

  def get_spec_by_number(number) when is_integer(number) do
    Spec |> preload_spec() |> Repo.get_by(number: number)
  end

  def get_spec_by_number(number) when is_binary(number) do
    case Integer.parse(number) do
      {number, ""} -> get_spec_by_number(number)
      _invalid -> nil
    end
  end

  def get_spec_by_reference!(reference) when is_integer(reference), do: get_spec_by_number!(reference)

  def get_spec_by_reference!(reference) when is_binary(reference) do
    reference
    |> reference_identifier()
    |> case do
      "" ->
        raise Ecto.NoResultsError, queryable: Spec

      identifier ->
        if public_number?(identifier),
          do: get_spec_by_number!(identifier),
          else: get_spec!(identifier)
    end
  end

  def get_spec_by_reference(reference) when is_integer(reference), do: get_spec_by_number(reference)

  def get_spec_by_reference(reference) when is_binary(reference) do
    reference
    |> reference_identifier()
    |> case do
      "" ->
        nil

      identifier ->
        if public_number?(identifier),
          do: get_spec_by_number(identifier),
          else: get_spec(identifier)
    end
  rescue
    Ecto.Query.CastError -> nil
  end

  def fetch_visible_spec_by_number(number, user) do
    case get_spec_by_number(number) do
      %Spec{} = spec ->
        if(can_view?(spec, user), do: {:ok, spec}, else: {:error, :not_found})

      _ ->
        {:error, :not_found}
    end
  end

  def fetch_visible_spec_by_reference(reference, user) do
    case get_spec_by_reference(reference) do
      %Spec{} = spec ->
        if(can_view?(spec, user), do: {:ok, spec}, else: {:error, :not_found})

      _ ->
        {:error, :not_found}
    end
  end

  defp reference_identifier(reference) do
    reference = String.trim(reference)

    case URI.parse(reference) do
      %URI{path: path} when is_binary(path) and path != "" ->
        path
        |> String.split("/", trim: true)
        |> spec_path_number()
        |> Kernel.||(reference)

      _uri ->
        reference
    end
  end

  defp spec_path_number(["specs", number | _rest]), do: number
  defp spec_path_number([_segment | rest]), do: spec_path_number(rest)
  defp spec_path_number([]), do: nil

  defp public_number?(identifier), do: match?({_number, ""}, Integer.parse(identifier))

  defp preload_spec(query) do
    comments_query =
      from comment in Comment, order_by: [asc: comment.inserted_at], preload: [:user]

    revisions_query =
      from revision in Revision, order_by: [desc: revision.revision], preload: [:user]

    preload(query, [
      :engineering_project,
      :created_by_user,
      :updated_by_user,
      :domains,
      comments: ^comments_query,
      revisions: ^revisions_query
    ])
  end

  def change_spec(spec \\ %Spec{}, attrs \\ %{}) do
    spec
    |> preload_for_form()
    |> Spec.changeset(attrs)
    |> maybe_put_existing_domain_ids(attrs)
  end

  def create_spec(attrs, %User{} = user) do
    case write_transaction(fn -> create_spec_transaction(attrs, user) end) do
      {:ok, spec} ->
        record_spec_event("spec.created", spec, user)
        {:ok, spec}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_spec(_attrs, _user), do: {:error, :unauthorized}

  def update_spec(%Spec{} = spec, attrs, %User{} = user) do
    if can_edit?(spec, user) do
      case write_transaction(fn -> update_spec_transaction(spec, attrs, user) end) do
        {:ok, updated_spec} ->
          record_spec_event("spec.updated", updated_spec, user)
          {:ok, updated_spec}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :unauthorized}
    end
  end

  def update_spec(_spec, _attrs, _user), do: {:error, :unauthorized}

  def delete_spec(%Spec{} = spec, %User{} = user) do
    if can_delete?(spec, user) do
      spec
      |> Changeset.optimistic_lock(:lock_version)
      |> Repo.delete()
      |> case do
        {:ok, deleted_spec} ->
          record_spec_event("spec.deleted", deleted_spec, user)
          {:ok, deleted_spec}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :unauthorized}
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  def delete_spec(_spec, _user), do: {:error, :unauthorized}

  # request_review is kept for API compatibility with Hive but returns
  # :notifications_not_configured because Atlas has no Slack/notifications
  # pipeline for specs yet.
  def request_review(%Spec{} = spec, %User{} = user) do
    if can_edit?(spec, user) do
      record_spec_event("spec.review.requested", spec, user)
      {:error, :notifications_not_configured}
    else
      {:error, :unauthorized}
    end
  end

  def request_review(_spec, _user), do: {:error, :unauthorized}

  defp write_transaction(fun) do
    Repo.transaction(fn ->
      Repo.query!("SET LOCAL lock_timeout = #{@write_lock_timeout_ms}")
      fun.()
    end)
  rescue
    error in Postgrex.Error ->
      if lock_not_available?(error),
        do: {:error, :locked},
        else: reraise(error, __STACKTRACE__)
  end

  defp lock_not_available?(%Postgrex.Error{postgres: %{code: :lock_not_available}}), do: true
  defp lock_not_available?(_error), do: false

  defp create_spec_transaction(attrs, user) do
    attrs = maybe_put_project_id(attrs)

    with {:ok, spec} <-
           %Spec{}
           |> Spec.changeset(attrs)
           |> Changeset.put_change(:created_by_user_id, user.id)
           |> Changeset.put_change(:updated_by_user_id, user.id)
           |> put_next_spec_number()
           |> Repo.insert(),
         {:ok, spec} <- put_domains(spec, attrs),
         {:ok, _revision} <- create_revision(spec, user) do
      spec
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp put_next_spec_number(%Changeset{valid?: true} = changeset) do
    lock_specs_for_numbering()
    Changeset.put_change(changeset, :number, next_spec_number())
  end

  defp put_next_spec_number(%Changeset{} = changeset), do: changeset

  defp lock_specs_for_numbering do
    Repo.query!(
      "SELECT pg_advisory_xact_lock($1::integer, $2::integer)",
      [@spec_number_lock_namespace, @spec_number_lock_key]
    )
  end

  defp next_spec_number do
    Repo.one!(from spec in Spec, select: fragment("COALESCE(MAX(?), 0) + 1", spec.number))
  end

  defp maybe_put_project_id(attrs) when is_map(attrs) do
    if project_id_present?(attrs) do
      attrs
    else
      project_id = inferred_project_id(attrs) || fallback_project_id()

      if project_id do
        Map.put(attrs, project_id_key(attrs), project_id)
      else
        attrs
      end
    end
  end

  defp maybe_put_project_id(attrs), do: attrs

  defp project_id_present?(attrs) do
    present?(Map.get(attrs, "engineering_project_id")) or
      present?(Map.get(attrs, :engineering_project_id))
  end

  defp project_id_key(attrs) do
    if Enum.any?(Map.keys(attrs), &is_binary/1),
      do: "engineering_project_id",
      else: :engineering_project_id
  end

  defp inferred_project_id(attrs) do
    case normalized_domain_ids(attrs) do
      [] ->
        nil

      domain_ids ->
        ProjectDomain
        |> where([project_domain], project_domain.domain_id in ^domain_ids)
        |> select([project_domain], project_domain.project_id)
        |> distinct(true)
        |> Repo.all()
        |> case do
          [project_id] -> project_id
          _project_ids -> nil
        end
    end
  end

  defp fallback_project_id do
    Project
    |> order_by([project], asc: project.inserted_at)
    |> limit(2)
    |> select([project], project.id)
    |> Repo.all()
    |> case do
      [project_id] -> project_id
      _projects -> nil
    end
  end

  defp update_spec_transaction(spec, attrs, user) do
    with {:ok, spec} <-
           spec
           |> Spec.update_changeset(attrs)
           |> Changeset.put_change(:updated_by_user_id, user.id)
           |> Repo.update(stale_error_field: :lock_version),
         {:ok, spec} <- put_domains(spec, attrs),
         {:ok, _revision} <- create_revision(spec, user) do
      spec
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def change_comment(comment \\ %Comment{}, attrs \\ %{}) do
    Comment.changeset(comment, attrs)
  end

  def get_comment!(id), do: Repo.get!(Comment, id)

  def add_comment(spec, attrs, user \\ nil)

  def add_comment(%Spec{} = spec, attrs, %User{} = user) do
    Repo.transaction(fn ->
      %Comment{}
      |> Comment.changeset(attrs)
      |> Changeset.put_change(:spec_id, spec.id)
      |> Changeset.put_change(:user_id, user.id)
      |> Repo.insert()
      |> unwrap_or_rollback()
    end)
    |> tap(fn
      {:ok, comment} -> record_comment_event("spec_comment.added", comment, spec, user)
      _ -> :ok
    end)
  end

  def add_comment(_spec, _attrs, _user), do: {:error, :unauthorized}

  def update_comment(%Comment{} = comment, attrs, %User{} = user) do
    if can_edit_comment?(comment, user) do
      comment
      |> Comment.changeset(attrs)
      |> Repo.update()
      |> tap(fn
        {:ok, updated} -> record_comment_event("spec_comment.updated", updated, user)
        _ -> :ok
      end)
    else
      {:error, :unauthorized}
    end
  end

  def update_comment(_comment, _attrs, _user), do: {:error, :unauthorized}

  def delete_comment(%Comment{} = comment, %User{} = user) do
    if can_edit_comment?(comment, user) do
      comment
      |> Repo.delete()
      |> tap(fn
        {:ok, deleted} -> record_comment_event("spec_comment.deleted", deleted, user)
        _ -> :ok
      end)
    else
      {:error, :unauthorized}
    end
  end

  def delete_comment(_comment, _user), do: {:error, :unauthorized}

  defp create_revision(%Spec{} = spec, %User{} = user) do
    %Revision{}
    |> Revision.changeset(%{
      revision: spec.lock_version,
      title: spec.title,
      body: spec.body,
      status: spec.status,
      summary: spec.summary,
      spec_id: spec.id,
      user_id: user.id
    })
    |> Repo.insert()
  end

  defp preload_for_form(%Spec{} = spec), do: Repo.preload(spec, [:domains, :engineering_project])

  defp maybe_put_existing_domain_ids(changeset, attrs) do
    if domain_ids_present?(attrs) do
      changeset
    else
      domains = get_field_or_loaded_assoc(changeset.data, :domains)
      Changeset.put_change(changeset, :domain_ids, Enum.map(domains, & &1.id))
    end
  end

  defp get_field_or_loaded_assoc(spec, assoc) do
    case Map.fetch!(spec, assoc) do
      %Ecto.Association.NotLoaded{} -> []
      values -> values
    end
  end

  defp put_domains(%Spec{} = spec, attrs) do
    if domain_ids_present?(attrs) do
      put_domain_ids(spec, normalized_domain_ids(attrs), attrs)
    else
      {:ok, spec}
    end
  end

  defp put_domain_ids(%Spec{} = spec, domain_ids, attrs) do
    domains =
      Repo.all(
        from domain in Domain,
          join: project_domain in ProjectDomain,
          on: project_domain.domain_id == domain.id,
          where:
            domain.id in ^domain_ids and
              project_domain.project_id == ^spec.engineering_project_id
      )

    if length(domains) == length(domain_ids) do
      spec
      |> Repo.preload(:domains)
      |> Changeset.change()
      |> Changeset.put_assoc(:domains, domains)
      |> Repo.update()
    else
      {:error,
       spec
       |> Spec.changeset(attrs)
       |> Changeset.add_error(:domain_ids, "contains unknown domains")}
    end
  end

  defp domain_ids_present?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, "domain_ids") or Map.has_key?(attrs, :domain_ids)
  end

  defp domain_ids_present?(_attrs), do: false

  defp normalized_domain_ids(attrs) do
    attrs
    |> Map.get("domain_ids", Map.get(attrs, :domain_ids, []))
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, reason}), do: Repo.rollback(reason)

  defp record_spec_event(action, %Spec{} = spec, %User{} = user) do
    Audit.record(action, %{
      actor: user,
      target_type: "spec",
      target_id: spec.id,
      target_label: title(spec),
      metadata: %{
        "number" => spec.number && to_string(spec.number),
        "status" => spec.status && Atom.to_string(spec.status),
        "path" => spec.number && "/engineering/specs/#{spec.number}"
      }
    })
  end

  defp record_comment_event(action, %Comment{} = comment, %User{} = user) do
    case Repo.get(Spec, comment.spec_id) do
      %Spec{} = spec -> record_comment_event(action, comment, spec, user)
      _ -> :ok
    end
  end

  defp record_comment_event(action, %Comment{} = comment, %Spec{} = spec, %User{} = user) do
    Audit.record(action, %{
      actor: user,
      target_type: "spec_comment",
      target_id: comment.id,
      target_label: title(spec),
      metadata: %{
        "spec_id" => spec.id,
        "number" => spec.number && to_string(spec.number),
        "path" => spec.number && "/engineering/specs/#{spec.number}"
      }
    })
  end
end
