defmodule TuistEx.Cache.DependencyKeyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistEx.Cache.Compiler
  alias TuistEx.DependencyCache

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "tuist-key-model-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    dependencies =
      for app <- [:producer, :consumer] do
        source = Path.join(root, "#{app}-source")
        build = Path.join(root, "#{app}-build")
        File.mkdir_p!(Path.join(source, "src"))
        File.mkdir_p!(build)

        File.write!(
          Path.join(source, "src/#{app}.app.src"),
          "{application, #{app}, [{vsn, \"1.0\"}, {modules, []}]}."
        )

        %Mix.Dep{
          app: app,
          manager: :make,
          scm: Mix.SCM.Git,
          opts: [dest: source, build: build, lock: {:git, "repository", "revision", []}],
          deps: [],
          system_env: []
        }
      end

    [producer, consumer] = dependencies
    consumer = %{consumer | deps: [producer]}

    options = [
      path: Path.join(root, "store"),
      builders: [
        producer: [platform: "immutable-image", outputs: []],
        consumer: [platform: "immutable-image", outputs: []]
      ]
    ]

    %{producer: producer, consumer: consumer, options: options}
  end

  test "unsupported compiler configuration rejects a closure without reading source bytes", ctx do
    expect(Compiler, :config, fn _, true, _ -> [compilers: [:unsupported]] end)
    reject(Compiler, :source_tree, 2)
    reject(Compiler, :source_paths, 2)
    assert {:bypass, "custom_compiler"} = action_key(ctx)
  end

  test "an unsupported upstream source rejects the whole closure before any source hashing",
       ctx do
    stub(Compiler, :config, fn _, true, _ -> [] end)

    stub(Compiler, :source_paths, fn dep, _ ->
      if dep.app == :producer, do: ["src/native.c"], else: ["lib/consumer.ex"]
    end)

    reject(Compiler, :source_tree, 2)
    assert {:bypass, "custom_compiler"} = action_key(ctx)
  end

  test "source bytes are rechecked after structural enumeration", ctx do
    stub(Compiler, :config, fn _, true, _ -> [] end)
    stub(Compiler, :source_paths, fn _, _ -> [] end)

    expect(Compiler, :source_tree, fn _, _ -> [{"src/added_after_enumeration.c", 0, "digest"}] end)

    assert {:bypass, "custom_compiler"} = action_key(ctx)
  end

  test "runtime, optional and app flags on dependency edges enter the key", ctx do
    first = key(ctx)

    for {flag, value} <- [
          runtime: false,
          optional: true,
          app: false,
          only: [:prod],
          targets: [:host]
        ] do
      child = %{ctx.producer | opts: Keyword.put(ctx.producer.opts, flag, value)}
      consumer = %{ctx.consumer | deps: [child]}
      refute key(%{ctx | consumer: consumer}) == first, "missing edge input #{flag}"
    end
  end

  test "ordinary private resources and nonstandard native outputs enter downstream keys", ctx do
    build = ctx.producer.opts[:build]
    File.mkdir_p!(Path.join(build, "bin"))
    File.write!(Path.join(build, "bin/tool"), "first")
    first = key(ctx)
    File.write!(Path.join(build, "bin/tool"), "second")
    second = key(ctx)
    refute second == first
    File.mkdir_p!(Path.join(build, "priv"))
    File.write!(Path.join(build, "priv/template"), "template")
    refute key(ctx) == second
  end

  test "declared tools include executable bytes, not only a name or version label", ctx do
    tool = Path.join(Path.dirname(ctx.producer.opts[:dest]), "tool")
    File.write!(tool, "#!/bin/sh\nprintf first\n")
    File.chmod!(tool, 0o755)

    builders =
      Keyword.update!(ctx.options[:builders], :producer, &Keyword.put(&1, :tools, [tool]))

    ctx = %{ctx | options: Keyword.put(ctx.options, :builders, builders)}
    first = key(ctx)
    File.write!(tool, "#!/bin/sh\nprintf other\n")
    refute key(ctx) == first
    File.rm!(tool)
    assert {:bypass, "unmodeled_input"} = action_key(ctx)
  end

  test "builder declaration ordering does not change an action key", ctx do
    first = key(ctx)

    builders =
      for {app, builder} <- Enum.reverse(ctx.options[:builders]) do
        {app, [env: [], generated: [], tools: [], inputs: []] ++ Enum.reverse(builder)}
      end

    assert key(%{ctx | options: Keyword.put(ctx.options, :builders, builders)}) == first
  end

  defp key(ctx) do
    assert {:ok, key} = action_key(ctx)
    key
  end

  defp action_key(ctx),
    do:
      DependencyCache.action_key(
        ctx.consumer,
        [ctx.producer, ctx.consumer],
        %{compiler_options: []},
        ctx.options
      )
end
