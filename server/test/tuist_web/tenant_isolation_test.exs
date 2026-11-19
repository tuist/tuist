defmodule TuistWeb.TenantIsolationTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.AppBuilds.Preview
  alias Tuist.Bundles
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.TenantIsolationFixtures
  alias TuistWeb.Errors.NotFoundError

  setup do
    TenantIsolationFixtures.tenants_fixture("isolation-#{System.unique_integer([:positive])}")
  end

  test "real user, project and account credentials isolate populated private reads", tenants do
    for {own, other} <- [{tenants.alpha, tenants.beta}, {tenants.beta, tenants.alpha}],
        token <- [user_token(own.user), own.project.token, account_token(own), account_token(own, restricted: true)] do
      conn = bearer(token)

      bundles = conn |> get(api_path(own, "/bundles")) |> json_response(200)
      assert Enum.map(bundles["bundles"], & &1["id"]) == [own.bundle.id]
      bundle = conn |> get(api_path(own, "/bundles/#{own.bundle.id}")) |> json_response(200)
      assert bundle["name"] == own.bundle.name
      assert bundle["install_size"] == own.bundle.install_size
      assert [%{"path" => path}] = bundle["artifacts"]
      assert path == "#{if own == tenants.alpha, do: "alpha", else: "beta"}.txt"

      runs = conn |> get(api_path(own, "/tests")) |> json_response(200)
      assert Enum.map(runs["test_runs"], & &1["id"]) == [own.test_run.id]
      run = conn |> get(api_path(own, "/tests/#{own.test_run.id}")) |> json_response(200)
      assert run["scheme"] == own.test_run.scheme
      assert run["total_test_count"] == 1

      preview = conn |> get(api_path(own, "/previews/#{own.preview.id}")) |> json_response(200)
      assert preview["display_name"] == own.preview.display_name

      for suffix <- [
            "/bundles",
            "/bundles/#{other.bundle.id}",
            "/tests",
            "/tests/#{other.test_run.id}",
            "/previews/#{other.preview.id}"
          ] do
        assert conn |> get(api_path(other, suffix)) |> json_response(403)
      end

      # A valid parent URL must not authorize a foreign child identifier.
      for suffix <- ["/bundles/#{other.bundle.id}", "/tests/#{other.test_run.id}", "/previews/#{other.preview.id}"] do
        assert conn |> get(api_path(own, suffix)) |> json_response(404)
      end
    end
  end

  for action <- [:generate_url, :complete, :icon] do
    @action action
    test "#{action} binds preview uploads to the authorized project", tenants do
      # Only object-storage I/O is substituted; authentication, policy, resource
      # lookups and the preview metadata update use the real application stack.
      stub(Storage, :multipart_generate_url, fn _, _, _, _, _ -> "https://storage.invalid/part" end)
      stub(Storage, :multipart_complete_upload, fn _, _, _, _ -> :ok end)
      stub(Storage, :generate_upload_url, fn _, _, _ -> "https://storage.invalid/icon" end)
      stub(Storage, :generate_download_url, fn _, _, _ -> "https://storage.invalid/download" end)

      for {own, other} <- [{tenants.alpha, tenants.beta}, {tenants.beta, tenants.alpha}] do
        own_build = AppBuildsFixtures.app_build_fixture(preview: own.preview)
        other_build = AppBuildsFixtures.app_build_fixture(preview: other.preview)
        sibling_preview = AppBuildsFixtures.preview_fixture(project: own.sibling, visibility: :private)
        sibling_build = AppBuildsFixtures.app_build_fixture(preview: sibling_preview)

        for token <- [user_token(own.user), own.project.token, account_token(own), account_token(own, restricted: true)],
            legacy? <- if(@action == :icon, do: [false], else: [true, false]) do
          conn = bearer(token)

          foreign_ids = [{other.preview, other_build}, {sibling_preview, sibling_build}]

          # A valid deprecated ID must not authorize a foreign current app_build_id.
          foreign_ids =
            if !legacy? && @action != :icon,
              do: [{own.preview, other_build} | foreign_ids],
              else: foreign_ids

          for {preview, build} <- foreign_ids do
            before = Repo.get!(Preview, build.preview_id)
            denied = upload(conn, own, preview, build, @action, legacy?)

            assert {denied.status, Repo.get!(Preview, build.preview_id).supported_platforms} ==
                     {404, before.supported_platforms}

            assert json_response(denied, 404)
            assert Repo.get!(Preview, build.preview_id) == before
          end

          assert conn |> upload(other, other.preview, other_build, @action, legacy?) |> json_response(403)

          # The current app_build_id takes precedence over the deprecated field.
          preview = if !legacy? && @action != :icon, do: other.preview, else: own.preview
          result = conn |> upload(own, preview, own_build, @action, legacy?) |> json_response(200)

          case @action do
            :complete ->
              assert result["id"] == own.preview.id
              assert Repo.get!(Preview, own.preview.id).supported_platforms == [:ios]

            :generate_url ->
              assert result["data"]["url"] == "https://storage.invalid/part"

            :icon ->
              assert result["url"] == "https://storage.invalid/icon"
          end
        end
      end
    end
  end

  test "real write credentials cannot delete a foreign preview through either parent", tenants do
    for {own, other} <- [{tenants.alpha, tenants.beta}, {tenants.beta, tenants.alpha}],
        token <- [user_token(own.user), own.project.token, account_token(own), account_token(own, restricted: true)] do
      conn = bearer(token)
      preview = AppBuildsFixtures.preview_fixture(project: own.project, visibility: :private)

      assert conn |> delete(api_path(other, "/previews/#{other.preview.id}")) |> json_response(403)
      assert conn |> delete(api_path(own, "/previews/#{other.preview.id}")) |> json_response(404)
      assert Repo.get!(Preview, other.preview.id).project_id == other.project.id

      assert conn |> delete(api_path(own, "/previews/#{preview.id}")) |> response(204)
      refute Repo.get(Preview, preview.id)
    end
  end

  test "project and restricted account tokens cannot widen access to a sibling project", %{alpha: own} do
    sibling = %{own | project: own.sibling}
    bundle = BundlesFixtures.bundle_fixture(project: sibling.project, name: "sibling-only")
    preview = AppBuildsFixtures.preview_fixture(project: sibling.project, visibility: :private)

    for token <- [own.project.token, account_token(own, restricted: true)] do
      conn = bearer(token)
      assert conn |> get(api_path(own, "/bundles/#{own.bundle.id}")) |> json_response(200)
      assert conn |> get(api_path(sibling, "/bundles/#{bundle.id}")) |> json_response(403)
      assert conn |> get(api_path(own, "/bundles/#{bundle.id}")) |> json_response(404)
      assert conn |> get(api_path(own, "/previews/#{preview.id}")) |> json_response(404)
      assert conn |> delete(api_path(sibling, "/previews/#{preview.id}")) |> json_response(403)
      assert Repo.get(Preview, preview.id)
    end

    conn = bearer(account_token(own))
    assert conn |> get(api_path(sibling, "/bundles/#{bundle.id}")) |> json_response(200)
    assert conn |> get(api_path(sibling, "/previews/#{preview.id}")) |> json_response(200)
    assert conn |> get(api_path(own, "/previews/#{preview.id}")) |> json_response(404)
    assert conn |> delete(api_path(sibling, "/previews/#{preview.id}")) |> response(204)
  end

  test "viewer and read-only tokens can read but cannot mutate, while only tenant admins change settings", %{
    alpha: own,
    beta: other
  } do
    for token <- [user_token(own.viewer), account_token(own, read_only: true)] do
      conn = bearer(token)
      assert conn |> get(api_path(own, "/bundles/#{own.bundle.id}")) |> json_response(200)
      assert conn |> delete(api_path(own, "/previews/#{own.preview.id}")) |> json_response(403)
      assert Repo.get(Preview, own.preview.id)
    end

    for user <- [own.user, own.viewer, other.admin] do
      assert user
             |> user_token()
             |> bearer()
             |> put(api_path(own), %{default_branch: "unauthorized"})
             |> json_response(403)

      assert Projects.get_project_by_id(own.project.id).default_branch == "main"
    end

    assert own.admin
           |> user_token()
           |> bearer()
           |> put(api_path(own), %{default_branch: "release-alpha"})
           |> json_response(200)

    assert Projects.get_project_by_id(own.project.id).default_branch == "release-alpha"
    assert Projects.get_project_by_id(other.project.id).default_branch == "main"
  end

  test "browser sessions isolate bundle mounts and bind deletion to the authorized bundle", %{alpha: own, beta: other} do
    conn = log_in_user(build_conn(), own.user)
    {:ok, view, html} = live(conn, bundle_path(own, own.bundle))
    assert html =~ own.bundle.name
    refute html =~ other.bundle.name
    assert has_element?(view, "[data-part='delete-button']")

    assert_raise NotFoundError, fn -> live(conn, bundle_path(other, other.bundle)) end
    assert_raise NotFoundError, fn -> live(conn, bundle_path(own, other.bundle)) end

    {:ok, viewer, _html} = live(log_in_user(build_conn(), own.viewer), bundle_path(own, own.bundle))
    refute has_element?(viewer, "[data-part='delete-button']")
    render_hook(viewer, "delete_bundle", %{"bundle_id" => other.bundle.id})
    assert {:ok, _} = Bundles.get_bundle(own.bundle.id, project_id: own.project.id)

    render_hook(view, "delete_bundle", %{"bundle_id" => other.bundle.id, "project_id" => other.project.id})
    assert {:error, :not_found} = Bundles.get_bundle(own.bundle.id, project_id: own.project.id)
    assert {:ok, _} = Bundles.get_bundle(other.bundle.id, project_id: other.project.id)
  end

  test "public reads are intentional but do not permit foreign writes", %{alpha: own, beta: other} do
    {:ok, _} = Projects.update_project(other.project, %{visibility: :public})
    conn = bearer(user_token(own.user))
    assert conn |> get(api_path(other, "/bundles/#{other.bundle.id}")) |> json_response(200)
    assert conn |> get(api_path(other, "/previews/#{other.preview.id}")) |> json_response(200)
    assert conn |> delete(api_path(other, "/previews/#{other.preview.id}")) |> json_response(403)
    assert Repo.get(Preview, other.preview.id)
    assert conn |> get(api_path(own, "/bundles/#{other.bundle.id}")) |> json_response(404)
  end

  defp api_path(tenant, suffix \\ ""), do: "/api/projects/#{tenant.project.account.name}/#{tenant.project.name}#{suffix}"

  defp bundle_path(tenant, bundle), do: "/#{tenant.project.account.name}/#{tenant.project.name}/bundles/#{bundle.id}"

  defp upload(conn, tenant, preview, _build, :icon, _legacy?),
    do: post(conn, api_path(tenant, "/previews/#{preview.id}/icons"))

  defp upload(conn, tenant, preview, build, action, legacy?) do
    id_params = if legacy?, do: %{preview_id: build.id}, else: %{preview_id: preview.id, app_build_id: build.id}

    {suffix, params} =
      case action do
        :generate_url ->
          {"generate-url", %{multipart_upload_part: %{part_number: 1, upload_id: "local-upload", content_length: 17}}}

        :complete ->
          {"complete",
           %{multipart_upload_parts: %{parts: [%{part_number: 1, etag: "local-etag"}], upload_id: "local-upload"}}}
      end

    post(conn, api_path(tenant, "/previews/#{suffix}"), Map.merge(id_params, params))
  end

  defp bearer(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
  end

  defp user_token(user) do
    {:ok, token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")
    token
  end

  defp account_token(tenant, opts \\ []) do
    scopes =
      if opts[:read_only],
        do: ["project:bundles:read", "project:tests:read", "project:previews:read"],
        else: ["project:bundles:write", "project:tests:write", "project:previews:write"]

    {:ok, {_, token}} =
      Accounts.create_account_token(%{
        account: tenant.organization.account,
        name: "isolation-#{System.unique_integer([:positive])}",
        scopes: scopes,
        all_projects: !opts[:restricted],
        project_ids: if(opts[:restricted], do: [tenant.project.id], else: [])
      })

    token
  end
end
