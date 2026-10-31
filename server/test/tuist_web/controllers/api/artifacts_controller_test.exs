defmodule TuistWeb.API.ArtifactsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.AppBuilds.AppBuild
  alias Tuist.AppBuilds.Preview
  alias Tuist.Artifacts.Package
  alias Tuist.Artifacts.ProjectApplicationsWorker
  alias Tuist.Artifacts.Publication
  alias Tuist.Artifacts.RetentionWorker
  alias Tuist.Repo
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture()

    project =
      [account_id: user.account.id, build_system: :once] |> ProjectsFixtures.project_fixture() |> Repo.preload(:account)

    {:ok, store} = Agent.start_link(fn -> %{} end)

    stub(Storage, :upload_file, fn path, key, _ ->
      Agent.update(store, &Map.put(&1, key, File.read!(path)))
      {:ok, %{status_code: 200}}
    end)

    stub(Storage, :stream_object, fn key, _ -> [Agent.get(store, &Map.fetch!(&1, key))] end)

    stub(Storage, :get_object_size, fn key, _ ->
      case Agent.get(store, &Map.get(&1, key)) do
        nil -> {:error, :not_found}
        bytes -> {:ok, byte_size(bytes)}
      end
    end)

    stub(Storage, :upload, fn stream, key, _ ->
      bytes = Enum.join(stream)
      Agent.update(store, &Map.put(&1, key, bytes))
      %{status_code: 200}
    end)

    %{user: user, project: project, store: store}
  end

  test "retains a multi-kind closure and projects eligible applications exactly once", context do
    metadata = [
      {"dev.once.android-install.v1",
       %{
         "schema" => "once.android_application.v1",
         "signature_verified" => true,
         "application_id" => "org.example.android",
         "version_name" => "2.3",
         "version_code" => "23"
       }},
      {"dev.once.apple-install.v2",
       %{
         "schema" => "once.apple_application.v1",
         "signature_verified" => true,
         "signing" => "ad_hoc",
         "platform" => "ios",
         "sdk_variant" => "simulator",
         "bundle_identifier" => "org.example.apple",
         "display_name" => "Apple App",
         "version" => "4.5",
         "build_version" => "45"
       }},
      {"dev.once.android-install.v1",
       %{
         "schema" => "once.android_application.v1",
         "signature_verified" => false,
         "application_id" => "org.example.unsigned"
       }},
      {"dev.once.apple-install.v2",
       %{
         "schema" => "once.apple_application.v1",
         "signature_verified" => true,
         "signing" => "ad_hoc",
         "platform" => "ios",
         "sdk_variant" => "device",
         "bundle_identifier" => "org.example.device"
       }},
      {"example.dataset.v3", %{"schema" => "example.dataset.v3"}}
    ]

    {intent, blobs} = package(metadata)
    key = Package.key(intent)
    upload(context, key, blobs)
    conn = request(context, :post, "/publications/#{key}", intent)
    receipt = json_response(conn, :ok)
    assert receipt["root"] == intent["root"]
    assert receipt["destination"] == "project:#{context.project.id}"
    assert receipt["key"] == key

    assert json_response(request(context, :post, "/publications/#{key}", intent), :ok) == receipt
    assert json_response(request(context, :get, "/publications/#{key}"), :ok) == receipt
    assert [publication] = Repo.all(Publication)
    assert map_size(publication.contents) == map_size(blobs)
    assert [job] = Repo.all(Oban.Job)
    assert job.args == %{"publication_id" => publication.id}
    assert :ok = ProjectApplicationsWorker.perform(%Oban.Job{args: job.args})
    assert :ok = ProjectApplicationsWorker.perform(%Oban.Job{args: job.args})
    assert Enum.sort(Enum.map(Repo.all(Preview), & &1.bundle_identifier)) == ["org.example.android", "org.example.apple"]

    assert Enum.sort(Enum.map(Repo.all(AppBuild), &{&1.type, &1.supported_platforms, &1.build_version})) ==
             [{:apk, [:android], "23"}, {:app_bundle, [:ios_simulator], "45"}]

    assert Repo.get!(Publication, publication.id).projected
  end

  test "projects desktop applications and executables with target compatibility and respects the rollout gate", context do
    interfaces = [
      {"dev.once.apple-install.v2",
       %{
         "schema" => "once.apple_application.v1",
         "signature_verified" => true,
         "signing" => "ad_hoc",
         "platform" => "macos",
         "sdk_variant" => "device",
         "bundle_identifier" => "org.example.desktop"
       }},
      {"dev.tuist.executable.v1",
       %{
         "schema" => "tuist.executable.v1",
         "display_name" => "tool",
         "platform" => "linux",
         "architectures" => ["arm64"],
         "executable" => "bin/tool"
       }},
      {"dev.tuist.executable.v1",
       %{
         "schema" => "tuist.executable.v1",
         "display_name" => "mac-tool",
         "platform" => "macos",
         "architectures" => ["x86_64", "arm64"],
         "executable" => "bin/mac-tool"
       }},
      {"dev.tuist.executable.v1",
       %{
         "schema" => "tuist.executable.v1",
         "display_name" => "unsupported",
         "platform" => "linux",
         "architectures" => ["mips"]
       }}
    ]

    {intent, blobs} = package(interfaces)
    key = Package.key(intent)
    upload(context, key, blobs)
    assert json_response(request(context, :post, "/publications/#{key}", intent), :ok)
    [publication] = Repo.all(Publication)
    job = %Oban.Job{args: %{"publication_id" => publication.id}}

    stub(Tuist.FeatureFlags, :cli_previews_enabled?, fn _ -> false end)
    assert {:error, :cli_previews_disabled} = ProjectApplicationsWorker.perform(job)
    assert Repo.all(AppBuild) == []
    refute Repo.get!(Publication, publication.id).projected

    stub(Tuist.FeatureFlags, :cli_previews_enabled?, fn _ -> true end)
    assert :ok = ProjectApplicationsWorker.perform(job)
    assert :ok = ProjectApplicationsWorker.perform(job)
    builds = Repo.all(AppBuild)
    assert length(builds) == 3
    assert Enum.any?(builds, &(&1.type == :app_bundle and &1.supported_platforms == [:macos]))

    assert Enum.any?(
             builds,
             &(&1.type == :executable and &1.supported_platforms == [:linux] and &1.supported_architectures == ["arm64"])
           )

    assert Enum.any?(
             builds,
             &(&1.type == :executable and &1.supported_platforms == [:macos] and
                 &1.supported_architectures == ["x86_64", "arm64"])
           )

    assert Enum.all?(builds, &String.contains?(&1.artifact_storage_key, "/artifacts/"))
  end

  test "rejects incomplete closures, wrong hashes and failed storage without acknowledging publication", context do
    {intent, blobs} = package([{"example.report.v1", %{}}])
    key = Package.key(intent)
    [missing | rest] = Map.to_list(blobs)
    upload(context, key, Map.new(rest))
    assert json_response(request(context, :post, "/publications/#{key}", intent), :unprocessable_entity)
    assert json_response(request(context, :get, "/publications/#{key}"), :not_found)
    assert Repo.all(Oban.Job) == []
    {digest, bytes} = missing
    conn = raw_upload(context, key, digest, bytes <> "corrupt")
    assert json_response(conn, :unprocessable_entity)["error"] == "digest_mismatch"
    stub(Storage, :upload_file, fn _, _, _ -> {:error, :unavailable} end)
    assert json_response(raw_upload(context, key, digest, bytes), :service_unavailable)
    assert json_response(request(context, :get, "/publications/#{key}"), :not_found)
  end

  test "commit-time storage outages remain retryable without acknowledging a publication", context do
    {intent, blobs} = package([{"example.report.v1", %{}}])
    key = Package.key(intent)
    upload(context, key, blobs)

    stub(Storage, :get_object_size, fn _, _ -> {:error, :timeout} end)
    assert json_response(request(context, :post, "/publications/#{key}", intent), :service_unavailable)
    assert json_response(request(context, :get, "/publications/#{key}"), :not_found)
    assert Repo.all(Oban.Job) == []

    stub(Storage, :get_object_size, fn object_key, _ ->
      {:ok, byte_size(Agent.get(context.store, &Map.fetch!(&1, object_key)))}
    end)

    assert json_response(request(context, :post, "/publications/#{key}", intent), :ok)
    assert length(Repo.all(Oban.Job)) == 1
  end

  test "rejects intent strings that PostgreSQL cannot represent", context do
    {intent, _blobs} = package([{"example.report.v1", %{}}])

    invalid_intents =
      Enum.map(["target", "track", "revision"], &Map.put(intent, &1, "bad\0value")) ++
        [put_in(intent, ["root", "media_type"], "application/bad\0type")]

    for invalid <- invalid_intents do
      key = Package.key(invalid)
      assert json_response(request(context, :post, "/publications/#{key}", invalid), :unprocessable_entity)
    end

    assert Repo.all(Publication) == []
    assert Repo.all(Oban.Job) == []
  end

  test "validation pins old uploads without exposing an uncommitted receipt", context do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    {intent, blobs} = package([{"example.report.v1", %{}}])
    key = Package.key(intent)
    upload(context, key, blobs)

    stub(Storage, :list_objects, fn _, _, _ ->
      objects =
        context.store
        |> Agent.get(&Map.keys/1)
        |> Enum.map(&%{key: &1, last_modified: DateTime.add(DateTime.utc_now(), -31, :day)})

      {:ok, %{body: %{contents: objects, is_truncated: false}}}
    end)

    stub(Storage, :delete_objects, fn keys, _ ->
      Agent.update(context.store, &Map.drop(&1, keys))
      :ok
    end)

    root_key = Package.storage_key(context.project, key, intent["root"]["digest"])

    stub(Storage, :get_object_size, fn object_key, _ ->
      if object_key == root_key do
        assert json_response(request(context, :get, "/publications/#{key}"), :not_found)
        assert :ok = RetentionWorker.perform(%Oban.Job{args: %{"account_id" => context.user.account.id}})
      end

      {:ok, byte_size(Agent.get(context.store, &Map.fetch!(&1, object_key)))}
    end)

    assert json_response(request(context, :post, "/publications/#{key}", intent), :ok)
    assert map_size(Agent.get(context.store, & &1)) == map_size(blobs)
    assert json_response(request(context, :get, "/publications/#{key}"), :ok)
  end

  test "malformed native interfaces do not prevent eligible siblings from becoming previews", context do
    {intent, blobs} =
      package([
        {"dev.once.android-install.v1", %{}},
        {"dev.once.android-install.v1",
         %{"schema" => "once.android_application.v1", "signature_verified" => true, "application_id" => %{}}},
        {"dev.once.android-install.v1",
         %{"schema" => "once.android_application.v1", "signature_verified" => true, "application_id" => "org.bad\0id"}},
        {"dev.once.android-install.v1",
         %{
           "schema" => "once.android_application.v1",
           "signature_verified" => true,
           "application_id" => "org.example.badversion",
           "version_name" => "bad\0version"
         }},
        {"dev.once.android-install.v1",
         %{
           "schema" => "once.android_application.v1",
           "signature_verified" => true,
           "application_id" => "org.example.valid",
           "version_name" => "1.2",
           "version_code" => "12"
         }}
      ])

    root = JSON.decode!(blobs[intent["root"]["digest"]])
    manifest = JSON.decode!(blobs[root["members"]["member0"]["artifact"]["digest"]])
    manifest = put_in(manifest, ["interfaces", "dev.once.android-install.v1", "spec"], %{})
    {member, blobs} = add_blob(blobs, JSON.encode!(manifest), "application/vnd.once.artifact.v1+json")
    root = put_in(root, ["members", "member0", "artifact"], member)
    {root, blobs} = add_blob(blobs, JSON.encode!(root), "application/vnd.once.artifact-set.v1+json")
    intent = %{intent | "root" => root}
    key = Package.key(intent)
    upload(context, key, blobs)
    assert json_response(request(context, :post, "/publications/#{key}", intent), :ok)
    [job] = Repo.all(Oban.Job)

    stub(Storage, :get_object_size, fn _, _ -> {:error, :timeout} end)
    assert {:error, :storage_unavailable} = ProjectApplicationsWorker.perform(%Oban.Job{args: job.args})
    assert Repo.all(Preview) == []

    stub(Storage, :get_object_size, fn object_key, _ ->
      {:ok, byte_size(Agent.get(context.store, &Map.fetch!(&1, object_key)))}
    end)

    assert :ok = ProjectApplicationsWorker.perform(%Oban.Job{args: job.args})
    assert [%{bundle_identifier: "org.example.valid"}] = Repo.all(Preview)
  end

  test "does not disclose foreign publications or blobs", context do
    {intent, blobs} = package([{"example.report.v1", %{}}])
    key = Package.key(intent)
    upload(context, key, blobs)
    assert json_response(request(context, :post, "/publications/#{key}", intent), :ok)
    stranger = AccountsFixtures.user_fixture()
    conn = request(%{context | user: stranger}, :get, "/publications/#{key}")
    assert conn.status in [403, 404]
    other = [account_id: context.user.account.id] |> ProjectsFixtures.project_fixture() |> Repo.preload(:account)
    assert json_response(request(%{context | project: other}, :get, "/publications/#{key}"), :not_found)
    digest = List.first(Map.keys(blobs))
    assert json_response(request(%{context | project: other}, :get, "/publications/#{key}/content/#{digest}"), :not_found)
  end

  test "delayed consumer work does not recreate expired publications", context do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    {intent, blobs} = package([{"example.report.v1", %{}}])
    key = Package.key(intent)
    upload(context, key, blobs)
    assert json_response(request(context, :post, "/publications/#{key}", intent), :ok)
    [publication] = Repo.all(Publication)
    publication |> Ecto.Changeset.change(inserted_at: DateTime.add(publication.inserted_at, -31, :day)) |> Repo.update!()
    assert json_response(request(context, :get, "/publications/#{key}"), :gone)
    assert :ok = ProjectApplicationsWorker.perform(%Oban.Job{args: %{"publication_id" => publication.id}})
    assert Repo.all(Preview) == []
    refute Repo.get!(Publication, publication.id).projected
  end

  test "previews reference retained content without detached copies", context do
    project = context.project |> Ecto.Changeset.change(default_previews_visibility: :public) |> Repo.update!()
    context = %{context | project: project}

    {intent, blobs} =
      package([
        {"dev.once.android-install.v1",
         %{
           "schema" => "once.android_application.v1",
           "signature_verified" => true,
           "application_id" => "org.example.retry",
           "version_name" => "1",
           "version_code" => "3"
         }}
      ])

    key = Package.key(intent)
    upload(context, key, blobs)
    assert json_response(request(context, :post, "/publications/#{key}", intent), :ok)
    [publication] = Repo.all(Publication)
    job = %Oban.Job{args: %{"publication_id" => publication.id}}
    original = Agent.get(context.store, & &1)
    assert :ok = ProjectApplicationsWorker.perform(job)
    assert [%Preview{bundle_identifier: "org.example.retry", visibility: :public}] = Repo.all(Preview)
    [app] = Repo.all(AppBuild)
    object_key = Tuist.AppBuilds.storage_key(%{app_build: app})
    assert Map.fetch!(original, object_key) == "mock native payload 0"
    assert Agent.get(context.store, & &1) == original

    stub(Storage, :object_exists?, fn key, _ -> Agent.get(context.store, &Map.has_key?(&1, key)) end)

    download =
      Phoenix.ConnTest.build_conn()
      |> log_in_user(context.user)
      |> get("/#{project.account.name}/#{project.name}/previews/#{app.id}/app.apk")

    download_query = download |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert download_query["response-content-disposition"] == ~s(attachment; filename="app.apk")

    for {action, upload_params} <- [
          {"generate-url", %{multipart_upload_part: %{part_number: 1, upload_id: "arbitrary"}}},
          {"complete",
           %{multipart_upload_parts: %{parts: [%{part_number: 1, etag: "replacement"}], upload_id: "arbitrary"}}}
        ] do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Authentication.put_current_user(context.user)
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/projects/#{context.user.account.name}/#{context.project.name}/previews/#{action}",
          Map.put(upload_params, :preview_id, app.id)
        )

      assert json_response(conn, :conflict)["message"] == "Published artifact content is immutable."
    end
  end

  test "expiry during projection does not publish it", context do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

    {intent, blobs} =
      package([
        {"dev.once.android-install.v1",
         %{
           "schema" => "once.android_application.v1",
           "signature_verified" => true,
           "application_id" => "org.example.expiry"
         }}
      ])

    key = Package.key(intent)
    upload(context, key, blobs)
    assert json_response(request(context, :post, "/publications/#{key}", intent), :ok)
    [publication] = Repo.all(Publication)

    stub(Storage, :stream_object, fn key, _ ->
      bytes = Agent.get(context.store, &Map.fetch!(&1, key))

      if String.contains?(bytes, "once.android_application.v1") do
        publication
        |> Ecto.Changeset.change(inserted_at: DateTime.add(publication.inserted_at, -31, :day))
        |> Repo.update!()
      end

      [bytes]
    end)

    assert :ok = ProjectApplicationsWorker.perform(%Oban.Job{args: %{"publication_id" => publication.id}})
    assert Repo.all(Preview) == []
    refute Enum.any?(Agent.get(context.store, &Map.keys/1), &String.contains?(&1, "/previews/"))
  end

  test "retention removes expired and abandoned bytes but preserves retained closures", context do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    {intent, blobs} = package([{"example.report.v1", %{}}])
    key = Package.key(intent)
    upload(context, key, blobs)
    assert json_response(request(context, :post, "/publications/#{key}", intent), :ok)
    [publication] = Repo.all(Publication)
    orphan = Package.storage_key(context.project, Package.digest("orphan"), Package.digest("data"))
    unrelated = "#{context.user.account.id}/other/data"
    Agent.update(context.store, &(&1 |> Map.put(orphan, "data") |> Map.put(unrelated, "keep")))

    stub(Storage, :list_objects, fn _, _, _ ->
      objects =
        context.store
        |> Agent.get(&Map.keys/1)
        |> Enum.map(&%{key: &1, last_modified: DateTime.add(publication.inserted_at, -31, :day)})

      {:ok, %{body: %{contents: objects, is_truncated: false}}}
    end)

    stub(Storage, :delete_objects, fn keys, _ ->
      Agent.update(context.store, &Map.drop(&1, keys))
      :ok
    end)

    job = %Oban.Job{args: %{"account_id" => context.user.account.id}}
    assert :ok = RetentionWorker.perform(job)
    refute Agent.get(context.store, &Map.has_key?(&1, orphan))
    assert map_size(Agent.get(context.store, & &1)) == map_size(blobs) + 1
    publication |> Ecto.Changeset.change(inserted_at: DateTime.add(publication.inserted_at, -31, :day)) |> Repo.update!()

    stub(Storage, :delete_objects, fn
      [], _ ->
        :ok

      keys, _ ->
        Agent.update(context.store, &Map.drop(&1, keys))
        {:error, :unavailable}
    end)

    assert {:error, :unavailable} = RetentionWorker.perform(job)
    assert Repo.get!(Publication, publication.id).expired
    assert Agent.get(context.store, & &1) == %{unrelated => "keep"}
    stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
    stub(Tuist.Environment, :artifact_retention_days, fn -> %{} end)
    assert {:error, :expired} = Tuist.Artifacts.get(context.project, key)
    assert {:error, :expired} = Tuist.Artifacts.commit(context.project, key, intent, context.user.account.id)
  end

  test "unconfirmed orphan deletion permanently fences publication before its remote effect", context do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    {intent, blobs} = package([{"example.report.v1", %{}}])
    key = Package.key(intent)
    upload(context, key, blobs)

    stub(Storage, :list_objects, fn _, _, _ ->
      objects =
        context.store
        |> Agent.get(&Map.keys/1)
        |> Enum.map(&%{key: &1, last_modified: DateTime.add(DateTime.utc_now(), -31, :day)})

      {:ok, %{body: %{contents: objects, is_truncated: false}}}
    end)

    # The provider accepts the deletion, but its effect is delayed past the
    # caller's timeout. The closure is still complete when commit is attempted.
    stub(Storage, :delete_objects, fn keys, _ ->
      send(self(), {:pending_delete, keys})
      {:error, :timeout}
    end)

    assert {:error, :timeout} =
             RetentionWorker.perform(%Oban.Job{args: %{"account_id" => context.user.account.id}})

    assert json_response(request(context, :post, "/publications/#{key}", intent), :gone)
    {digest, bytes} = Enum.at(blobs, 0)
    assert json_response(raw_upload(context, key, digest, bytes), :gone)
    assert Repo.all(Oban.Job) == []

    assert_receive {:pending_delete, keys}
    Agent.update(context.store, &Map.drop(&1, keys))
    assert Agent.get(context.store, & &1) == %{}
    stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
    stub(Tuist.Environment, :artifact_retention_days, fn -> %{} end)
    assert {:error, :expired} = Tuist.Artifacts.get(context.project, key)
    assert {:error, :expired} = Tuist.Artifacts.commit(context.project, key, intent, context.user.account.id)
  end

  test "public projects do not make generic artifact closures public", context do
    project = context.project |> Ecto.Changeset.change(visibility: :public) |> Repo.update!()
    context = %{context | project: project}
    {intent, blobs} = package([{"example.private.v1", %{}}])
    key = Package.key(intent)
    upload(context, key, blobs)
    assert json_response(request(context, :post, "/publications/#{key}", intent), :ok)
    stranger = AccountsFixtures.user_fixture()
    assert request(%{context | user: stranger}, :get, "/publications/#{key}").status == 403
    assert request(%{context | user: nil}, :get, "/publications/#{key}").status in [401, 403]
    assert request(%{context | user: stranger}, :get, "").status == 403
  end

  defp request(context, _method, suffix, body \\ nil) do
    conn = Authentication.put_current_user(Phoenix.ConnTest.build_conn(), context.user)
    path = "/api/projects/#{context.project.account.name}/#{context.project.name}/artifacts" <> suffix

    if is_nil(body),
      do: get(conn, path),
      else: post(put_req_header(conn, "content-type", "application/json"), path, JSON.encode!(body))
  end

  defp raw_upload(context, key, digest, bytes) do
    Phoenix.ConnTest.build_conn()
    |> Authentication.put_current_user(context.user)
    |> put_req_header("content-type", "application/octet-stream")
    |> post(
      "/api/projects/#{context.user.account.name}/#{context.project.name}/artifacts/publications/#{key}/content/#{digest}",
      bytes
    )
  end

  defp upload(context, key, blobs) do
    Enum.each(blobs, fn {digest, bytes} ->
      assert response(raw_upload(context, key, digest, bytes), :no_content) == ""
    end)
  end

  defp package(interfaces) do
    {members, blobs} =
      interfaces
      |> Enum.with_index()
      |> Enum.reduce({%{}, %{}}, fn {{interface, metadata}, index}, {members, blobs} ->
        {payload, blobs} = add_blob(blobs, "mock native payload #{index}", "application/octet-stream")
        {metadata, blobs} = add_blob(blobs, JSON.encode!(metadata), "application/json")

        manifest = %{
          "schema" => "once.artifact.v1",
          "payloads" => %{"product" => payload, "metadata" => metadata},
          "interfaces" => %{interface => %{"payload" => "product", "spec" => %{"metadata_payload" => "metadata"}}}
        }

        {descriptor, blobs} = add_blob(blobs, JSON.encode!(manifest), "application/vnd.once.artifact.v1+json")
        {Map.put(members, "member#{index}", %{"artifact" => descriptor, "selectors" => %{}}), blobs}
      end)

    {root, blobs} =
      add_blob(
        blobs,
        JSON.encode!(%{"schema" => "once.artifact_set.v1", "members" => members}),
        "application/vnd.once.artifact-set.v1+json"
      )

    {%{
       "schema" => "once.publication_intent.v1",
       "root" => root,
       "target" => "Applications",
       "track" => nil,
       "revision" => "abc123"
     }, blobs}
  end

  defp add_blob(blobs, bytes, media_type) do
    digest = Package.digest(bytes)
    {%{"digest" => digest, "size_bytes" => byte_size(bytes), "media_type" => media_type}, Map.put(blobs, digest, bytes)}
  end
end
