defmodule Atlas.Audit do
  @moduledoc """
  Activity audit trail for user, agent, and integration actions.
  """

  import Ecto.Query

  alias Atlas.Audit.Activity
  alias Atlas.Repo
  alias Atlas.Users.User

  @context_key {__MODULE__, :context}
  @default_page_size 25
  @max_page_size 100
  @activity_attrs [
    :action,
    :interface,
    :occurred_at,
    :actor_id,
    :actor_email,
    :actor_name,
    :actor_role,
    :target_type,
    :target_id,
    :target_label,
    :metadata
  ]
  @string_activity_attrs Map.new(@activity_attrs, &{Atom.to_string(&1), &1})
  @query_search_fields [
    :action,
    :interface,
    :actor_email,
    :actor_name,
    :target_type,
    :target_id,
    :target_label
  ]

  def interfaces, do: Activity.interfaces()

  def with_context(context, fun) when is_function(fun, 0) do
    previous = Process.get(@context_key)

    try do
      put_context(context, previous || %{})
      fun.()
    after
      restore_context(previous)
    end
  end

  def put_context(context, previous \\ %{}) do
    Process.put(@context_key, normalize_context(context, previous))
  end

  def current_context, do: Process.get(@context_key, %{})

  def context_from_conn(conn, default_interface \\ "mcp")

  def context_from_conn(%{assigns: assigns}, default_interface) when is_map(assigns) do
    %{
      actor: assigns[:current_user],
      interface: assigns[:audit_interface] || default_interface,
      metadata: claim_metadata(assigns[:mcp_claims])
    }
  end

  def context_from_conn(_conn, default_interface), do: %{interface: default_interface}

  def get_activity(id) when is_binary(id) do
    Activity
    |> preload(:actor)
    |> Repo.get(id)
  end

  def log(action, attrs \\ %{}) do
    attrs
    |> Map.put(:action, to_string(action))
    |> normalize_attrs()
    |> then(&Activity.changeset(%Activity{}, &1))
    |> Repo.insert()
  end

  def record(action, attrs \\ %{}, opts \\ []) do
    context_attrs = context_attrs(opts)
    attrs = attrs |> opts_map() |> merge_context_metadata(context_attrs)

    action
    |> log(Map.merge(context_attrs, attrs))
    |> case do
      {:ok, _activity} -> :ok
      {:error, _reason} -> :ok
    end
  end

  def context_attrs(opts \\ []) do
    opts = opts_map(opts)
    context = current_context()

    %{}
    |> put_present(:actor, Map.get(opts, :actor) || Map.get(context, :actor))
    |> put_present(:actor_id, Map.get(opts, :actor_id) || Map.get(context, :actor_id))
    |> put_present(:actor_email, Map.get(opts, :actor_email) || Map.get(context, :actor_email))
    |> put_present(:actor_name, Map.get(opts, :actor_name) || Map.get(context, :actor_name))
    |> put_present(:actor_role, Map.get(opts, :actor_role) || Map.get(context, :actor_role))
    |> put_present(:metadata, Map.get(opts, :metadata) || Map.get(context, :metadata))
    |> put_present(:interface, Map.get(opts, :interface) || Map.get(context, :interface) || "system")
  end

  def list_activities(opts \\ []) do
    page_size = opts |> Keyword.get(:page_size, @default_page_size) |> normalize_page_size()
    page = opts |> Keyword.get(:page, 1) |> normalize_page()
    offset = (page - 1) * page_size

    query =
      Activity
      |> maybe_filter(:interface, Keyword.get(opts, :interface))
      |> maybe_filter(:action, Keyword.get(opts, :action))
      |> maybe_filter(:actor_id, Keyword.get(opts, :actor_id))
      |> maybe_filter(:actor_email, Keyword.get(opts, :actor_email))
      |> maybe_filter(:target_type, Keyword.get(opts, :target_type))
      |> maybe_filter(:target_id, Keyword.get(opts, :target_id))
      |> maybe_exclude(:interface, Keyword.get(opts, :exclude_interface))
      |> maybe_exclude(:action, Keyword.get(opts, :exclude_action))
      |> maybe_exclude(:target_type, Keyword.get(opts, :exclude_target_type))
      |> maybe_filter_occurred_after(Keyword.get(opts, :occurred_after))
      |> maybe_filter_occurred_before(Keyword.get(opts, :occurred_before))
      |> maybe_filter_query(Keyword.get(opts, :query))
      |> order_by([activity], desc: activity.occurred_at, desc: activity.id)
      |> preload(:actor)

    {activities, flop_meta} = Flop.run(query, %Flop{limit: page_size, offset: offset}, for: Activity)
    total_count = flop_meta.total_count || length(activities)

    meta = %{
      current_page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages(total_count, page_size),
      has_next_page?: flop_meta.has_next_page?,
      has_previous_page?: flop_meta.has_previous_page?
    }

    {activities, meta}
  end

  def filter_options do
    %{
      interfaces: distinct_values(:interface),
      actions: distinct_values(:action),
      target_types: distinct_values(:target_type)
    }
  end

  def actor_label(%Activity{actor_name: name}) when is_binary(name) and name != "", do: name
  def actor_label(%Activity{actor_email: email}) when is_binary(email) and email != "", do: email
  def actor_label(%Activity{}), do: "System"

  def serialize(%Activity{} = activity) do
    %{
      id: activity.id,
      action: activity.action,
      interface: activity.interface,
      occurred_at: iso8601(activity.occurred_at),
      actor: %{
        id: activity.actor_id,
        email: activity.actor_email,
        name: activity.actor_name,
        role: activity.actor_role
      },
      target: %{
        type: activity.target_type,
        id: activity.target_id,
        label: activity.target_label,
        path: resource_path(activity.target_type, activity.target_id, activity.metadata)
      },
      metadata: activity.metadata || %{}
    }
  end

  @doc """
  JSON Schema describing the map produced by `serialize/1`. Shared by the
  `list_audit_activities` and `get_audit_activity` MCP tools so both tools stay
  in sync with the serialized shape.
  """
  def serialize_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "action" => %{"type" => "string"},
        "interface" => %{"type" => "string"},
        "occurred_at" => %{"type" => "string"},
        "actor" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => ["string", "null"]},
            "email" => %{"type" => ["string", "null"]},
            "name" => %{"type" => ["string", "null"]},
            "role" => %{"type" => ["string", "null"]}
          },
          "required" => ["id", "email", "name", "role"],
          "additionalProperties" => false
        },
        "target" => %{
          "type" => "object",
          "properties" => %{
            "type" => %{"type" => ["string", "null"]},
            "id" => %{"type" => ["string", "null"]},
            "label" => %{"type" => ["string", "null"]},
            "path" => %{"type" => ["string", "null"]}
          },
          "required" => ["type", "id", "label", "path"],
          "additionalProperties" => false
        },
        "metadata" => %{"type" => "object"}
      },
      "required" => ["id", "action", "interface", "occurred_at", "actor", "target", "metadata"],
      "additionalProperties" => false
    }
  end

  def resource_path(target_type, target_id, metadata \\ %{})
  def resource_path(_target_type, _target_id, %{"path" => path}) when is_binary(path) and path != "", do: path
  def resource_path(_target_type, _target_id, %{path: path}) when is_binary(path) and path != "", do: path

  def resource_path("account", target_id, _metadata) when is_binary(target_id) and target_id != "",
    do: "/commercial/sales/accounts/#{target_id}"

  def resource_path("document", target_id, _metadata) when is_binary(target_id) and target_id != "",
    do: "/library/documents/#{target_id}"

  def resource_path("session", target_id, _metadata) when is_binary(target_id) and target_id != "",
    do: "/admin/sessions/#{target_id}"

  def resource_path("support_thread", target_id, _metadata) when is_binary(target_id) and target_id != "",
    do: "/commercial/support/#{target_id}"

  def resource_path("memory_node", target_id, _metadata) when is_binary(target_id) and target_id != "",
    do: "/admin/memory/#{target_id}"

  def resource_path("note", target_id, _metadata) when is_binary(target_id) and target_id != "",
    do: "/library/notes/#{target_id}"

  def resource_path("memory_bulletin", _target_id, _metadata), do: "/admin/memory"

  def resource_path("finance_source", _target_id, _metadata), do: "/commercial/finance"

  def resource_path("finance_category", _target_id, _metadata), do: "/commercial/finance"

  def resource_path("finance_transaction", _target_id, _metadata), do: "/commercial/finance"

  def resource_path("blog_post_idea", target_id, _metadata) when is_binary(target_id) and target_id != "",
    do: "/commercial/gtm/content/#{target_id}"

  def resource_path("social_channel_idea", target_id, _metadata) when is_binary(target_id) and target_id != "",
    do: "/commercial/gtm/social/#{target_id}"

  def resource_path("gtm_opportunity", target_id, _metadata) when is_binary(target_id) and target_id != "",
    do: "/commercial/gtm/outreach"

  def resource_path("contact", target_id, _metadata) when is_binary(target_id) and target_id != "",
    do: "/commercial/gtm/outreach/#{target_id}"

  def resource_path("gtm_subscriber", _target_id, _metadata), do: "/outbound/email"

  def resource_path("license", _target_id, _metadata), do: "/commercial/sales/licenses"

  def resource_path("gtm_audience", target_id, _metadata) when is_binary(target_id) and target_id != "",
    do: "/outbound/email/audiences/#{target_id}"

  def resource_path("gtm_broadcast", _target_id, %{"audience_id" => audience_id}) when is_binary(audience_id),
    do: "/outbound/email/audiences/#{audience_id}"

  def resource_path("gtm_broadcast", _target_id, %{audience_id: audience_id}) when is_binary(audience_id),
    do: "/outbound/email/audiences/#{audience_id}"

  def resource_path("gtm_delivery", _target_id, %{"audience_id" => audience_id}) when is_binary(audience_id),
    do: "/outbound/email/audiences/#{audience_id}"

  def resource_path("gtm_delivery", _target_id, %{audience_id: audience_id}) when is_binary(audience_id),
    do: "/outbound/email/audiences/#{audience_id}"

  def resource_path("cross_domain_claim", _target_id, %{"account_id" => account_id}) when is_binary(account_id),
    do: "/commercial/sales/accounts/#{account_id}"

  def resource_path(_target_type, _target_id, _metadata), do: nil

  def changeset_changes(%Ecto.Changeset{} = changeset) do
    changeset.changes
    |> Map.new(fn {key, value} -> {key, encode_value(value)} end)
  end

  def iso8601(nil), do: nil
  def iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  def iso8601(%NaiveDateTime{} = datetime),
    do: datetime |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

  def iso8601(%Date{} = date), do: Date.to_iso8601(date)
  def iso8601(value), do: to_string(value)

  def claim_metadata(claims) when is_map(claims) do
    %{}
    |> put_claim(claims, "slack_agent")
    |> put_claim(claims, "agent_identity_id")
    |> put_claim(claims, "agent_identity_key")
    |> put_claim(claims, "agent_identity_display_name")
    |> put_claim(claims, "slack_app")
    |> put_claim(claims, "slack_channel_id")
    |> put_claim(claims, "mcp_tool_groups")
  end

  def claim_metadata(_claims), do: %{}

  defp restore_context(nil), do: Process.delete(@context_key)
  defp restore_context(previous), do: Process.put(@context_key, previous)

  defp normalize_context(context, previous) do
    previous
    |> Map.merge(opts_map(context))
    |> normalize_actor_context()
    |> normalize_interface()
  end

  defp put_claim(metadata, claims, key) do
    case Map.get(claims, key) do
      nil -> metadata
      value -> Map.put(metadata, key, value)
    end
  end

  defp merge_context_metadata(attrs, %{metadata: context_metadata})
       when is_map(context_metadata) and map_size(context_metadata) > 0 do
    attrs_metadata =
      attrs
      |> Map.get(:metadata)
      |> case do
        nil -> %{}
        metadata when is_map(metadata) -> metadata
        _metadata -> %{}
      end

    Map.put(attrs, :metadata, Map.merge(context_metadata, attrs_metadata))
  end

  defp merge_context_metadata(attrs, _context_attrs), do: attrs

  defp opts_map(opts) when is_map(opts), do: opts
  defp opts_map(opts) when is_list(opts), do: Map.new(opts)
  defp opts_map(_opts), do: %{}

  defp normalize_attrs(attrs) do
    actor = Map.get(attrs, :actor) || Map.get(attrs, "actor")

    attrs
    |> atomize_activity_attrs()
    |> normalize_actor_attrs(actor)
    |> maybe_put_resource_path()
    |> Map.update(:metadata, %{}, &encode_value/1)
    |> normalize_interface()
  end

  defp atomize_activity_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {:actor, _value}, acc ->
        acc

      {"actor", _value}, acc ->
        acc

      {key, value}, acc ->
        case activity_attr(key) do
          nil -> acc
          attr -> Map.put(acc, attr, value)
        end
    end)
  end

  defp activity_attr(key) when is_atom(key) and key in @activity_attrs, do: key
  defp activity_attr(key) when is_binary(key), do: Map.get(@string_activity_attrs, key)
  defp activity_attr(_key), do: nil

  defp maybe_put_resource_path(attrs) do
    metadata = metadata_map(Map.get(attrs, :metadata))
    target_type = Map.get(attrs, :target_type)
    target_id = Map.get(attrs, :target_id)

    case resource_path(target_type, target_id, metadata) do
      nil ->
        attrs

      path ->
        Map.put(attrs, :metadata, Map.put(metadata, "path", path))
    end
  end

  defp metadata_map(metadata) when is_map(metadata), do: metadata
  defp metadata_map(_metadata), do: %{}

  defp normalize_actor_context(%{actor: %User{} = user} = attrs), do: normalize_actor_attrs(attrs, user)
  defp normalize_actor_context(attrs), do: attrs

  defp normalize_actor_attrs(attrs, %User{} = user) do
    attrs
    |> Map.put_new(:actor_id, user.id)
    |> Map.put_new(:actor_email, user.email)
    |> Map.put_new(:actor_name, user.name)
  end

  defp normalize_actor_attrs(attrs, _actor), do: attrs

  defp normalize_interface(%{interface: interface} = attrs) when is_atom(interface) do
    Map.put(attrs, :interface, Atom.to_string(interface))
  end

  defp normalize_interface(%{"interface" => interface} = attrs) when is_atom(interface) do
    Map.put(attrs, "interface", Atom.to_string(interface))
  end

  defp normalize_interface(attrs), do: attrs

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp normalize_page(page) when is_integer(page) and page > 0, do: page

  defp normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _other -> 1
    end
  end

  defp normalize_page(_page), do: 1

  defp normalize_page_size(page_size) when is_integer(page_size) and page_size > 0 do
    min(page_size, @max_page_size)
  end

  defp normalize_page_size(page_size) when is_binary(page_size) do
    case Integer.parse(page_size) do
      {page_size, ""} when page_size > 0 -> normalize_page_size(page_size)
      _other -> @default_page_size
    end
  end

  defp normalize_page_size(_page_size), do: @default_page_size

  defp total_pages(0, _page_size), do: 1
  defp total_pages(total_count, page_size), do: div(total_count + page_size - 1, page_size)

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, ""), do: query

  defp maybe_filter(query, field, value) do
    where(query, [activity], field(activity, ^field) == ^value)
  end

  defp maybe_exclude(query, _field, nil), do: query
  defp maybe_exclude(query, _field, ""), do: query

  defp maybe_exclude(query, field, value) do
    where(query, [activity], field(activity, ^field) != ^value or is_nil(field(activity, ^field)))
  end

  defp maybe_filter_occurred_after(query, nil), do: query

  defp maybe_filter_occurred_after(query, %DateTime{} = datetime),
    do: where(query, [activity], activity.occurred_at >= ^datetime)

  defp maybe_filter_occurred_after(query, value) when is_binary(value) do
    case parse_datetime(value, ~T[00:00:00]) do
      %DateTime{} = datetime -> maybe_filter_occurred_after(query, datetime)
      nil -> query
    end
  end

  defp maybe_filter_occurred_after(query, _value), do: query

  defp maybe_filter_occurred_before(query, nil), do: query

  defp maybe_filter_occurred_before(query, %DateTime{} = datetime),
    do: where(query, [activity], activity.occurred_at <= ^datetime)

  defp maybe_filter_occurred_before(query, value) when is_binary(value) do
    case parse_datetime(value, ~T[23:59:59]) do
      %DateTime{} = datetime -> maybe_filter_occurred_before(query, datetime)
      nil -> query
    end
  end

  defp maybe_filter_occurred_before(query, _value), do: query

  defp maybe_filter_query(query, value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        query

      trimmed ->
        pattern = "%#{trimmed}%"
        where(query, ^query_search_dynamic(pattern))
    end
  end

  defp maybe_filter_query(query, _value), do: query

  defp query_search_dynamic(pattern) do
    @query_search_fields
    |> Enum.reduce(dynamic([activity], false), fn field, search_dynamic ->
      dynamic([activity], ^search_dynamic or ilike(field(activity, ^field), ^pattern))
    end)
    |> then(fn search_dynamic ->
      dynamic([activity], ^search_dynamic or fragment("?::text ILIKE ?", activity.metadata, ^pattern))
    end)
  end

  defp parse_datetime(value, fallback_time) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        DateTime.new!(date, fallback_time, "Etc/UTC")

      _error ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
          _error -> nil
        end
    end
  end

  defp distinct_values(field) do
    Activity
    |> where([activity], not is_nil(field(activity, ^field)))
    |> distinct(true)
    |> order_by([activity], asc: field(activity, ^field))
    |> select([activity], field(activity, ^field))
    |> Repo.all()
  end

  defp encode_value(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp encode_value(%NaiveDateTime{} = datetime),
    do: datetime |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

  defp encode_value(%Date{} = date), do: Date.to_iso8601(date)
  defp encode_value(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  defp encode_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_value(value) when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value), do: value
  defp encode_value(value) when is_list(value), do: Enum.map(value, &encode_value/1)

  defp encode_value(value) when is_map(value) do
    if Map.has_key?(value, :__struct__) do
      inspect(value)
    else
      Map.new(value, fn {key, value} -> {to_string(key), encode_value(value)} end)
    end
  end

  defp encode_value(value), do: inspect(value)
end
