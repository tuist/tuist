defmodule Atlas.GTM.SocialPublishingTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.MCP.ToolCase, only: [insert_user!: 1]

  alias Atlas.GTM.SocialAccount
  alias Atlas.GTM.SocialPublication
  alias Atlas.GTM.SocialPublishing
  alias Atlas.GTM.Workers.PublishSocialPost

  @publish_scopes ~w(tweet.read tweet.write users.read media.write offline.access)

  defp insert_account!(attrs \\ %{}) do
    %SocialAccount{platform: "x", external_id: "#{System.unique_integer([:positive])}"}
    |> SocialAccount.changeset(
      Map.merge(
        %{
          handle: "@tuistdev",
          kind: "brand",
          access_token: "x-access",
          refresh_token: "x-refresh",
          scopes: @publish_scopes,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        },
        attrs
      )
    )
    |> Ecto.Changeset.put_change(:connected_by_id, attrs[:connected_by_id])
    |> Repo.insert!()
  end

  defp draft!(user, account, items, at \\ DateTime.add(DateTime.utc_now(), -60, :second)) do
    {:ok, publication} =
      SocialPublishing.create(user, %{
        "social_account_id" => account.id,
        "scheduled_at" => DateTime.to_iso8601(at),
        "items" => items
      })

    publication
  end

  # Records X calls and answers with sequential post ids; `fail_on` makes the
  # nth create fail with the given response.
  defp stub_x(test, fail_on \\ nil) do
    counter = :counters.new(1, [])

    stub(Req, :request, fn opts ->
      "https://api.x.com/2/tweets" = opts[:url]
      :counters.add(counter, 1, 1)
      n = :counters.get(counter, 1)
      send(test, {:create, opts[:json]})

      case fail_on do
        {^n, response} -> response
        _ -> {:ok, %Req.Response{status: 201, body: %{"data" => %{"id" => "post-#{n}"}}}}
      end
    end)
  end

  setup do
    user = insert_user!(%{scopes: ["gtm:write"]})
    %{user: user, account: insert_account!()}
  end

  test "publishes an approved thread as replies, in order", %{user: user, account: account} do
    stub_x(self())
    publication = draft!(user, account, [%{"text" => "First"}, %{"text" => "Second"}])

    assert {:ok, approved} = SocialPublishing.approve(user, publication.id, publication.revision)
    assert_enqueued(worker: PublishSocialPost, args: %{"publication_id" => approved.id, "revision" => 1})

    assert :ok = perform_job(PublishSocialPost, %{"publication_id" => approved.id, "revision" => 1})

    assert_received {:create, %{text: "First"} = first}
    refute Map.has_key?(first, :reply)
    assert_received {:create, %{text: "Second", reply: %{in_reply_to_tweet_id: "post-1"}}}

    published = Repo.get!(SocialPublication, approved.id)
    assert {published.status, published.published_ids} == {"published", ["post-1", "post-2"]}
  end

  test "an edit after approval needs a new approval, and the old job does nothing", %{user: user, account: account} do
    stub(Req, :request, fn _ -> flunk("must not reach X") end)
    publication = draft!(user, account, [%{"text" => "Original"}])
    {:ok, _} = SocialPublishing.approve(user, publication.id, 1)

    assert {:ok, edited} = SocialPublishing.update(user, publication.id, %{"items" => [%{"text" => "Changed"}]})
    assert {edited.status, edited.revision, edited.approved_by_id} == {"draft", 2, nil}

    assert :ok = perform_job(PublishSocialPost, %{"publication_id" => publication.id, "revision" => 1})
    assert Repo.get!(SocialPublication, publication.id).status == "draft"

    # Approving what the reviewer saw before the edit is refused.
    assert {:error, :stale_revision} = SocialPublishing.approve(user, publication.id, 1)
  end

  test "a scheduled post does not publish early", %{user: user, account: account} do
    stub(Req, :request, fn _ -> flunk("must not reach X") end)
    publication = draft!(user, account, [%{"text" => "Later"}], DateTime.add(DateTime.utc_now(), 3600, :second))
    {:ok, _} = SocialPublishing.approve(user, publication.id, 1)

    assert :ok = perform_job(PublishSocialPost, %{"publication_id" => publication.id, "revision" => 1})
    assert Repo.get!(SocialPublication, publication.id).status == "approved"
  end

  test "only whoever connected a personal account approves its posts", %{user: user} do
    owner = insert_user!(%{scopes: ["gtm:write"]})
    account = insert_account!(%{handle: "@founder", kind: "personal", connected_by_id: owner.id})
    publication = draft!(user, account, [%{"text" => "Hi"}])

    assert {:error, :personal_account} = SocialPublishing.approve(user, publication.id, 1)
    assert {:ok, _} = SocialPublishing.approve(owner, publication.id, 1)
  end

  test "approval needs the publish scopes and gtm:write", %{user: user} do
    read_only = insert_account!(%{scopes: ~w(tweet.read users.read offline.access)})
    publication = draft!(user, read_only, [%{"text" => "Hi"}])
    assert {:error, :needs_publish_scope} = SocialPublishing.approve(user, publication.id, 1)

    reader = insert_user!(%{scopes: ["gtm:read"]})
    assert {:error, :forbidden} = SocialPublishing.approve(reader, publication.id, 1)
  end

  test "rejects posts X would refuse", %{user: user, account: account} do
    # 257 characters plus a link counted as 23 is exactly 280.
    fits = String.duplicate("a", 256) <> " https://tuist.dev/" <> String.duplicate("x", 60)
    assert SocialPublishing.weighted_length(fits) == 280

    assert {:ok, _} =
             SocialPublishing.create(user, %{
               "social_account_id" => account.id,
               "scheduled_at" => "2026-12-01T10:00:00Z",
               "items" => [%{"text" => fits}]
             })

    assert {:error, changeset} =
             SocialPublishing.create(user, %{
               "social_account_id" => account.id,
               "scheduled_at" => "2026-12-01T10:00:00Z",
               "items" => [%{"text" => "!" <> fits}, %{"text" => ""}]
             })

    assert %{items: errors} = errors_on(changeset)
    assert "post 1 is longer than 280 characters" in errors
    assert "post 2 is empty" in errors
  end

  test "a failure that may have reached X is not retried; a rejection resumes after published posts",
       %{user: user, account: account} do
    stub_x(self(), {2, {:error, %Req.TransportError{reason: :timeout}}})
    publication = draft!(user, account, [%{"text" => "One"}, %{"text" => "Two"}])
    {:ok, _} = SocialPublishing.approve(user, publication.id, 1)

    assert {:cancel, message} = perform_job(PublishSocialPost, %{"publication_id" => publication.id, "revision" => 1})
    assert message =~ "may have published"

    failed = Repo.get!(SocialPublication, publication.id)
    assert {failed.status, failed.published_ids} == {"failed", ["post-1"]}
    refute SocialPublication.editable?(failed)

    assert_received {:create, %{text: "One"}}
    assert_received {:create, %{text: "Two"}}

    # A person checks X and approves again; only the second post goes out.
    stub_x(self())
    {:ok, _} = SocialPublishing.approve(user, publication.id, 1)
    assert :ok = perform_job(PublishSocialPost, %{"publication_id" => publication.id, "revision" => 1})
    assert_received {:create, %{text: "Two", reply: %{in_reply_to_tweet_id: "post-1"}}}
    refute_received {:create, %{text: "One"}}
    resumed = Repo.get!(SocialPublication, publication.id)
    assert resumed.status == "published"
    assert length(resumed.published_ids) == 2
  end

  test "uploads attached images to X and attaches them to the post", %{user: user, account: account} do
    {:ok, media} = SocialPublishing.store_media(user, "card.png", "image/png", "png-bytes")
    test = self()

    stub(Req, :request, fn opts ->
      case opts[:url] do
        "https://api.x.com/2/media/upload" ->
          send(test, {:upload, opts[:json]})
          {:ok, %Req.Response{status: 200, body: %{"data" => %{"id" => "x-media-1"}}}}

        "https://api.x.com/2/tweets" ->
          send(test, {:create, opts[:json]})
          {:ok, %Req.Response{status: 201, body: %{"data" => %{"id" => "post-1"}}}}
      end
    end)

    publication = draft!(user, account, [%{"text" => "", "media_ids" => [media.id]}])
    {:ok, _} = SocialPublishing.approve(user, publication.id, 1)
    assert :ok = perform_job(PublishSocialPost, %{"publication_id" => publication.id, "revision" => 1})

    assert_received {:upload, %{media: encoded, media_category: "tweet_image"}}
    assert Base.decode64!(encoded) == "png-bytes"
    assert_received {:create, %{media: %{media_ids: ["x-media-1"]}}}
  end

  test "an oversized image is refused before it is stored", %{user: user} do
    assert {:error, {:media_too_large, "image", 5_000_000}} =
             SocialPublishing.store_media(user, "huge.png", "image/png", :binary.copy("a", 5_000_001))
  end
end
