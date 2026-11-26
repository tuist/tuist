defmodule Atlas.GTM.SocialPublishing do
  @moduledoc """
  Posts and threads Atlas publishes to the X accounts it holds.

  Anyone with `gtm:write`, people and agents, drafts publications and uploads
  their media. Only a person approves one, on the dashboard, and the approval
  covers that exact revision: any edit returns it to draft. A personal
  account's posts are approved only by whoever connected that account.
  Approved publications publish at `scheduled_at`. A publish that may have
  reached X is never retried automatically, so a post cannot go out twice.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Documents.Storage
  alias Atlas.GTM.SocialAccount
  alias Atlas.GTM.SocialAccounts
  alias Atlas.GTM.SocialMedia
  alias Atlas.GTM.SocialPublication
  alias Atlas.GTM.Workers.PublishSocialPost
  alias Atlas.GTM.XPublisher
  alias Atlas.Repo
  alias Atlas.Users.User

  @dashboard_path "/commercial/gtm/social/publishing"
  @max_chars 280
  # X counts every link as 23 characters, whatever its length.
  @url_weight 23
  @url ~r{https?://\S+}
  @upload_ttl 3_600

  def dashboard_path, do: @dashboard_path

  def list(opts \\ []) do
    SocialPublication
    |> maybe_status(Keyword.get(opts, :status))
    |> order_by([p], desc: p.scheduled_at)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> preload([:social_account, :approved_by, :created_by])
    |> Repo.all()
  end

  def get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> SocialPublication |> Repo.get(id) |> Repo.preload([:social_account, :approved_by, :created_by])
      :error -> nil
    end
  end

  defp maybe_status(query, nil), do: query
  defp maybe_status(query, status), do: where(query, [p], p.status == ^status)

  @doc "Media rows by id, in the given order."
  def media(ids) do
    by_id = SocialMedia |> where([m], m.id in ^ids) |> Repo.all() |> Map.new(&{&1.id, &1})
    ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1)
  end

  @doc """
  Reserves a media row and returns a signed URL to PUT its bytes to. Call
  `finalize_media/2` after the upload.
  """
  def create_media_upload(%User{} = user, filename, content_type) do
    with :ok <- authorize(user) do
      media = %SocialMedia{uploaded_by_id: user.id}

      changeset =
        SocialMedia.changeset(media, %{
          filename: filename,
          content_type: content_type,
          storage_key: storage_key(filename),
          status: "pending_upload"
        })

      with {:ok, media} <- Repo.insert(changeset),
           {:ok, url} <-
             Storage.presigned_put_url(media.storage_key, expires_in: @upload_ttl, content_type: content_type) do
        {:ok,
         %{
           media: media,
           upload_url: url,
           required_headers: %{"Content-Type" => content_type},
           upload_expires_at: DateTime.add(DateTime.utc_now(), @upload_ttl, :second)
         }}
      end
    end
  end

  @doc "Checks that the bytes arrived and are within X's limits for their kind."
  def finalize_media(%User{} = user, id) do
    with :ok <- authorize(user),
         %SocialMedia{status: "pending_upload"} = media <- Repo.get(SocialMedia, id) || {:error, :not_found},
         {:ok, size} <- stored_size(media.storage_key),
         :ok <- within_limit(media, size) do
      media |> SocialMedia.changeset(%{byte_size: size, status: "uploaded"}) |> Repo.update()
    else
      %SocialMedia{} = media -> {:ok, media}
      error -> error
    end
  end

  @doc "Stores media bytes uploaded through the dashboard."
  def store_media(%User{} = user, filename, content_type, bytes) do
    with :ok <- authorize(user),
         :ok <- within_limit(%SocialMedia{content_type: content_type}, byte_size(bytes)) do
      changeset =
        SocialMedia.changeset(%SocialMedia{uploaded_by_id: user.id}, %{
          filename: filename,
          content_type: content_type,
          byte_size: byte_size(bytes),
          storage_key: storage_key(filename),
          status: "uploaded"
        })

      with {:ok, _changes} <- Ecto.Changeset.apply_action(changeset, :insert),
           {:ok, _response} <- Storage.put_object(changeset.changes.storage_key, bytes, content_type: content_type) do
        Repo.insert(changeset)
      end
    end
  end

  defp stored_size(key) do
    case Storage.head_object(key) do
      {:ok, %{headers: headers}} -> content_length(headers)
      _missing -> {:error, :media_not_uploaded}
    end
  end

  defp content_length(headers) do
    headers
    |> Enum.find_value(fn {name, value} -> String.downcase(name) == "content-length" && value end)
    |> List.wrap()
    |> List.first()
    |> case do
      nil -> {:error, :media_not_uploaded}
      value -> {:ok, String.to_integer(value)}
    end
  end

  defp within_limit(media, size) do
    kind = SocialMedia.kind(media.content_type)
    max = SocialMedia.max_bytes(kind)
    if size > 0 and size <= max, do: :ok, else: {:error, {:media_too_large, kind, max}}
  end

  defp storage_key(filename) do
    extension = filename |> Path.extname() |> String.downcase() |> String.slice(0, 8)
    "social-media/#{Ecto.UUID.generate()}#{extension}"
  end

  @doc """
  Drafts a publication. `items` is the thread in order, each with `text` and
  optional `media_ids`.
  """
  def create(%User{} = user, attrs) do
    with :ok <- authorize(user),
         {:ok, attrs} <- normalize(attrs) do
      %SocialPublication{created_by_id: user.id}
      |> SocialPublication.changeset(attrs)
      |> validate_content()
      |> Repo.insert()
      |> audited("social_publication.created", user)
    end
  end

  @doc "Edits a publication that has not started publishing; it returns to draft."
  def update(%User{} = user, id, attrs) do
    with :ok <- authorize(user) do
      locked(id, fn publication ->
        with true <- SocialPublication.editable?(publication) || {:error, :not_editable},
             {:ok, attrs} <- normalize(Map.merge(current_attrs(publication), stringify(attrs))) do
          publication
          |> SocialPublication.changeset(attrs)
          |> Ecto.Changeset.put_change(:revision, publication.revision + 1)
          |> Ecto.Changeset.put_change(:status, "draft")
          |> Ecto.Changeset.put_change(:approved_revision, nil)
          |> Ecto.Changeset.put_change(:approved_at, nil)
          |> Ecto.Changeset.put_change(:approved_by_id, nil)
          |> Ecto.Changeset.put_change(:last_error, nil)
          |> validate_content()
          |> Repo.update()
        end
      end)
      |> audited("social_publication.updated", user)
    end
  end

  @doc """
  Approves the revision the person reviewed and schedules it. A failed
  publication can be approved again; it resumes after the posts X created.
  """
  def approve(%User{} = user, id, revision) do
    with :ok <- authorize(user) do
      locked(id, fn publication ->
        with :ok <- approvable(publication, revision),
             :ok <- can_approve_for(user, publication.social_account),
             :ok <- can_publish(publication) do
          now = DateTime.truncate(DateTime.utc_now(), :second)

          {:ok, approved} =
            publication
            |> Ecto.Changeset.change(
              status: "approved",
              approved_revision: publication.revision,
              approved_at: now,
              approved_by_id: user.id,
              last_error: nil
            )
            |> Repo.update()

          {:ok, _job} =
            %{"publication_id" => approved.id, "revision" => approved.revision}
            |> PublishSocialPost.new(scheduled_at: Enum.max([approved.scheduled_at, now], DateTime))
            |> Oban.insert()

          {:ok, approved}
        end
      end)
      |> audited("social_publication.approved", user)
    end
  end

  def cancel(%User{} = user, id) do
    with :ok <- authorize(user) do
      locked(id, fn publication ->
        if publication.status in ~w(draft approved failed) do
          publication |> Ecto.Changeset.change(status: "cancelled") |> Repo.update()
        else
          {:error, :not_cancellable}
        end
      end)
      |> audited("social_publication.cancelled", user)
    end
  end

  defp approvable(%SocialPublication{revision: revision} = publication, reviewed) do
    cond do
      not (publication.status in ~w(draft failed) or SocialPublication.stalled?(publication)) ->
        {:error, :not_approvable}

      reviewed != revision ->
        {:error, :stale_revision}

      true ->
        :ok
    end
  end

  defp can_approve_for(_user, nil), do: {:error, :account_disconnected}
  defp can_approve_for(_user, %SocialAccount{kind: "brand"}), do: :ok
  defp can_approve_for(%User{id: id}, %SocialAccount{kind: "personal", connected_by_id: id}), do: :ok
  defp can_approve_for(_user, _account), do: {:error, :personal_account}

  @doc "Whether the account's grant allows publishing these items."
  def can_publish(%SocialPublication{social_account: account, items: items}) do
    needed = if Enum.any?(items, &(&1["media_ids"] != [])), do: ~w(tweet.write media.write), else: ~w(tweet.write)

    cond do
      is_nil(account) -> {:error, :account_disconnected}
      account.needs_authorization -> {:error, :needs_authorization}
      needed -- account.scopes != [] -> {:error, :needs_publish_scope}
      true -> :ok
    end
  end

  @doc """
  Publishes an approved publication whose time has come, item by item, as
  a thread. Called by `PublishSocialPost`; returns `:skip` when it no longer
  applies, such as after an edit or cancellation.
  """
  def publish(id, revision) do
    case claim(id, revision) do
      {:ok, publication} -> publish_items(publication)
      {:error, :skip} -> :skip
    end
  end

  defp claim(id, revision) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      publication = Repo.one(from p in SocialPublication, where: p.id == ^id, lock: "FOR UPDATE")

      if publication && publication.status == "approved" && publication.revision == revision &&
           publication.approved_revision == revision && not DateTime.after?(publication.scheduled_at, now) do
        publication
        |> Ecto.Changeset.change(status: "publishing")
        |> Repo.update!()
        |> Repo.preload(:social_account)
      else
        Repo.rollback(:skip)
      end
    end)
  end

  defp publish_items(%SocialPublication{social_account: nil} = publication),
    do: fail(publication, "The account was disconnected before it published.")

  defp publish_items(publication) do
    publication.items
    |> Enum.drop(length(publication.published_ids))
    |> Enum.reduce_while({:ok, publication}, fn item, {:ok, publication} ->
      case publish_item(publication, item) do
        {:ok, post_id} -> {:cont, {:ok, record_post(publication, post_id)}}
        {:error, reason} -> {:halt, fail(publication, failure(reason))}
      end
    end)
    |> case do
      {:ok, publication} -> published(publication)
      failed -> failed
    end
  end

  defp publish_item(publication, item) do
    reply_to = List.last(publication.published_ids)

    SocialAccounts.with_token(publication.social_account, fn token ->
      with {:ok, media_ids} <- upload_media(token, item["media_ids"]) do
        XPublisher.create_post(token, item["text"], media_ids, reply_to)
      end
    end)
  end

  defp upload_media(token, ids) do
    ids
    |> media()
    |> Enum.reduce_while({:ok, []}, fn media, {:ok, uploaded} ->
      case Storage.get_object(media.storage_key) do
        {:ok, %{body: bytes}} ->
          case XPublisher.upload_media(token, bytes, media.content_type, SocialMedia.kind(media)) do
            {:ok, x_id} -> {:cont, {:ok, uploaded ++ [x_id]}}
            error -> {:halt, error}
          end

        _missing ->
          {:halt, {:error, {:rejected, "#{media.filename} is missing from storage."}}}
      end
    end)
  end

  defp record_post(publication, post_id) do
    publication
    |> Ecto.Changeset.change(published_ids: publication.published_ids ++ [post_id])
    |> Repo.update!()
  end

  defp published(publication) do
    publication =
      publication
      |> Ecto.Changeset.change(status: "published", published_at: DateTime.truncate(DateTime.utc_now(), :second))
      |> Repo.update!()

    audit("social_publication.published", publication, nil)
    {:ok, publication}
  end

  defp fail(publication, message) do
    publication = publication |> Ecto.Changeset.change(status: "failed", last_error: message) |> Repo.update!()
    audit("social_publication.failed", publication, nil)
    {:error, publication}
  end

  defp failure({:unknown, detail}),
    do: "X may have published this post (#{detail}). Check the account on X before approving it again."

  defp failure({:rejected, detail}), do: "X rejected the post: #{detail}"
  defp failure({:http, status, detail}), do: "X rejected the post (HTTP #{status}): #{detail}"
  defp failure(:needs_authorization), do: "The account needs to be reconnected."
  defp failure(reason), do: "Could not publish: #{inspect(reason)}"

  defp current_attrs(publication) do
    %{
      "social_account_id" => publication.social_account_id,
      "social_post_revision_id" => publication.social_post_revision_id,
      "scheduled_at" => publication.scheduled_at,
      "items" => publication.items
    }
  end

  defp stringify(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

  defp normalize(attrs) do
    attrs = stringify(attrs)

    with {:ok, scheduled_at} <- scheduled_at(attrs["scheduled_at"]),
         {:ok, items} <- items(attrs["items"]) do
      {:ok,
       attrs
       |> Map.take(["social_account_id", "social_post_revision_id"])
       |> Map.merge(%{"scheduled_at" => scheduled_at, "items" => items})}
    end
  end

  defp scheduled_at(%DateTime{} = at), do: {:ok, DateTime.truncate(at, :second)}

  defp scheduled_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, DateTime.truncate(at, :second)}
      _invalid -> {:error, :invalid_scheduled_at}
    end
  end

  defp scheduled_at(_value), do: {:error, :invalid_scheduled_at}

  defp items(items) when is_list(items) do
    {:ok,
     Enum.map(items, fn item ->
       item = stringify(item)
       %{"text" => String.trim(item["text"] || ""), "media_ids" => List.wrap(item["media_ids"])}
     end)}
  end

  defp items(_items), do: {:error, :invalid_items}

  defp validate_content(changeset) do
    changeset
    |> Ecto.Changeset.validate_change(:items, fn :items, items ->
      items |> Enum.with_index(1) |> Enum.flat_map(fn {item, n} -> item_errors(item, n) end) |> Enum.map(&{:items, &1})
    end)
    |> Ecto.Changeset.validate_change(:social_account_id, fn :social_account_id, id ->
      case Repo.get(SocialAccount, id) do
        %SocialAccount{platform: "x"} -> []
        %SocialAccount{} -> [social_account_id: "Atlas publishes to X accounts only for now"]
        nil -> [social_account_id: "is not a connected account"]
      end
    end)
  end

  defp item_errors(%{"text" => text, "media_ids" => ids}, n) do
    media = media(ids)
    kinds = Enum.map(media, &SocialMedia.kind/1)

    [
      (text == "" and ids == []) && "post #{n} is empty",
      weighted_length(text) > @max_chars && "post #{n} is longer than #{@max_chars} characters",
      length(media) != length(ids) && "post #{n} has media that does not exist",
      Enum.any?(media, &(&1.status != "uploaded")) && "post #{n} has media that has not finished uploading",
      (length(kinds) > 4 or (length(kinds) > 1 and Enum.any?(kinds, &(&1 != "image")))) &&
        "post #{n} can have up to four images, or one GIF or video"
    ]
    |> Enum.filter(&is_binary/1)
  end

  @doc "Length as X counts it, with every link as 23 characters."
  def weighted_length(text) do
    urls = Regex.scan(@url, text) |> length()
    String.length(Regex.replace(@url, text, "")) + urls * @url_weight
  end

  defp locked(id, fun) do
    Repo.transaction(fn ->
      with {:ok, id} <- Ecto.UUID.cast(id) |> ok_or(:not_found),
           %SocialPublication{} = publication <-
             Repo.one(from p in SocialPublication, where: p.id == ^id, lock: "FOR UPDATE") || {:error, :not_found},
           publication = Repo.preload(publication, :social_account),
           {:ok, result} <- fun.(publication) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp ok_or({:ok, value}, _reason), do: {:ok, value}
  defp ok_or(:error, reason), do: {:error, reason}

  defp authorize(user), do: if(SocialAccounts.can_manage?(user), do: :ok, else: {:error, :forbidden})

  defp audited({:ok, publication} = result, action, user) do
    audit(action, publication, user)
    result
  end

  defp audited(error, _action, _user), do: error

  defp audit(action, publication, user) do
    Audit.record(
      action,
      %{
        target_type: "social_publication",
        target_id: publication.id,
        target_label: publication.items |> List.first(%{}) |> Map.get("text", "") |> String.slice(0, 80),
        metadata: %{
          "social_account_id" => publication.social_account_id,
          "revision" => publication.revision,
          "status" => publication.status,
          "dashboard_path" => @dashboard_path
        }
      },
      if(user, do: [actor: user], else: [])
    )
  end
end
