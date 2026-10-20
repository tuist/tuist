---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Understand test-sharding availability for plain Cargo test runs."
}
---
# Rust test sharding {#rust-test-sharding}

Tuist does not shard plain `cargo test` runs or distribute their compiled tests across CI workers. Setting shard-plan environment variables does not change which tests Cargo executes.

Run your tests in a single CI job instead:

```sh
tuist cargo test --workspace
```

Cargo manages local test parallelism, and Tuist reports the results, including doctests. See <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> for setup and reporting details.

You can use Cargo's package selection and test filters to choose what each job executes, but these jobs are independent runs, not Tuist-managed shards.
