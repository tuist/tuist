defmodule LuftServer.Threads.Cards do
  @moduledoc """
  Locally compiles native NSH cards, without Tuist or workspace credentials.
  Only the card and trusted Luft kit may enter a bundle. Commands run with an
  empty environment, bounded output, wall/CPU/memory limits and two build slots.

  Configure `:luft_server, LuftServer.Threads.Cards` with `:nsh_path`,
  `:muontrap_path` and optionally `:kit_path`. The default kit is the release
  asset `priv/threads/card_kit.tsx`; NSH and muontrap must be installed locally.
  Missing dependencies disable card presentation, never its source checks.
  """
  @heights %{"compact" => 120, "medium" => 240, "tall" => 400}
  @registry __MODULE__.Slots
  @timeout 30_000
  @foreign "A card may import only Luft's card kit, ./luft."

  defmodule Output do
    @moduledoc false
    defstruct size: 0, chunks: [], overflow?: false

    def text(output), do: output.chunks |> Enum.reverse() |> IO.iodata_to_binary()

    defimpl Collectable do
      def into(output) do
        {output,
         fn
           %{overflow?: true} = acc, {:cont, _} ->
             acc

           acc, {:cont, chunk} ->
             size = acc.size + byte_size(chunk)

             if size > 2 * 1024 * 1024,
               do: %{acc | size: size, chunks: [], overflow?: true},
               else: %{acc | size: size, chunks: [chunk | acc.chunks]}

           acc, :done ->
             acc

           _, :halt ->
             :ok
         end}
      end
    end
  end

  def child_spec(_), do: Registry.child_spec(keys: :duplicate, name: @registry)
  def sizes, do: @heights |> Map.keys() |> Enum.sort()
  def available?, do: is_binary(nsh()) and is_binary(muontrap()) and File.regular?(kit())

  def build(tsx, size) when is_binary(tsx) and is_binary(size) do
    with :ok <- check_source(tsx), do: build_card(tsx, size, ["reply"])
  end

  def build(_, _), do: {:error, "Give the card's TSX as tsx and its size class as size."}

  def build_decision(question) do
    props = %{
      question: question["question"],
      options: question["options"],
      allowOther: question["allow_other"]
    }

    source =
      "import { mount, Decision } from './luft';\nconst props = #{Jason.encode!(props)};\nmount(() => <Decision {...props} />);"

    build_card(source, "medium", ["answer"])
  end

  def check_source(tsx) do
    specifiers =
      Regex.scan(~r/\b(?:from|import)\s*["']([^"']*)["']/, tsx, capture: :all_but_first)

    cond do
      byte_size(tsx) > 64 * 1024 ->
        {:error, "The card's TSX is longer than 64 KB."}

      Regex.match?(~r{\b(?:from|import|require)\s*/[*/]}, tsx) ->
        {:error, "Put no comment right after import, from or require."}

      Regex.match?(~r/\bimport\s*[(.]|\brequire\s*\(/, tsx) ->
        {:error, "Use static imports from ./luft, not import(), import.meta or require."}

      Enum.any?(specifiers, &(&1 != ["./luft"])) ->
        {:error, @foreign}

      true ->
        :ok
    end
  end

  defp build_card(tsx, size, capabilities) do
    with {:ok, height} <- height(size),
         true <-
           available?() || {:error, "Native card compilation is unavailable on this server."},
         :ok <- take_slot() do
      dir = Path.join(System.tmp_dir!(), "luft-card-" <> Ecto.UUID.generate())

      try do
        File.mkdir!(dir)
        File.write!(Path.join(dir, "App.tsx"), tsx)
        File.cp!(kit(), Path.join(dir, "luft.tsx"))

        File.write!(
          Path.join(dir, "nsh.json"),
          Jason.encode!(%{
            name: "Card",
            id: "dev.tuist.thread-card",
            version: "1.0.0",
            build: 1,
            capabilities: %{host: capabilities}
          })
        )

        File.write!(Path.join(dir, "check.test.tsx"), test_file(height))

        with {:ok, _} <-
               ["build", "App.tsx", "--release", "--out", "out"]
               |> run(dir)
               |> quoting_only_card(),
             :ok <- only_card_bundled(dir),
             {:ok, trace} <- run(["test", "check.test.tsx", "--trace"], dir),
             :ok <- fits(trace, height),
             {:ok, %{size: bytes}} when bytes <= 256 * 1024 <-
               File.stat(Path.join(dir, "out/bundle.js")),
             {:ok, bundle} <- File.read(Path.join(dir, "out/bundle.js")) do
          {:ok, bundle}
        else
          {:error, message} when is_binary(message) -> {:error, message}
          _ -> {:error, "The card did not build, or its bundle exceeds 256 KB."}
        end
      after
        File.rm_rf(dir)
        Registry.unregister(@registry, :build)
      end
    end
  end

  defp height(size) do
    case Map.fetch(@heights, size) do
      {:ok, height} -> {:ok, height}
      :error -> {:error, "Use compact, medium or tall for the card's size."}
    end
  end

  defp take_slot do
    {:ok, _} = Registry.register(@registry, :build, nil)

    if length(Registry.lookup(@registry, :build)) <= 2 do
      :ok
    else
      Registry.unregister(@registry, :build)
      {:error, "The server is checking other cards. Try again in a moment."}
    end
  end

  defp config, do: Application.get_env(:luft_server, __MODULE__, [])
  defp nsh, do: config()[:nsh_path] || System.find_executable("nsh")
  defp muontrap, do: config()[:muontrap_path] || Application.app_dir(:muontrap, "priv/muontrap")

  defp kit,
    do: config()[:kit_path] || Application.app_dir(:luft_server, "priv/threads/card_kit.tsx")

  defp test_file(height) do
    """
    import { open, test } from "nsh/test";
    for (const width of [320, 600]) {
      test(`at ${width} points wide`, async () => {
        await open("./App.tsx", { width, height: #{height}, host: { handlers: { reply: () => null, answer: () => null } } });
      });
    }
    """
  end

  defp run(args, dir) do
    env =
      System.get_env()
      |> Map.new(fn {key, _} -> {key, nil} end)
      |> Map.merge(%{"PATH" => "/usr/local/bin:/usr/bin:/bin", "HOME" => dir, "NO_COLOR" => "1"})

    limits =
      if :os.type() == {:unix, :linux},
        do: "ulimit -t 30 && ulimit -v 4194304",
        else: "ulimit -t 30"

    task =
      Task.async(fn ->
        System.cmd(
          muontrap(),
          ["--", "/bin/sh", "-c", ~s(#{limits} && exec "$0" "$@"), nsh() | args],
          cd: dir,
          env: env,
          stderr_to_stdout: true,
          into: %Output{}
        )
      end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      nil ->
        {:error, "The card took longer than 30 seconds to build and open."}

      {:ok, {%Output{overflow?: true}, _}} ->
        {:error, "The card wrote more than 2 MB while building and opening."}

      {:ok, {output, 0}} ->
        {:ok, Output.text(output)}

      {:ok, {output, _}} ->
        {:error, feedback(Output.text(output), dir)}
    end
  end

  defp feedback(output, dir) do
    output
    |> String.replace(dir <> "/", "")
    |> String.replace(dir, ".")
    |> String.replace(~r/\e\[[0-9;]*m/, "")
    |> String.split("\n")
    |> Enum.reject(&Regex.match?(~r/^\s*(warn |perf |✓ |── )|^\s+[A-Z]\w* \{/, &1))
    |> Enum.join("\n")
    |> String.trim()
    |> String.slice(0, 4_000)
  end

  defp quoting_only_card({:error, feedback} = error) do
    places = Regex.scan(~r/([^\s\[\]()"'`]+):\d+:\d+/, feedback, capture: :all_but_first)
    own = [["App.tsx"], ["./App.tsx"], ["luft.tsx"], ["./luft.tsx"]]
    if Enum.all?(places, &(&1 in own)), do: error, else: {:error, @foreign}
  end

  defp quoting_only_card(result), do: result

  defp only_card_bundled(dir) do
    with {:ok, map} <- File.read(Path.join(dir, "out/bundle.js.map")),
         {:ok, %{"sources" => sources}} <- Jason.decode(map),
         ["App.tsx", "luft.tsx"] <- Enum.sort(sources) do
      :ok
    else
      _ -> {:error, @foreign}
    end
  end

  def fits(trace, height) do
    trace
    |> String.split("\n")
    |> Enum.chunk_while(nil, &chunk_open/2, &{:cont, &1, nil})
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(fn lines -> overflow(Enum.reverse(lines), height) end)
    |> case do
      nil -> :ok
      message -> {:error, message}
    end
  end

  defp chunk_open(line, acc) do
    cond do
      String.starts_with?(line, "── open(") and acc -> {:cont, acc, [line]}
      String.starts_with?(line, "── open(") -> {:cont, [line]}
      acc -> {:cont, [line | acc]}
      true -> {:cont, nil}
    end
  end

  defp overflow(lines, height) do
    tree =
      Enum.reduce(lines, %{parents: %{}, kinds: %{}, frames: %{}}, fn line, tree ->
        cond do
          match = Regex.run(~r/Create \{ id: (\d+), kind: (\w+)/, line) ->
            [_, id, kind] = match
            put_in(tree, [:kinds, id], kind)

          match = Regex.run(~r/Insert \{ parent: (\d+), child: (\d+)/, line) ->
            [_, parent, child] = match
            put_in(tree, [:parents, child], parent)

          match = Regex.run(~r/(?:Remove|Delete) \{[^}]*?(?:child|id): (\d+)/, line) ->
            [_, id] = match
            update_in(tree, [:parents], &Map.delete(&1, id))

          match =
              Regex.run(
                ~r/Frame \{ id: (\d+), x: (-?[\d.]+), y: (-?[\d.]+), w: ([\d.]+), h: ([\d.]+)/,
                line
              ) ->
            [_, id | values] = match

            put_in(
              tree,
              [:frames, id],
              Enum.map(values, fn value ->
                {number, _} = Float.parse(value)
                number
              end)
            )

          true ->
            tree
        end
      end)

    bottom =
      tree.frames
      |> Map.keys()
      |> Enum.reject(&scrolled?(tree, &1))
      |> Enum.map(&absolute(tree, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn [_, y, _, h] -> y + h end)
      |> Enum.max(fn -> 0 end)

    if bottom > height + 1,
      do:
        "The card's content is #{round(bottom)} points tall, but its frame is #{height}. Use a larger size, less content or Scroll."
  end

  defp scrolled?(tree, id) do
    case tree.parents[id] do
      nil -> false
      "1" -> false
      parent -> tree.kinds[parent] in ["Scroll", "List"] or scrolled?(tree, parent)
    end
  end

  defp absolute(tree, id) do
    with [x, y, w, h] <- tree.frames[id], parent when is_binary(parent) <- tree.parents[id] do
      case parent do
        "1" -> [x, y, w, h]
        _ -> with [px, py, _, _] <- absolute(tree, parent), do: [px + x, py + y, w, h]
      end
    else
      _ -> nil
    end
  end
end
