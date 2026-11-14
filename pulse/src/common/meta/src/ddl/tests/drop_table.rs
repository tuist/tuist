// Copyright 2023 Greptime Team
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Modified by Tuist; see pulse/FORK.md.

use std::assert_matches;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::Duration;

use api::v1::region::{RegionRequest, region_request};
use async_trait::async_trait;
use common_catalog::consts::{DEFAULT_CATALOG_NAME, DEFAULT_SCHEMA_NAME};
use common_error::ext::ErrorExt;
use common_error::status_code::StatusCode;
use common_procedure::{Procedure, StringKey};
use common_procedure_test::{
    execute_procedure_until, execute_procedure_until_done, new_test_procedure_context,
};
use store_api::region_engine::RegionRole;
use store_api::storage::RegionId;
use table::metadata::TableId;
use tokio::sync::{Mutex, mpsc};

use crate::ddl::create_logical_tables::CreateLogicalTablesProcedure;
use crate::ddl::drop_table::{DropTableProcedure, DropTableState};
use crate::ddl::test_util::create_table::test_create_table_task;
use crate::ddl::test_util::datanode_handler::{DatanodeWatcher, NaiveDatanodeHandler};
use crate::ddl::test_util::{
    create_logical_table, create_physical_table, create_physical_table_metadata,
    put_datanode_address, test_create_logical_table_task, test_create_physical_table_task,
};
use crate::ddl::{DetectingRegion, RegionFailureDetectorController, TableMetadata};
use crate::key::table_route::TableRouteValue;
use crate::kv_backend::memory::MemoryKvBackend;
use crate::peer::Peer;
use crate::rpc::ddl::DropTableTask;
use crate::rpc::router::{Region, RegionRoute};
use crate::test_util::{MockDatanodeManager, new_ddl_context, new_ddl_context_with_kv_backend};

#[test]
fn test_old_drop_table_json_defaults_to_hard_drop() {
    let mut runtime_context = new_ddl_context(Arc::new(MockDatanodeManager::new(())));
    runtime_context.soft_drop_enabled = true;
    let procedure = DropTableProcedure::new(
        new_drop_table_task("foo", 1024, false),
        runtime_context.clone(),
    );
    let mut old_data: serde_json::Value = serde_json::from_str(&procedure.dump().unwrap()).unwrap();
    old_data
        .as_object_mut()
        .unwrap()
        .remove("soft_drop_enabled");
    old_data.as_object_mut().unwrap().remove("dropped_at");

    let recovered = DropTableProcedure::from_json(&old_data.to_string(), runtime_context).unwrap();
    let recovered_data: serde_json::Value =
        serde_json::from_str(&recovered.dump().unwrap()).unwrap();

    assert_eq!(recovered_data["soft_drop_enabled"], false);
    assert_eq!(recovered_data["dropped_at"], serde_json::Value::Null);
}

#[test]
fn test_drop_table_lock_key_includes_table_name() {
    let context = new_ddl_context(Arc::new(MockDatanodeManager::new(())));
    let procedure = DropTableProcedure::new(new_drop_table_task("foo", 1024, false), context);

    let keys = procedure
        .lock_key()
        .keys_to_lock()
        .cloned()
        .collect::<Vec<_>>();
    assert!(
        keys.iter().any(|key| matches!(
            key,
            StringKey::Exclusive(key) if key == "__table_name_lock/pulse.public.foo"
        )),
        "drop lock keys should include the table name: {keys:?}"
    );
    assert!(
        keys.iter().any(|key| matches!(
            key,
            StringKey::Exclusive(key) if key == "__table_lock/1024"
        )),
        "drop lock keys should include the table id: {keys:?}"
    );
}

#[test]
fn test_new_drop_table_procedure_disables_soft_drop() {
    let mut context = new_ddl_context(Arc::new(MockDatanodeManager::new(())));
    context.soft_drop_enabled = true;

    let procedure = DropTableProcedure::new(new_drop_table_task("foo", 1024, false), context);

    assert!(!procedure.data.soft_drop_enabled);
}

#[tokio::test]
async fn test_disabled_soft_drop_creates_hard_drop_procedure() {
    let node_manager = Arc::new(MockDatanodeManager::new(()));
    let mut context = new_ddl_context(node_manager);
    context.soft_drop_enabled = false;
    context.soft_drop_retention = Some(Duration::from_millis(100));

    let procedure = DropTableProcedure::new(new_drop_table_task("foo", 1024, false), context);

    assert!(!procedure.data.soft_drop_enabled);
    assert_eq!(None, procedure.data.dropped_at);
    assert_eq!(None, procedure.data.retention_expires_at);
}

#[tokio::test]
async fn test_recovered_hard_drop_ignores_soft_runtime_context() {
    let (tx, mut rx) = mpsc::channel(8);
    let node_manager = Arc::new(MockDatanodeManager::new(DatanodeWatcher::new(tx)));
    let kv_backend = Arc::new(MemoryKvBackend::new());
    let hard_context = new_ddl_context_with_kv_backend(node_manager.clone(), kv_backend.clone());
    let table_id = 1024;
    let task = test_create_table_task("foo", table_id);
    hard_context
        .table_metadata_manager
        .create_table_metadata(
            task.table_info,
            TableRouteValue::physical(vec![RegionRoute {
                region: Region::new_test(RegionId::new(table_id, 1)),
                leader_peer: Some(Peer::empty(1)),
                follower_peers: vec![],
                leader_state: None,
                leader_down_since: None,
                write_route_policy: None,
            }]),
            HashMap::new(),
        )
        .await
        .unwrap();
    let procedure = DropTableProcedure::new(
        new_drop_table_task("foo", table_id, false),
        hard_context.clone(),
    );

    let mut soft_context = new_ddl_context_with_kv_backend(node_manager, kv_backend);
    soft_context.soft_drop_enabled = true;
    let mut recovered =
        DropTableProcedure::from_json(&procedure.dump().unwrap(), soft_context).unwrap();
    execute_procedure_until_done(&mut recovered).await;

    assert!(
        hard_context
            .table_metadata_manager
            .get_dropped_table_by_id(table_id)
            .await
            .unwrap()
            .is_none()
    );
    let (_, request) = rx.try_recv().unwrap();
    assert_matches!(request.body, Some(region_request::Body::Drop(_)));
}

#[tokio::test]
async fn test_on_prepare_table_not_exists_err() {
    let node_manager = Arc::new(MockDatanodeManager::new(()));
    let mut ddl_context = new_ddl_context(node_manager);
    ddl_context.soft_drop_enabled = true;
    ddl_context.soft_drop_retention = Some(Duration::from_millis(100));
    let table_name = "foo";
    let table_id = 1024;
    let task = test_create_table_task(table_name, table_id);
    // Puts a value to table name key.
    ddl_context
        .table_metadata_manager
        .create_table_metadata(
            task.table_info.clone(),
            TableRouteValue::physical(vec![]),
            HashMap::new(),
        )
        .await
        .unwrap();

    let task = new_drop_table_task("bar", table_id, false);
    let mut procedure = DropTableProcedure::new(task, ddl_context);
    assert_eq!(procedure.data.dropped_at, None);
    assert_eq!(procedure.data.retention_expires_at, None);
    let err = procedure.on_prepare().await.unwrap_err();
    assert_eq!(err.status_code(), StatusCode::TableNotFound);
    assert_eq!(procedure.data.dropped_at, None);
    assert_eq!(procedure.data.retention_expires_at, None);
}

#[tokio::test]
async fn test_on_prepare_table() {
    let node_manager = Arc::new(MockDatanodeManager::new(()));
    let ddl_context = new_ddl_context(node_manager);
    let table_name = "foo";
    let table_id = 1024;
    let task = test_create_table_task(table_name, table_id);
    // Puts a value to table name key.
    ddl_context
        .table_metadata_manager
        .create_table_metadata(
            task.table_info.clone(),
            TableRouteValue::physical(vec![]),
            HashMap::new(),
        )
        .await
        .unwrap();

    let task = new_drop_table_task("bar", table_id, true);
    // Drop if exists
    let mut procedure = DropTableProcedure::new(task, ddl_context.clone());
    procedure.on_prepare().await.unwrap();
    assert!(!procedure.rollback_supported());

    let task = new_drop_table_task(table_name, table_id, false);
    // Drop table
    let mut procedure = DropTableProcedure::new(task, ddl_context);
    procedure.on_prepare().await.unwrap();
}

#[tokio::test]
async fn test_on_datanode_drop_regions() {
    let (tx, mut rx) = mpsc::channel(8);
    let datanode_handler = DatanodeWatcher::new(tx);
    let node_manager = Arc::new(MockDatanodeManager::new(datanode_handler));
    let ddl_context = new_ddl_context(node_manager);
    let table_id = 1024;
    let table_name = "foo";
    let task = test_create_table_task(table_name, table_id);
    // Puts a value to table name key.
    ddl_context
        .table_metadata_manager
        .create_table_metadata(
            task.table_info.clone(),
            TableRouteValue::physical(vec![
                RegionRoute {
                    region: Region::new_test(RegionId::new(table_id, 1)),
                    leader_peer: Some(Peer::empty(1)),
                    follower_peers: vec![Peer::empty(5)],
                    leader_state: None,
                    leader_down_since: None,
                    write_route_policy: None,
                },
                RegionRoute {
                    region: Region::new_test(RegionId::new(table_id, 2)),
                    leader_peer: Some(Peer::empty(2)),
                    follower_peers: vec![Peer::empty(4)],
                    leader_state: None,
                    leader_down_since: None,
                    write_route_policy: None,
                },
                RegionRoute {
                    region: Region::new_test(RegionId::new(table_id, 3)),
                    leader_peer: Some(Peer::empty(3)),
                    follower_peers: vec![],
                    leader_state: None,
                    leader_down_since: None,
                    write_route_policy: None,
                },
            ]),
            HashMap::new(),
        )
        .await
        .unwrap();

    let task = new_drop_table_task(table_name, table_id, false);
    // Drop table
    let mut procedure = DropTableProcedure::new(task, ddl_context);
    procedure.on_prepare().await.unwrap();
    procedure.on_datanode_drop_regions(false).await.unwrap();

    let check = |peer: Peer,
                 request: RegionRequest,
                 expected_peer_id: u64,
                 expected_region_id: RegionId,
                 follower: bool| {
        assert_eq!(peer.id, expected_peer_id);
        if follower {
            let Some(region_request::Body::Close(req)) = request.body else {
                unreachable!();
            };
            assert_eq!(req.region_id, expected_region_id);
        } else {
            let Some(region_request::Body::Drop(req)) = request.body else {
                unreachable!();
            };
            assert_eq!(req.region_id, expected_region_id);
        };
    };

    let mut results = Vec::new();
    for _ in 0..5 {
        let result = rx.try_recv().unwrap();
        results.push(result);
    }
    results.sort_unstable_by_key(|(a, _)| a.id);

    let (peer, request) = results.remove(0);
    check(peer, request, 1, RegionId::new(table_id, 1), false);
    let (peer, request) = results.remove(0);
    check(peer, request, 2, RegionId::new(table_id, 2), false);
    let (peer, request) = results.remove(0);
    check(peer, request, 3, RegionId::new(table_id, 3), false);
    let (peer, request) = results.remove(0);
    check(peer, request, 4, RegionId::new(table_id, 2), true);
    let (peer, request) = results.remove(0);
    check(peer, request, 5, RegionId::new(table_id, 1), true);
}

#[tokio::test]
async fn test_on_datanode_drop_regions_remaps_addresses_when_retrying() {
    let (tx, mut rx) = mpsc::channel(8);
    let datanode_handler = DatanodeWatcher::new(tx);
    let node_manager = Arc::new(MockDatanodeManager::new(datanode_handler));
    let ddl_context = new_ddl_context(node_manager);
    let table_id = 1024;
    let table_name = "foo";
    let task = test_create_table_task(table_name, table_id);
    ddl_context
        .table_metadata_manager
        .create_table_metadata(
            task.table_info.clone(),
            TableRouteValue::physical(vec![RegionRoute {
                region: Region::new_test(RegionId::new(table_id, 1)),
                leader_peer: Some(Peer::new(1, "old-leader")),
                follower_peers: vec![Peer::new(5, "old-follower")],
                leader_state: None,
                leader_down_since: None,
                write_route_policy: None,
            }]),
            HashMap::new(),
        )
        .await
        .unwrap();

    let task = new_drop_table_task(table_name, table_id, false);
    let mut procedure = DropTableProcedure::new(task, ddl_context.clone());
    procedure.on_prepare().await.unwrap();

    put_datanode_address(&ddl_context, 1, "new-leader").await;
    put_datanode_address(&ddl_context, 5, "new-follower").await;

    procedure.on_datanode_drop_regions(true).await.unwrap();

    let mut peers = Vec::new();
    for _ in 0..2 {
        peers.push(rx.try_recv().unwrap().0);
    }
    peers.sort_unstable_by_key(|p| p.id);
    assert_eq!(peers[0].addr, "new-leader");
    assert_eq!(peers[1].addr, "new-follower");
}

#[tokio::test]
async fn test_hard_drop_keeps_delete_tombstone_flow() {
    let node_manager = Arc::new(MockDatanodeManager::new(NaiveDatanodeHandler));
    let detector_controller = Arc::new(RecordingRegionFailureDetectorController::default());
    let mut ddl_context = new_ddl_context(node_manager);
    ddl_context.region_failure_detector_controller = detector_controller.clone();
    let table_id = 1024;
    let table_name = "foo";
    let task = test_create_table_task(table_name, table_id);
    ddl_context
        .table_metadata_manager
        .create_table_metadata(
            task.table_info.clone(),
            TableRouteValue::physical(vec![RegionRoute {
                region: Region::new_test(RegionId::new(table_id, 1)),
                leader_peer: Some(Peer::empty(1)),
                follower_peers: vec![],
                leader_state: None,
                leader_down_since: None,
                write_route_policy: None,
            }]),
            HashMap::new(),
        )
        .await
        .unwrap();

    let task = new_drop_table_task(table_name, table_id, false);
    let mut procedure = DropTableProcedure::new(task, ddl_context.clone());

    execute_procedure_until(&mut procedure, |p| {
        p.data.state == DropTableState::DeleteTombstone
    })
    .await;

    assert_eq!(procedure.data.state, DropTableState::DeleteTombstone);

    execute_procedure_until_done(&mut procedure).await;

    let dropped_table = ddl_context
        .table_metadata_manager
        .get_dropped_table(&procedure.data.task.table_name())
        .await
        .unwrap();
    assert!(dropped_table.is_none());
    assert_eq!(
        detector_controller.deregistered().await,
        vec![(1, RegionId::new(table_id, 1))]
    );
}

#[tokio::test]
async fn test_hard_drop_recreated_table_ignores_previous_orphan_tombstone() {
    let node_manager = Arc::new(MockDatanodeManager::new(NaiveDatanodeHandler));
    let ddl_context = new_ddl_context(node_manager);
    let original_table_id = 1024;
    let recreated_table_id = 1025;
    let table_name = "foo";
    let task = test_create_table_task(table_name, original_table_id);
    ddl_context
        .table_metadata_manager
        .create_table_metadata(
            task.table_info.clone(),
            TableRouteValue::physical(vec![]),
            HashMap::new(),
        )
        .await
        .unwrap();

    let drop_task = new_drop_table_task(table_name, original_table_id, false);
    let mut drop_procedure = DropTableProcedure::new(drop_task, ddl_context.clone());
    execute_procedure_until(&mut drop_procedure, |p| {
        p.data.state == DropTableState::DeleteTombstone
    })
    .await;

    ddl_context
        .table_metadata_manager
        .create_table_metadata(
            test_create_table_task(table_name, recreated_table_id).table_info,
            TableRouteValue::physical(vec![]),
            HashMap::new(),
        )
        .await
        .unwrap();

    let mut procedure = DropTableProcedure::new(
        new_drop_table_task(table_name, recreated_table_id, false),
        ddl_context,
    );

    procedure.on_prepare().await.unwrap();
}

#[tokio::test]
async fn test_on_rollback() {
    let node_manager = Arc::new(MockDatanodeManager::new(NaiveDatanodeHandler));
    let kv_backend = Arc::new(MemoryKvBackend::new());
    let mut ddl_context = new_ddl_context_with_kv_backend(node_manager, kv_backend.clone());
    // Prepares physical table metadata.
    let mut create_physical_table_task = test_create_physical_table_task("phy_table");
    let TableMetadata {
        table_id,
        table_route,
        ..
    } = ddl_context
        .table_metadata_allocator
        .create(&create_physical_table_task)
        .await
        .unwrap();
    create_physical_table_task.set_table_id(table_id);
    create_physical_table_metadata(
        &ddl_context,
        create_physical_table_task.table_info.clone(),
        TableRouteValue::Physical(table_route),
    )
    .await;
    // The create logical table procedure.
    let physical_table_id = table_id;
    // Creates the logical table metadata.
    let task = test_create_logical_table_task("foo");
    let mut procedure =
        CreateLogicalTablesProcedure::new(vec![task], physical_table_id, ddl_context.clone());
    procedure.on_prepare().await.unwrap();
    let ctx = new_test_procedure_context();
    procedure.execute(&ctx).await.unwrap();
    // Triggers procedure to create table metadata
    let status = procedure.execute(&ctx).await.unwrap();
    let table_ids = status.downcast_output_ref::<Vec<u32>>().unwrap();
    assert_eq!(*table_ids, vec![1025]);

    let expected_kvs = kv_backend.dump();
    // Drops the physical table
    {
        let task = new_drop_table_task("phy_table", physical_table_id, false);
        let mut procedure = DropTableProcedure::new(task, ddl_context.clone());
        procedure.on_prepare().await.unwrap();
        assert!(procedure.rollback_supported());
        procedure.on_delete_metadata().await.unwrap();
        assert!(procedure.rollback_supported());
        procedure.rollback(&ctx).await.unwrap();
        assert!(procedure.dropping_regions.is_empty());
        assert_eq!(ddl_context.memory_region_keeper.len(), 0);

        // The physical table can be dropped again after the metadata rollback.
        let retry_task = new_drop_table_task("phy_table", physical_table_id, false);
        let mut retry = DropTableProcedure::new(retry_task, ddl_context.clone());
        retry.on_prepare().await.unwrap();
        retry.on_delete_metadata().await.unwrap();
        retry.rollback(&ctx).await.unwrap();
        assert!(retry.dropping_regions.is_empty());
        assert_eq!(ddl_context.memory_region_keeper.len(), 0);

        // Rollback again
        assert!(procedure.rollback_supported());
        procedure.rollback(&ctx).await.unwrap();
        let kvs = kv_backend.dump();
        assert_eq!(kvs, expected_kvs);
    }

    // Drops the logical table
    ddl_context.soft_drop_enabled = false;
    let task = new_drop_table_task("foo", table_ids[0], false);
    let mut procedure = DropTableProcedure::new(task, ddl_context.clone());
    procedure.on_prepare().await.unwrap();
    assert!(!procedure.rollback_supported());
}

fn new_drop_table_task(table_name: &str, table_id: TableId, drop_if_exists: bool) -> DropTableTask {
    DropTableTask {
        catalog: DEFAULT_CATALOG_NAME.to_string(),
        schema: DEFAULT_SCHEMA_NAME.to_string(),
        table: table_name.to_string(),
        table_id,
        drop_if_exists,
    }
}

#[derive(Default)]
struct RecordingRegionFailureDetectorController {
    registered: Mutex<Vec<DetectingRegion>>,
    deregistered: Mutex<Vec<DetectingRegion>>,
}

impl RecordingRegionFailureDetectorController {
    async fn deregistered(&self) -> Vec<DetectingRegion> {
        self.deregistered.lock().await.clone()
    }
}

#[async_trait]
impl RegionFailureDetectorController for RecordingRegionFailureDetectorController {
    async fn register_failure_detectors(&self, detecting_regions: Vec<DetectingRegion>) {
        self.registered.lock().await.extend(detecting_regions);
    }

    async fn reset_failure_detectors(&self, detecting_regions: Vec<DetectingRegion>) {
        self.registered.lock().await.extend(detecting_regions);
    }

    async fn deregister_failure_detectors(&self, detecting_regions: Vec<DetectingRegion>) {
        self.deregistered.lock().await.extend(detecting_regions);
    }
}

#[tokio::test]
async fn test_memory_region_keeper_guard_dropped_on_procedure_done() {
    let node_manager = Arc::new(MockDatanodeManager::new(NaiveDatanodeHandler));
    let kv_backend = Arc::new(MemoryKvBackend::new());
    let ddl_context = new_ddl_context_with_kv_backend(node_manager, kv_backend);

    let physical_table_id = create_physical_table(&ddl_context, "t").await;
    let logical_table_id = create_logical_table(ddl_context.clone(), physical_table_id, "s").await;

    let inner_test = |task: DropTableTask| async {
        let mut procedure = DropTableProcedure::new(task, ddl_context.clone());
        execute_procedure_until(&mut procedure, |p| {
            p.data.state == DropTableState::InvalidateTableCache
        })
        .await;

        // Ensure that after running to the state `InvalidateTableCache`(just past `DeleteMetadata`),
        // the dropping regions should be recorded:
        let guards = &procedure.dropping_regions;
        assert_eq!(guards.len(), 1);
        let (datanode_id, region_id) = (0, RegionId::new(physical_table_id, 0));
        assert_eq!(guards[0].info(), (datanode_id, region_id));
        assert!(
            ddl_context
                .memory_region_keeper
                .contains(datanode_id, region_id)
        );
        let roles = ddl_context
            .memory_region_keeper
            .extract_operating_region_roles(datanode_id, &HashSet::from([region_id]));
        assert_eq!(roles.get(&region_id), Some(&RegionRole::Leader));

        execute_procedure_until_done(&mut procedure).await;

        // Ensure that when run to the end, the dropping regions should be cleared:
        let guards = &procedure.dropping_regions;
        assert!(guards.is_empty());
        assert!(
            !ddl_context
                .memory_region_keeper
                .contains(datanode_id, region_id)
        );
    };

    inner_test(new_drop_table_task("s", logical_table_id, false)).await;
    inner_test(new_drop_table_task("t", physical_table_id, false)).await;
}

#[tokio::test]
async fn test_from_json() {
    for (state, num_operating_regions, num_operating_regions_after_recovery) in [
        (DropTableState::DeleteMetadata, 0, 1),
        (DropTableState::InvalidateTableCache, 1, 1),
        (DropTableState::DatanodeDropRegions, 1, 1),
        (DropTableState::DeleteTombstone, 1, 0),
    ] {
        let node_manager = Arc::new(MockDatanodeManager::new(NaiveDatanodeHandler));
        let kv_backend = Arc::new(MemoryKvBackend::new());
        let ddl_context = new_ddl_context_with_kv_backend(node_manager, kv_backend);

        let physical_table_id = create_physical_table(&ddl_context, "t").await;
        let task = new_drop_table_task("t", physical_table_id, false);
        let mut procedure = DropTableProcedure::new(task, ddl_context.clone());
        execute_procedure_until(&mut procedure, |p| p.data.state == state).await;
        let data = procedure.dump().unwrap();
        assert_eq!(
            ddl_context.memory_region_keeper.len(),
            num_operating_regions
        );
        // Cleans up the keeper.
        ddl_context.memory_region_keeper.clear();
        let mut procedure = DropTableProcedure::from_json(&data, ddl_context.clone()).unwrap();
        procedure.recover().unwrap();
        assert_eq!(
            ddl_context.memory_region_keeper.len(),
            num_operating_regions_after_recovery
        );
        assert_eq!(
            procedure.dropping_regions.len(),
            num_operating_regions_after_recovery
        );
    }

    let num_operating_regions = 0;
    let num_operating_regions_after_recovery = 0;
    let node_manager = Arc::new(MockDatanodeManager::new(NaiveDatanodeHandler));
    let kv_backend = Arc::new(MemoryKvBackend::new());
    let ddl_context = new_ddl_context_with_kv_backend(node_manager, kv_backend);

    let physical_table_id = create_physical_table(&ddl_context, "t").await;
    let task = new_drop_table_task("t", physical_table_id, false);
    let mut procedure = DropTableProcedure::new(task, ddl_context.clone());
    execute_procedure_until_done(&mut procedure).await;
    let data = procedure.dump().unwrap();
    assert_eq!(
        ddl_context.memory_region_keeper.len(),
        num_operating_regions
    );
    // Cleans up the keeper.
    ddl_context.memory_region_keeper.clear();
    let mut procedure = DropTableProcedure::from_json(&data, ddl_context.clone()).unwrap();
    procedure.recover().unwrap();
    assert_eq!(
        ddl_context.memory_region_keeper.len(),
        num_operating_regions_after_recovery
    );
    assert_eq!(
        procedure.dropping_regions.len(),
        num_operating_regions_after_recovery
    );
}
