use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{BufRead, BufReader, Read, Seek},
    path::{Component, Path, PathBuf},
    sync::Arc,
    time::{Duration, Instant},
};

use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
};
use globset::{GlobBuilder, GlobMatcher};
use grep_regex::RegexMatcherBuilder;
use grep_searcher::{BinaryDetection, SearcherBuilder, sinks};
use ignore::WalkBuilder;
use percent_encoding::{AsciiSet, CONTROLS, utf8_percent_encode};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::{sync::Semaphore, task::JoinError, time::timeout};
use tracing::warn;

const SOURCE_PATH_SEGMENT: &AsciiSet = &CONTROLS
    .add(b' ')
    .add(b'"')
    .add(b'#')
    .add(b'%')
    .add(b'/')
    .add(b'<')
    .add(b'>')
    .add(b'?')
    .add(b'`')
    .add(b'{')
    .add(b'}');

#[derive(Clone, Debug)]
pub struct Limits {
    pub max_concurrent_operations: usize,
    pub max_request_body_bytes: usize,
    pub operation_timeout: Duration,
    pub max_pattern_bytes: usize,
    pub max_path_bytes: usize,
    pub max_glob_bytes: usize,
    pub max_traversal_depth: usize,
    pub max_files_scanned: usize,
    pub max_search_bytes: u64,
    pub max_search_file_bytes: u64,
    pub max_context_bytes: u64,
    pub max_search_results: usize,
    pub max_context_lines: usize,
    pub max_list_results: usize,
    pub max_entries_visited: usize,
    pub max_read_file_bytes: u64,
    pub max_read_lines: usize,
    pub max_returned_text_bytes: usize,
    pub max_line_bytes: usize,
    pub regex_program_bytes: usize,
    pub regex_cache_bytes: usize,
    pub regex_nesting: u32,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            max_concurrent_operations: 4,
            max_request_body_bytes: 16 * 1024,
            operation_timeout: Duration::from_secs(4),
            max_pattern_bytes: 512,
            max_path_bytes: 512,
            max_glob_bytes: 256,
            max_traversal_depth: 32,
            max_files_scanned: 20_000,
            max_search_bytes: 128 * 1024 * 1024,
            max_search_file_bytes: 2 * 1024 * 1024,
            max_context_bytes: 16 * 1024 * 1024,
            max_search_results: 50,
            max_context_lines: 3,
            max_list_results: 500,
            max_entries_visited: 10_000,
            max_read_file_bytes: 4 * 1024 * 1024,
            max_read_lines: 400,
            max_returned_text_bytes: 128 * 1024,
            max_line_bytes: 2 * 1024,
            regex_program_bytes: 1024 * 1024,
            regex_cache_bytes: 2 * 1024 * 1024,
            regex_nesting: 64,
        }
    }
}

#[derive(Debug, Error)]
pub enum CodebaseError {
    #[error("{0}")]
    InvalidRequest(String),
    #[error("path was not found: {0}")]
    NotFound(String),
    #[error("the requested path is outside the repository")]
    OutsideRepository,
    #[error("the requested path is not a text file")]
    NotText,
    #[error("the service is busy; retry later")]
    Busy,
    #[error("the operation exceeded its time limit")]
    TimedOut,
    #[error("the operation failed")]
    Internal,
}

impl CodebaseError {
    fn invalid(message: impl Into<String>) -> Self {
        Self::InvalidRequest(message.into())
    }

    fn code(&self) -> &'static str {
        match self {
            Self::InvalidRequest(_) => "invalid_request",
            Self::NotFound(_) => "not_found",
            Self::OutsideRepository => "outside_repository",
            Self::NotText => "not_text",
            Self::Busy => "busy",
            Self::TimedOut => "timed_out",
            Self::Internal => "internal",
        }
    }

    fn status(&self) -> StatusCode {
        match self {
            Self::InvalidRequest(_) | Self::OutsideRepository | Self::NotText => {
                StatusCode::BAD_REQUEST
            }
            Self::NotFound(_) => StatusCode::NOT_FOUND,
            Self::Busy => StatusCode::TOO_MANY_REQUESTS,
            Self::TimedOut => StatusCode::GATEWAY_TIMEOUT,
            Self::Internal => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

#[derive(Serialize)]
struct ErrorBody<'a> {
    code: &'a str,
    error: String,
}

impl IntoResponse for CodebaseError {
    fn into_response(self) -> Response {
        let status = self.status();
        let body = ErrorBody {
            code: self.code(),
            error: self.to_string(),
        };
        (status, Json(body)).into_response()
    }
}

#[derive(Clone, Debug)]
pub struct Codebase {
    root: PathBuf,
    revision: String,
    repository_url: String,
    limits: Limits,
}

impl Codebase {
    pub fn new(
        root: PathBuf,
        revision: String,
        repository_url: String,
        limits: Limits,
    ) -> Result<Self, CodebaseError> {
        let root = root
            .canonicalize()
            .map_err(|_| CodebaseError::NotFound("repository root".into()))?;
        if !root.is_dir() {
            return Err(CodebaseError::invalid(
                "repository root must be a directory",
            ));
        }
        let revision = revision.trim();
        if revision.len() != 40
            || !revision
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
        {
            return Err(CodebaseError::invalid(
                "repository revision must be a full lowercase commit hash",
            ));
        }
        if !repository_url.starts_with("https://") {
            return Err(CodebaseError::invalid(
                "repository address must start with https://",
            ));
        }

        Ok(Self {
            root,
            revision: revision.to_string(),
            repository_url: repository_url.trim_end_matches('/').to_string(),
            limits,
        })
    }

    pub fn search(&self, request: SearchRequest) -> Result<SearchResponse, CodebaseError> {
        request.validate(&self.limits)?;
        let started = Instant::now();
        let deadline = started + self.limits.operation_timeout;
        let start_path = self.resolve(&request.path)?;
        let requested_results = request.max_results.unwrap_or(20);
        let context_lines = request.context_lines.unwrap_or(2);
        let glob = request.file_glob.as_deref().map(build_glob).transpose()?;

        let mut matcher_builder = RegexMatcherBuilder::new();
        matcher_builder
            .case_insensitive(!request.case_sensitive)
            .fixed_strings(!request.use_regular_expression)
            .size_limit(self.limits.regex_program_bytes)
            .dfa_size_limit(self.limits.regex_cache_bytes)
            .nest_limit(self.limits.regex_nesting);
        let matcher = matcher_builder
            .build(&request.pattern)
            .map_err(|error| CodebaseError::invalid(format!("invalid search pattern: {error}")))?;

        let mut searcher = SearcherBuilder::new()
            .line_number(true)
            .heap_limit(Some(self.limits.max_search_file_bytes as usize))
            .binary_detection(BinaryDetection::quit(b'\x00'))
            .build();
        let mut matches = Vec::new();
        let mut stats = SearchStats::default();
        let mut returned_text_bytes = 0usize;
        let mut truncation_reason = None;

        let mut walker = WalkBuilder::new(start_path);
        walker
            .hidden(false)
            .require_git(false)
            .follow_links(false)
            .max_depth(Some(self.limits.max_traversal_depth));

        for entry in walker.build() {
            if Instant::now() >= deadline {
                truncation_reason = Some("time_limit".to_string());
                break;
            }

            let entry = match entry {
                Ok(entry) => entry,
                Err(_) => {
                    stats.walk_errors += 1;
                    continue;
                }
            };
            let Some(file_type) = entry.file_type() else {
                continue;
            };
            if !file_type.is_file() {
                continue;
            }

            let relative = self.relative_path(entry.path())?;
            if glob.as_ref().is_some_and(|glob| !glob.is_match(&relative)) {
                continue;
            }

            if stats.files_scanned >= self.limits.max_files_scanned {
                truncation_reason = Some("file_limit".to_string());
                break;
            }

            let metadata = match entry.metadata() {
                Ok(metadata) => metadata,
                Err(_) => {
                    stats.file_errors += 1;
                    continue;
                }
            };
            let file_bytes = metadata.len();
            if file_bytes > self.limits.max_search_file_bytes {
                stats.files_skipped_too_large += 1;
                continue;
            }
            if stats.bytes_scanned.saturating_add(file_bytes) > self.limits.max_search_bytes {
                truncation_reason = Some("byte_limit".to_string());
                break;
            }

            stats.files_scanned += 1;
            stats.bytes_scanned += file_bytes;
            let path = path_to_string(&relative);
            let source_url = self.source_url(&relative, SourceKind::File);
            let result = searcher.search_path(
                &matcher,
                entry.path(),
                sinks::Lossy(|line_number, line| {
                    if matches.len() >= requested_results {
                        truncation_reason = Some("match_limit".to_string());
                        return Ok(false);
                    }

                    let line = bounded_line(line, self.limits.max_line_bytes);
                    let url = format!("{source_url}#L{line_number}");
                    let match_bytes = line
                        .len()
                        .saturating_add(path.len())
                        .saturating_add(url.len());
                    if returned_text_bytes.saturating_add(match_bytes)
                        > self.limits.max_returned_text_bytes
                    {
                        truncation_reason = Some("output_limit".to_string());
                        return Ok(false);
                    }

                    returned_text_bytes += match_bytes;
                    matches.push(SearchMatch {
                        path: path.clone(),
                        line_number,
                        line,
                        context_before: Vec::new(),
                        context_after: Vec::new(),
                        url,
                    });
                    Ok(true)
                }),
            );
            if result.is_err() {
                stats.file_errors += 1;
            }
            if truncation_reason.is_some() {
                break;
            }
        }

        if context_lines > 0 && !matches.is_empty() {
            self.add_context(
                &mut matches,
                context_lines,
                &mut returned_text_bytes,
                &mut stats,
                &mut truncation_reason,
                deadline,
            )?;
        }

        if truncation_reason.is_none() && stats.files_skipped_too_large > 0 {
            truncation_reason = Some("large_files_skipped".to_string());
        }
        if truncation_reason.is_none() && stats.walk_errors > 0 {
            truncation_reason = Some("walk_errors".to_string());
        }

        matches.sort_by(|left, right| {
            left.path
                .cmp(&right.path)
                .then(left.line_number.cmp(&right.line_number))
        });
        stats.elapsed_milliseconds = elapsed_milliseconds(started);

        Ok(SearchResponse {
            revision: self.revision.clone(),
            query: request.pattern,
            matches,
            truncated: truncation_reason.is_some(),
            truncation_reason,
            stats,
        })
    }

    pub fn list_files(
        &self,
        request: ListFilesRequest,
    ) -> Result<ListFilesResponse, CodebaseError> {
        request.validate(&self.limits)?;
        let started = Instant::now();
        let deadline = started + self.limits.operation_timeout;
        let start_path = self.resolve(&request.path)?;
        let requested_results = request.max_results.unwrap_or(100);
        let requested_depth = request.depth.unwrap_or(2);
        let glob = request.file_glob.as_deref().map(build_glob).transpose()?;
        let mut entries = Vec::new();
        let mut stats = ListStats::default();
        let mut returned_text_bytes = 0usize;
        let mut truncation_reason = None;

        let mut walker = WalkBuilder::new(start_path);
        walker
            .hidden(false)
            .require_git(false)
            .follow_links(false)
            .max_depth(Some(requested_depth));

        for entry in walker.build() {
            if Instant::now() >= deadline {
                truncation_reason = Some("time_limit".to_string());
                break;
            }
            if stats.entries_visited >= self.limits.max_entries_visited {
                truncation_reason = Some("entry_limit".to_string());
                break;
            }
            stats.entries_visited += 1;

            let entry = match entry {
                Ok(entry) => entry,
                Err(_) => {
                    stats.walk_errors += 1;
                    continue;
                }
            };
            if entry.depth() == 0 {
                continue;
            }
            let relative = self.relative_path(entry.path())?;
            if glob.as_ref().is_some_and(|glob| !glob.is_match(&relative)) {
                continue;
            }
            if entries.len() >= requested_results {
                truncation_reason = Some("result_limit".to_string());
                break;
            }

            let Some(file_type) = entry.file_type() else {
                continue;
            };
            let entry_type = if file_type.is_dir() {
                EntryType::Directory
            } else if file_type.is_file() {
                EntryType::File
            } else if file_type.is_symlink() {
                EntryType::Symlink
            } else {
                continue;
            };
            let source_kind = if entry_type == EntryType::Directory {
                SourceKind::Directory
            } else {
                SourceKind::File
            };
            let path = path_to_string(&relative);
            let url = self.source_url(&relative, source_kind);
            let entry_bytes = path.len().saturating_add(url.len());
            if returned_text_bytes.saturating_add(entry_bytes) > self.limits.max_returned_text_bytes
            {
                truncation_reason = Some("output_limit".to_string());
                break;
            }
            returned_text_bytes += entry_bytes;
            entries.push(FileEntry {
                path,
                entry_type,
                url,
            });
        }

        if truncation_reason.is_none() && stats.walk_errors > 0 {
            truncation_reason = Some("walk_errors".to_string());
        }
        entries.sort_by(|left, right| left.path.cmp(&right.path));
        stats.elapsed_milliseconds = elapsed_milliseconds(started);

        Ok(ListFilesResponse {
            revision: self.revision.clone(),
            entries,
            truncated: truncation_reason.is_some(),
            truncation_reason,
            stats,
        })
    }

    pub fn read_file(&self, request: ReadFileRequest) -> Result<ReadFileResponse, CodebaseError> {
        request.validate(&self.limits)?;
        let started = Instant::now();
        let resolved = self.resolve(&request.path)?;
        let metadata =
            fs::metadata(&resolved).map_err(|_| CodebaseError::NotFound(request.path.clone()))?;
        if !metadata.is_file() {
            return Err(CodebaseError::invalid("path must identify a file"));
        }
        if metadata.len() > self.limits.max_read_file_bytes {
            return Err(CodebaseError::invalid(format!(
                "file exceeds the {} byte read limit",
                self.limits.max_read_file_bytes
            )));
        }

        let mut file = File::open(&resolved).map_err(|_| CodebaseError::Internal)?;
        let mut prefix = [0u8; 8 * 1024];
        let prefix_length = file
            .read(&mut prefix)
            .map_err(|_| CodebaseError::Internal)?;
        if prefix[..prefix_length].contains(&b'\x00') {
            return Err(CodebaseError::NotText);
        }
        file.rewind().map_err(|_| CodebaseError::Internal)?;

        let start_line = request.start_line.unwrap_or(1);
        let max_lines = request.max_lines.unwrap_or(200);
        let mut reader = BufReader::new(file.take(self.limits.max_read_file_bytes + 1));
        let mut buffer = Vec::new();
        let mut current_line = 0usize;
        let mut lines = Vec::new();
        let mut returned_text_bytes = 0usize;
        let mut has_more = false;
        let mut output_limited = false;

        loop {
            if Instant::now().duration_since(started) >= self.limits.operation_timeout {
                return Err(CodebaseError::TimedOut);
            }
            buffer.clear();
            let bytes_read = reader
                .read_until(b'\n', &mut buffer)
                .map_err(|_| CodebaseError::Internal)?;
            if bytes_read == 0 {
                break;
            }
            current_line += 1;
            if current_line < start_line {
                continue;
            }
            if lines.len() >= max_lines {
                has_more = true;
                break;
            }

            let text = bounded_bytes_line(&buffer, self.limits.max_line_bytes);
            if returned_text_bytes.saturating_add(text.len()) > self.limits.max_returned_text_bytes
            {
                has_more = true;
                output_limited = true;
                break;
            }
            returned_text_bytes += text.len();
            lines.push(SourceLine {
                number: current_line,
                text,
            });
        }

        let end_line = lines
            .last()
            .map(|line| line.number)
            .unwrap_or(start_line.saturating_sub(1));
        let next_start_line = has_more.then_some(end_line.saturating_add(1).max(start_line));
        let relative = self.relative_path(&resolved)?;
        let mut url = self.source_url(&relative, SourceKind::File);
        if !lines.is_empty() {
            url.push_str(&format!("#L{start_line}-L{end_line}"));
        }

        Ok(ReadFileResponse {
            revision: self.revision.clone(),
            path: path_to_string(&relative),
            start_line,
            end_line,
            lines,
            file_size_bytes: metadata.len(),
            truncated: has_more,
            truncation_reason: if output_limited {
                Some("output_limit".to_string())
            } else if has_more {
                Some("line_limit".to_string())
            } else {
                None
            },
            next_start_line,
            url,
            elapsed_milliseconds: elapsed_milliseconds(started),
        })
    }

    fn add_context(
        &self,
        matches: &mut [SearchMatch],
        context_lines: usize,
        returned_text_bytes: &mut usize,
        stats: &mut SearchStats,
        truncation_reason: &mut Option<String>,
        deadline: Instant,
    ) -> Result<(), CodebaseError> {
        let mut matches_by_path = BTreeMap::<String, Vec<usize>>::new();
        for (index, search_match) in matches.iter().enumerate() {
            matches_by_path
                .entry(search_match.path.clone())
                .or_default()
                .push(index);
        }

        for (path, indices) in matches_by_path {
            if Instant::now() >= deadline {
                truncation_reason.get_or_insert_with(|| "time_limit".to_string());
                break;
            }
            let resolved = self.resolve(&path)?;
            let file_bytes = fs::metadata(&resolved)
                .map_err(|_| CodebaseError::Internal)?
                .len();
            if stats.context_bytes_read.saturating_add(file_bytes) > self.limits.max_context_bytes {
                stats.contexts_skipped += indices.len();
                truncation_reason.get_or_insert_with(|| "context_byte_limit".to_string());
                continue;
            }

            let bytes = fs::read(resolved).map_err(|_| CodebaseError::Internal)?;
            stats.context_bytes_read += bytes.len() as u64;
            let source_lines: Vec<&[u8]> = bytes.split(|byte| *byte == b'\n').collect();

            for index in indices {
                let line_index = matches[index].line_number.saturating_sub(1) as usize;
                if line_index >= source_lines.len() {
                    stats.contexts_skipped += 1;
                    continue;
                }
                let before_start = line_index.saturating_sub(context_lines);
                let after_end = (line_index + context_lines + 1).min(source_lines.len());
                let before = &source_lines[before_start..line_index];
                let after = &source_lines[(line_index + 1).min(source_lines.len())..after_end];

                if !append_context(
                    &mut matches[index].context_before,
                    before,
                    returned_text_bytes,
                    &self.limits,
                ) || !append_context(
                    &mut matches[index].context_after,
                    after,
                    returned_text_bytes,
                    &self.limits,
                ) {
                    stats.contexts_skipped += 1;
                    truncation_reason.get_or_insert_with(|| "output_limit".to_string());
                }
            }
        }

        Ok(())
    }

    fn resolve(&self, requested: &str) -> Result<PathBuf, CodebaseError> {
        if requested.len() > self.limits.max_path_bytes {
            return Err(CodebaseError::invalid("path is too long"));
        }
        let relative = normalize_relative(requested)?;
        let joined = self.root.join(relative);
        let canonical = joined
            .canonicalize()
            .map_err(|_| CodebaseError::NotFound(requested.to_string()))?;
        if !canonical.starts_with(&self.root) {
            return Err(CodebaseError::OutsideRepository);
        }
        Ok(canonical)
    }

    fn relative_path(&self, path: &Path) -> Result<PathBuf, CodebaseError> {
        path.strip_prefix(&self.root)
            .map(Path::to_path_buf)
            .map_err(|_| CodebaseError::OutsideRepository)
    }

    fn source_url(&self, relative: &Path, kind: SourceKind) -> String {
        let revision = encode_segment(&self.revision);
        let path = relative
            .components()
            .filter_map(|component| match component {
                Component::Normal(value) => Some(encode_segment(&value.to_string_lossy())),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join("/");
        let route = match kind {
            SourceKind::File => "blob",
            SourceKind::Directory => "tree",
        };
        if path.is_empty() {
            format!("{}/{route}/{revision}", self.repository_url)
        } else {
            format!("{}/{route}/{revision}/{path}", self.repository_url)
        }
    }
}

#[derive(Clone)]
pub struct AppState {
    codebase: Arc<Codebase>,
    operations: Arc<Semaphore>,
}

impl AppState {
    pub fn new(codebase: Arc<Codebase>) -> Self {
        Self {
            operations: Arc::new(Semaphore::new(codebase.limits.max_concurrent_operations)),
            codebase,
        }
    }
}

pub fn router(state: AppState) -> Router {
    let body_limit = state.codebase.limits.max_request_body_bytes;
    Router::new()
        .route("/health", get(health))
        .route("/v1/search", post(search_handler))
        .route("/v1/files", post(list_files_handler))
        .route("/v1/file", post(read_file_handler))
        .layer(DefaultBodyLimit::max(body_limit))
        .with_state(state)
}

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        revision: state.codebase.revision.clone(),
    })
}

async fn search_handler(
    State(state): State<AppState>,
    Json(request): Json<SearchRequest>,
) -> Result<Json<SearchResponse>, CodebaseError> {
    run_bounded(state, move |codebase| codebase.search(request))
        .await
        .map(Json)
}

async fn list_files_handler(
    State(state): State<AppState>,
    Json(request): Json<ListFilesRequest>,
) -> Result<Json<ListFilesResponse>, CodebaseError> {
    run_bounded(state, move |codebase| codebase.list_files(request))
        .await
        .map(Json)
}

async fn read_file_handler(
    State(state): State<AppState>,
    Json(request): Json<ReadFileRequest>,
) -> Result<Json<ReadFileResponse>, CodebaseError> {
    run_bounded(state, move |codebase| codebase.read_file(request))
        .await
        .map(Json)
}

async fn run_bounded<T, F>(state: AppState, operation: F) -> Result<T, CodebaseError>
where
    T: Send + 'static,
    F: FnOnce(Arc<Codebase>) -> Result<T, CodebaseError> + Send + 'static,
{
    let permit = state
        .operations
        .clone()
        .try_acquire_owned()
        .map_err(|_| CodebaseError::Busy)?;
    let operation_timeout = state.codebase.limits.operation_timeout + Duration::from_millis(250);
    let codebase = state.codebase.clone();
    let task = tokio::task::spawn_blocking(move || {
        let _permit = permit;
        operation(codebase)
    });

    match timeout(operation_timeout, task).await {
        Ok(Ok(result)) => result,
        Ok(Err(error)) => Err(join_error(error)),
        Err(_) => Err(CodebaseError::TimedOut),
    }
}

fn join_error(error: JoinError) -> CodebaseError {
    warn!(%error, "codebase operation task failed");
    CodebaseError::Internal
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SearchRequest {
    pub pattern: String,
    #[serde(default)]
    pub path: String,
    pub file_glob: Option<String>,
    #[serde(default)]
    pub use_regular_expression: bool,
    #[serde(default)]
    pub case_sensitive: bool,
    pub context_lines: Option<usize>,
    pub max_results: Option<usize>,
}

impl SearchRequest {
    fn validate(&self, limits: &Limits) -> Result<(), CodebaseError> {
        if self.pattern.trim().len() < 2 {
            return Err(CodebaseError::invalid(
                "search pattern must contain at least two characters",
            ));
        }
        if self.pattern.len() > limits.max_pattern_bytes {
            return Err(CodebaseError::invalid("search pattern is too long"));
        }
        if self.pattern.contains('\0') {
            return Err(CodebaseError::invalid(
                "search pattern contains a null byte",
            ));
        }
        validate_path_and_glob(&self.path, self.file_glob.as_deref(), limits)?;
        if self.context_lines.unwrap_or(2) > limits.max_context_lines {
            return Err(CodebaseError::invalid(format!(
                "context_lines must not exceed {}",
                limits.max_context_lines
            )));
        }
        validate_positive_limit("max_results", self.max_results, limits.max_search_results)
    }
}

#[derive(Debug, Serialize)]
pub struct SearchResponse {
    pub revision: String,
    pub query: String,
    pub matches: Vec<SearchMatch>,
    pub truncated: bool,
    pub truncation_reason: Option<String>,
    pub stats: SearchStats,
}

#[derive(Debug, Serialize)]
pub struct SearchMatch {
    pub path: String,
    pub line_number: u64,
    pub line: String,
    pub context_before: Vec<String>,
    pub context_after: Vec<String>,
    pub url: String,
}

#[derive(Debug, Default, Serialize)]
pub struct SearchStats {
    pub files_scanned: usize,
    pub bytes_scanned: u64,
    pub context_bytes_read: u64,
    pub files_skipped_too_large: usize,
    pub contexts_skipped: usize,
    pub file_errors: usize,
    pub walk_errors: usize,
    pub elapsed_milliseconds: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListFilesRequest {
    #[serde(default)]
    pub path: String,
    pub file_glob: Option<String>,
    pub depth: Option<usize>,
    pub max_results: Option<usize>,
}

impl ListFilesRequest {
    fn validate(&self, limits: &Limits) -> Result<(), CodebaseError> {
        validate_path_and_glob(&self.path, self.file_glob.as_deref(), limits)?;
        let depth = self.depth.unwrap_or(2);
        if depth == 0 || depth > limits.max_traversal_depth {
            return Err(CodebaseError::invalid(format!(
                "depth must be between 1 and {}",
                limits.max_traversal_depth
            )));
        }
        validate_positive_limit("max_results", self.max_results, limits.max_list_results)
    }
}

#[derive(Debug, Serialize)]
pub struct ListFilesResponse {
    pub revision: String,
    pub entries: Vec<FileEntry>,
    pub truncated: bool,
    pub truncation_reason: Option<String>,
    pub stats: ListStats,
}

#[derive(Debug, Serialize)]
pub struct FileEntry {
    pub path: String,
    #[serde(rename = "type")]
    pub entry_type: EntryType,
    pub url: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum EntryType {
    File,
    Directory,
    Symlink,
}

#[derive(Debug, Default, Serialize)]
pub struct ListStats {
    pub entries_visited: usize,
    pub walk_errors: usize,
    pub elapsed_milliseconds: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReadFileRequest {
    pub path: String,
    pub start_line: Option<usize>,
    pub max_lines: Option<usize>,
}

impl ReadFileRequest {
    fn validate(&self, limits: &Limits) -> Result<(), CodebaseError> {
        if self.path.trim().is_empty() {
            return Err(CodebaseError::invalid("path must not be empty"));
        }
        validate_path_and_glob(&self.path, None, limits)?;
        if self.start_line.unwrap_or(1) == 0 {
            return Err(CodebaseError::invalid("start_line must be positive"));
        }
        validate_positive_limit("max_lines", self.max_lines, limits.max_read_lines)
    }
}

#[derive(Debug, Serialize)]
pub struct ReadFileResponse {
    pub revision: String,
    pub path: String,
    pub start_line: usize,
    pub end_line: usize,
    pub lines: Vec<SourceLine>,
    pub file_size_bytes: u64,
    pub truncated: bool,
    pub truncation_reason: Option<String>,
    pub next_start_line: Option<usize>,
    pub url: String,
    pub elapsed_milliseconds: u64,
}

#[derive(Debug, Serialize)]
pub struct SourceLine {
    pub number: usize,
    pub text: String,
}

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
    revision: String,
}

#[derive(Clone, Copy)]
enum SourceKind {
    File,
    Directory,
}

fn normalize_relative(requested: &str) -> Result<PathBuf, CodebaseError> {
    let mut normalized = PathBuf::new();
    for component in Path::new(requested).components() {
        match component {
            Component::CurDir => {}
            Component::Normal(value) => normalized.push(value),
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(CodebaseError::OutsideRepository);
            }
        }
    }
    Ok(normalized)
}

fn validate_path_and_glob(
    path: &str,
    glob: Option<&str>,
    limits: &Limits,
) -> Result<(), CodebaseError> {
    if path.len() > limits.max_path_bytes {
        return Err(CodebaseError::invalid("path is too long"));
    }
    normalize_relative(path)?;
    if let Some(glob) = glob
        && (glob.is_empty() || glob.len() > limits.max_glob_bytes)
    {
        return Err(CodebaseError::invalid("file_glob has an invalid length"));
    }
    Ok(())
}

fn validate_positive_limit(
    name: &str,
    value: Option<usize>,
    maximum: usize,
) -> Result<(), CodebaseError> {
    if let Some(value) = value
        && (value == 0 || value > maximum)
    {
        return Err(CodebaseError::invalid(format!(
            "{name} must be between 1 and {maximum}"
        )));
    }
    Ok(())
}

fn build_glob(pattern: &str) -> Result<GlobMatcher, CodebaseError> {
    GlobBuilder::new(pattern)
        .literal_separator(true)
        .build()
        .map(|glob| glob.compile_matcher())
        .map_err(|error| CodebaseError::invalid(format!("invalid file_glob: {error}")))
}

fn append_context(
    destination: &mut Vec<String>,
    source: &[&[u8]],
    returned_text_bytes: &mut usize,
    limits: &Limits,
) -> bool {
    for bytes in source {
        let line = bounded_bytes_line(bytes, limits.max_line_bytes);
        if returned_text_bytes.saturating_add(line.len()) > limits.max_returned_text_bytes {
            return false;
        }
        *returned_text_bytes += line.len();
        destination.push(line);
    }
    true
}

fn bounded_line(line: &str, max_bytes: usize) -> String {
    bounded_string(line.trim_end_matches(['\r', '\n']), max_bytes)
}

fn bounded_bytes_line(bytes: &[u8], max_bytes: usize) -> String {
    let text = String::from_utf8_lossy(bytes);
    bounded_line(&text, max_bytes)
}

fn bounded_string(value: &str, max_bytes: usize) -> String {
    if value.len() <= max_bytes {
        return value.to_string();
    }
    let mut boundary = max_bytes.saturating_sub('…'.len_utf8());
    while boundary > 0 && !value.is_char_boundary(boundary) {
        boundary -= 1;
    }
    let mut truncated = value[..boundary].to_string();
    truncated.push('…');
    truncated
}

fn path_to_string(path: &Path) -> String {
    path.components()
        .filter_map(|component| match component {
            Component::Normal(value) => Some(value.to_string_lossy()),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("/")
}

fn encode_segment(value: &str) -> String {
    utf8_percent_encode(value, SOURCE_PATH_SEGMENT).to_string()
}

fn elapsed_milliseconds(started: Instant) -> u64 {
    started.elapsed().as_millis().try_into().unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests {
    use std::fs;

    use tempfile::TempDir;

    use super::*;

    const REVISION: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    fn fixture(limits: Limits) -> (TempDir, Codebase) {
        let directory = tempfile::tempdir().unwrap();
        fs::create_dir_all(directory.path().join("src/nested")).unwrap();
        fs::write(
            directory.path().join("src/cache.rs"),
            "use crate::store;\n\npub fn cache_key() {\n    store::write(\"cache\");\n}\n",
        )
        .unwrap();
        fs::write(
            directory.path().join("src/nested/cache_test.rs"),
            "#[test]\nfn writes_cache_key() {\n    assert_eq!(\"cache\", \"cache\");\n}\n",
        )
        .unwrap();
        fs::write(
            directory.path().join("README.md"),
            "# Example\nBounded search\n",
        )
        .unwrap();

        let codebase = Codebase::new(
            directory.path().to_path_buf(),
            REVISION.to_string(),
            "https://github.com/tuist/tuist".to_string(),
            limits,
        )
        .unwrap();
        (directory, codebase)
    }

    #[test]
    fn searches_literal_text_with_context_and_source_links() {
        let (_directory, codebase) = fixture(Limits::default());

        let response = codebase
            .search(SearchRequest {
                pattern: "store::write".to_string(),
                path: "src".to_string(),
                file_glob: Some("**/*.rs".to_string()),
                use_regular_expression: false,
                case_sensitive: true,
                context_lines: Some(1),
                max_results: Some(10),
            })
            .unwrap();

        assert_eq!(response.revision, REVISION);
        assert_eq!(response.matches.len(), 1);
        assert_eq!(response.matches[0].path, "src/cache.rs");
        assert_eq!(response.matches[0].line_number, 4);
        assert_eq!(response.matches[0].context_before, ["pub fn cache_key() {"]);
        assert_eq!(response.matches[0].context_after, ["}"]);
        assert_eq!(
            response.matches[0].url,
            "https://github.com/tuist/tuist/blob/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/src/cache.rs#L4"
        );
        assert!(!response.truncated);
    }

    #[test]
    fn rejects_paths_outside_the_repository() {
        let (_directory, codebase) = fixture(Limits::default());

        let error = codebase
            .read_file(ReadFileRequest {
                path: "../outside".to_string(),
                start_line: None,
                max_lines: None,
            })
            .unwrap_err();

        assert!(matches!(error, CodebaseError::OutsideRepository));
    }

    #[test]
    fn rejects_mutable_revision_names() {
        let directory = tempfile::tempdir().unwrap();

        let error = Codebase::new(
            directory.path().to_path_buf(),
            "main".to_string(),
            "https://github.com/tuist/tuist".to_string(),
            Limits::default(),
        )
        .unwrap_err();

        assert!(matches!(error, CodebaseError::InvalidRequest(_)));
    }

    #[test]
    fn reports_file_budget_truncation() {
        let limits = Limits {
            max_files_scanned: 1,
            ..Limits::default()
        };
        let (_directory, codebase) = fixture(limits);

        let response = codebase
            .search(SearchRequest {
                pattern: "cache".to_string(),
                path: String::new(),
                file_glob: None,
                use_regular_expression: false,
                case_sensitive: false,
                context_lines: Some(0),
                max_results: Some(50),
            })
            .unwrap();

        assert!(response.truncated);
        assert_eq!(response.truncation_reason.as_deref(), Some("file_limit"));
        assert_eq!(response.stats.files_scanned, 1);
    }

    #[test]
    fn reports_files_skipped_by_the_individual_file_limit() {
        let limits = Limits {
            max_search_file_bytes: 8,
            ..Limits::default()
        };
        let (_directory, codebase) = fixture(limits);

        let response = codebase
            .search(SearchRequest {
                pattern: "cache".to_string(),
                path: String::new(),
                file_glob: None,
                use_regular_expression: false,
                case_sensitive: false,
                context_lines: Some(0),
                max_results: Some(50),
            })
            .unwrap();

        assert!(response.truncated);
        assert_eq!(
            response.truncation_reason.as_deref(),
            Some("large_files_skipped")
        );
        assert!(response.stats.files_skipped_too_large > 0);
    }

    #[test]
    fn lists_files_with_depth_and_result_limits() {
        let (_directory, codebase) = fixture(Limits::default());

        let response = codebase
            .list_files(ListFilesRequest {
                path: "src".to_string(),
                file_glob: Some("**/*.rs".to_string()),
                depth: Some(3),
                max_results: Some(1),
            })
            .unwrap();

        assert_eq!(response.entries.len(), 1);
        assert!(response.truncated);
        assert_eq!(response.truncation_reason.as_deref(), Some("result_limit"));
    }

    #[test]
    fn reads_bounded_line_ranges_with_continuation_metadata() {
        let (_directory, codebase) = fixture(Limits::default());

        let response = codebase
            .read_file(ReadFileRequest {
                path: "src/cache.rs".to_string(),
                start_line: Some(3),
                max_lines: Some(2),
            })
            .unwrap();

        assert_eq!(response.start_line, 3);
        assert_eq!(response.end_line, 4);
        assert_eq!(response.lines[0].number, 3);
        assert_eq!(response.lines[1].text, "    store::write(\"cache\");");
        assert!(response.truncated);
        assert_eq!(response.next_start_line, Some(5));
        assert_eq!(response.truncation_reason.as_deref(), Some("line_limit"));
    }

    #[test]
    fn rejects_request_limits_above_the_service_caps() {
        let (_directory, codebase) = fixture(Limits::default());

        let error = codebase
            .search(SearchRequest {
                pattern: "cache".to_string(),
                path: String::new(),
                file_glob: None,
                use_regular_expression: false,
                case_sensitive: false,
                context_lines: Some(4),
                max_results: Some(51),
            })
            .unwrap_err();

        assert!(matches!(error, CodebaseError::InvalidRequest(_)));
    }

    #[tokio::test]
    async fn timed_out_tasks_keep_their_concurrency_slot_until_they_stop() {
        let limits = Limits {
            max_concurrent_operations: 1,
            operation_timeout: Duration::from_millis(1),
            ..Limits::default()
        };
        let (_directory, codebase) = fixture(limits);
        let state = AppState::new(Arc::new(codebase));

        let result = run_bounded(state.clone(), |_| {
            std::thread::sleep(Duration::from_millis(300));
            Ok(())
        })
        .await;
        assert!(matches!(result, Err(CodebaseError::TimedOut)));

        let result = run_bounded(state.clone(), |_| Ok(())).await;
        assert!(matches!(result, Err(CodebaseError::Busy)));

        tokio::time::sleep(Duration::from_millis(60)).await;
        assert!(run_bounded(state, |_| Ok(())).await.is_ok());
    }

    #[cfg(unix)]
    #[test]
    fn rejects_symbolic_links_that_escape_the_repository() {
        use std::os::unix::fs::symlink;

        let (directory, codebase) = fixture(Limits::default());
        symlink("/etc/hosts", directory.path().join("hosts")).unwrap();

        let error = codebase
            .read_file(ReadFileRequest {
                path: "hosts".to_string(),
                start_line: None,
                max_lines: None,
            })
            .unwrap_err();

        assert!(matches!(error, CodebaseError::OutsideRepository));
    }
}
