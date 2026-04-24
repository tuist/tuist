defmodule TuistWeb.DocsMarkdownTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs
  alias TuistWeb.DocsMarkdown

  describe "get/2" do
    test "returns markdown for a docs page backed by source markdown" do
      page = Docs.get_page("/en/guides/install-tuist")

      assert DocsMarkdown.get("en", ["guides", "install-tuist"]) == {:ok, page.markdown}
    end

    test "returns :error when the docs page does not exist" do
      assert DocsMarkdown.get("en", ["guides", "does-not-exist"]) == :error
    end
  end

  describe "from_request_path/1" do
    test "resolves docs markdown from a public docs path" do
      page = Docs.get_page("/en/guides/install-tuist")

      assert DocsMarkdown.from_request_path("/en/docs/guides/install-tuist") == {:ok, page.markdown}
    end

    test "returns :error for unsupported locales" do
      assert DocsMarkdown.from_request_path("/zz/docs/guides/install-tuist") == :error
    end

    test "returns :error for non-docs paths" do
      assert DocsMarkdown.from_request_path("/en/blog") == :error
    end
  end
end
