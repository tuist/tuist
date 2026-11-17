//! Reusable controls, modeled on gpui-component's (`crates/ui/src`) but built
//! on the pinned, AccessKit-capable GPUI and colored with Noora's tokens
//! through `Theme`. gpui-component itself tracks a different GPUI snapshot, so
//! it cannot be a dependency.
mod button;
mod composer;
mod message;

pub use button::{Button, Variant};
pub use composer::composer;
pub use message::{chat_message, message, presence_dot};
