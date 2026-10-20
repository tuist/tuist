# Vendored norimel

Source: norimel 0.1.1 from crates.io, from https://github.com/romancitodev/nobubbles.
Published archive SHA-256: `f7d8b322f404eea16e474b2ed1e1f2c344db702ed0e892fefe0ff5b296ebf2b0`.
Revision: `d9a2c5d45c7f5b2c3db6322428e6ebcd5971d45c`, directory `crates/norimel`.

The MIT license is retained in LICENSE and the repository NOTICE. This private
module ships inside tuist_cargo_cache, including crates.io packages; it is not a registry dependency.

Local integration changes: lib.rs becomes mod.rs; ratatui conversions are always
enabled, optional gradient code stays disabled, crossterm uses ratatui's re-export,
and unused upstream APIs are allowed. Upstream examples are ignored because this
is a private module, while upstream unit tests remain enabled. Rustfmt normalizes
formatting. No rendering behavior changes are intended.
