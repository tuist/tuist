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

use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use async_trait::async_trait;
use common_pulse_telemetry::{
    Collector, Mode as VersionReporterMode, PulseTelemetry, PulseTelemetryTask, TELEMETRY_INTERVAL,
    default_get_uuid,
};

struct StandalonePulseTelemetryCollector {
    uuid: Option<String>,
    retry: i32,
}
#[async_trait]
impl Collector for StandalonePulseTelemetryCollector {
    fn get_mode(&self) -> VersionReporterMode {
        VersionReporterMode::Standalone
    }

    async fn get_nodes(&self) -> Option<i32> {
        Some(1)
    }

    fn get_retry(&self) -> i32 {
        self.retry
    }

    fn inc_retry(&mut self) {
        self.retry += 1;
    }

    fn set_uuid_cache(&mut self, uuid: String) {
        self.uuid = Some(uuid);
    }

    fn get_uuid_cache(&self) -> Option<String> {
        self.uuid.clone()
    }
}

pub async fn get_pulse_telemetry_task(
    working_home: Option<String>,
    enable: bool,
) -> Arc<PulseTelemetryTask> {
    if !enable || cfg!(test) || cfg!(debug_assertions) {
        return Arc::new(PulseTelemetryTask::disable());
    }
    // Always enable.
    let should_report = Arc::new(AtomicBool::new(true));

    let uuid = default_get_uuid(&working_home);
    Arc::new(PulseTelemetryTask::enable(
        TELEMETRY_INTERVAL,
        Box::new(PulseTelemetry::new(
            working_home,
            Box::new(StandalonePulseTelemetryCollector { uuid, retry: 0 }),
            should_report.clone(),
        )),
        should_report,
    ))
}
