defmodule Atlas.Engineering.PagesTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Engineering.Pages
  alias Atlas.Repo
  alias Atlas.Users.User

  defp user(email \\ nil) do
    email = email || "pages-#{System.unique_integer([:positive])}@tuist.dev"

    %User{}
    |> User.changeset(%{email: email, name: "Pages Author"})
    |> Repo.insert!()
  end

  describe "create_page/2" do
    test "normalizes the slug and rejects reserved names" do
      assert {:ok, page} = Pages.create_page(%{"slug" => "  MY-Site "}, user())
      assert page.slug == "my-site"

      assert {:error, changeset} = Pages.create_page(%{"slug" => "api"}, user())
      assert %{slug: [message]} = errors_on(changeset)
      assert message =~ "reserved"
    end

    test "rejects slugs with disallowed characters" do
      assert {:error, changeset} = Pages.create_page(%{"slug" => "My_Site!"}, user())
      assert %{slug: [_message | _]} = errors_on(changeset)
    end
  end

  describe "start_deploy/3 -> finalize_deploy/2" do
    setup do
      author = user()
      {:ok, page} = Pages.create_page(%{"slug" => "docs-site"}, author)
      {:ok, %{author: author, page: page}}
    end

    test "creates a pending deploy with presigned URLs", %{author: author, page: page} do
      Atlas.ObjectStorage
      |> stub(:presigned_put_url, fn key, opts ->
        assert String.starts_with?(key, "pages/#{page.id}/")
        assert Keyword.get(opts, :content_type) in ["text/html; charset=utf-8", "text/css; charset=utf-8"]
        {:ok, "https://example.test/#{key}?sig=fake"}
      end)

      files = [
        %{"path" => "index.html", "size" => 12},
        %{"path" => "assets/app.css", "size" => 2}
      ]

      assert {:ok, %{deploy: deploy, uploads: uploads}} = Pages.start_deploy(page, files, author)
      assert deploy.state == :pending
      assert deploy.file_count == 2
      assert Enum.all?(uploads, &String.starts_with?(&1["upload_url"], "https://example.test/"))
    end

    test "rejects an empty manifest", %{author: author, page: page} do
      assert {:error, :empty_manifest} = Pages.start_deploy(page, [], author)
    end

    test "finalize promotes to live and points current_deploy", %{author: author, page: page} do
      Atlas.ObjectStorage
      |> stub(:presigned_put_url, fn _key, _opts -> {:ok, "https://example.test/put"} end)
      |> stub(:head_object, fn _key, _opts -> {:ok, %{status: 200, headers: [], body: ""}} end)

      files = [%{"path" => "index.html", "size" => 4}]

      {:ok, %{deploy: deploy}} = Pages.start_deploy(page, files, author)

      assert {:ok, %{page: promoted, deploy: promoted_deploy}} = Pages.finalize_deploy(deploy, author)
      assert promoted_deploy.state == :live
      assert promoted.current_deploy_id == promoted_deploy.id
    end

    test "finalize fails when an object is missing", %{author: author, page: page} do
      Atlas.ObjectStorage
      |> stub(:presigned_put_url, fn _key, _opts -> {:ok, "https://example.test/put"} end)
      |> stub(:head_object, fn _key, _opts -> {:error, {:unexpected_status, 404, ""}} end)

      files = [%{"path" => "index.html", "size" => 4}]
      {:ok, %{deploy: deploy}} = Pages.start_deploy(page, files, author)

      assert {:error, {:missing_object, "index.html"}} = Pages.finalize_deploy(deploy, author)
    end
  end

  describe "fetch_object/2" do
    test "returns the stored bytes for the current deploy path" do
      author = user()
      {:ok, page} = Pages.create_page(%{"slug" => "readme"}, author)

      Atlas.ObjectStorage
      |> stub(:presigned_put_url, fn _key, _opts -> {:ok, "https://example.test/put"} end)
      |> stub(:head_object, fn _key, _opts -> {:ok, %{status: 200, headers: [], body: ""}} end)

      {:ok, %{deploy: deploy}} = Pages.start_deploy(page, [%{"path" => "index.html", "size" => 3}], author)
      {:ok, %{page: page}} = Pages.finalize_deploy(deploy, author)

      Atlas.ObjectStorage
      |> stub(:get_object, fn key, _opts ->
        assert String.ends_with?(key, "/index.html")
        {:ok, %{body: "hi\n", content_type: "text/html; charset=utf-8", key: key}}
      end)

      assert {:ok, %{body: "hi\n", content_type: "text/html; charset=utf-8"}} = Pages.fetch_object(page, "/")
    end

    test "returns :not_found when the site has no live deploy" do
      author = user()
      {:ok, page} = Pages.create_page(%{"slug" => "empty"}, author)
      assert {:error, :not_found} = Pages.fetch_object(page, "/")
    end
  end
end
