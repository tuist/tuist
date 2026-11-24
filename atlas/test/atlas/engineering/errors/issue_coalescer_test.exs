defmodule Atlas.Engineering.Errors.IssueCoalescerTest do
  # credo:disable-for-next-line Credo.Check.Warning.AsyncTests
  use Atlas.DataCase, async: false

  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Errors.IssueCoalescer
  alias Atlas.Engineering.Errors.SentryEvent
  alias Atlas.Engineering.Projects
  alias Atlas.Repo

  setup context do
    name = :"issue_coalescer_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      start_supervised(
        {IssueCoalescer,
         [
           name: name,
           flush_interval_ms: 60_000
         ]}
      )

    {:ok, project} =
      Projects.create_project(%{
        "name" => "coalescer-#{System.unique_integer([:positive])}",
        "visibility" => "public"
      })

    {:ok, Map.merge(context, %{coalescer: name, pid: pid, project: project})}
  end

  defp fake_event(opts \\ []) do
    %SentryEvent{
      event_id: Ecto.UUID.generate() |> String.replace("-", ""),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now()),
      level: Keyword.get(opts, :level, "error"),
      platform: Keyword.get(opts, :platform, "elixir"),
      environment: "prod",
      release: nil,
      dist: nil,
      server_name: nil,
      transaction: nil,
      logger: nil,
      exception_type: Keyword.get(opts, :type, "RuntimeError"),
      exception_value: Keyword.get(opts, :value, "kaboom"),
      top_frame: nil,
      tags: %{},
      user: %{id: nil, email: nil, ip_address: nil},
      request: %{url: nil, method: nil},
      sdk_name: nil,
      sdk_version: nil,
      payload: %{}
    }
  end

  describe "coalescing" do
    test "inserts a new issue on first observation", ctx do
      fingerprint = String.duplicate("a", 64)
      event = fake_event()

      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, event)
      :ok = IssueCoalescer.flush(ctx.coalescer)

      expected_id = Issue.deterministic_id(ctx.project.id, fingerprint)
      issue = Repo.get!(Issue, expected_id)

      assert issue.project_id == ctx.project.id
      assert issue.fingerprint == fingerprint
      assert issue.status == :unresolved
      assert issue.event_count == 1
      assert issue.title == "RuntimeError: kaboom"
    end

    test "coalesces N events for one fingerprint into a single upsert", ctx do
      fingerprint = String.duplicate("b", 64)

      Enum.each(1..250, fn i ->
        :ok =
          IssueCoalescer.observe(
            ctx.coalescer,
            ctx.project,
            fingerprint,
            fake_event(value: "boom-#{i}")
          )
      end)

      :ok = IssueCoalescer.flush(ctx.coalescer)

      expected_id = Issue.deterministic_id(ctx.project.id, fingerprint)
      issue = Repo.get!(Issue, expected_id)

      assert issue.event_count == 250
    end

    test "second flush increments the existing counter (idempotent id)", ctx do
      fingerprint = String.duplicate("c", 64)

      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, fake_event())
      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, fake_event())
      :ok = IssueCoalescer.flush(ctx.coalescer)

      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, fake_event())
      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, fake_event())
      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, fake_event())
      :ok = IssueCoalescer.flush(ctx.coalescer)

      id = Issue.deterministic_id(ctx.project.id, fingerprint)
      assert Repo.get!(Issue, id).event_count == 5
    end

    test "spreads across fingerprints in a single upsert batch", ctx do
      fingerprints = for i <- 1..10, do: String.pad_leading("#{i}", 64, "0")

      Enum.each(fingerprints, fn fp ->
        :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fp, fake_event())
        :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fp, fake_event())
      end)

      :ok = IssueCoalescer.flush(ctx.coalescer)

      assert Repo.aggregate(from(i in Issue, where: i.project_id == ^ctx.project.id), :count) ==
               10

      counts =
        Repo.all(from(i in Issue, where: i.project_id == ^ctx.project.id, select: i.event_count))

      assert Enum.all?(counts, &(&1 == 2))
    end
  end

  describe "regression logic" do
    test "ignored issues stay ignored across new events", ctx do
      fingerprint = String.duplicate("d", 64)
      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, fake_event())
      :ok = IssueCoalescer.flush(ctx.coalescer)

      id = Issue.deterministic_id(ctx.project.id, fingerprint)
      Repo.update_all(from(i in Issue, where: i.id == ^id), set: [status: :ignored])

      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, fake_event())
      :ok = IssueCoalescer.flush(ctx.coalescer)

      assert Repo.get!(Issue, id).status == :ignored
    end

    test "resolved issues auto-reopen when a NEWER event lands", ctx do
      fingerprint = String.duplicate("e", 64)

      old_event = fake_event(timestamp: ~U[2026-01-01 00:00:00.000000Z])
      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, old_event)
      :ok = IssueCoalescer.flush(ctx.coalescer)

      id = Issue.deterministic_id(ctx.project.id, fingerprint)
      resolved_at = ~U[2026-01-02 00:00:00.000000Z]

      Repo.update_all(
        from(i in Issue, where: i.id == ^id),
        set: [status: :resolved, resolved_at: resolved_at]
      )

      new_event = fake_event(timestamp: ~U[2026-01-03 00:00:00.000000Z])
      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, new_event)
      :ok = IssueCoalescer.flush(ctx.coalescer)

      reopened = Repo.get!(Issue, id)
      assert reopened.status == :unresolved
      assert reopened.resolved_at == nil
    end

    test "resolved issues do NOT reopen on a backfilled older event", ctx do
      fingerprint = String.duplicate("f", 64)

      recent = fake_event(timestamp: ~U[2026-03-01 00:00:00.000000Z])
      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, recent)
      :ok = IssueCoalescer.flush(ctx.coalescer)

      id = Issue.deterministic_id(ctx.project.id, fingerprint)
      resolved_at = ~U[2026-04-01 00:00:00.000000Z]

      Repo.update_all(
        from(i in Issue, where: i.id == ^id),
        set: [status: :resolved, resolved_at: resolved_at]
      )

      backfilled = fake_event(timestamp: ~U[2026-02-01 00:00:00.000000Z])
      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, backfilled)
      :ok = IssueCoalescer.flush(ctx.coalescer)

      still_resolved = Repo.get!(Issue, id)
      assert still_resolved.status == :resolved
      assert still_resolved.resolved_at == resolved_at
    end
  end

  describe "regrouping" do
    setup ctx do
      legacy = String.duplicate("1", 64)
      user = Atlas.TimeOffFixtures.user_fixture()
      first_seen = ~U[2026-01-01 00:00:00.000000Z]
      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, legacy, fake_event(timestamp: first_seen))
      :ok = IssueCoalescer.flush(ctx.coalescer)
      legacy_id = Issue.deterministic_id(ctx.project.id, legacy)
      Repo.update_all(from(i in Issue, where: i.id == ^legacy_id), set: [assignee_id: user.id])

      %{legacy: legacy, legacy_id: legacy_id, user: user, first_seen: first_seen}
    end

    defp observe_regrouped(ctx, fingerprint, timestamp) do
      event = fake_event(timestamp: timestamp)
      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, event, legacy_fingerprint: ctx.legacy)
      :ok = IssueCoalescer.flush(ctx.coalescer)
      Repo.get!(Issue, Issue.deterministic_id(ctx.project.id, fingerprint))
    end

    test "a new issue starts from its legacy issue", ctx do
      issue = observe_regrouped(ctx, String.duplicate("2", 64), ~U[2026-02-01 00:00:00.000000Z])

      assert issue.assignee_id == ctx.user.id
      assert issue.first_seen == ctx.first_seen
      assert issue.status == :unresolved
      assert issue.event_count == 1
    end

    test "a resolved legacy issue regresses only on a newer event", ctx do
      resolved_at = ~U[2026-03-01 00:00:00.000000Z]

      Repo.update_all(from(i in Issue, where: i.id == ^ctx.legacy_id),
        set: [status: :resolved, resolved_at: resolved_at]
      )

      older = observe_regrouped(ctx, String.duplicate("3", 64), ~U[2026-02-01 00:00:00.000000Z])
      assert {older.status, older.resolved_at} == {:resolved, resolved_at}

      newer = observe_regrouped(ctx, String.duplicate("4", 64), ~U[2026-04-01 00:00:00.000000Z])
      assert {newer.status, newer.resolved_at} == {:unresolved, nil}
    end

    test "an ignored legacy issue stays ignored", ctx do
      Repo.update_all(from(i in Issue, where: i.id == ^ctx.legacy_id), set: [status: :ignored])

      assert observe_regrouped(ctx, String.duplicate("5", 64), ~U[2026-04-01 00:00:00.000000Z]).status == :ignored
    end

    for order <- [:ignored_first, :missing_first], batches <- [:together, :separate] do
      test "a missing legacy origin prevents suppression: #{order}, #{batches}", ctx do
        missing = String.duplicate("e", 64)
        fingerprint = String.duplicate("f", 64)
        event = fake_event(timestamp: ~U[2026-02-01 00:00:00.000000Z])
        missing_id = Issue.deterministic_id(ctx.project.id, missing)
        refute Repo.get(Issue, missing_id)
        Repo.update_all(from(i in Issue, where: i.id == ^ctx.legacy_id), set: [status: :ignored])
        origins = if unquote(order) == :ignored_first, do: [ctx.legacy, missing], else: [missing, ctx.legacy]

        for origin <- origins do
          :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, event, legacy_fingerprint: origin)
          if unquote(batches) == :separate, do: IssueCoalescer.flush(ctx.coalescer)
        end

        :ok = IssueCoalescer.flush(ctx.coalescer)
        issue = Repo.get!(Issue, Issue.deterministic_id(ctx.project.id, fingerprint))
        assert issue.status == :unresolved
        assert issue.resolved_at == nil
        assert issue.first_seen == ctx.first_seen
        assert issue.assignee_id == ctx.user.id
        assert issue.event_count == 2
        assert Enum.sort(issue.legacy_ids) == Enum.sort([ctx.legacy_id, missing_id])
      end
    end

    for order <- [:ignored_first, :unresolved_first], batches <- [:together, :separate] do
      test "conflicting legacy origins remain unresolved: #{order}, #{batches}", ctx do
        other = String.duplicate("7", 64)
        fingerprint = String.duplicate("8", 64)
        earliest = ~U[2025-12-01 00:00:00.000000Z]
        event = fake_event(timestamp: ~U[2026-02-01 00:00:00.000000Z])

        :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, other, fake_event(timestamp: earliest))
        :ok = IssueCoalescer.flush(ctx.coalescer)
        Repo.update_all(from(i in Issue, where: i.id == ^ctx.legacy_id), set: [status: :ignored])

        origins = if unquote(order) == :ignored_first, do: [ctx.legacy, other], else: [other, ctx.legacy]

        for origin <- origins do
          :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, event, legacy_fingerprint: origin)
          if unquote(batches) == :separate, do: IssueCoalescer.flush(ctx.coalescer)
        end

        :ok = IssueCoalescer.flush(ctx.coalescer)
        issue = Repo.get!(Issue, Issue.deterministic_id(ctx.project.id, fingerprint))
        assert issue.status == :unresolved
        assert issue.resolved_at == nil
        assert issue.first_seen == earliest
        assert issue.assignee_id == ctx.user.id
        assert issue.event_count == 2
      end
    end

    for order <- [:newer_first, :older_first] do
      test "unequal legacy resolutions reconcile all observed events: #{order}", ctx do
        other = String.duplicate("c", 64)
        fingerprint = String.duplicate("d", 64)
        newer = ~U[2026-03-15 00:00:00.000000Z]
        older = ~U[2026-03-05 00:00:00.000000Z]
        :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, other, fake_event(timestamp: older))
        :ok = IssueCoalescer.flush(ctx.coalescer)
        other_id = Issue.deterministic_id(ctx.project.id, other)

        Repo.update_all(from(i in Issue, where: i.id == ^ctx.legacy_id),
          set: [status: :resolved, resolved_at: ~U[2026-03-20 00:00:00.000000Z]]
        )

        Repo.update_all(from(i in Issue, where: i.id == ^other_id),
          set: [status: :resolved, resolved_at: ~U[2026-03-10 00:00:00.000000Z]]
        )

        origins = [{ctx.legacy, newer}, {other, older}]
        origins = if unquote(order) == :newer_first, do: origins, else: Enum.reverse(origins)

        for {origin, timestamp} <- origins do
          :ok =
            IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, fake_event(timestamp: timestamp),
              legacy_fingerprint: origin
            )

          :ok = IssueCoalescer.flush(ctx.coalescer)
        end

        issue = Repo.get!(Issue, Issue.deterministic_id(ctx.project.id, fingerprint))
        assert issue.status == :unresolved
        assert issue.resolved_at == nil
        assert issue.last_seen == newer
        assert issue.first_seen == ctx.first_seen
        assert issue.assignee_id == ctx.user.id
        assert issue.event_count == 2
      end
    end

    test "a known legacy origin does not overwrite a manual decision", ctx do
      fingerprint = String.duplicate("9", 64)
      timestamp = ~U[2026-02-01 00:00:00.000000Z]
      issue = observe_regrouped(ctx, fingerprint, timestamp)
      Repo.update_all(from(i in Issue, where: i.id == ^issue.id), set: [status: :ignored, assignee_id: nil])

      repeated = observe_regrouped(ctx, fingerprint, timestamp)
      assert repeated.status == :ignored
      assert repeated.assignee_id == nil
    end

    for status <- [:ignored, :resolved, :unresolved], batches <- [:together, :separate] do
      test "known origins do not replay manual overrides with a new origin: #{status}, #{batches}", ctx do
        other = String.duplicate("a", 64)
        fingerprint = String.duplicate("b", 64)
        timestamp = ~U[2026-02-01 00:00:00.000000Z]
        resolved_at = if unquote(status) == :resolved, do: ~U[2026-03-01 00:00:00.000000Z]
        :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, other, fake_event(timestamp: timestamp))
        :ok = IssueCoalescer.flush(ctx.coalescer)
        other_id = Issue.deterministic_id(ctx.project.id, other)

        Repo.update_all(from(i in Issue, where: i.id == ^other_id),
          set: [status: unquote(status), resolved_at: resolved_at]
        )

        issue = observe_regrouped(ctx, fingerprint, timestamp)

        Repo.update_all(from(i in Issue, where: i.id == ^issue.id),
          set: [status: unquote(status), resolved_at: resolved_at, assignee_id: nil]
        )

        for origin <- [other, ctx.legacy] do
          :ok =
            IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, fake_event(timestamp: timestamp),
              legacy_fingerprint: origin
            )

          if unquote(batches) == :separate, do: IssueCoalescer.flush(ctx.coalescer)
        end

        :ok = IssueCoalescer.flush(ctx.coalescer)
        updated = Repo.get!(Issue, issue.id)
        assert updated.status == unquote(status)
        assert updated.resolved_at == resolved_at
        assert updated.assignee_id == nil
        assert updated.first_seen == ctx.first_seen
        assert updated.event_count == 3
        assert Enum.sort(updated.legacy_ids) == Enum.sort([ctx.legacy_id, other_id])
      end
    end

    for status <- [:ignored, :resolved] do
      test "unanimous legacy origins preserve #{status} across batches", ctx do
        other = String.duplicate("a", 64)
        fingerprint = String.duplicate("b", 64)
        timestamp = ~U[2026-02-01 00:00:00.000000Z]
        resolved_at = if unquote(status) == :resolved, do: ~U[2026-03-01 00:00:00.000000Z]
        :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, other, fake_event(timestamp: timestamp))
        :ok = IssueCoalescer.flush(ctx.coalescer)
        other_id = Issue.deterministic_id(ctx.project.id, other)

        Repo.update_all(from(i in Issue, where: i.id in ^[ctx.legacy_id, other_id]),
          set: [status: unquote(status), resolved_at: resolved_at]
        )

        observe_regrouped(ctx, fingerprint, timestamp)
        event = fake_event(timestamp: timestamp)
        :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, event, legacy_fingerprint: other)
        :ok = IssueCoalescer.flush(ctx.coalescer)
        issue = Repo.get!(Issue, Issue.deterministic_id(ctx.project.id, fingerprint))
        assert issue.status == unquote(status)
        assert issue.resolved_at == resolved_at
        assert issue.assignee_id == ctx.user.id
        assert issue.first_seen == ctx.first_seen
      end
    end

    test "an existing current issue keeps its own state", ctx do
      fingerprint = String.duplicate("6", 64)
      :ok = IssueCoalescer.observe(ctx.coalescer, ctx.project, fingerprint, fake_event())
      :ok = IssueCoalescer.flush(ctx.coalescer)
      Repo.update_all(from(i in Issue, where: i.id == ^ctx.legacy_id), set: [status: :ignored])

      issue = observe_regrouped(ctx, fingerprint, DateTime.utc_now())

      assert issue.status == :unresolved
      assert issue.assignee_id == nil
      assert issue.event_count == 2
    end
  end

  describe "deterministic id" do
    test "same inputs always produce the same id" do
      project_id = Ecto.UUID.generate()
      fingerprint = String.duplicate("g", 64)

      assert Issue.deterministic_id(project_id, fingerprint) ==
               Issue.deterministic_id(project_id, fingerprint)
    end

    test "different projects with same fingerprint yield different ids" do
      p1 = Ecto.UUID.generate()
      p2 = Ecto.UUID.generate()
      fingerprint = String.duplicate("h", 64)

      refute Issue.deterministic_id(p1, fingerprint) ==
               Issue.deterministic_id(p2, fingerprint)
    end

    test "different fingerprints in same project yield different ids" do
      project_id = Ecto.UUID.generate()
      fp1 = String.duplicate("i", 64)
      fp2 = String.duplicate("j", 64)

      refute Issue.deterministic_id(project_id, fp1) ==
               Issue.deterministic_id(project_id, fp2)
    end

    test "produces a valid UUIDv5 (version 5, RFC 4122 variant)" do
      uuid = Issue.deterministic_id(Ecto.UUID.generate(), String.duplicate("k", 64))
      assert uuid =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    end
  end
end
