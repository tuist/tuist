> [!WARNING]
> **Experimental compilation cache**
>
> The cache is experimental and qualified on Apple silicon Macs. Libraries are cached by the sources the compiler read, on every platform, but library caching on Linux isn't qualified yet. Build scripts, procedural macros, executables and native code are cached only on Apple silicon Macs. Cache keys replace checkout and toolchain paths with placeholders, so reuse works for checkouts at different paths on the same machine, not across machines.
