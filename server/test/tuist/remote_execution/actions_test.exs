defmodule Tuist.RemoteExecution.ActionsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.FeatureFlags
  alias Tuist.RemoteExecution.Actions
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @queued 1_793_157_000_000_000

  defp record(overrides \\ %{}) do
    Map.merge(
      %{
        "operation_id" => Ecto.UUID.generate(),
        "action_hash" => String.duplicate("a", 64),
        "action_size" => 142,
        "invocation_id" => "inv-1",
        "tool_name" => "bazel",
        "mnemonic" => "CppCompile",
        "target" => "//pkg:foo",
        "execution_path" => "lease",
        "sandbox_id" => "vm-1",
        "memory_gb" => 4,
        "arguments" => ["gcc", "-c", "foo.c", "-o", "bazel-out/foo.o"],
        "environment" => [%{"name" => "PATH", "value" => "/usr/bin"}, %{"name" => "GITHUB_TOKEN", "value" => "ghp_x"}],
        "working_directory" => "",
        "platform" => [%{"name" => "OSFamily", "value" => "Linux"}],
        "output_paths" => ["bazel-out/foo.o"],
        "exit_code" => 0,
        "timestamps" => %{
          "queued" => @queued,
          "worker_start" => @queued + 1_000_000,
          "execution_start" => @queued + 2_000_000,
          "execution_completed" => @queued + 5_500_000,
          "worker_completed" => @queued + 6_000_000
        },
        "stdout" => "ok",
        "stdout_size" => 2
      },
      overrides
    )
  end

  test "stores bounded records, masks secrets the gateway missed and derives phases" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    long = String.duplicate("x", 20 * 1024)
    rec = record(%{"arguments" => ["tool", "--auth_token=t", "--api-key", "k"], "stderr" => long})

    assert {:ok, 1} = Actions.ingest(project, [rec])

    assert {:ok, action} = Actions.get(project.id, "inv-1", rec["operation_id"])
    assert action.arguments == ["tool", "--auth_token=****", "--api-key", "****"]
    # A gateway that sends no output count still counts the paths it sent.
    assert action.output_count == 1

    cut = record(%{"output_count" => 2000})
    assert {:ok, 1} = Actions.ingest(project, [cut])

    assert {:ok, %{output_count: 2000, output_paths: ["bazel-out/foo.o"]}} =
             Actions.get(project.id, "inv-1", cut["operation_id"])

    assert Enum.zip(action.environment_names, action.environment_values) == [
             {"PATH", "/usr/bin"},
             {"GITHUB_TOKEN", "****"}
           ]

    assert byte_size(action.stderr) == 16 * 1024 and action.stderr_truncated
    assert action.stdout == "ok" and not action.stdout_truncated
    assert action.queue_ms == 1000.0
    assert action.execution_ms == 3500.0
    assert action.duration_ms == 6000.0
    # Phases the executor did not report stay unavailable rather than zero.
    assert action.input_fetch_ms == nil and action.output_upload_ms == nil
  end

  test "skips records nothing could find and refuses oversized batches" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)

    assert {:ok, 1} =
             Actions.ingest(project, [
               record(),
               record(%{"invocation_id" => ""}),
               record(%{"operation_id" => "not-a-uuid"}),
               record(%{"action_hash" => "ABC"}),
               "garbage"
             ])

    assert {:error, :invalid_request} = Actions.ingest(project, List.duplicate(record(), Actions.max_records() + 1))
  end

  test "a record delivered twice is one action, and reads stay in their project and invocation" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    other = ProjectsFixtures.project_fixture(build_system: :bazel)
    rec = record()
    # Both copies are accepted; the table keeps one row per operation.
    {:ok, 2} = Actions.ingest(project, [rec, rec])
    {:ok, 1} = Actions.ingest(other, [record(%{"operation_id" => rec["operation_id"]})])
    {:ok, 1} = Actions.ingest(project, [record(%{"invocation_id" => "inv-2"})])

    assert {[action], %{total_count: 1}} = Actions.list(project.id, "inv-1")
    assert action.operation_id == rec["operation_id"]
    assert {:error, :not_found} = Actions.get(project.id, "inv-2", rec["operation_id"])
  end

  test "lists failed actions and sorts by duration or queue time" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)

    short = record(%{"timestamps" => %{"queued" => @queued + 50_000_000, "worker_completed" => @queued + 51_000_000}})
    long = record(%{"timestamps" => %{"queued" => @queued + 10_000_000, "worker_completed" => @queued + 40_000_000}})

    failed =
      record(%{"exit_code" => 1, "timestamps" => %{"queued" => @queued, "worker_completed" => @queued + 5_000_000}})

    {:ok, 3} = Actions.ingest(project, [short, long, failed])

    ids = fn {actions, _} -> Enum.map(actions, & &1.operation_id) end

    assert ids.(Actions.list(project.id, "inv-1")) == [
             long["operation_id"],
             failed["operation_id"],
             short["operation_id"]
           ]

    assert ids.(Actions.list(project.id, "inv-1", %{sort_by: "queued_at"})) ==
             [failed["operation_id"], long["operation_id"], short["operation_id"]]

    assert ids.(Actions.list(project.id, "inv-1", %{failed: true})) == [failed["operation_id"]]
  end

  test "maps declared outputs to their records" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    one = record(%{"output_paths" => ["bazel-out/a.o"]})
    retry = record(%{"output_paths" => ["bazel-out/b.o"]})
    again = record(%{"output_paths" => ["bazel-out/b.o"], "action_hash" => String.duplicate("b", 64)})
    {:ok, 3} = Actions.ingest(project, [one, retry, again])

    result = Actions.by_output(project.id, "inv-1", ["bazel-out/a.o", "bazel-out/b.o", "bazel-out/c.o"])
    assert result["bazel-out/a.o"] == [{one["action_hash"], one["operation_id"]}]
    assert length(result["bazel-out/b.o"]) == 2
    refute Map.has_key?(result, "bazel-out/c.o")
  end

  test "the command line quotes only the arguments that need it" do
    action = %{arguments: ["gcc", "-DMSG=it's here", "-I", "a dir", "-c", "foo.c"]}

    assert Actions.command_line(action) == ~S|gcc '-DMSG=it'\''s here' -I 'a dir' -c foo.c|
  end

  test "recognises compiler errors in the stderr of failed actions only" do
    stderr =
      Enum.join(
        [
          "\e[1mservices/api/codec.cc:42:17: \e[31merror:\e[0m no member named 'total_cents'",
          "services/api/codec.cc:50:3: warning: unused variable 'x'",
          "In file included from lib.h:3:",
          "Foo.java:12: error: cannot find symbol",
          "svc/main.go:9:5: undefined: Foo",
          "error[E0425]: cannot find value `y` in this scope",
          "  --> src/lib.rs:4:13",
          "error: aborting due to 1 previous error"
        ],
        "\n"
      )

    failed = %{exit_code: 1, status_code: 0, stderr: stderr}

    assert Actions.errors(failed) == [
             %{path: "services/api/codec.cc", line: 42, column: 17, message: "no member named 'total_cents'"},
             %{path: "Foo.java", line: 12, column: nil, message: "cannot find symbol"},
             %{path: "svc/main.go", line: 9, column: 5, message: "undefined: Foo"},
             %{path: "src/lib.rs", line: 4, column: 13, message: "cannot find value `y` in this scope"}
           ]

    assert Actions.errors(%{failed | exit_code: 0}) == []
    assert Actions.error_line?("error: aborting due to 1 previous error")
    refute Actions.error_line?("services/api/codec.cc:50:3: warning: unused variable")
  end

  describe "full logs" do
    setup do
      stub(Storage, :generate_upload_url, fn key, _actor, opts ->
        "https://storage.example/#{key}?ttl=#{opts[:expires_in]}"
      end)

      %{project: ProjectsFixtures.project_fixture(preload: [:account])}
    end

    test "records get uploads for the whole of each stream longer than a record keeps, up to its last 16 MiB", %{
      project: project
    } do
      hash = String.duplicate("b", 64)

      long =
        record(%{
          "stderr_hash" => hash,
          "stderr_size" => 20 * 1024 * 1024,
          "stdout_hash" => hash,
          "stdout_size" => 16_384
        })

      just_over = record(%{"stdout_hash" => hash, "stdout_size" => 16_385})
      at_limit = record(%{"stdout_hash" => hash, "stdout_size" => 16 * 1024 * 1024})

      assert [stderr, stdout, whole] = Actions.log_uploads(project, [long, just_over, at_limit])

      # Over 16 MiB, only the end; otherwise, the whole stream.
      assert %{hash: ^hash, size: 20_971_520, offset: 4_194_304, length: 16_777_216} = stderr

      assert stderr.url ==
               "https://storage.example/#{project.account.name}/#{project.name}/runs/inv-1/remote-actions/#{long["operation_id"]}/stderr.log?ttl=900"

      assert %{offset: 0, length: 16_385} = stdout
      assert stdout.url =~ "/remote-actions/#{just_over["operation_id"]}/stdout.log"
      assert %{offset: 0, length: 16_777_216} = whole
    end

    test "records that are not stored or would escape their key get no uploads", %{project: project} do
      long = %{"stderr_hash" => String.duplicate("b", 64), "stderr_size" => 100_000}

      assert Actions.log_uploads(project, [
               record(Map.put(long, "operation_id", "not-a-uuid")),
               record(Map.put(long, "invocation_id", "../other/runs/x")),
               record(%{"stderr_hash" => "../" <> String.duplicate("b", 61), "stderr_size" => 100_000})
             ]) == []

      stub(FeatureFlags, :remote_action_log_copies_disabled?, fn -> true end)
      assert Actions.log_uploads(project, [record(long)]) == []
    end

    test "the stored end of a stream joins its preview once, or follows it after a gap" do
      stream = Enum.map_join(1..40, "", &"line #{&1}\n")
      size = byte_size(stream)

      action = %{
        stdout: "",
        stdout_size: 0,
        stdout_truncated: false,
        stderr: binary_part(stream, 0, 16),
        stderr_size: size,
        stderr_truncated: true
      }

      # The copy starts inside the preview: one range, the whole stream.
      assert Actions.recorded_log(action, "stderr", binary_part(stream, 10, size - 10)) == [{0, stream}]

      tail = binary_part(stream, size - 40, 40)
      assert Actions.recorded_log(action, "stderr", tail) == [{0, binary_part(stream, 0, 16)}, {size - 40, tail}]
      assert Actions.recorded_log(action, "stderr", nil) == [{0, binary_part(stream, 0, 16)}]

      assert [{:lines, 1, "line 1\nline 2\nli"}, {:gap, "stderr", gap, :skipped}, {:lines, 4, ^tail}] =
               Actions.log_pages(action, %{"stderr" => tail})

      assert gap == size - 40 - 16

      # Without the copy, the marker ends the stream.
      assert [{:lines, 1, _}, {:gap, "stderr", missing, :missing}] = Actions.log_pages(action, %{})
      assert missing == size - 16
    end

    test "pages hold at most 1000 lines and never cut a character" do
      lines = Enum.map_join(1..2500, "\n", &"#{&1}")

      action = %{
        stdout: lines,
        stdout_size: byte_size(lines),
        stdout_truncated: false,
        stderr: "x",
        stderr_size: 1,
        stderr_truncated: false
      }

      assert [{:lines, 1, first}, {:lines, 1001, _}, {:lines, 2001, last}, {:lines, 2501, "x"}] =
               Actions.log_pages(action, %{})

      assert first |> Actions.log_lines() |> List.last() == "1000"
      assert last |> Actions.log_lines() |> length() == 500

      # A 2-byte character straddles the 64 KiB cut of a long line.
      long = String.duplicate("a", 65_535) <> "é" <> "b"
      action = %{action | stdout: long, stdout_size: byte_size(long), stderr: "", stderr_size: 0}
      pages = Actions.log_pages(action, %{})

      assert [{:lines, 1, head}, {:lines, 2, rest}] = pages
      assert byte_size(head) == 65_535 and rest == "éb"
    end

    test "API reads return a stream's recorded bytes in a range, and where the recorded ones are" do
      stream = String.duplicate("0123456789", 10)

      action = %{
        stdout: "",
        stdout_size: 0,
        stdout_truncated: false,
        stderr: binary_part(stream, 0, 20),
        stderr_size: 100,
        stderr_truncated: true
      }

      tail = binary_part(stream, 60, 40)
      recorded = [%{offset: 0, length: 20}, %{offset: 60, length: 40}]

      assert %{offset: 90, text: "0123456789", size_bytes: 100, recorded: ^recorded} =
               Actions.log_range(action, "stderr", tail, nil, 10)

      assert %{offset: 15, text: "56789"} = Actions.log_range(action, "stderr", tail, 15, 10)
      assert %{offset: 30, text: ""} = Actions.log_range(action, "stderr", tail, 30, 10)
    end
  end

  test "log lines keep what a terminal shows after carriage returns" do
    assert Actions.log_lines("fetch  10%\rfetch 100%\r\nok\r\n\n\e[31mdone\e[0m\n") == ["fetch 100%", "ok", "", "done"]
  end
end
