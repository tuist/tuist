//! A local action-cache hit does not prove its value graph is present, and this
//! crate used to hand such a hit straight to the compiler -- the state behind
//! `error: CAS operation failed: missing object '0~...'`
//! (<https://github.com/tuist/tuist/issues/12245>), fatal on the clang lane and
//! permanent, because the poisoned association shadows the remote on every get.
//!
//! These drive THIS crate's exported `llcas_*` surface against a scripted fake
//! proxy, so the fall-through to the remote is observable: a short-circuit and a
//! fall-through both end in NOTFOUND, and only the proxy tells them apart.
//!
//! The defect state is built directly rather than by pruning, using two ABI facts:
//! `llcas_cas_get_objectid` mints an id WITHOUT requiring the object, and
//! `llcas_actioncache_put_for_digest` does not validate that the value exists. So
//! a digest learned from a throwaway store, put into a FRESH one, is "association
//! present, root absent" with no size limits or directory surgery.
//!
//! Two independent conditions live here, and they fail the same way. An unbacked
//! HIT is a value root missing from this store, which the local probe catches. An
//! unbacked ASSOCIATION is a store that looks fine and a key the remote never
//! received, so the interior nodes below a present root can be produced by
//! nothing -- caught only by asking the proxy, because no local evidence
//! distinguishes it. The second arrives on a whole-image clone of another host's
//! store, which is why no write-side invariant in this crate reaches it.
//!
//! Not covered: how the state is REACHED. One consequence is worth naming -- a
//! prune ROTATES, and reads chain through the demoted generation, so the guard
//! stays quiet until that generation is collected. Inferred from tuist/tuist#12246,
//! not asserted here; reproducing a rotation needs that PR's harness, which holds
//! no other handle open on the store.

use std::ffi::{c_char, c_void, CStr, CString};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

use tuist_cas_plugin::proxy_proto::{
    read_request, write_response, OP_BACKED, OP_FETCH_OBJECT, OP_RESOLVE, STATUS_ERROR, STATUS_HIT,
    STATUS_MISS,
};
use tuist_cas_plugin::types::*;
use tuist_cas_plugin::upstream_path;

// --- The behaviour under test --------------------------------------------------

/// The defect: the association survives, its root does not, and the get is the
/// only place that can notice before the compiler does.
#[test]
fn an_unbacked_local_hit_is_not_served_to_the_caller() {
    let Some(env) = Fixture::new("unbacked-sync") else { return };
    let (key, absent_value) = env.seed_unbacked_association();

    // Precondition: this is genuinely a local hit over an absent root.
    let id = env.cas.objectid_for(&absent_value);
    assert_eq!(
        env.cas.contains(id),
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "the value object must be absent for this test to mean anything"
    );

    env.proxy.answer_resolve_with_miss();
    let (result, _) = env.cas.actioncache_get(&key);

    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_NOTFOUND,
        "an association whose root is absent must not reach the caller as SUCCESS"
    );
    assert_eq!(
        env.proxy.resolves_for(&key),
        1,
        "the unbacked hit must FALL THROUGH to the remote, not short-circuit: a \
         resolve can recover entries fetch_object cannot name (snapshot window, \
         restarted proxy) and registers the whole graph in one round trip"
    );
}

/// End to end, through the two calls a replay actually makes. The get is only
/// half of it: the failure happens at the LOAD, which is where an object id that
/// names nothing becomes `missing object '0~…'`. This asserts both halves --
/// that the value really is unloadable, and that the caller is never given it.
#[test]
fn the_caller_never_receives_an_id_that_cannot_be_loaded() {
    let Some(env) = Fixture::new("end-to-end") else { return };
    let (key, absent_value) = env.seed_unbacked_association();
    env.proxy.answer_resolve_with_miss();

    // What an unguarded get handed back, and what the compiler would then do with
    // it. NOTFOUND here is the build failure: fatal on the clang lane.
    let id = env.cas.objectid_for(&absent_value);
    assert_eq!(
        env.cas.load(id),
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "the association names an object that cannot be loaded -- this is the failure"
    );

    // So the get must not hand that id over in the first place.
    let (result, _) = env.cas.actioncache_get(&key);
    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_NOTFOUND,
        "the caller must get a miss and recompile, never the unloadable id"
    );
}

/// The limitation, as an assertion rather than a paragraph: the probe covers the
/// ROOT. A value whose root is present but whose child is gone passes the guard
/// and still fails at load time, on the child.
#[test]
fn a_present_root_with_a_missing_child_still_passes_the_guard() {
    let Some(env) = Fixture::new("deep-node") else { return };
    let absent_child = env.absent_value_digest();
    let child_id = env.cas.objectid_for(&absent_child);
    let root = env.cas.store_object_with_refs(b"a root whose child was never stored", &[child_id]);
    let key = env.cas.key_digest(b"deep-node");
    env.cas.actioncache_put(&key, root).expect("seeding put");
    env.proxy.answer_resolve_with_miss();

    let (result, served) = env.cas.actioncache_get(&key);

    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_SUCCESS,
        "the root is present, so the guard passes it -- verifying the whole graph \
         would put a walk on the serial task-setup path"
    );
    assert_eq!(env.cas.load(served), LLCAS_LOOKUP_RESULT_SUCCESS, "and the root loads");
    assert_eq!(
        env.cas.load(child_id),
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "while the child does not: the same `missing object` failure, one node deeper, \
         which the write-through ordering fixes rather than this guard"
    );
}

/// The incident the root probe cannot see, and the check that now catches it.
///
/// Root present, interior node gone, and a remote that does not hold the key --
/// so nothing anywhere can produce that node, and the compiler would be handed a
/// graph it cannot finish loading. This is the shape that reached CI as
/// `ClangCachingMaterializeKey <key>` failing on a DIFFERENT digest, five times
/// across five days, self-healing on every re-run because the recompile
/// republished the object. The write-side invariants do not cover it: the
/// association arrives on a whole-image clone of another host's store (the
/// per-account runner cache volume), so no writer in this crate ever touched it.
#[test]
fn an_association_the_remote_cannot_back_is_withheld() {
    let Some(env) = Fixture::uploading("unbacked-association") else { return };
    let absent_child = env.absent_value_digest();
    let child_id = env.cas.objectid_for(&absent_child);
    let root = env.cas.store_object_with_refs(b"an inherited root, hollow inside", &[child_id]);
    let key = env.cas.key_digest(b"unbacked-association");
    env.cas.actioncache_put(&key, root).expect("seeding put");

    // The root is present, so the probe passes and only the remote can tell.
    assert_eq!(env.cas.contains(root), LLCAS_LOOKUP_RESULT_SUCCESS);
    env.proxy.answer_backed_with_no();
    env.proxy.answer_resolve_with_miss();

    let (result, _) = env.cas.actioncache_get(&key);

    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_NOTFOUND,
        "an association the remote cannot back must not be served: the interior node \
         it names is unproducible, and clang does not survive that"
    );
    assert_eq!(
        env.proxy.backing_checks_for(&key),
        1,
        "and the verdict must come from asking, once, rather than from a graph walk \
         on the serial task-setup path"
    );
    assert_eq!(
        env.proxy.resolves_for(&key),
        1,
        "then fall through to the remote, which is what turns the dead build into a \
         recompile"
    );
}

/// The other half, and the one that protects the hit rate: when the remote DOES
/// hold the key, the check has already registered the closure's fetch
/// instructions, so a demand load for the missing interior node can repair it.
/// The hit is served exactly as before.
#[test]
fn an_association_the_remote_can_back_is_served() {
    let Some(env) = Fixture::uploading("backed-association") else { return };
    let key = env.cas.key_digest(b"backed-association");
    let value = env.cas.store_object(b"a value the remote also knows");
    env.cas.actioncache_put(&key, value).expect("seeding put");
    env.proxy.answer_backed_with_yes(&env.cas.digest_of(value));

    let (result, served) = env.cas.actioncache_get(&key);

    assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS);
    assert_eq!(
        env.cas.digest_of(served),
        env.cas.digest_of(value),
        "the served id must still name the stored value"
    );
    assert_eq!(
        env.proxy.resolves_for(&key),
        0,
        "a backed hit stays a local hit -- the check is not a resolve in disguise"
    );
}

/// A `Backed` verdict names the graph the REMOTE holds, and the fetch
/// instructions it registered describe that graph. When the remote's value
/// differs from the local association's -- a recompile that was not
/// byte-reproducible -- the verdict does not transfer, and the local closure is
/// still unvouched. Withholding costs no compile: the fall-through resolves the
/// same key and serves the remote's value, which IS backed. A substitution, not
/// a recompile.
#[test]
fn a_verdict_for_a_different_value_does_not_vouch_for_this_one() {
    let Some(env) = Fixture::uploading("divergent-value") else { return };
    let key = env.cas.key_digest(b"divergent-value");
    let local = env.cas.store_object(b"what this machine computed");
    let remote = env.cas.store_object(b"what the remote computed for the same key");
    env.cas.actioncache_put(&key, local).expect("seeding put");

    // The remote holds the key, but under a different graph than the local
    // association names.
    let remote_digest = env.cas.digest_of(remote);
    env.proxy.answer_backed_with_yes(&remote_digest);
    env.proxy.answer_resolve_with_hit(&remote_digest);

    let (result, served) = env.cas.actioncache_get(&key);

    assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS);
    assert_eq!(
        env.cas.digest_of(served),
        remote_digest,
        "the served value must be the one the verdict actually backed, not the local \
         association it says nothing about"
    );
    assert_eq!(
        env.proxy.resolves_for(&key),
        1,
        "which takes the fall-through: the local short-circuit cannot supply a backed value here"
    );
}

/// The failure mode that would cost the most: a proxy that cannot answer must
/// leave the decision alone. This covers a proxy older than the op (its dispatch
/// answers `bad op`), an instance with no snapshot to judge against, and any
/// transport failure -- all of which arrive as the same status, and none of
/// which is evidence that the association is dangling.
#[test]
fn a_proxy_that_cannot_tell_leaves_the_hit_alone() {
    let Some(env) = Fixture::uploading("backing-unknown") else { return };
    let key = env.cas.key_digest(b"backing-unknown");
    let value = env.cas.store_object(b"a value with no verdict available");
    env.cas.actioncache_put(&key, value).expect("seeding put");

    // The fixture's default: the proxy declines to judge.
    let (result, served) = env.cas.actioncache_get(&key);

    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_SUCCESS,
        "an inconclusive answer must never cost a recompile"
    );
    assert_eq!(env.cas.digest_of(served), env.cas.digest_of(value));
}

/// The upload policy is not the client's to apply. This process's `upload` flag
/// comes from a compiler option that reaches Swift, while swift-build's Clang
/// caching runs against a CAS created with a plugin path and no options -- so
/// the lane that actually fails builds reads as uploading even under an explicit
/// opt-out, and filtering here would have silently exempted the Swift lane while
/// leaving the Clang one recompiling every valid local entry.
///
/// So the question always goes to the proxy, which holds the project's real
/// answer and declines a read-only instance
/// (`a_read_only_project_is_never_told_its_association_is_unbacked`). Here the
/// fixture has uploads OFF and the proxy still answers, and its answer is what
/// counts.
#[test]
fn the_upload_policy_is_the_proxys_call_not_the_clients() {
    let Some(env) = Fixture::new("no-upload") else { return };
    let key = env.cas.key_digest(b"no-upload");
    let value = env.cas.store_object(b"a value that is local on purpose");
    env.cas.actioncache_put(&key, value).expect("seeding put");
    env.proxy.answer_backed_with_no();
    env.proxy.answer_resolve_with_miss();

    let (result, _) = env.cas.actioncache_get(&key);

    assert_eq!(
        env.proxy.backing_checks_for(&key),
        1,
        "the client must ask rather than decide -- its own upload flag does not speak \
         for the Clang lane"
    );
    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_NOTFOUND,
        "and must honour the answer it gets back"
    );
}

/// The other limitation: a REMOTE hit is served unverified on purpose, because it
/// arrives with fetch instructions for every node. When the remote can no longer
/// produce the bytes -- kura keeping an action entry whose blobs are gone -- that
/// promise is broken and the load fails. The guard does not cover this.
#[test]
fn a_remote_hit_whose_blobs_are_gone_is_served_and_fails_at_load() {
    let Some(env) = Fixture::new("remote-no-blobs") else { return };
    let key = env.cas.key_digest(b"remote-no-blobs");
    let never_stored = env.absent_value_digest();
    env.proxy.answer_resolve_with_hit(&never_stored);

    let (result, served) = env.cas.actioncache_get(&key);

    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_SUCCESS,
        "a remote hit is served without probing -- it is supposed to come with fetch \
         instructions covering the whole graph"
    );
    assert_eq!(
        env.cas.load(served),
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "but the proxy cannot produce it, so the failure lands at load time. This PR \
         does not fix that state; kura's blob-eviction cascade is what prevents it."
    );
}

/// The write-through used to be an author of unbacked associations in its own
/// right, with no prune involved: a resolve replies BEFORE materialisation
/// finishes, so recording `key -> value` there named a graph that might never
/// arrive -- and nothing can retract it. Reproduced on a real build over an EMPTY
/// store, which ended it holding 9 dangling roots.
///
/// So the association is recorded only once the root is actually present.
#[test]
fn a_resolve_hit_whose_graph_never_arrived_records_no_association() {
    let Some(env) = Fixture::new("write-through-ordering") else { return };
    let key = env.cas.key_digest(b"write-through-ordering");
    let never_materialized = env.absent_value_digest();
    env.proxy.answer_resolve_with_hit(&never_materialized);

    let (first, _) = env.cas.actioncache_get(&key);
    assert_eq!(
        first,
        LLCAS_LOOKUP_RESULT_SUCCESS,
        "the resolved value is still served -- a remote hit arrives with fetch \
         instructions for its whole graph, so the load path can produce it"
    );
    assert_eq!(env.proxy.resolves_for(&key), 1, "the first get reaches the remote");

    // This proxy materialises nothing, so the graph never arrived.
    let value_id = env.cas.objectid_for(&never_materialized);
    assert_eq!(
        env.cas.contains(value_id),
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "the value graph never materialised"
    );

    // Nothing was written for it. Probed by making the root present and asking
    // again with the remote answering MISS: an association from the first get
    // would answer SUCCESS with no further resolve. A second resolve is the proof
    // that the store holds no record of this key.
    let restored = env.cas.store_object(ABSENT_VALUE_CONTENT);
    assert_eq!(
        env.cas.digest_of(restored),
        never_materialized,
        "content addressing must reproduce the same digest for the same bytes"
    );
    env.proxy.answer_resolve_with_miss();

    let (second, _) = env.cas.actioncache_get(&key);
    assert_eq!(
        second,
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "no association was written, so the key falls through to the remote"
    );
    assert_eq!(
        env.proxy.resolves_for(&key),
        2,
        "and it resolves again rather than answering from a record naming nothing"
    );
}

/// The other half: the deferral must not stop associations being recorded at all,
/// or every build would re-resolve every key. When the graph IS present at resolve
/// time -- the warm snapshot path, where materialisation ran ahead of the build --
/// the association is recorded and answers later gets with no round trip.
#[test]
fn a_resolve_hit_whose_graph_is_present_is_recorded() {
    let Some(env) = Fixture::new("write-through-present") else { return };
    let key = env.cas.key_digest(b"write-through-present");
    // Already materialised locally, which is what the probe checks for.
    let materialized = env.cas.digest_of(env.cas.store_object(b"a graph that landed"));
    env.proxy.answer_resolve_with_hit(&materialized);

    let (first, _) = env.cas.actioncache_get(&key);
    assert_eq!(first, LLCAS_LOOKUP_RESULT_SUCCESS, "the remote hit is served");
    assert_eq!(env.proxy.resolves_for(&key), 1);

    env.proxy.answer_resolve_with_miss();
    let (second, served) = env.cas.actioncache_get(&key);

    assert_eq!(
        second,
        LLCAS_LOOKUP_RESULT_SUCCESS,
        "the association recorded during the first get answers this one"
    );
    assert_eq!(
        env.proxy.resolves_for(&key),
        1,
        "and it costs no second resolve -- the local record is what makes warm \
         builds cheap, so the deferral must not cost it when the graph is there"
    );
    assert_eq!(env.cas.digest_of(served), materialized);
}

/// The async entry point has its own upstream short-circuit that never reaches
/// `actioncache_get_impl`, so guarding only the sync path would leave the lane
/// the build system actually drives still broken.
#[test]
fn an_unbacked_local_hit_is_not_served_to_the_caller_asynchronously() {
    let Some(env) = Fixture::new("unbacked-async") else { return };
    let (key, _) = env.seed_unbacked_association();

    env.proxy.answer_resolve_with_miss();
    let (result, calls) = env.cas.actioncache_get_async(&key);

    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_NOTFOUND,
        "the async get must apply the same verification as the sync get"
    );
    assert_eq!(calls, 1, "the callback must fire exactly once");
    assert_eq!(env.proxy.resolves_for(&key), 1, "and fall through to the remote");
}

/// The async lane verifies the hit in its own fast path and then falls through to
/// the remote half. If that fall-through re-ran the local half, every unbacked hit
/// would be detected, logged and counted TWICE on exactly the lane the build
/// system drives, which would make the operational signal read 2x high.
#[test]
fn an_unbacked_local_hit_is_detected_once_per_get() {
    let Some(env) = Fixture::new("detected-once") else { return };
    let (key, _) = env.seed_unbacked_association();
    env.proxy.answer_resolve_with_miss();

    let log = env.capture_log();
    let (result, _) = env.cas.actioncache_get_async(&key);
    let lines = log.lines_containing("unbacked local hit");

    assert_eq!(result, LLCAS_LOOKUP_RESULT_NOTFOUND);
    assert_eq!(lines, 1, "the condition must be reported once per get, not once per layer");
    assert_eq!(env.proxy.resolves_for(&key), 1, "and cost one resolve, not two");
}

/// The regression that would cost the most: the guard must not turn ordinary
/// warm hits into misses.
#[test]
fn a_backed_local_hit_is_still_served_without_consulting_the_remote() {
    let Some(env) = Fixture::new("backed-sync") else { return };
    let key = env.cas.key_digest(b"backed-key");
    let value = env.cas.store_object(b"a value that is really here");
    env.cas.actioncache_put(&key, value).expect("seeding put");

    let (result, served) = env.cas.actioncache_get(&key);

    assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS);
    assert_eq!(
        env.cas.digest_of(served),
        env.cas.digest_of(value),
        "the served id must name the stored value"
    );
    assert_eq!(
        env.proxy.resolves_for(&key),
        0,
        "a backed local hit must stay purely local -- no proxy round trip"
    );
}

#[test]
fn a_backed_local_hit_is_still_served_asynchronously() {
    let Some(env) = Fixture::new("backed-async") else { return };
    let key = env.cas.key_digest(b"backed-key-async");
    let value = env.cas.store_object(b"a value that is really here, twice");
    env.cas.actioncache_put(&key, value).expect("seeding put");

    let (result, calls) = env.cas.actioncache_get_async(&key);

    assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS);
    assert_eq!(calls, 1);
    assert_eq!(env.proxy.resolves_for(&key), 0);
}

/// `p_value` is nullable in the ABI, and the verification needs an object id to
/// probe -- so the guard must not depend on the caller supplying the slot.
#[test]
fn a_null_out_parameter_is_handled_on_both_verdicts() {
    let Some(env) = Fixture::new("null-out") else { return };

    let backed_key = env.cas.key_digest(b"null-out-backed");
    let value = env.cas.store_object(b"present value");
    env.cas.actioncache_put(&backed_key, value).expect("seeding put");
    assert_eq!(
        env.cas.actioncache_get_without_out_param(&backed_key),
        LLCAS_LOOKUP_RESULT_SUCCESS
    );

    let (unbacked_key, _) = env.seed_unbacked_association();
    env.proxy.answer_resolve_with_miss();
    assert_eq!(
        env.cas.actioncache_get_without_out_param(&unbacked_key),
        LLCAS_LOOKUP_RESULT_NOTFOUND
    );
}

/// `globally = true` must not mask the condition: the point is to detect that the
/// LOCAL graph is gone, and a healthy remote answers yes to a global probe.
#[test]
fn a_global_lookup_still_verifies_locally() {
    let Some(env) = Fixture::new("globally") else { return };
    let (key, _) = env.seed_unbacked_association();

    env.proxy.answer_resolve_with_miss();
    let (result, _) = env.cas.actioncache_get_globally(&key);

    assert_eq!(result, LLCAS_LOOKUP_RESULT_NOTFOUND);
}

/// The two ABI facts the defect state is built from. If a future toolchain starts
/// validating puts, this fails loudly here rather than silently invalidating
/// every test above.
#[test]
fn a_put_for_a_never_stored_value_succeeds_and_leaves_the_root_absent() {
    let Some(env) = Fixture::new("preconditions") else { return };
    let absent = env.absent_value_digest();

    let id = env.cas.objectid_for(&absent);
    assert_eq!(
        env.cas.contains(id),
        LLCAS_LOOKUP_RESULT_NOTFOUND,
        "get_objectid must mint an id without requiring the object"
    );

    let key = env.cas.key_digest(b"precondition-key");
    env.cas
        .actioncache_put(&key, id)
        .expect("put_for_digest must not validate that the value object exists");
}

// --- The failure the verification makes reachable ------------------------------

/// The store refuses to change an association, and the verification deliberately
/// drives recompiles on exactly the keys whose associations are stale. Surfacing
/// the refusal would trade a `missing object` build failure for a `cache poisoned`
/// one, which is no better.
#[test]
fn re_putting_a_key_with_a_different_value_is_not_a_failure() {
    let Some(env) = Fixture::new("poisoned-put") else { return };
    let key = env.cas.key_digest(b"poisoned-put");
    let original = env.cas.store_object(b"the value the store already has");
    let recompiled = env.cas.store_object(b"what a non-reproducible recompile made");
    env.cas.actioncache_put(&key, original).expect("seeding put");

    env.cas
        .actioncache_put(&key, recompiled)
        .expect("a refused re-put must not reach the build system as a failure");

    let (result, served) = env.cas.actioncache_get(&key);
    assert_eq!(result, LLCAS_LOOKUP_RESULT_SUCCESS);
    assert_eq!(
        env.cas.digest_of(served),
        env.cas.digest_of(original),
        "reporting success must not be mistaken for having CHANGED the association \
         -- the original survives, which is why the key stays degraded until the \
         store generation rolls"
    );
}

#[test]
fn re_putting_a_key_with_a_different_value_is_not_a_failure_asynchronously() {
    let Some(env) = Fixture::new("poisoned-put-async") else { return };
    let key = env.cas.key_digest(b"poisoned-put-async");
    let original = env.cas.store_object(b"the value the store already has");
    let recompiled = env.cas.store_object(b"what a non-reproducible recompile made");
    env.cas.actioncache_put(&key, original).expect("seeding put");

    let (failed, calls, error) = env.cas.actioncache_put_async(&key, recompiled);

    assert!(!failed, "a refused re-put must be reported as success");
    assert_eq!(calls, 1, "the callback must fire exactly once");
    assert!(error.is_empty(), "and must carry no error string: {error}");
}

/// The hazard the verification CREATES, and the reason it cannot ship without the
/// downgrade above: a stale association naming X falls through, the remote answers
/// with a different digest Y, and caching that association is refused. Failing the
/// get there would be strictly worse than the bug being fixed.
#[test]
fn a_remote_value_that_contradicts_a_stale_association_is_still_served() {
    let Some(env) = Fixture::new("contradicting-remote") else { return };
    let (key, _) = env.seed_unbacked_association();
    let remote_value = env.cas.digest_of(env.cas.store_object(b"what the remote actually holds"));
    env.proxy.answer_resolve_with_hit(&remote_value);

    let (result, served) = env.cas.actioncache_get(&key);

    assert_eq!(
        result, LLCAS_LOOKUP_RESULT_SUCCESS,
        "the resolve succeeded; only caching its association was refused"
    );
    assert_eq!(
        env.cas.digest_of(served),
        remote_value,
        "and the value served must be the one the remote resolved"
    );
}

/// Not an assertion -- the record of what the verification costs, and the reason
/// there is no memoization of the verdict behind it.
///
/// Measured on an M-series Mac, release profile, against the in-process fake
/// proxy, so the socket figure below is a transport floor rather than a full
/// accounting of the real proxy's work.
///
/// Before the backing check: a served local hit was ~49ns end to end, of which
/// the root probe is ~10ns, or two thirds of a millisecond across the ~13.5k
/// hits of a warm runner build.
///
/// With it: ~14.3us per served hit, because the check is a unix-socket round
/// trip to the proxy and the root probe is a local `contains`. That is ~290x per
/// hit and ~193ms across the same warm build, against a runner warm build
/// measured at 96.8s +/- 3.9 (AGENTS.md, "Runner regime") -- 0.2% of the build
/// and about a twentieth of that measurement's own noise band.
///
/// The round trip is what makes memoizing the verdict tempting now in a way the
/// bare probe never did. It stays unmemoized for the reasons it always was: a
/// mutex on the serial task-setup path, plus a stale-positive window, since
/// another process pruning the shared store does not clear this process's cache.
/// Revisit only if a real-proxy measurement lands far from this floor.
///
/// The regime that would NOT be affordable -- a per-key `GetActionResult` per
/// served hit -- is declined proxy-side rather than paid: no snapshot and not
/// `Fetching` answers Unknown, which serves the hit without a veto. Only the
/// seconds-long fetch window resolves per key. See `OP_BACKED` in proxy.rs.
///
/// Re-run with `cargo test --release -- --ignored --nocapture probe_cost` if the
/// verification changes shape again.
#[test]
#[ignore = "a measurement, not an assertion"]
fn probe_cost() {
    let Some(env) = Fixture::new("probe-cost") else { return };
    let key = env.cas.key_digest(b"probe-cost");
    let value = env.cas.store_object(b"a value that is really here");
    env.cas.actioncache_put(&key, value).expect("seeding put");
    let id = env.cas.objectid_for(&env.cas.digest_of(value));
    // The warm-build regime: the remote holds the key, so the backing check
    // answers Backed and the hit is served. Without this the fake proxy answers
    // STATUS_ERROR, which reads as Unknown -- the same round trip, but not the
    // path a warm build actually takes.
    env.proxy.answer_backed_with_yes(&env.cas.digest_of(value));

    const ITERATIONS: u32 = 20_000;
    const WARM_BUILD_HITS: u32 = 13_500;
    for _ in 0..1_000 {
        let _ = env.cas.actioncache_get(&key);
    }

    let started = std::time::Instant::now();
    for _ in 0..ITERATIONS {
        let _ = env.cas.actioncache_get(&key);
    }
    let served = started.elapsed();

    let started = std::time::Instant::now();
    for _ in 0..ITERATIONS {
        let _ = env.cas.contains(id);
    }
    let probe = started.elapsed();

    eprintln!("verified get: {:?}/op", served / ITERATIONS);
    eprintln!("probe alone:  {:?}/op", probe / ITERATIONS);
    eprintln!(
        "at {WARM_BUILD_HITS} hits: {:?} per warm build",
        (served / ITERATIONS) * WARM_BUILD_HITS
    );
}

// --- Fixture -------------------------------------------------------------------

/// The bytes behind `absent_value_digest`, named so a test can make that exact
/// object present later: content addressing means storing them in any store of the
/// same schema yields the same digest.
const ABSENT_VALUE_CONTENT: &[u8] = b"a value that exists only somewhere else";

/// A plugin CAS over a fresh store, wired to a scripted proxy, plus the
/// throwaway store used to mint digests for objects the real store never holds.
struct Fixture {
    cas: PluginCas,
    proxy: FakeProxy,
    _store: TempDir,
    socket_dir: TempDir,
    // Held for the whole test: see `serialize_tests`.
    _serialized: MutexGuard<'static, ()>,
}

impl Fixture {
    /// `None` when Apple's plugin is unavailable (non-macOS, or no Xcode), which
    /// the caller turns into a skip -- there is nothing to wrap and nothing the
    /// assertions would mean.
    fn new(label: &str) -> Option<Self> {
        Self::with_upload(label, false)
    }

    /// The regime the backing check runs in. Uploads on means the machine's own
    /// results reach the remote, which is what makes a remote miss for a key the
    /// local store has an association for mean something.
    fn uploading(label: &str) -> Option<Self> {
        Self::with_upload(label, true)
    }

    fn with_upload(label: &str, upload: bool) -> Option<Self> {
        // Taken BEFORE anything reads the environment, and held for the whole
        // test. `llcas_cas_create` learns its proxy socket from
        // `TUIST_CAS_PROXY_SOCKET`, and cargo runs tests as parallel threads of
        // one process, where a `set_var` racing another thread's `var` is a data
        // race that segfaults rather than misbehaving politely.
        let serialized = serialize_tests();
        if !Path::new(&upstream_path()).exists() {
            eprintln!("skipping {label}: Apple's libToolchainCASPlugin is unavailable");
            return None;
        }
        let store = TempDir::new(label);
        // Sockets live under /tmp, not the store: a unix socket path is capped
        // near 104 bytes and macOS's per-user temp dir is long enough to blow it.
        let socket_dir = TempDir::in_tmp(label);
        let proxy = FakeProxy::listening(&socket_dir.path().join("proxy.sock"));
        std::env::set_var("TUIST_CAS_PROXY_SOCKET", proxy.socket());
        // Publishing is irrelevant to most of these and would spool records into
        // the store on every put; read behaviour is unaffected by it. The tests
        // that exercise the backing check turn it on, because the check is
        // deliberately inert while a build keeps its results off the remote.
        std::env::set_var("TUIST_CAS_UPLOAD", if upload { "true" } else { "false" });
        let cas = PluginCas::open(store.path());
        Some(Self {
            cas,
            proxy,
            _store: store,
            socket_dir,
            _serialized: serialized,
        })
    }

    /// Points `TUIST_CAS_LOG` at a fresh file for the rest of the test. Safe
    /// because `Fixture` serializes tests; the variable is cleared when the
    /// returned handle drops.
    fn capture_log(&self) -> CapturedLog {
        let path = self.socket_dir.path().join("cas.log");
        std::env::set_var("TUIST_CAS_LOG", &path);
        CapturedLog(path)
    }

    /// A digest that is well-formed for the store's hash schema but names an
    /// object this store has never held: minted in a throwaway store that is then
    /// discarded. Content addressing makes the digest valid in both.
    fn absent_value_digest(&self) -> Vec<u8> {
        let elsewhere = TempDir::new("elsewhere");
        let other = PluginCas::open(elsewhere.path());
        let id = other.store_object(ABSENT_VALUE_CONTENT);
        other.digest_of(id)
    }

    /// The defect state: `key -> value` recorded in the store, with the value's
    /// object never stored there.
    fn seed_unbacked_association(&self) -> (Vec<u8>, Vec<u8>) {
        let value_digest = self.absent_value_digest();
        let key = self.cas.key_digest(&value_digest);
        let value_id = self.cas.objectid_for(&value_digest);
        self.cas
            .actioncache_put(&key, value_id)
            .expect("seeding the dangling association");
        (key, value_digest)
    }
}

struct CapturedLog(PathBuf);

impl CapturedLog {
    fn lines_containing(&self, needle: &str) -> usize {
        std::fs::read_to_string(&self.0)
            .unwrap_or_default()
            .lines()
            .filter(|line| line.contains(needle))
            .count()
    }
}

impl Drop for CapturedLog {
    fn drop(&mut self) {
        std::env::remove_var("TUIST_CAS_LOG");
    }
}

// --- The plugin under test -----------------------------------------------------

/// One test at a time. `llcas_cas_create` reads `TUIST_CAS_PROXY_SOCKET` from the
/// environment and cargo runs tests as parallel threads of one process, where a
/// `set_var` racing another thread's `var` is a data race that takes the whole
/// binary down with SIGSEGV. Taken as the first thing each test does, before any
/// environment read, and held until it ends. Poisoning is ignored: a panicking
/// test has already failed and must not cascade into the rest.
fn serialize_tests() -> MutexGuard<'static, ()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(())).lock().unwrap_or_else(|e| e.into_inner())
}

struct PluginCas {
    raw: llcas_cas_t,
}

impl PluginCas {
    fn open(store: &Path) -> Self {
        unsafe {
            let options = tuist_cas_plugin::llcas_cas_options_create();
            tuist_cas_plugin::llcas_cas_options_set_client_version(
                options,
                LLCAS_VERSION_MAJOR,
                LLCAS_VERSION_MINOR,
            );
            let path = CString::new(store.to_str().expect("utf-8 store path")).unwrap();
            tuist_cas_plugin::llcas_cas_options_set_ondisk_path(options, path.as_ptr());
            let mut error: *mut c_char = ptr::null_mut();
            let raw = tuist_cas_plugin::llcas_cas_create(options, &mut error);
            tuist_cas_plugin::llcas_cas_options_dispose(options);
            assert!(!raw.is_null(), "llcas_cas_create: {}", take_error(error));
            Self { raw }
        }
    }

    /// An action key formed the way a real one is: the digest of a small object.
    fn key_digest(&self, material: &[u8]) -> Vec<u8> {
        let mut object = b"cache-key-material:".to_vec();
        object.extend_from_slice(material);
        self.digest_of(self.store_object(&object))
    }

    /// The call the compiler makes when it replays a cached result. This is where
    /// an unbacked value becomes `CAS operation failed: missing object '0~…'` --
    /// NOTFOUND here is fatal on the clang lane.
    fn load(&self, id: llcas_objectid_t) -> llcas_lookup_result_t {
        unsafe {
            let mut loaded = llcas_loaded_object_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let result =
                tuist_cas_plugin::llcas_cas_load_object(self.raw, id, &mut loaded, &mut error);
            assert_ne!(
                result,
                LLCAS_LOOKUP_RESULT_ERROR,
                "llcas_cas_load_object: {}",
                take_error(error)
            );
            result
        }
    }

    fn store_object(&self, data: &[u8]) -> llcas_objectid_t {
        self.store_object_with_refs(data, &[])
    }

    fn store_object_with_refs(
        &self,
        data: &[u8],
        refs: &[llcas_objectid_t],
    ) -> llcas_objectid_t {
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed = tuist_cas_plugin::llcas_cas_store_object(
                self.raw,
                llcas_data_t { data: data.as_ptr() as *const c_void, size: data.len() },
                refs.as_ptr(),
                refs.len(),
                &mut id,
                &mut error,
            );
            assert!(!failed, "llcas_cas_store_object: {}", take_error(error));
            id
        }
    }

    /// Copies the bytes out: the buffer belongs to the CAS handle.
    fn digest_of(&self, id: llcas_objectid_t) -> Vec<u8> {
        unsafe {
            let digest = tuist_cas_plugin::llcas_objectid_get_digest(self.raw, id);
            std::slice::from_raw_parts(digest.data, digest.size).to_vec()
        }
    }

    fn objectid_for(&self, digest: &[u8]) -> llcas_objectid_t {
        unsafe {
            let mut id = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let failed = tuist_cas_plugin::llcas_cas_get_objectid(
                self.raw,
                llcas_digest_t { data: digest.as_ptr(), size: digest.len() },
                &mut id,
                &mut error,
            );
            assert!(!failed, "llcas_cas_get_objectid: {}", take_error(error));
            id
        }
    }

    fn contains(&self, id: llcas_objectid_t) -> llcas_lookup_result_t {
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let result =
                tuist_cas_plugin::llcas_cas_contains_object(self.raw, id, false, &mut error);
            assert_ne!(
                result,
                LLCAS_LOOKUP_RESULT_ERROR,
                "llcas_cas_contains_object: {}",
                take_error(error)
            );
            result
        }
    }

    fn actioncache_put(&self, key: &[u8], value: llcas_objectid_t) -> Result<(), String> {
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let failed = tuist_cas_plugin::llcas_actioncache_put_for_digest(
                self.raw,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                value,
                false,
                &mut error,
            );
            let message = take_error(error);
            if failed {
                Err(message)
            } else {
                assert!(message.is_empty(), "a successful put must not report an error");
                Ok(())
            }
        }
    }

    fn actioncache_get(&self, key: &[u8]) -> (llcas_lookup_result_t, llcas_objectid_t) {
        self.get(key, false)
    }

    fn actioncache_get_globally(&self, key: &[u8]) -> (llcas_lookup_result_t, llcas_objectid_t) {
        self.get(key, true)
    }

    fn get(&self, key: &[u8], globally: bool) -> (llcas_lookup_result_t, llcas_objectid_t) {
        unsafe {
            let mut value = llcas_objectid_t { opaque: 0 };
            let mut error: *mut c_char = ptr::null_mut();
            let result = tuist_cas_plugin::llcas_actioncache_get_for_digest(
                self.raw,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                &mut value,
                globally,
                &mut error,
            );
            assert_ne!(
                result,
                LLCAS_LOOKUP_RESULT_ERROR,
                "llcas_actioncache_get_for_digest: {}",
                take_error(error)
            );
            (result, value)
        }
    }

    fn actioncache_get_without_out_param(&self, key: &[u8]) -> llcas_lookup_result_t {
        unsafe {
            let mut error: *mut c_char = ptr::null_mut();
            let result = tuist_cas_plugin::llcas_actioncache_get_for_digest(
                self.raw,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                ptr::null_mut(),
                false,
                &mut error,
            );
            assert_ne!(
                result,
                LLCAS_LOOKUP_RESULT_ERROR,
                "llcas_actioncache_get_for_digest: {}",
                take_error(error)
            );
            result
        }
    }

    /// Returns the callback's verdict and how many times it fired -- exactly once
    /// is part of the contract, and a build waits forever if it is not.
    fn actioncache_get_async(&self, key: &[u8]) -> (llcas_lookup_result_t, usize) {
        unsafe extern "C" fn callback(
            ctx: *mut c_void,
            result: llcas_lookup_result_t,
            _value: llcas_objectid_t,
            error: *mut c_char,
        ) {
            let slot = &mut *(ctx as *mut AsyncGet);
            slot.result = result;
            slot.calls += 1;
            if !error.is_null() {
                tuist_cas_plugin::llcas_string_dispose(error);
            }
        }

        let mut slot = AsyncGet { result: LLCAS_LOOKUP_RESULT_ERROR, calls: 0 };
        unsafe {
            tuist_cas_plugin::llcas_actioncache_get_for_digest_async(
                self.raw,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                false,
                &mut slot as *mut AsyncGet as *mut c_void,
                callback,
                ptr::null_mut(),
            );
        }
        (slot.result, slot.calls)
    }

    /// Returns the verdict, how many times the callback fired, and any error it
    /// carried.
    fn actioncache_put_async(&self, key: &[u8], value: llcas_objectid_t) -> (bool, usize, String) {
        unsafe extern "C" fn callback(ctx: *mut c_void, failed: bool, error: *mut c_char) {
            let slot = &mut *(ctx as *mut AsyncPut);
            slot.failed = failed;
            slot.calls += 1;
            slot.error = take_error(error);
        }

        let mut slot = AsyncPut { failed: true, calls: 0, error: String::new() };
        unsafe {
            tuist_cas_plugin::llcas_actioncache_put_for_digest_async(
                self.raw,
                llcas_digest_t { data: key.as_ptr(), size: key.len() },
                value,
                false,
                &mut slot as *mut AsyncPut as *mut c_void,
                callback,
                ptr::null_mut(),
            );
        }
        (slot.failed, slot.calls, slot.error)
    }
}

struct AsyncGet {
    result: llcas_lookup_result_t,
    calls: usize,
}

struct AsyncPut {
    failed: bool,
    calls: usize,
    error: String,
}

impl Drop for PluginCas {
    fn drop(&mut self) {
        unsafe { tuist_cas_plugin::llcas_cas_dispose(self.raw) };
    }
}

/// Adopts and frees a string the plugin allocated. Empty when there was none.
fn take_error(error: *mut c_char) -> String {
    if error.is_null() {
        return String::new();
    }
    unsafe {
        let text = CStr::from_ptr(error).to_string_lossy().into_owned();
        tuist_cas_plugin::llcas_string_dispose(error);
        text
    }
}

// --- A scripted proxy ----------------------------------------------------------

/// Answers the plugin's unix-socket requests with whatever the test scripts, and
/// records what it was asked. Without it a fall-through would be
/// indistinguishable from a short-circuit: both end in NOTFOUND.
struct FakeProxy {
    socket: PathBuf,
    seen: Arc<Mutex<Vec<(u8, Vec<u8>)>>>,
    resolve_answer: Arc<Mutex<Option<Vec<u8>>>>,
    backed_answer: Arc<Mutex<(u8, Vec<u8>)>>,
    stopping: Arc<AtomicBool>,
}

impl FakeProxy {
    fn listening(socket: &Path) -> Self {
        let listener = UnixListener::bind(socket).expect("bind fake proxy socket");
        let seen: Arc<Mutex<Vec<(u8, Vec<u8>)>>> = Arc::new(Mutex::new(Vec::new()));
        let resolve_answer: Arc<Mutex<Option<Vec<u8>>>> = Arc::new(Mutex::new(None));
        // A real proxy declines unless it has a snapshot to judge against, and a
        // proxy older than the op answers `bad op` with the same status. Both
        // mean "cannot tell", so that is the default a test opts out of.
        let backed_answer = Arc::new(Mutex::new((STATUS_ERROR, Vec::new())));
        let stopping = Arc::new(AtomicBool::new(false));

        let worker =
            (seen.clone(), resolve_answer.clone(), backed_answer.clone(), stopping.clone());
        std::thread::spawn(move || {
            let (seen, resolve_answer, backed_answer, stopping) = worker;
            for stream in listener.incoming() {
                if stopping.load(Ordering::SeqCst) {
                    return;
                }
                let Ok(mut stream) = stream else { return };
                let Ok(request) = read_request(&mut stream) else { continue };
                seen.lock().unwrap().push((request.op, request.payload.clone()));
                let (status, body) = match request.op {
                    OP_RESOLVE => match resolve_answer.lock().unwrap().clone() {
                        Some(value) => (STATUS_HIT, value),
                        None => (STATUS_MISS, Vec::new()),
                    },
                    OP_BACKED => backed_answer.lock().unwrap().clone(),
                    // This proxy materialises nothing, so it can never produce an
                    // object on demand -- the truthful answer, and the one a real
                    // proxy gives once kura no longer has the blob.
                    OP_FETCH_OBJECT => (STATUS_MISS, Vec::new()),
                    // Everything else (publish, invalidate) is acknowledged.
                    _ => (STATUS_HIT, Vec::new()),
                };
                let _ = write_response(&mut stream, status, &body);
            }
        });

        Self { socket: socket.to_path_buf(), seen, resolve_answer, backed_answer, stopping }
    }

    fn socket(&self) -> &Path {
        &self.socket
    }

    fn answer_resolve_with_miss(&self) {
        *self.resolve_answer.lock().unwrap() = None;
    }

    fn answer_resolve_with_hit(&self, value_digest: &[u8]) {
        *self.resolve_answer.lock().unwrap() = Some(value_digest.to_vec());
    }

    /// The remote holds the key under `value_digest`, so that graph's closure is
    /// producible on demand.
    fn answer_backed_with_yes(&self, value_digest: &[u8]) {
        *self.backed_answer.lock().unwrap() = (STATUS_HIT, value_digest.to_vec());
    }

    /// The remote does not hold the key at all -- the only answer that withholds
    /// a local hit outright.
    fn answer_backed_with_no(&self) {
        *self.backed_answer.lock().unwrap() = (STATUS_MISS, Vec::new());
    }

    fn resolves_for(&self, key: &[u8]) -> usize {
        self.count_of(OP_RESOLVE, key)
    }

    fn backing_checks_for(&self, key: &[u8]) -> usize {
        self.count_of(OP_BACKED, key)
    }

    fn count_of(&self, op: u8, payload: &[u8]) -> usize {
        self.seen
            .lock()
            .unwrap()
            .iter()
            .filter(|(seen_op, seen_payload)| *seen_op == op && seen_payload == payload)
            .count()
    }
}

impl Drop for FakeProxy {
    fn drop(&mut self) {
        self.stopping.store(true, Ordering::SeqCst);
        // Unblock the accept so the thread observes the flag and returns.
        let _ = UnixStream::connect(&self.socket);
        let _ = std::fs::remove_file(&self.socket);
    }
}

// --- Temporary directories -----------------------------------------------------

struct TempDir(PathBuf);

impl TempDir {
    fn new(label: &str) -> Self {
        Self::under(std::env::temp_dir(), label)
    }

    /// `/tmp` rather than the per-user temp dir, for paths that must stay short
    /// (unix sockets).
    fn in_tmp(label: &str) -> Self {
        Self::under(PathBuf::from("/tmp"), label)
    }

    fn under(root: PathBuf, label: &str) -> Self {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let path = root.join(format!(
            "tuist-cas-{label}-{}-{}",
            std::process::id(),
            SEQ.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).expect("create temp dir");
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
