defmodule Atlas.Accounts.POCs do
  @moduledoc """
  Proof-of-concept records attached to accounts.

  A POC captures the scope, context, and timeline of a customer evaluation.
  Each POC can be published to a signed, unauthenticated URL customers can
  open without an Atlas account, themed with the customer's brand.

  Public content lives entirely in this module. Internal notes, briefs, and
  events are never surfaced through the public page.
  """

  import Ecto.Query

  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.FeatureInterest
  alias Atlas.Accounts.POCs.AccessRequest
  alias Atlas.Accounts.POCs.Context
  alias Atlas.Accounts.POCs.POC
  alias Atlas.Accounts.POCs.ScopeFeature
  alias Atlas.Accounts.POCs.TimelineEntry
  alias Atlas.Audit
  alias Atlas.Repo
  alias Atlas.Users.User
  alias Ecto.Changeset

  @verification_token_bytes 32
  @verification_ttl_seconds 15 * 60
  @session_ttl_seconds 30 * 24 * 60 * 60
  @pubsub Atlas.PubSub

  def can_manage?(%User{}), do: true
  def can_manage?(_user), do: false

  def list_pocs(opts \\ []) do
    POC
    |> maybe_filter_account(Keyword.get(opts, :account_id))
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> order_by([poc], desc: poc.inserted_at)
    |> preload_poc()
    |> Repo.all()
  end

  def get_poc(id) when is_binary(id) do
    POC
    |> preload_poc()
    |> Repo.get(id)
  rescue
    Ecto.Query.CastError -> nil
  end

  def get_poc!(id) when is_binary(id) do
    POC
    |> preload_poc()
    |> Repo.get!(id)
  end

  def get_poc_by_public_token(nil), do: nil

  def get_poc_by_public_token(token) when is_binary(token) do
    POC
    |> preload_poc()
    |> Repo.get_by(public_token: token)
  rescue
    Ecto.Query.CastError -> nil
  end

  def change_poc(poc \\ %POC{}, attrs \\ %{}), do: POC.changeset(poc, attrs)

  def create_poc(attrs, %User{} = user) do
    %POC{}
    |> POC.changeset(attrs)
    |> Changeset.put_change(:created_by_user_id, user.id)
    |> Changeset.put_change(:updated_by_user_id, user.id)
    |> Repo.insert()
    |> case do
      {:ok, poc} ->
        poc = get_poc!(poc.id)
        record_event("poc.created", poc, user)
        {:ok, poc}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def create_poc(_attrs, _user), do: {:error, :unauthorized}

  def update_poc(%POC{} = poc, attrs, %User{} = user) do
    poc
    |> POC.changeset(attrs)
    |> Changeset.put_change(:updated_by_user_id, user.id)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        updated = get_poc!(updated.id)
        record_event("poc.updated", updated, user)
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update_poc(_poc, _attrs, _user), do: {:error, :unauthorized}

  def delete_poc(%POC{} = poc, %User{} = user) do
    case Repo.delete(poc) do
      {:ok, deleted} ->
        record_event("poc.deleted", deleted, user)
        {:ok, deleted}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def delete_poc(_poc, _user), do: {:error, :unauthorized}

  def publish_poc(%POC{public_token: token} = poc, _user) when is_binary(token), do: {:ok, poc}

  def publish_poc(%POC{} = poc, %User{} = user) do
    poc
    |> POC.public_token_changeset(Ecto.UUID.generate())
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        record_event("poc.published", updated, user)
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def publish_poc(_poc, _user), do: {:error, :unauthorized}

  def unpublish_poc(%POC{} = poc, %User{} = user) do
    poc
    |> POC.public_token_changeset(nil)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        record_event("poc.unpublished", updated, user)
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def unpublish_poc(_poc, _user), do: {:error, :unauthorized}

  def rotate_public_token(%POC{} = poc, %User{} = user) do
    poc
    |> POC.public_token_changeset(Ecto.UUID.generate())
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        record_event("poc.public_token_rotated", updated, user)
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def rotate_public_token(_poc, _user), do: {:error, :unauthorized}

  def upsert_context(%POC{} = poc, attrs, %User{} = user) do
    existing = Repo.get_by(Context, poc_id: poc.id) || %Context{poc_id: poc.id}

    existing
    |> Context.changeset(Map.put(attrs, "poc_id", poc.id))
    |> Repo.insert_or_update()
    |> case do
      {:ok, context} ->
        record_event("poc.context_upserted", poc, user, %{"context_id" => context.id})
        {:ok, context}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def upsert_context(_poc, _attrs, _user), do: {:error, :unauthorized}

  def add_scope_feature(%POC{} = poc, feature_interest_id, %User{} = user) when is_binary(feature_interest_id) do
    case Repo.get(FeatureInterest, feature_interest_id) do
      %FeatureInterest{} = feature_interest ->
        %ScopeFeature{}
        |> ScopeFeature.changeset(%{
          "poc_id" => poc.id,
          "feature_interest_id" => feature_interest.id
        })
        |> Repo.insert()
        |> case do
          {:ok, scope_feature} ->
            record_event("poc.scope_feature_added", poc, user, %{
              "feature_interest_id" => feature_interest.id
            })

            {:ok, scope_feature}

          {:error, changeset} ->
            {:error, changeset}
        end

      _ ->
        {:error, :feature_interest_not_found}
    end
  end

  def add_scope_feature(_poc, _id, _user), do: {:error, :unauthorized}

  def remove_scope_feature(%POC{} = poc, feature_interest_id, %User{} = user) when is_binary(feature_interest_id) do
    case Repo.get_by(ScopeFeature, poc_id: poc.id, feature_interest_id: feature_interest_id) do
      nil ->
        {:error, :not_found}

      %ScopeFeature{} = scope_feature ->
        case Repo.delete(scope_feature) do
          {:ok, deleted} ->
            record_event("poc.scope_feature_removed", poc, user, %{
              "feature_interest_id" => feature_interest_id
            })

            {:ok, deleted}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  def remove_scope_feature(_poc, _id, _user), do: {:error, :unauthorized}

  def add_timeline_entry(%POC{} = poc, attrs, %User{} = user) do
    attrs =
      attrs
      |> Map.put("poc_id", poc.id)
      |> maybe_put_author_label(user)

    %TimelineEntry{}
    |> TimelineEntry.changeset(attrs)
    |> Changeset.put_change(:created_by_user_id, user.id)
    |> Repo.insert()
    |> case do
      {:ok, entry} ->
        record_event("poc.timeline_entry_added", poc, user, %{"entry_id" => entry.id})
        {:ok, entry}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def add_timeline_entry(_poc, _attrs, _user), do: {:error, :unauthorized}

  def update_timeline_entry(%POC{} = poc, %TimelineEntry{} = entry, attrs, %User{} = user) do
    if entry.poc_id == poc.id do
      entry
      |> TimelineEntry.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          record_event("poc.timeline_entry_updated", poc, user, %{"entry_id" => updated.id})
          {:ok, updated}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_found}
    end
  end

  def update_timeline_entry(_poc, _entry, _attrs, _user), do: {:error, :unauthorized}

  def delete_timeline_entry(%POC{} = poc, %TimelineEntry{} = entry, %User{} = user) do
    if entry.poc_id == poc.id do
      case Repo.delete(entry) do
        {:ok, deleted} ->
          record_event("poc.timeline_entry_deleted", poc, user, %{"entry_id" => deleted.id})
          {:ok, deleted}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_found}
    end
  end

  def delete_timeline_entry(_poc, _entry, _user), do: {:error, :unauthorized}

  def get_timeline_entry(id) when is_binary(id) do
    Repo.get(TimelineEntry, id)
  rescue
    Ecto.Query.CastError -> nil
  end

  def dashboard_path(%POC{} = poc), do: "/commercial/sales/pocs/#{poc.id}"

  # ---------- Access requests (customer-facing gate) ----------

  @doc """
  True when `email` is either an existing contact on the POC's account or
  belongs to the account's `primary_domain`. Domain match lets forwarded
  links work for colleagues without an operator having to add every teammate
  as a contact manually.
  """
  def authorized_email?(%POC{account: account}, email) when is_binary(email) do
    normalized = String.downcase(String.trim(email))

    domain_match?(account, normalized) or contact_match?(account, normalized)
  end

  def authorized_email?(_poc, _email), do: false

  defp domain_match?(%{primary_domain: domain}, email) when is_binary(domain) and domain != "" do
    trimmed = domain |> String.trim() |> String.downcase()
    String.ends_with?(email, "@" <> trimmed)
  end

  defp domain_match?(_account, _email), do: false

  defp contact_match?(%{id: account_id}, email) when is_binary(account_id) do
    Repo.exists?(
      from contact in Contact,
        where: contact.account_id == ^account_id and fragment("lower(?)", contact.email) == ^email
    )
  end

  defp contact_match?(_account, _email), do: false

  def get_access_request(id) when is_binary(id) do
    Repo.get(AccessRequest, id)
  rescue
    Ecto.Query.CastError -> nil
  end

  @doc """
  Creates a pending access request for `email` on `poc`. Returns
  `{:ok, request, plaintext_verification_token}`. The plaintext token is used
  to build the verification link that is emailed to the requester; only its
  hash is persisted.
  """
  def create_access_request(%POC{} = poc, email, opts \\ []) do
    token = generate_verification_token()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    session_expires_at = DateTime.add(now, session_ttl_seconds(poc), :second)
    verification_expires_at = DateTime.add(now, @verification_ttl_seconds, :second)

    attrs = %{
      "poc_id" => poc.id,
      "email" => email,
      "requester_ip" => Keyword.get(opts, :ip),
      "requester_user_agent" => Keyword.get(opts, :user_agent),
      "verification_token_hash" => hash_token(token),
      "verification_expires_at" => verification_expires_at,
      "expires_at" => session_expires_at
    }

    %AccessRequest{}
    |> AccessRequest.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, request} ->
        Audit.record("poc.access_requested", %{
          interface: "public",
          target_type: "poc",
          target_id: poc.id,
          target_label: poc.title,
          metadata: %{
            "access_request_id" => request.id,
            "email" => request.email,
            "path" => dashboard_path(poc)
          }
        })

        {:ok, request, token}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def record_slack_message(%AccessRequest{} = request, channel_id, message_ts) do
    request
    |> AccessRequest.slack_message_changeset(%{
      "slack_channel_id" => channel_id,
      "slack_message_ts" => message_ts
    })
    |> Repo.update()
  end

  @doc """
  Marks the request as email-verified when the presented plaintext token
  matches the stored hash and the request has not expired.
  """
  def verify_access_email(request_id, plaintext_token) when is_binary(request_id) do
    with %AccessRequest{} = request <- get_access_request(request_id),
         false <- AccessRequest.verification_expired?(request),
         true <- Plug.Crypto.secure_compare(hash_token(plaintext_token), request.verification_token_hash) do
      if request.verified_at do
        {:ok, request}
      else
        request
        |> Ecto.Changeset.change(verified_at: now())
        |> Repo.update()
        |> tap_ok(fn updated ->
          Audit.record("poc.access_verified", %{
            interface: "public",
            target_type: "poc",
            target_id: request.poc_id,
            metadata: %{"access_request_id" => request.id, "email" => request.email}
          })

          broadcast(request.id, {:poc_access_request_updated, updated})
        end)
      end
    else
      _ -> {:error, :invalid_token}
    end
  end

  def approve_access_request(request_id, %User{} = user) when is_binary(request_id) do
    case get_access_request(request_id) do
      nil ->
        {:error, :not_found}

      %AccessRequest{approved_at: %DateTime{}} = request ->
        {:ok, request}

      %AccessRequest{denied_at: %DateTime{}} ->
        {:error, :already_denied}

      request ->
        request
        |> Ecto.Changeset.change(approved_at: now(), approved_by_user_id: user.id)
        |> Repo.update()
        |> tap_ok(fn updated ->
          Audit.record("poc.access_approved", %{
            actor: user,
            interface: "slack",
            target_type: "poc",
            target_id: request.poc_id,
            metadata: %{"access_request_id" => request.id, "email" => request.email}
          })

          broadcast(request.id, {:poc_access_request_updated, updated})
        end)
    end
  end

  def deny_access_request(request_id, %User{} = user) when is_binary(request_id) do
    case get_access_request(request_id) do
      nil ->
        {:error, :not_found}

      %AccessRequest{denied_at: %DateTime{}} = request ->
        {:ok, request}

      request ->
        request
        |> Ecto.Changeset.change(denied_at: now(), denied_by_user_id: user.id)
        |> Repo.update()
        |> tap_ok(fn updated ->
          Audit.record("poc.access_denied", %{
            actor: user,
            interface: "slack",
            target_type: "poc",
            target_id: request.poc_id,
            metadata: %{"access_request_id" => request.id, "email" => request.email}
          })

          broadcast(request.id, {:poc_access_request_updated, updated})
        end)
    end
  end

  def revoke_access_request(request_id, %User{} = user) when is_binary(request_id) do
    case get_access_request(request_id) do
      nil ->
        {:error, :not_found}

      request ->
        request
        |> Ecto.Changeset.change(revoked_at: now(), revoked_by_user_id: user.id)
        |> Repo.update()
        |> tap_ok(fn updated ->
          Audit.record("poc.access_revoked", %{
            actor: user,
            interface: "dashboard",
            target_type: "poc",
            target_id: request.poc_id,
            metadata: %{"access_request_id" => request.id, "email" => request.email}
          })

          broadcast(request.id, {:poc_access_request_updated, updated})
        end)
    end
  end

  def list_access_requests(%POC{id: poc_id}) do
    from(request in AccessRequest,
      where: request.poc_id == ^poc_id,
      order_by: [desc: request.inserted_at]
    )
    |> Repo.all()
  end

  def subscribe_to_access_request(request_id) when is_binary(request_id) do
    Phoenix.PubSub.subscribe(@pubsub, access_request_topic(request_id))
  end

  # A signed cookie carrying (poc_id, access_request_id). Validating the
  # cookie also queries the request row so revocation takes effect
  # immediately without waiting for the cookie to expire.
  def sign_session_cookie(%POC{} = poc, %AccessRequest{poc_id: poc_id} = request) when poc.id == poc_id do
    Phoenix.Token.sign(AtlasWeb.Endpoint, session_token_salt(), %{
      "poc_id" => poc.id,
      "request_id" => request.id
    })
  end

  def verify_session_cookie(%POC{} = poc, cookie) when is_binary(cookie) do
    max_age = session_ttl_seconds(poc)

    case Phoenix.Token.verify(AtlasWeb.Endpoint, session_token_salt(), cookie, max_age: max_age) do
      {:ok, %{"poc_id" => poc_id, "request_id" => request_id}} when poc_id == poc.id ->
        case get_access_request(request_id) do
          %AccessRequest{poc_id: ^poc_id} = request ->
            if AccessRequest.active?(request), do: {:ok, request}, else: {:error, :revoked}

          _ ->
            {:error, :not_found}
        end

      _ ->
        {:error, :invalid}
    end
  end

  def verify_session_cookie(_poc, _cookie), do: {:error, :missing}

  def session_ttl_seconds, do: @session_ttl_seconds

  # The session cookie's TTL is capped at the POC's `ends_on` date so a
  # long-closed POC is not accessible indefinitely from a laptop that once
  # opened it.
  def session_ttl_seconds(%POC{ends_on: %Date{} = ends_on}) do
    seconds_until_end = DateTime.diff(DateTime.new!(ends_on, ~T[23:59:59]), DateTime.utc_now())
    max(min(seconds_until_end, @session_ttl_seconds), 60)
  end

  def session_ttl_seconds(_poc), do: @session_ttl_seconds

  def verification_ttl_seconds, do: @verification_ttl_seconds

  defp generate_verification_token do
    :crypto.strong_rand_bytes(@verification_token_bytes) |> Base.url_encode64(padding: false)
  end

  defp hash_token(token) when is_binary(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  defp session_token_salt, do: "poc-public-session:v1"

  defp access_request_topic(request_id), do: "poc_access:" <> request_id

  defp broadcast(request_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, access_request_topic(request_id), message)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  defp tap_ok(result, _fun), do: result

  defp maybe_filter_account(query, nil), do: query

  defp maybe_filter_account(query, account_id) when is_binary(account_id) do
    where(query, [poc], poc.account_id == ^account_id)
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) when is_binary(status) do
    where(query, [poc], poc.status == ^status)
  end

  defp preload_poc(query) do
    preload(query, [
      :account,
      :created_by_user,
      :updated_by_user,
      :context,
      scope_features: [:feature_interest],
      timeline_entries: ^timeline_entries_query()
    ])
  end

  defp timeline_entries_query do
    from entry in TimelineEntry,
      order_by: [desc: entry.occurred_on, desc: entry.inserted_at]
  end

  defp maybe_put_author_label(attrs, %User{name: name}) when is_binary(name) and name != "" do
    Map.put_new(attrs, "author_label", name)
  end

  defp maybe_put_author_label(attrs, %User{email: email}) when is_binary(email) do
    Map.put_new(attrs, "author_label", email)
  end

  defp maybe_put_author_label(attrs, _user), do: attrs

  defp record_event(action, %POC{} = poc, user, extra_metadata \\ %{}) do
    metadata =
      Map.merge(
        %{
          "poc_id" => poc.id,
          "account_id" => poc.account_id,
          "title" => poc.title,
          "path" => dashboard_path(poc)
        },
        extra_metadata
      )

    Audit.record(action, %{
      actor: user,
      target_type: "poc",
      target_id: poc.id,
      target_label: poc.title,
      metadata: metadata
    })
  end
end
