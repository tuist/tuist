//! Tuist's cache authorization, in Rust.
//!
//! This was a Lua hook loaded through a generic extension point. Nothing
//! outside Tuist ever wrote one, so the policy moved into the binary and the
//! scripting layer went with it: no interpreter pool to keep hooks from
//! serializing, no marshalling of the request into Lua values per call, and a
//! claim shape the compiler checks rather than a cross-language test.

// Nothing calls these until the policy that replaces `authenticate` and
// `authorize` lands and the extension module is deleted; the allow goes with it.
#![allow(dead_code)]

pub mod grants;
pub mod target;
