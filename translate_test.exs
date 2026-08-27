# Unit tests for the pure parts of translate.exs.
#
#     elixir translate_test.exs
#
# Nothing here reaches a model: the incremental translation logic is a set
# difference over catalog keys plus a merge, so it can be proven on fixtures.

System.put_env("L10N_SKIP_CLI", "1")
Code.require_file("translate.exs", __DIR__)

ExUnit.start()

defmodule L10n.CatalogTest do
  use ExUnit.Case, async: true

  alias L10n.Catalog

  @pot """
  msgid ""
  msgstr ""

  #: lib/app.ex:1
  msgid "Hello"
  msgstr ""

  #: lib/app.ex:2
  msgid "Goodbye"
  msgstr ""

  #: lib/app.ex:3
  msgid "One item"
  msgid_plural "%{count} items"
  msgstr[0] ""
  msgstr[1] ""
  """

  defp pot, do: parse(@pot)

  defp parse(content) do
    {:ok, messages} = Catalog.parse(content)
    messages
  end

  defp msgids(messages), do: Enum.map(messages, &IO.iodata_to_binary(&1.msgid))

  describe "untranslated/2" do
    test "returns every message when nothing is translated yet" do
      assert pot().messages |> Catalog.untranslated(%{}) |> msgids() ==
               ["Hello", "Goodbye", "One item"]
    end

    test "returns only the messages missing from an existing catalog" do
      existing =
        parse("""
        msgid ""
        msgstr ""

        msgid "Hello"
        msgstr "Hola"
        """)

      pending = Catalog.untranslated(pot().messages, Catalog.index(existing.messages))

      assert msgids(pending) == ["Goodbye", "One item"]
    end

    test "treats an empty msgstr as untranslated" do
      existing =
        parse("""
        msgid ""
        msgstr ""

        msgid "Hello"
        msgstr ""
        """)

      pending = Catalog.untranslated(pot().messages, Catalog.index(existing.messages))

      assert "Hello" in msgids(pending)
    end

    test "treats a partially translated plural as untranslated" do
      existing =
        parse("""
        msgid ""
        msgstr ""

        msgid "One item"
        msgid_plural "%{count} items"
        msgstr[0] "Un elemento"
        msgstr[1] ""
        """)

      pending = Catalog.untranslated(pot().messages, Catalog.index(existing.messages))

      assert "One item" in msgids(pending)
    end

    test "a reworded source string surfaces as a new message" do
      existing =
        parse("""
        msgid ""
        msgstr ""

        msgid "Hi"
        msgstr "Hola"
        """)

      pending = Catalog.untranslated(pot().messages, Catalog.index(existing.messages))

      assert "Hello" in msgids(pending)
    end

    test "distinguishes messages that differ only by context" do
      with_context =
        parse("""
        msgid ""
        msgstr ""

        msgctxt "menu"
        msgid "Hello"
        msgstr "Hola"
        """)

      pending = Catalog.untranslated(pot().messages, Catalog.index(with_context.messages))

      assert "Hello" in msgids(pending)
    end
  end

  describe "fragment/1" do
    test "round-trips through the parser and carries only the given messages" do
      fragment = pot().messages |> Enum.take(1) |> Catalog.fragment()

      assert msgids(parse(fragment).messages) == ["Hello"]
    end
  end

  describe "merge/5" do
    test "keeps existing translations and applies fresh ones" do
      existing =
        Catalog.index(
          parse("""
          msgid ""
          msgstr ""

          msgid "Hello"
          msgstr "Hola"
          """).messages
        )

      fresh =
        Catalog.index(
          parse("""
          msgid ""
          msgstr ""

          msgid "Goodbye"
          msgstr "Adios"
          """).messages
        )

      merged = Catalog.merge(pot(), existing, fresh, "es", "nplurals=2; plural=n != 1;")
      by_id = Map.new(merged.messages, &{IO.iodata_to_binary(&1.msgid), &1})

      assert IO.iodata_to_binary(by_id["Hello"].msgstr) == "Hola"
      assert IO.iodata_to_binary(by_id["Goodbye"].msgstr) == "Adios"
    end

    test "prefers a fresh translation over the existing one" do
      existing =
        Catalog.index(parse(~s|msgid ""\nmsgstr ""\n\nmsgid "Hello"\nmsgstr "viejo"\n|).messages)

      fresh =
        Catalog.index(parse(~s|msgid ""\nmsgstr ""\n\nmsgid "Hello"\nmsgstr "nuevo"\n|).messages)

      merged = Catalog.merge(pot(), existing, fresh, "es", "nplurals=2; plural=n != 1;")
      by_id = Map.new(merged.messages, &{IO.iodata_to_binary(&1.msgid), &1})

      assert IO.iodata_to_binary(by_id["Hello"].msgstr) == "nuevo"
    end

    test "leaves untranslated messages blank rather than dropping them" do
      merged = Catalog.merge(pot(), %{}, %{}, "es", "nplurals=2; plural=n != 1;")

      assert msgids(merged.messages) == ["Hello", "Goodbye", "One item"]
      refute Enum.any?(merged.messages, &Catalog.translated?/1)
    end

    test "sizes plural forms to the locale" do
      for {locale, count} <- [{"ru", 3}, {"ja", 1}, {"es", 2}] do
        merged = Catalog.merge(pot(), %{}, %{}, locale, "nplurals=#{count};")
        plural = Enum.find(merged.messages, &is_map(&1.msgstr))

        assert map_size(plural.msgstr) == count, "#{locale} expected #{count} plural forms"
      end
    end

    test "writes the locale header" do
      merged = Catalog.merge(pot(), %{}, %{}, "ko", "nplurals=1; plural=0;")

      assert "Language: ko\n" in merged.headers
      assert "Plural-Forms: nplurals=1; plural=0;\n" in merged.headers
    end

    test "refreshes references from the template" do
      existing =
        Catalog.index(
          parse("""
          msgid ""
          msgstr ""

          #: lib/old_location.ex:99
          msgid "Hello"
          msgstr "Hola"
          """).messages
        )

      merged = Catalog.merge(pot(), existing, %{}, "es", "nplurals=2; plural=n != 1;")
      hello = Enum.find(merged.messages, &(IO.iodata_to_binary(&1.msgid) == "Hello"))

      assert hello.references == [[{"lib/app.ex", 1}]]
    end

    test "produces output the validator accepts" do
      existing =
        Catalog.index(parse(~s|msgid ""\nmsgstr ""\n\nmsgid "Hello"\nmsgstr "Hola"\n|).messages)

      content =
        pot()
        |> Catalog.merge(existing, %{}, "es", "nplurals=2; plural=n != 1;")
        |> Expo.PO.compose()
        |> IO.iodata_to_binary()

      assert :ok == L10n.Validator.validate(content)
    end

    test "a full merge leaves nothing pending on the next run" do
      fresh =
        Catalog.index(
          parse("""
          msgid ""
          msgstr ""

          msgid "Hello"
          msgstr "Hola"

          msgid "Goodbye"
          msgstr "Adios"

          msgid "One item"
          msgid_plural "%{count} items"
          msgstr[0] "Un elemento"
          msgstr[1] "%{count} elementos"
          """).messages
        )

      merged = Catalog.merge(pot(), %{}, fresh, "es", "nplurals=2; plural=n != 1;")

      assert Catalog.untranslated(pot().messages, Catalog.index(merged.messages)) == []
    end
  end
end

defmodule L10n.IncrementalTranslationTest do
  use ExUnit.Case, async: true

  alias L10n.Catalog

  @pot """
  msgid ""
  msgstr ""

  #: lib/app.ex:1
  msgid "Hello"
  msgstr ""

  #: lib/app.ex:2
  msgid "Goodbye"
  msgstr ""
  """

  @targets [%{"locale" => "es", "language" => "Spanish", "path" => "es/LC_MESSAGES"}]

  setup do
    root = Path.join(System.tmp_dir!(), "l10n-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  defp po_path(root), do: Path.join([root, "es/LC_MESSAGES/default.po"])
  defp lock_path(root), do: L10n.Lock.lock_path(root, "priv/gettext/default.pot", "es")

  defp write_po!(root, content) do
    path = po_path(root)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
  end

  # Records every batch it is handed, then translates each entry as "<msgid>!".
  defp recorder(test_pid) do
    fn batch, _locale, _language, _context, _override, _model, _timeout ->
      send(test_pid, {:batch, Enum.map(batch, &IO.iodata_to_binary(&1.msgid))})

      body =
        Enum.map_join(batch, "\n", fn message ->
          id = IO.iodata_to_binary(message.msgid)
          ~s|msgid "#{id}"\nmsgstr "#{id}!"\n|
        end)

      {:ok, parsed} = Catalog.parse(body)
      {:ok, Catalog.index(parsed.messages)}
    end
  end

  defp run(root, opts) do
    L10n.Translator.translate_all(
      @pot,
      @targets,
      "context",
      "test:model",
      root,
      root,
      "priv/gettext/default.pot",
      [],
      Keyword.merge([locale_override_fn: fn _ -> {"", []} end], opts)
    )
  end

  test "an already-complete catalog costs no model calls and still advances the lock", %{
    root: root
  } do
    write_po!(
      root,
      ~s|msgid ""\nmsgstr ""\n\nmsgid "Hello"\nmsgstr "Hola"\n\nmsgid "Goodbye"\nmsgstr "Adios"\n|
    )

    assert [{:translated, "es"}] = run(root, batch_fn: recorder(self()))

    refute_received {:batch, _}
    assert File.exists?(lock_path(root))
  end

  test "only the missing entries reach the model", %{root: root} do
    write_po!(root, ~s|msgid ""\nmsgstr ""\n\nmsgid "Hello"\nmsgstr "Hola"\n|)

    assert [{:translated, "es"}] = run(root, batch_fn: recorder(self()))

    assert_received {:batch, ["Goodbye"]}
    refute_received {:batch, _}

    {:ok, written} = Catalog.parse(File.read!(po_path(root)))

    by_id =
      Map.new(written.messages, &{IO.iodata_to_binary(&1.msgid), IO.iodata_to_binary(&1.msgstr)})

    assert by_id == %{"Hello" => "Hola", "Goodbye" => "Goodbye!"}
  end

  test "a failed batch banks progress but does not advance the lock", %{root: root} do
    write_po!(root, ~s|msgid ""\nmsgstr ""\n\nmsgid "Hello"\nmsgstr "Hola"\n|)

    failing = fn _batch, _l, _lang, _c, _o, _m, _t -> {:error, "provider exploded"} end

    assert [{:error, "es", reason}] = run(root, batch_fn: failing)
    assert reason =~ "provider exploded"

    refute File.exists?(lock_path(root))

    # The existing translation survives, so the next run only retries "Goodbye".
    {:ok, written} = Catalog.parse(File.read!(po_path(root)))

    by_id =
      Map.new(written.messages, &{IO.iodata_to_binary(&1.msgid), IO.iodata_to_binary(&1.msgstr)})

    assert by_id["Hello"] == "Hola"
    assert by_id["Goodbye"] == ""
  end

  test "a partially answered batch leaves the rest for the next run", %{root: root} do
    partial = fn _batch, _l, _lang, _c, _o, _m, _t ->
      {:ok, parsed} = Catalog.parse(~s|msgid "Hello"\nmsgstr "Hola"\n|)
      {:ok, Catalog.index(parsed.messages)}
    end

    assert [{:error, "es", reason}] = run(root, batch_fn: partial)
    assert reason =~ "1 entries left untranslated"
    refute File.exists?(lock_path(root))

    assert [{:translated, "es"}] = run(root, batch_fn: recorder(self()))
    assert_received {:batch, ["Goodbye"]}
  end

  test "force re-sends entries that are already translated", %{root: root} do
    write_po!(
      root,
      ~s|msgid ""\nmsgstr ""\n\nmsgid "Hello"\nmsgstr "Hola"\n\nmsgid "Goodbye"\nmsgstr "Adios"\n|
    )

    assert [{:translated, "es"}] = run(root, batch_fn: recorder(self()), force: true)

    assert_received {:batch, ["Hello", "Goodbye"]}
  end

  test "a fresh lock skips the catalog entirely", %{root: root} do
    write_po!(
      root,
      ~s|msgid ""\nmsgstr ""\n\nmsgid "Hello"\nmsgstr "Hola"\n\nmsgid "Goodbye"\nmsgstr "Adios"\n|
    )

    assert [{:translated, "es"}] = run(root, batch_fn: recorder(self()))
    assert [{:skipped, "es"}] = run(root, batch_fn: recorder(self()))

    refute_received {:batch, _}
  end
end
