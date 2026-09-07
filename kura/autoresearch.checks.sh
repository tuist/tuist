#!/usr/bin/env bash
set -euo pipefail

bazel-bin/kura_lib_test --exact store::tests::concurrent_recipe_replication_and_high_fanout_eviction_stay_consistent
bazel-bin/kura_lib_test --exact reapi::service::tests::splice_split_and_read_a_composite_blob_without_materializing_it_in_the_store
bazel-bin/kura_lib_test --exact reapi::service::tests::replicated_recipe_waits_for_every_chunk_and_remains_readable_when_disabled
bazel-bin/kura_lib_test --exact reapi::chunking::tests::presence_expansion_has_an_aggregate_request_budget
bazel-bin/kura_lib_test --exact store::tests::chunk_recipe_backfill_reconstructs_refs_created_by_an_older_node
