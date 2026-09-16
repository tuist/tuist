defmodule Atlas.GTM.Audiences do
  @moduledoc """
  Subscriber and audience management for Atlas-owned email communication.
  """

  import Ecto.Query

  alias Atlas.Accounts.IncidentContact
  alias Atlas.Audit
  alias Atlas.GTM.Audience
  alias Atlas.GTM.AudienceMembership
  alias Atlas.GTM.Broadcast
  alias Atlas.GTM.DynamicAudience
  alias Atlas.GTM.Subscriber
  alias Atlas.GTM.Subscriptions
  alias Atlas.GTM.Workers.PostAudienceMemberNotification
  alias Atlas.Repo

  require Logger

  @default_page_size 25
  @max_page_size 100

  @present_value "present"
  @absent_value "absent"

  @doc """
  Values accepted by the audience `:subscribers` and `:broadcasts` filters.
  """
  def presence_values, do: [@present_value, @absent_value]

  def list_subscribers(opts \\ []) do
    query =
      Subscriber
      |> maybe_search(Keyword.get(opts, :query))
      |> maybe_filter_status(Keyword.get(opts, :status))
      |> maybe_filter_source(Keyword.get(opts, :source))
      |> order_by([subscriber], asc: subscriber.email)

    query
    |> Flop.run(
      %Flop{
        limit: page_size(Keyword.get(opts, :page_size)),
        offset: pagination_offset(Keyword.get(opts, :page), Keyword.get(opts, :page_size))
      },
      for: Subscriber
    )
    |> then(fn {subscribers, metadata} -> {subscribers, pagination_metadata(metadata, opts)} end)
  end

  def list_all_subscribers do
    Subscriber
    |> order_by([subscriber], asc: subscriber.email)
    |> Repo.all()
  end

  def get_subscriber(id) when is_binary(id), do: Repo.get(Subscriber, id)

  def get_subscriber_by_email(email) when is_binary(email) do
    normalized = email |> String.trim() |> String.downcase()
    Repo.one(from subscriber in Subscriber, where: fragment("lower(?)", subscriber.email) == ^normalized)
  end

  def change_subscriber(%Subscriber{} = subscriber, attrs \\ %{}) do
    Subscriber.changeset(subscriber, attrs)
  end

  def create_subscriber(attrs, actor \\ nil) when is_map(attrs) do
    create_subscriber(attrs, actor, [])
  end

  def create_subscriber(attrs, actor, opts) when is_map(attrs) and is_list(opts) do
    changeset = Subscriber.changeset(%Subscriber{}, attrs)

    result =
      changeset
      |> Repo.insert()
      |> tap(fn
        {:ok, subscriber} -> audit_subscriber("gtm_subscriber.created", subscriber, changeset, actor)
        _result -> :ok
      end)

    with true <- Keyword.get(opts, :automations, true),
         {:ok, subscriber} <- result do
      case Subscriptions.maybe_enqueue_welcome(subscriber) do
        {:ok, _outcome} ->
          :ok

        {:error, reason} ->
          # The welcome audience is seeded, so a missing one is a deployment
          # problem that would otherwise drop every welcome email silently.
          Logger.error("Could not enqueue the welcome email for #{subscriber.email}: #{inspect(reason)}")
      end
    end

    result
  end

  def upsert_subscriber(attrs, actor \\ nil) when is_map(attrs) do
    upsert_subscriber(attrs, actor, [])
  end

  def upsert_subscriber(attrs, actor, opts) when is_map(attrs) and is_list(opts) do
    email = attrs[:email] || attrs["email"]

    case is_binary(email) && get_subscriber_by_email(email) do
      %Subscriber{} = subscriber -> update_subscriber(subscriber, attrs, actor)
      _missing -> create_subscriber(attrs, actor, opts)
    end
  end

  def update_subscriber(%Subscriber{} = subscriber, attrs, actor \\ nil) when is_map(attrs) do
    changeset = Subscriber.changeset(subscriber, attrs)

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> audit_subscriber("gtm_subscriber.updated", updated, changeset, actor)
      _result -> :ok
    end)
  end

  def list_audiences(opts \\ []) do
    query =
      audiences_with_counts()
      |> maybe_search_audiences(Keyword.get(opts, :query))
      |> maybe_filter_source_id(Keyword.get(opts, :source_id))
      |> maybe_filter_subscribers_presence(Keyword.get(opts, :subscribers))
      |> maybe_filter_broadcasts_presence(Keyword.get(opts, :broadcasts))
      |> order_by([audience], asc: audience.name)

    {audiences, metadata} =
      Flop.run(
        query,
        %Flop{
          limit: page_size(Keyword.get(opts, :page_size)),
          offset: pagination_offset(Keyword.get(opts, :page), Keyword.get(opts, :page_size))
        },
        for: Audience
      )

    {hydrate_dynamic_counts(audiences), pagination_metadata(metadata, opts)}
  end

  defp audiences_with_counts do
    membership_counts =
      from membership in AudienceMembership,
        where: membership.status == "subscribed",
        group_by: membership.audience_id,
        select: %{audience_id: membership.audience_id, count: count(membership.id)}

    broadcast_counts =
      from broadcast in Broadcast,
        group_by: broadcast.audience_id,
        select: %{audience_id: broadcast.audience_id, count: count(broadcast.id)}

    from(audience in Audience,
      left_join: membership_count in subquery(membership_counts),
      as: :membership_count,
      on: membership_count.audience_id == audience.id,
      left_join: broadcast_count in subquery(broadcast_counts),
      as: :broadcast_count,
      on: broadcast_count.audience_id == audience.id,
      select_merge: %{
        subscribers_count: fragment("COALESCE(?, 0)", membership_count.count),
        broadcasts_count: fragment("COALESCE(?, 0)", broadcast_count.count)
      }
    )
  end

  @doc """
  Loads one audience with its subscriber and broadcast counts, without pulling
  every membership into memory the way `get_audience/1` does.
  """
  def get_audience_with_counts(id) when is_binary(id) do
    audiences_with_counts()
    |> where([audience], audience.id == ^id)
    |> Repo.one()
    |> hydrate_dynamic_count()
  end

  @doc """
  Members of an audience, paginated and filterable by status or by a search
  over the subscriber's email and name.
  """
  def list_memberships(%Audience{} = audience, opts \\ []) do
    audience_id = audience.id

    case Audience.dynamic?(audience) do
      true ->
        DynamicAudience.list_memberships(audience, opts)

      false ->
        query =
          from(membership in AudienceMembership,
            join: subscriber in assoc(membership, :subscriber),
            as: :subscriber,
            where: membership.audience_id == ^audience_id,
            preload: [subscriber: subscriber]
          )
          |> maybe_search_members(Keyword.get(opts, :query))
          |> maybe_filter_membership_status(Keyword.get(opts, :status))

        paginate_association(query, [asc: dynamic([subscriber: s], s.email)], opts)
    end
  end

  def list_all_audiences do
    from(audience in Audience, order_by: [asc: audience.name])
    |> Repo.all()
  end

  def distinct_source_ids do
    Audience
    |> where([audience], not is_nil(audience.source_id))
    |> select([audience], audience.source_id)
    |> distinct(true)
    |> order_by(asc: :source_id)
    |> Repo.all()
  end

  def distinct_subscriber_sources do
    Subscriber
    |> select([subscriber], subscriber.source)
    |> distinct(true)
    |> order_by(asc: :source)
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
  end

  def get_audience(id) when is_binary(id) do
    Audience
    |> Repo.get(id)
    |> preload_audience()
  end

  @doc """
  Looks an audience up by the id it carries in the system it came from, such as
  a Loops mailing list id sent by the PostHog destination.
  """
  def get_audience_by_source_id(source_id) when is_binary(source_id) do
    Audience
    |> Repo.get_by(source_id: source_id)
    |> preload_audience()
  end

  def get_audience_by_slug(slug) when is_binary(slug) do
    Audience
    |> Repo.get_by(slug: slug)
    |> preload_audience()
  end

  def change_audience(%Audience{} = audience, attrs \\ %{}) do
    attrs = put_slug(attrs)
    Audience.changeset(audience, attrs)
  end

  def create_audience(attrs, actor \\ nil) when is_map(attrs) do
    changeset = change_audience(%Audience{}, attrs)

    changeset
    |> Repo.insert()
    |> tap(fn
      {:ok, audience} -> audit_audience("gtm_audience.created", audience, changeset, actor)
      _result -> :ok
    end)
  end

  @doc """
  Deletes a manual audience that has never been used for a broadcast.

  Broadcast history is intentionally retained, so audiences with broadcasts
  remain available as the delivery record those broadcasts refer to.
  """
  def delete_audience(audience, actor \\ nil)

  def delete_audience(%Audience{membership_type: "static"} = audience, actor) do
    if Repo.exists?(from broadcast in Broadcast, where: broadcast.audience_id == ^audience.id) do
      {:error, :has_broadcasts}
    else
      audience
      |> Repo.delete()
      |> tap(fn
        {:ok, deleted} -> audit_audience_deleted(deleted, actor)
        _result -> :ok
      end)
    end
  end

  def delete_audience(%Audience{}, _actor), do: {:error, :dynamic_audience}

  def add_subscriber(%Audience{} = audience, %Subscriber{} = subscriber, actor \\ nil, status \\ "subscribed") do
    if Audience.dynamic?(audience) do
      {:error, :dynamic_audience}
    else
      add_static_subscriber(audience, subscriber, actor, status)
    end
  end

  defp add_static_subscriber(%Audience{} = audience, %Subscriber{} = subscriber, actor, status) do
    now = timestamp()
    row_timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    previous_status =
      case Repo.get_by(AudienceMembership, audience_id: audience.id, subscriber_id: subscriber.id) do
        %AudienceMembership{status: previous_status} -> previous_status
        nil -> nil
      end

    attrs = %{
      status: status,
      unsubscribed_at: if(status == "unsubscribed", do: now),
      updated_at: row_timestamp,
      inserted_at: row_timestamp
    }

    result =
      %AudienceMembership{audience_id: audience.id, subscriber_id: subscriber.id}
      |> AudienceMembership.changeset(attrs)
      |> Repo.insert(
        on_conflict: [set: [status: status, unsubscribed_at: attrs.unsubscribed_at, updated_at: row_timestamp]],
        conflict_target: [:audience_id, :subscriber_id],
        returning: true
      )

    tap(result, fn
      {:ok, membership} ->
        Audit.record(
          "gtm_audience.subscriber_added",
          %{
            target_type: "gtm_audience",
            target_id: audience.id,
            target_label: audience.name,
            metadata: %{subscriber_id: subscriber.id, subscriber_email: subscriber.email, status: membership.status}
          },
          actor: actor
        )

        maybe_enqueue_member_notification(previous_status, membership)

      _result ->
        :ok
    end)
  end

  defp maybe_enqueue_member_notification("subscribed", %AudienceMembership{}), do: :ok

  defp maybe_enqueue_member_notification(_previous_status, %AudienceMembership{status: "subscribed"} = membership) do
    %{
      "membership_id" => membership.id,
      "notification_id" => Ecto.UUID.generate()
    }
    |> PostAudienceMemberNotification.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Could not enqueue audience member notification for #{membership.id}: #{inspect(reason)}")
    end
  end

  defp maybe_enqueue_member_notification(_previous_status, %AudienceMembership{}), do: :ok

  def add_subscriber_by_email(%Audience{} = audience, email, actor \\ nil) when is_binary(email) do
    case get_subscriber_by_email(email) do
      nil -> {:error, :subscriber_not_found}
      subscriber -> add_subscriber(audience, subscriber, actor)
    end
  end

  def unsubscribe(%Audience{} = audience, %Subscriber{} = subscriber, actor \\ nil) do
    membership =
      Repo.get_by(AudienceMembership, audience_id: audience.id, subscriber_id: subscriber.id)

    case membership do
      nil ->
        if Audience.dynamic?(audience) do
          unsubscribe_dynamic_subscriber(audience, subscriber, actor)
        else
          {:error, :membership_not_found}
        end

      %AudienceMembership{} = membership ->
        changeset = AudienceMembership.changeset(membership, %{status: "unsubscribed", unsubscribed_at: timestamp()})

        changeset
        |> Repo.update()
        |> tap(fn
          {:ok, _membership} ->
            audit_unsubscribe(audience, subscriber, actor)

          _result ->
            :ok
        end)
    end
  end

  def subscribed?(%Audience{} = audience, %Subscriber{id: subscriber_id}) do
    audience_id = audience.id
    subscriber = Repo.get(Subscriber, subscriber_id)

    if Audience.dynamic?(audience) do
      dynamic_subscribed?(audience, subscriber)
    else
      Repo.exists?(
        from membership in AudienceMembership,
          where:
            membership.audience_id == ^audience_id and membership.subscriber_id == ^subscriber_id and
              membership.status == "subscribed"
      )
    end
  end

  def subscribed_recipients(%Audience{} = audience) do
    if Audience.dynamic?(audience) do
      dynamic_subscribed_recipients(audience)
    else
      static_subscribed_recipients(audience)
    end
  end

  defp static_subscribed_recipients(%Audience{id: audience_id}) do
    from(subscriber in Subscriber,
      join: membership in AudienceMembership,
      on: membership.subscriber_id == subscriber.id,
      where:
        membership.audience_id == ^audience_id and membership.status == "subscribed" and
          subscriber.status == "subscribed",
      order_by: [asc: subscriber.email]
    )
    |> Repo.all()
  end

  defp dynamic_subscribed_recipients(audience) do
    audience
    |> DynamicAudience.contacts()
    |> Enum.reduce([], fn contact, recipients ->
      case dynamic_subscriber(contact) do
        %Subscriber{} = subscriber when subscriber.status == "subscribed" ->
          if dynamic_subscribed?(audience, subscriber, contact), do: [subscriber | recipients], else: recipients

        _subscriber ->
          recipients
      end
    end)
    |> Enum.sort_by(& &1.email)
  end

  defp dynamic_subscriber(%IncidentContact{} = contact) do
    dynamic_subscriber(contact, "contract", %{"account_incident_contact_id" => contact.id})
  end

  defp dynamic_subscriber(contact) do
    dynamic_subscriber(contact, "account contact", %{"account_contact_id" => contact.id})
  end

  defp dynamic_subscriber(contact, source, metadata) do
    case get_subscriber_by_email(contact.email) do
      %Subscriber{} = subscriber ->
        subscriber

      nil ->
        case create_subscriber(
               %{
                 email: contact.email,
                 first_name: contact_name(contact),
                 source: source,
                 user_group: contact.account.name,
                 metadata: metadata
               },
               nil,
               automations: false
             ) do
          {:ok, subscriber} -> subscriber
          {:error, _changeset} -> get_subscriber_by_email(contact.email)
        end
    end
  end

  defp contact_name(%IncidentContact{full_name: nil, role: role}), do: role || "Incident contact"
  defp contact_name(contact), do: contact.full_name

  defp dynamic_subscribed?(%Audience{} = audience, %Subscriber{} = subscriber) do
    subscriber.status == "subscribed" and DynamicAudience.matches_subscriber?(audience, subscriber) and
      not Repo.exists?(
        from membership in AudienceMembership,
          where:
            membership.audience_id == ^audience.id and membership.subscriber_id == ^subscriber.id and
              membership.status == "unsubscribed"
      )
  end

  defp dynamic_subscribed?(_audience, _subscriber), do: false

  defp dynamic_subscribed?(%Audience{} = audience, %Subscriber{} = subscriber, _contact) do
    subscriber.status == "subscribed" and
      not Repo.exists?(
        from membership in AudienceMembership,
          where:
            membership.audience_id == ^audience.id and membership.subscriber_id == ^subscriber.id and
              membership.status == "unsubscribed"
      )
  end

  defp unsubscribe_dynamic_subscriber(audience, subscriber, actor) do
    now = timestamp()

    %AudienceMembership{audience_id: audience.id, subscriber_id: subscriber.id}
    |> AudienceMembership.changeset(%{status: "unsubscribed", unsubscribed_at: now})
    |> Repo.insert()
    |> tap(fn
      {:ok, _membership} -> audit_unsubscribe(audience, subscriber, actor)
      _result -> :ok
    end)
  end

  defp audit_unsubscribe(audience, subscriber, actor) do
    Audit.record(
      "gtm_audience.subscriber_unsubscribed",
      %{
        target_type: "gtm_audience",
        target_id: audience.id,
        target_label: audience.name,
        metadata: %{subscriber_id: subscriber.id, subscriber_email: subscriber.email}
      },
      actor: actor
    )
  end

  defp preload_audience(nil), do: nil

  defp preload_audience(audience) do
    audience =
      Repo.preload(audience,
        memberships:
          from(membership in AudienceMembership,
            order_by: [asc: membership.status, desc: membership.inserted_at],
            preload: [:subscriber]
          ),
        broadcasts:
          from(broadcast in Broadcast,
            order_by: [desc: broadcast.inserted_at],
            preload: [:sender]
          )
      )

    if Audience.dynamic?(audience) do
      {memberships, _metadata} = DynamicAudience.list_memberships(audience, page_size: @max_page_size)
      %{audience | memberships: memberships, subscribers_count: DynamicAudience.contacts_count(audience)}
    else
      audience
    end
  end

  defp hydrate_dynamic_counts(audiences) do
    Enum.map(audiences, &hydrate_dynamic_count/1)
  end

  defp hydrate_dynamic_count(nil), do: nil

  defp hydrate_dynamic_count(audience) do
    if Audience.dynamic?(audience) do
      %{audience | subscribers_count: DynamicAudience.contacts_count(audience)}
    else
      audience
    end
  end

  defp put_slug(attrs) do
    name = attrs[:name] || attrs["name"]
    slug = attrs[:slug] || attrs["slug"]

    if blank?(slug) and is_binary(name) do
      key = if Map.has_key?(attrs, :name), do: :slug, else: "slug"
      Map.put(attrs, key, slugify(name))
    else
      attrs
    end
  end

  defp slugify(value) do
    # Decompose first and drop the combining marks, otherwise they survive into
    # the ASCII filter below and "Se\u00f1or" slugifies to "sen-or".
    value
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp audit_subscriber(action, subscriber, changeset, actor) do
    Audit.record(
      action,
      %{
        target_type: "gtm_subscriber",
        target_id: subscriber.id,
        target_label: subscriber.email,
        metadata: %{changed: Audit.changeset_changes(changeset)}
      },
      actor: actor
    )
  end

  defp audit_audience(action, audience, changeset, actor) do
    Audit.record(
      action,
      %{
        target_type: "gtm_audience",
        target_id: audience.id,
        target_label: audience.name,
        metadata: %{changed: Audit.changeset_changes(changeset)}
      },
      actor: actor
    )
  end

  defp audit_audience_deleted(audience, actor) do
    Audit.record(
      "gtm_audience.deleted",
      %{
        target_type: "gtm_audience",
        target_id: audience.id,
        target_label: audience.name,
        metadata: %{
          membership_type: audience.membership_type,
          dashboard_path: "/email"
        }
      },
      actor: actor
    )
  end

  defp maybe_search(query, value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        query

      value ->
        where(
          query,
          [subscriber],
          ilike(subscriber.email, ^"%#{value}%") or ilike(subscriber.first_name, ^"%#{value}%") or
            ilike(subscriber.last_name, ^"%#{value}%")
        )
    end
  end

  defp maybe_search(query, _value), do: query

  defp maybe_search_audiences(query, value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        query

      value ->
        where(
          query,
          [audience],
          ilike(audience.name, ^"%#{value}%") or ilike(audience.description, ^"%#{value}%") or
            ilike(audience.slug, ^"%#{value}%")
        )
    end
  end

  defp maybe_search_audiences(query, _value), do: query

  defp maybe_filter_source_id(query, filter) do
    case option_filter(filter) do
      nil -> query
      {:==, value} -> where(query, [audience], audience.source_id == ^value)
      {:!=, value} -> where(query, [audience], audience.source_id != ^value or is_nil(audience.source_id))
    end
  end

  defp maybe_filter_subscribers_presence(query, filter) do
    case presence_filter(filter) do
      nil -> query
      :present -> where(query, [membership_count: count], coalesce(count.count, 0) > 0)
      :absent -> where(query, [membership_count: count], coalesce(count.count, 0) == 0)
    end
  end

  defp maybe_filter_broadcasts_presence(query, filter) do
    case presence_filter(filter) do
      nil -> query
      :present -> where(query, [broadcast_count: count], coalesce(count.count, 0) > 0)
      :absent -> where(query, [broadcast_count: count], coalesce(count.count, 0) == 0)
    end
  end

  defp maybe_search_members(query, value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        query

      value ->
        where(
          query,
          [subscriber: subscriber],
          ilike(subscriber.email, ^"%#{value}%") or ilike(subscriber.first_name, ^"%#{value}%") or
            ilike(subscriber.last_name, ^"%#{value}%")
        )
    end
  end

  defp maybe_search_members(query, _value), do: query

  defp maybe_filter_membership_status(query, filter) do
    case option_filter(filter) do
      nil -> query
      {:==, value} -> where(query, [membership], membership.status == ^value)
      {:!=, value} -> where(query, [membership], membership.status != ^value)
    end
  end

  @doc """
  Pages a query that hangs off an audience with Flop while preserving the
  association-specific ordering.
  """
  def paginate_association(query, order, opts) do
    page = normalized_page(Keyword.get(opts, :page))
    size = page_size(Keyword.get(opts, :page_size))

    query
    |> order_by(^order)
    |> Flop.run(%Flop{limit: size, offset: (page - 1) * size}, repo: Repo)
    |> then(fn {rows, metadata} -> {rows, pagination_metadata(metadata, page: page, page_size: size)} end)
  end

  defp normalized_page(page) when is_integer(page) and page > 0, do: page
  defp normalized_page(_page), do: 1

  defp maybe_filter_status(query, filter) do
    case option_filter(filter) do
      nil -> query
      {:==, value} -> where(query, [subscriber], subscriber.status == ^value)
      {:!=, value} -> where(query, [subscriber], subscriber.status != ^value or is_nil(subscriber.status))
    end
  end

  defp maybe_filter_source(query, filter) do
    case option_filter(filter) do
      nil -> query
      {:==, value} -> where(query, [subscriber], subscriber.source == ^value)
      {:!=, value} -> where(query, [subscriber], subscriber.source != ^value or is_nil(subscriber.source))
    end
  end

  # Filters arrive either as a bare value, which means "is", or as an
  # `{operator, value}` tuple once the caller exposes the "is not" operator.
  defp option_filter(nil), do: nil
  defp option_filter(""), do: nil
  defp option_filter({_operator, nil}), do: nil
  defp option_filter({_operator, ""}), do: nil
  defp option_filter({operator, value}) when operator in [:==, :!=], do: {operator, value}
  defp option_filter({_operator, _value}), do: nil
  defp option_filter(value), do: {:==, value}

  # "Is not present" is the same query as "is absent", so the operator folds
  # into the value rather than reaching the query builders.
  defp presence_filter(filter) do
    case option_filter(filter) do
      {:==, @present_value} -> :present
      {:==, @absent_value} -> :absent
      {:!=, @present_value} -> :absent
      {:!=, @absent_value} -> :present
      _other -> nil
    end
  end

  defp page_size(value) when is_integer(value) and value > 0, do: min(value, @max_page_size)
  defp page_size(_value), do: @default_page_size

  defp pagination_offset(page, page_size) do
    normalized_page = if is_integer(page) and page > 0, do: page, else: 1
    (normalized_page - 1) * page_size(page_size)
  end

  defp pagination_metadata(metadata, opts) do
    total_count = metadata.total_count || 0
    page_size = metadata.page_size || page_size(Keyword.get(opts, :page_size))
    current_page = metadata.current_page || Keyword.get(opts, :page, 1) || 1

    %{
      current_page: current_page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages(total_count, page_size),
      has_next_page?: metadata.has_next_page?,
      has_previous_page?: metadata.has_previous_page?
    }
  end

  defp total_pages(0, _page_size), do: 1
  defp total_pages(total_count, page_size), do: ceil(total_count / page_size)

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
