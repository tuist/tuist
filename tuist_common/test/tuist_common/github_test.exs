defmodule TuistCommon.GitHubTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistCommon.GitHub

  describe "list_tags/3" do
    test "returns tags from a repository" do
      stub(Req, :request, fn opts ->
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/tags?per_page=100"
        assert {"authorization", "Bearer test-token"} in opts[:headers]
        assert {"accept", "application/vnd.github+json"} in opts[:headers]

        {:ok,
         %Req.Response{
           status: 200,
           body: [%{"name" => "1.0.0"}, %{"name" => "2.0.0"}],
           headers: %{}
         }}
      end)

      assert {:ok, ["1.0.0", "2.0.0"]} = GitHub.list_tags("tuist/tuist", "test-token")
    end

    test "handles pagination via Link header" do
      stub(Req, :request, fn opts ->
        if String.contains?(opts[:url], "page=2") do
          {:ok, %Req.Response{status: 200, body: [%{"name" => "0.1.0"}], headers: %{}}}
        else
          {:ok,
           %Req.Response{
             status: 200,
             body: [%{"name" => "1.0.0"}],
             headers: %{
               "link" => "<https://api.github.com/repos/tuist/tuist/tags?page=2>; rel=\"next\""
             }
           }}
        end
      end)

      assert {:ok, ["1.0.0", "0.1.0"]} = GitHub.list_tags("tuist/tuist", "test-token")
    end

    test "returns error for 404" do
      stub(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 404, body: %{}}}
      end)

      assert {:error, {:http_error, 404}} = GitHub.list_tags("tuist/nonexistent", "test-token")
    end

    test "returns http_error for other status codes" do
      stub(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 500, body: %{}}}
      end)

      assert {:error, {:http_error, 500}} = GitHub.list_tags("tuist/tuist", "test-token")
    end

    test "works without a token" do
      stub(Req, :request, fn opts ->
        refute Enum.any?(opts[:headers], fn {k, _} -> k == "authorization" end)
        {:ok, %Req.Response{status: 200, body: [%{"name" => "1.0.0"}], headers: %{}}}
      end)

      assert {:ok, ["1.0.0"]} = GitHub.list_tags("tuist/tuist", nil)
    end
  end

  describe "get_repository_content/5" do
    test "returns file content when response is a file" do
      stub(Req, :request, fn opts ->
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/contents/Package.swift"
        assert opts[:params] == %{ref: "main"}

        content = Base.encode64("// Swift Package")

        {:ok, %Req.Response{status: 200, body: %{"content" => content, "encoding" => "base64"}}}
      end)

      assert {:ok, {:file, "// Swift Package"}} =
               GitHub.get_repository_content("tuist/tuist", "test-token", "Package.swift", "main")
    end

    test "returns directory listing when response is a list" do
      stub(Req, :request, fn opts ->
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/contents/Sources"
        assert opts[:params] == %{ref: "main"}

        {:ok,
         %Req.Response{
           status: 200,
           body: [
             %{"path" => "Sources/Foo.swift", "type" => "file"},
             %{"path" => "Sources/Bar", "type" => "dir"}
           ]
         }}
      end)

      assert {:ok, {:directory, contents}} =
               GitHub.get_repository_content("tuist/tuist", "test-token", "Sources", "main")

      assert length(contents) == 2
    end

    test "returns error for 404" do
      stub(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 404, body: %{}}}
      end)

      assert {:error, :not_found} =
               GitHub.get_repository_content("tuist/tuist", "test-token", "nonexistent", "main")
    end

    test "returns error for invalid base64 content" do
      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"content" => "not-valid-base64!!!", "encoding" => "base64"}
         }}
      end)

      assert {:error, :invalid_content} =
               GitHub.get_repository_content("tuist/tuist", "test-token", "Package.swift", "main")
    end
  end

  describe "get_file_content/5" do
    test "returns decoded file content" do
      stub(Req, :request, fn opts ->
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/contents/Package.swift"
        assert opts[:params] == %{ref: "main"}

        content = Base.encode64("// Swift Package")

        {:ok, %Req.Response{status: 200, body: %{"content" => content, "encoding" => "base64"}}}
      end)

      assert {:ok, "// Swift Package"} =
               GitHub.get_file_content("tuist/tuist", "test-token", "Package.swift", "main")
    end

    test "returns error for 404" do
      stub(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 404, body: %{}}}
      end)

      assert {:error, :not_found} =
               GitHub.get_file_content("tuist/tuist", "test-token", "nonexistent.swift", "main")
    end

    test "identifies GitHub throttling responses with list-valued headers" do
      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 403,
           body: %{},
           headers: %{"x-ratelimit-remaining" => ["0"]}
         }}
      end)

      assert {:error, {:rate_limited, 403, nil}} =
               GitHub.get_file_content("tuist/tuist", "test-token", "Package.swift", "main")
    end

    test "reports the delay a throttling response asks for" do
      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 403,
           body: %{},
           headers: %{"x-ratelimit-remaining" => ["0"], "retry-after" => ["120"]}
         }}
      end)

      assert {:error, {:rate_limited, 403, 120}} =
               GitHub.get_file_content("tuist/tuist", "test-token", "Package.swift", "main")
    end

    test "derives the delay from the quota reset timestamp when no retry-after is sent" do
      reset = DateTime.to_unix(DateTime.utc_now()) + 900

      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 403,
           body: %{},
           headers: %{"x-ratelimit-remaining" => ["0"], "x-ratelimit-reset" => [to_string(reset)]}
         }}
      end)

      assert {:error, {:rate_limited, 403, seconds}} =
               GitHub.get_file_content("tuist/tuist", "test-token", "Package.swift", "main")

      assert_in_delta seconds, 900, 5
    end

    test "does not read a forbidden response without throttling headers as a rate limit" do
      stub(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 403, body: %{}, headers: %{}}}
      end)

      assert {:error, {:http_error, 403}} =
               GitHub.get_file_content("tuist/tuist", "test-token", "Package.swift", "main")
    end

    test "returns error for invalid base64 content" do
      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"content" => "not-valid-base64!!!", "encoding" => "base64"}
         }}
      end)

      assert {:error, :invalid_content} =
               GitHub.get_file_content("tuist/tuist", "test-token", "Package.swift", "main")
    end
  end

  describe "list_repository_contents/4" do
    test "returns list of directory contents" do
      stub(Req, :request, fn opts ->
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/contents"
        assert opts[:params] == %{ref: "main"}

        {:ok,
         %Req.Response{
           status: 200,
           body: [
             %{"path" => "Package.swift", "type" => "file"},
             %{"path" => "Sources", "type" => "dir"}
           ]
         }}
      end)

      assert {:ok, contents} =
               GitHub.list_repository_contents("tuist/tuist", "test-token", "main")

      assert length(contents) == 2
    end

    test "returns error for 404" do
      stub(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 404, body: %{}}}
      end)

      assert {:error, :not_found} =
               GitHub.list_repository_contents("tuist/nonexistent", "test-token", "main")
    end

    test "identifies GitHub throttling responses" do
      stub(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 429, body: %{}}}
      end)

      assert {:error, {:rate_limited, 429, nil}} =
               GitHub.list_repository_contents("tuist/tuist", "test-token", "main")
    end
  end

  describe "download_zipball/5" do
    test "downloads zipball to destination path" do
      test_path = Path.join(System.tmp_dir!(), "test_zipball_#{:rand.uniform(1_000_000)}.zip")

      stub(Req, :request, fn opts ->
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/zipball/refs/tags/1.0.0"
        assert opts[:decode_body] == false
        assert %File.Stream{} = opts[:into]

        {:ok, %Req.Response{status: 200}}
      end)

      result = GitHub.download_zipball("tuist/tuist", "test-token", "1.0.0", test_path)
      File.rm(test_path)
      assert :ok = result
    end

    test "returns error for non-200 status" do
      test_path = Path.join(System.tmp_dir!(), "test_zipball_#{:rand.uniform(1_000_000)}.zip")

      stub(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 404}}
      end)

      result = GitHub.download_zipball("tuist/tuist", "test-token", "1.0.0", test_path)
      File.rm(test_path)
      assert {:error, {:http_error, 404}} = result
    end
  end

  describe "fetch_packages_json/2" do
    test "fetches packages.json from SwiftPackageIndex" do
      stub(Req, :request, fn opts ->
        assert opts[:url] ==
                 "https://api.github.com/repos/SwiftPackageIndex/PackageList/contents/packages.json"

        assert opts[:params] == %{ref: "main"}

        content = Base.encode64(~s(["https://github.com/tuist/tuist"]))

        {:ok, %Req.Response{status: 200, body: %{"content" => content, "encoding" => "base64"}}}
      end)

      assert {:ok, ~s(["https://github.com/tuist/tuist"])} =
               GitHub.fetch_packages_json("test-token")
    end
  end

  describe "rate limit telemetry" do
    setup do
      handler_id = "github-rate-limit-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        GitHub.rate_limit_event_name(),
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:rate_limit, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok
    end

    test "emits the budget reported on a successful response" do
      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [%{"name" => "1.0.0"}],
           headers: %{
             "x-ratelimit-limit" => ["5000"],
             "x-ratelimit-used" => ["4998"],
             "x-ratelimit-reset" => ["1780000000"],
             "x-ratelimit-resource" => ["core"]
           }
         }}
      end)

      assert {:ok, ["1.0.0"]} = GitHub.list_tags("tuist/tuist", "test-token")

      assert_receive {:rate_limit, %{limit: 5000, used: 4998, reset: 1_780_000_000},
                      %{resource: "core"}}
    end

    test "omits the reset measurement when GitHub does not send the header" do
      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [],
           headers: %{
             "x-ratelimit-limit" => ["5000"],
             "x-ratelimit-used" => ["1"],
             "x-ratelimit-resource" => ["core"]
           }
         }}
      end)

      assert {:ok, []} = GitHub.list_tags("tuist/tuist", "test-token")

      assert_receive {:rate_limit, measurements, %{resource: "core"}}
      assert measurements == %{limit: 5000, used: 1}
    end

    test "emits the budget reported on a rate-limited response" do
      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 403,
           body: %{},
           headers: %{
             "x-ratelimit-limit" => ["5000"],
             "x-ratelimit-used" => ["5000"],
             "x-ratelimit-remaining" => ["0"],
             "x-ratelimit-resource" => ["core"]
           }
         }}
      end)

      assert {:error, {:rate_limited, 403, nil}} = GitHub.list_tags("tuist/tuist", "test-token")

      assert_receive {:rate_limit, %{limit: 5000, used: 5000}, %{resource: "core"}}
    end

    test "falls back to an unknown resource when the header is absent" do
      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [],
           headers: [{"x-ratelimit-limit", "60"}, {"x-ratelimit-used", "1"}]
         }}
      end)

      assert {:ok, []} = GitHub.list_tags("tuist/tuist", nil)

      assert_receive {:rate_limit, %{limit: 60, used: 1}, %{resource: "unknown"}}
    end

    test "does not emit when the response carries no rate limit headers" do
      stub(Req, :request, fn _opts ->
        {:ok, %Req.Response{status: 200, body: [], headers: %{}}}
      end)

      assert {:ok, []} = GitHub.list_tags("tuist/tuist", "test-token")

      refute_received {:rate_limit, _measurements, _metadata}
    end

    test "does not emit when the request fails at the transport level" do
      stub(Req, :request, fn _opts ->
        {:error, %Req.TransportError{reason: :closed}}
      end)

      assert {:error, %Req.TransportError{}} = GitHub.list_tags("tuist/tuist", "test-token")

      refute_received {:rate_limit, _measurements, _metadata}
    end

    # The header helpers exist so a malformed header can't blow up `request/4`,
    # which the telemetry call sits inline in. Pinning them keeps a later
    # simplification to `String.to_integer/1` from turning a cosmetic header
    # anomaly into a failed job on every registry sync.
    test "does not emit when only one half of the budget is reported" do
      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [],
           headers: %{"x-ratelimit-limit" => ["5000"], "x-ratelimit-resource" => ["core"]}
         }}
      end)

      assert {:ok, []} = GitHub.list_tags("tuist/tuist", "test-token")

      refute_received {:rate_limit, _measurements, _metadata}
    end

    test "does not emit or raise when a budget header is not a number" do
      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [],
           headers: %{"x-ratelimit-limit" => ["n/a"], "x-ratelimit-used" => ["1"]}
         }}
      end)

      assert {:ok, []} = GitHub.list_tags("tuist/tuist", "test-token")

      refute_received {:rate_limit, _measurements, _metadata}
    end

    test "does not emit or raise when a budget header carries no value" do
      stub(Req, :request, fn _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [],
           headers: %{"x-ratelimit-limit" => [], "x-ratelimit-used" => ["1"]}
         }}
      end)

      assert {:ok, []} = GitHub.list_tags("tuist/tuist", "test-token")

      refute_received {:rate_limit, _measurements, _metadata}
    end
  end

  describe "anonymous fallback" do
    @allow_list_refusal %Req.Response{
      status: 403,
      body: %{"message" => "the `acme` organization has an IP allow list enabled"},
      headers: %{
        "x-ratelimit-limit" => ["5000"],
        "x-ratelimit-used" => ["10"],
        "x-ratelimit-remaining" => ["4990"]
      }
    }

    # Answers authenticated requests with `authenticated` and anonymous ones
    # with `anonymous`, reporting each call's credential to the test process.
    defp stub_by_credential(authenticated, anonymous) do
      test_pid = self()

      stub(Req, :request, fn opts ->
        authorized? = Enum.any?(opts[:headers], &match?({"authorization", _}, &1))
        send(test_pid, {:requested, if(authorized?, do: :authenticated, else: :anonymous)})
        if authorized?, do: {:ok, authenticated}, else: {:ok, anonymous}
      end)
    end

    test "repeats a refused request without the token when opted in" do
      stub_by_credential(@allow_list_refusal, %Req.Response{
        status: 200,
        body: [%{"name" => "11.0.3"}],
        headers: %{}
      })

      assert {:ok, ["11.0.3"]} =
               GitHub.list_tags("acme/sdk", "test-token", anonymous_fallback: true)

      assert_received {:requested, :authenticated}
      assert_received {:requested, :anonymous}
    end

    test "keeps an anonymous not found, which is the real answer for a public repository" do
      stub_by_credential(@allow_list_refusal, %Req.Response{status: 404, body: %{}, headers: %{}})

      assert {:error, :not_found} =
               GitHub.get_file_content("acme/sdk", "test-token", ".gitmodules", "v1",
                 anonymous_fallback: true
               )
    end

    test "returns the original refusal when the anonymous request is throttled" do
      stub_by_credential(@allow_list_refusal, %Req.Response{
        status: 403,
        body: %{},
        headers: %{"x-ratelimit-remaining" => ["0"], "x-ratelimit-reset" => ["1780000000"]}
      })

      assert {:error, {:http_error, 403}} =
               GitHub.list_tags("acme/sdk", "test-token", anonymous_fallback: true)
    end

    test "does not retry a rate-limited 403" do
      stub_by_credential(
        %Req.Response{status: 403, body: %{}, headers: %{"x-ratelimit-remaining" => ["0"]}},
        %Req.Response{status: 200, body: [], headers: %{}}
      )

      assert {:error, {:rate_limited, 403, nil}} =
               GitHub.list_tags("acme/sdk", "test-token", anonymous_fallback: true)

      refute_received {:requested, :anonymous}
    end

    test "does not retry a secondary rate limit that carries no rate-limit headers" do
      stub_by_credential(
        %Req.Response{
          status: 403,
          body: %{"message" => "You have exceeded a secondary rate limit."},
          headers: %{}
        },
        %Req.Response{status: 200, body: [], headers: %{}}
      )

      assert {:error, {:http_error, 403}} =
               GitHub.list_tags("acme/sdk", "test-token", anonymous_fallback: true)

      refute_received {:requested, :anonymous}
    end

    test "returns the original refusal when the anonymous request fails to connect" do
      test_pid = self()

      stub(Req, :request, fn opts ->
        if Enum.any?(opts[:headers], &match?({"authorization", _}, &1)) do
          {:ok, @allow_list_refusal}
        else
          send(test_pid, {:requested, :anonymous})
          {:error, %Req.TransportError{reason: :timeout}}
        end
      end)

      assert {:error, {:http_error, 403}} =
               GitHub.list_tags("acme/sdk", "test-token", anonymous_fallback: true)

      assert_received {:requested, :anonymous}
    end

    test "reports only the token's budget to rate-limit telemetry" do
      test_pid = self()
      handler_id = "github-anonymous-fallback-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        GitHub.rate_limit_event_name(),
        fn _event, measurements, _metadata, _config ->
          send(test_pid, {:rate_limit, measurements})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      stub_by_credential(@allow_list_refusal, %Req.Response{
        status: 200,
        body: [],
        headers: %{"x-ratelimit-limit" => ["60"], "x-ratelimit-used" => ["1"]}
      })

      assert {:ok, []} = GitHub.list_tags("acme/sdk", "test-token", anonymous_fallback: true)
      assert_received {:rate_limit, %{limit: 5000, used: 10}}
      refute_received {:rate_limit, %{limit: 60}}
    end

    test "does not retry unless the caller opts in" do
      stub_by_credential(@allow_list_refusal, %Req.Response{status: 200, body: [], headers: %{}})

      assert {:error, {:http_error, 403}} = GitHub.list_tags("acme/sdk", "test-token")
      refute_received {:requested, :anonymous}
    end
  end
end
