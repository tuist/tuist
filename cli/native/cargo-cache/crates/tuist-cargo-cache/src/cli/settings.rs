use crate::config::{check_global_file, config_file_path, resolve_settings, settings_registry};
use eyre::{Context, Result, bail, eyre};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use toml_edit::{DocumentMut, Item, TableLike};
use usage_config::{PropMeta, Resolved, Scope, Ty, Value};

#[derive(usage_rs::Args)]
pub(super) struct SettingsArgs {
    #[usage(subcommand)]
    pub(super) command: SettingsCommands,
}

#[derive(usage_rs::Subcommands)]
pub(super) enum SettingsCommands {
    /// List settings and their current values.
    ///
    /// Values come from the environment, the global configuration file, and
    /// defaults. Workspace `.tuist_cargo_cache.toml` settings are not included. If a setting
    /// whose default tuist_cargo_cache computes when it runs has no value, `ls` shows it as
    /// unset, followed by a description of that default. The value of
    /// `remote.token` is not printed; `tuist_cargo_cache settings get remote.token` prints it.
    Ls(LsArgs),
    /// Print the current value of one setting.
    ///
    /// The value comes from the environment, the global configuration file, or
    /// the setting's fixed default. Workspace `.tuist_cargo_cache.toml` settings are not
    /// included. A setting with neither a value nor a fixed default prints
    /// nothing. That includes a setting whose default tuist_cargo_cache computes when it
    /// runs, such as `gc.max_size`; `tuist_cargo_cache settings ls` describes those defaults.
    Get(KeyArgs),
    /// Write a setting to the global configuration file.
    ///
    /// tuist_cargo_cache writes nothing unless the value has the setting's type, is one of
    /// its allowed values, and loads as that setting. List settings take
    /// comma-separated items, such as `tuist_cargo_cache settings set target.keep ~/src,/work`.
    /// Edit table settings, such as `linker.profiles`, in the file directly.
    /// Settings read only from the environment, such as `verify`, cannot be
    /// set this way. Comments and formatting elsewhere in the file are kept.
    /// An environment variable for the same setting still takes precedence.
    Set(SetArgs),
    /// Remove a setting from the global configuration file.
    ///
    /// The setting then falls back to its default. An environment variable for
    /// the same setting still takes precedence. You can also unset a key tuist_cargo_cache
    /// does not recognize, such as a misspelled one that stops tuist_cargo_cache from
    /// loading, as long as the key holds a value rather than a table.
    Unset(KeyArgs),
}

#[derive(usage_rs::Args)]
pub(super) struct LsArgs {
    /// Setting or group to list, such as `gc` or `gc.max_size`.
    ///
    /// Lists every setting when omitted.
    key: Option<String>,
}

#[derive(usage_rs::Args)]
pub(super) struct KeyArgs {
    /// Setting name, such as `gc.max_size`.
    key: String,
}

#[derive(usage_rs::Args)]
pub(super) struct SetArgs {
    /// Setting name, such as `gc.max_size`.
    key: String,
    /// New value.
    #[usage(allow_negative_numbers)]
    value: String,
}

/// Settings whose values `ls` does not print, since a listing is easy to
/// paste somewhere it should not go.
const SECRETS: &[&str] = &["remote.token"];

pub(super) fn run(args: SettingsArgs) -> Result<ExitCode> {
    match args.command {
        SettingsCommands::Ls(args) => list(args.key.as_deref()),
        SettingsCommands::Get(args) => get(&args.key),
        SettingsCommands::Set(args) => set(&args.key, &args.value),
        SettingsCommands::Unset(args) => unset(&args.key),
    }
    .map(|()| ExitCode::SUCCESS)
}

fn list(filter: Option<&str>) -> Result<()> {
    let resolved = resolved()?;
    let registry = resolved.registry();
    let mut ids = registry
        .ids()
        .filter(|id| {
            let meta = registry.get(*id);
            !meta.hide
                && meta.renamed_to.is_none()
                && filter.is_none_or(|filter| in_group(meta.key, filter))
        })
        .collect::<Vec<_>>();
    if let Some(filter) = filter
        && ids.is_empty()
    {
        bail!("unknown setting: {filter}");
    }
    ids.sort_by_key(|id| registry.get(*id).key);
    for id in ids {
        let meta = registry.get(id);
        match (resolved.get(id), meta.default_note) {
            (Some(_), _) if SECRETS.contains(&meta.key) => {
                println!(
                    "{} is set; `tuist_cargo_cache settings get {}` prints it",
                    meta.key, meta.key
                )
            }
            (Some(value), _) => println!("{} = {}", meta.key, toml_value(value)),
            (None, Some(note)) => println!("{} is unset; default: {note}", meta.key),
            (None, None) => println!("{} is unset", meta.key),
        }
    }
    Ok(())
}

fn get(key: &str) -> Result<()> {
    let meta = setting(key)?;
    let resolved = resolved()?;
    match resolved.get_key(meta.key) {
        Some(Value::String(text)) => println!("{text}"),
        Some(value @ (Value::List(_) | Value::Map(_))) => println!("{}", toml_value(value)),
        Some(value) => println!("{value}"),
        None => {}
    }
    Ok(())
}

fn set(key: &str, raw: &str) -> Result<()> {
    let meta = setting(key)?;
    let path = file_path()?;
    // The new value on its own is what has to load, so a problem already
    // elsewhere in the file cannot stop this setting from being repaired.
    let mut alone = DocumentMut::new();
    set_value(&mut alone, meta, raw, &path)?;
    let _lock = lock(&path)?;
    let mut document = read(&path)?;
    set_value(&mut document, meta, raw, &path)?;
    save(&path, &document, Some(alone.to_string()))?;
    note_environment(meta);
    Ok(())
}

fn unset(key: &str) -> Result<()> {
    // A key tuist_cargo_cache does not declare can still be in the file, which is how a
    // misspelling gets there, and removing it is how that load error is fixed.
    let meta = match setting(key) {
        Ok(meta) => Some(meta),
        Err(error) if is_group(key) => return Err(error),
        Err(_) => None,
    };
    let path = file_path()?;
    let mut removed = false;
    if path.try_exists()? {
        let _lock = lock(&path)?;
        let mut document = read(&path)?;
        removed = remove_value(
            &mut document,
            meta.map_or(key, |meta| meta.key),
            meta.is_some(),
            &path,
        )?;
        if removed {
            save(&path, &document, None)?;
        }
    }
    match meta {
        Some(meta) => note_environment(meta),
        None if !removed => return setting(key).map(|_| ()),
        None => {}
    }
    Ok(())
}

/// Write `raw` into `document` as the value of `meta`.
///
/// `path` only names the file in errors.
pub(super) fn set_value(
    document: &mut DocumentMut,
    meta: &PropMeta,
    raw: &str,
    path: &Path,
) -> Result<()> {
    if meta.scope == Scope::Env {
        match meta.envs.first() {
            Some(env) => bail!(
                "{} can only be set in the environment, with {env}",
                meta.key
            ),
            None => bail!("{} can only be set in the environment", meta.key),
        }
    }
    if matches!(meta.ty.inner(), Ty::Map(_) | Ty::Object) {
        bail!(
            "{} is a table; edit {} to change it",
            meta.key,
            path.display()
        );
    }
    let mut value = toml_value(&parse(meta, raw)?);
    let (table, name, inline) =
        parent_table(document, meta.key, true, path)?.expect("missing tables are created");
    match table.get_mut(name) {
        // Replaced in place, so a comment above the key and one after the old
        // value both stay where they were.
        Some(Item::Value(previous)) => {
            *value.decor_mut() = previous.decor().clone();
            *previous = value;
        }
        _ => {
            table.insert(name, Item::Value(value));
            // An inline table keeps the spacing its last value had before the
            // closing brace, which would now sit before a comma.
            if inline {
                table.fmt();
            }
        }
    }
    Ok(())
}

/// Remove `key` from `document`, reporting whether it was there.
///
/// A key tuist_cargo_cache does not declare is removed only when it holds a plain value, not
/// a table of either kind, so a typo cannot take a group of settings with it.
pub(super) fn remove_value(
    document: &mut DocumentMut,
    key: &str,
    known: bool,
    path: &Path,
) -> Result<bool> {
    let Some((table, name, _)) = parent_table(document, key, false, path)? else {
        return Ok(false);
    };
    match table.get(name) {
        Some(_) if known => {}
        Some(Item::Value(value)) if !value.is_inline_table() => {}
        _ => return Ok(false),
    }
    table.remove(name);
    remove_empty_group(document, key);
    Ok(true)
}

/// The setting `key` names, following a rename to its current name.
pub(super) fn setting(key: &str) -> Result<&'static PropMeta> {
    let registry = settings_registry();
    if let Some(found) = registry.lookup(key) {
        return Ok(registry.get(found.id));
    }
    if is_group(key) {
        bail!("{key} is a group of settings; `tuist_cargo_cache settings ls {key}` lists them");
    }
    bail!("unknown setting: {key}; `tuist_cargo_cache settings ls` lists them")
}

fn is_group(key: &str) -> bool {
    settings_registry()
        .props
        .iter()
        .any(|meta| !meta.hide && meta.key != key && in_group(meta.key, key))
}

fn in_group(key: &str, group: &str) -> bool {
    key.strip_prefix(group)
        .is_some_and(|rest| rest.is_empty() || rest.starts_with('.'))
}

fn resolved() -> Result<Resolved> {
    let resolved = resolve_settings()?;
    for warning in &resolved.warnings {
        match &warning.origin {
            Some(origin) => log::warn!("{} ({})", warning.message, origin.describe()),
            None => log::warn!("{}", warning.message),
        }
    }
    Ok(resolved)
}

/// Read `raw` the way the environment variable for this setting would be read.
fn parse(meta: &PropMeta, raw: &str) -> Result<Value> {
    let text = match meta.parse {
        Some(parser) => parser.split(raw),
        None => Value::String(raw.to_owned()),
    };
    let value = meta.ty.coerce(text).map_err(|error| {
        eyre!(
            "invalid {}: expected {}, found `{}`",
            meta.key,
            error.expected,
            error.found
        )
    })?;
    if let Some(refused) = meta.refuses(&value) {
        bail!(
            "invalid {}: `{refused}` is not one of {}",
            meta.key,
            meta.allowed()
        );
    }
    Ok(value)
}

fn toml_value(value: &Value) -> toml_edit::Value {
    match value {
        Value::Bool(value) => (*value).into(),
        Value::Int(value) => (*value).into(),
        Value::Float(value) => (*value).into(),
        Value::String(value) => value.as_str().into(),
        Value::List(items) => items
            .iter()
            .map(toml_value)
            .collect::<toml_edit::Array>()
            .into(),
        Value::Map(entries) => entries
            .iter()
            .map(|(key, value)| (key.as_str(), toml_value(value)))
            .collect::<toml_edit::InlineTable>()
            .into(),
    }
}

fn file_path() -> Result<PathBuf> {
    config_file_path()
        .ok_or_else(|| eyre!("the platform configuration directory could not be located"))
}

fn read(path: &Path) -> Result<DocumentMut> {
    let contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(error) => {
            return Err(error).wrap_err_with(|| format!("failed to read {}", path.display()));
        }
    };
    contents
        .parse()
        .wrap_err_with(|| format!("failed to parse {}", path.display()))
}

/// The table holding `key`, the key's last segment, and whether that table is
/// inline, creating the tables on the way when `create` is set.
fn parent_table<'a>(
    document: &'a mut DocumentMut,
    key: &'a str,
    create: bool,
    path: &Path,
) -> Result<Option<(&'a mut dyn TableLike, &'a str, bool)>> {
    let (groups, name) = match key.rsplit_once('.') {
        Some((groups, name)) => (Some(groups), name),
        None => (None, key),
    };
    // A table added after existing content gets a blank line above its header.
    let spaced = !document.as_table().is_empty();
    let mut table: &mut dyn TableLike = document.as_table_mut();
    let mut inline = false;
    for group in groups.into_iter().flat_map(|groups| groups.split('.')) {
        if create && !table.contains_key(group) {
            let mut created = toml_edit::Table::new();
            if spaced {
                created.decor_mut().set_prefix("\n");
            }
            table.insert(group, Item::Table(created));
        }
        let Some(item) = table.get_mut(group) else {
            return Ok(None);
        };
        inline = item.is_inline_table();
        table = item
            .as_table_like_mut()
            .ok_or_else(|| eyre!("{group} in {} is not a table", path.display()))?;
    }
    Ok(Some((table, name, inline)))
}

/// Drop the table `key` was in once nothing is left in it, unless a comment
/// sits above or beside it.
fn remove_empty_group(document: &mut DocumentMut, key: &str) {
    let Some((group, _)) = key.split_once('.') else {
        return;
    };
    let empty = match document.get(group) {
        Some(Item::Table(table)) => table.is_empty() && !commented(table.decor()),
        // An inline table's neighbours are on the key above it and on the
        // value itself, after its closing brace.
        Some(Item::Value(toml_edit::Value::InlineTable(table))) => {
            let key_commented = document
                .as_table()
                .key(group)
                .is_some_and(|key| commented(key.leaf_decor()));
            table.is_empty() && !commented(table.decor()) && !key_commented
        }
        _ => false,
    };
    if empty {
        document.remove(group);
    }
}

fn commented(decor: &toml_edit::Decor) -> bool {
    [decor.prefix(), decor.suffix()]
        .into_iter()
        .flatten()
        .filter_map(|text| text.as_str())
        .any(|text| text.contains('#'))
}

/// Write `document` to `path`, refusing it unless `check` loads as a
/// configuration, then warn about any problem left elsewhere in the file.
fn save(path: &Path, document: &DocumentMut, check: Option<String>) -> Result<()> {
    let contents = document.to_string();
    // Through any link, so a managed dotfile stays a link.
    let target = link_target(path)?;
    // The check reads through the file layer, which treats a missing file as
    // empty without looking at the text it is handed. An empty file is a valid
    // configuration, so it can stand in until the real one is written.
    let created = !target.try_exists()?;
    if created {
        std::fs::write(&target, "")
            .wrap_err_with(|| format!("failed to create {}", target.display()))?;
    }
    let written = (|| {
        if let Some(check) = check {
            check_global_file(path, check)
                .map_err(|error| error.wrap_err(format!("{} was not changed", path.display())))?;
        }
        crate::util::write_atomic(&target, contents.as_bytes())
    })();
    // The placeholder, never the link that led to it.
    if written.is_err() && created {
        let _ = std::fs::remove_file(&target);
    }
    written?;
    if let Err(error) = check_global_file(path, contents) {
        log::warn!("{error:#}");
    }
    Ok(())
}

/// The file `path` names once every link is followed, whether or not that
/// file exists yet.
///
/// `canonicalize` cannot answer for a link to a file that has not been
/// written, and treating that link as the file is how a failed first write
/// used to delete it.
pub(super) fn link_target(path: &Path) -> Result<PathBuf> {
    let mut current = path.to_path_buf();
    // The same bound the kernel puts on a chain of links.
    for _ in 0..40 {
        match std::fs::symlink_metadata(&current) {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                let next = std::fs::read_link(&current)
                    .wrap_err_with(|| format!("failed to read {}", current.display()))?;
                current = match current.parent() {
                    Some(parent) => parent.join(next),
                    None => next,
                };
            }
            Ok(_) => return Ok(current),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(current),
            Err(error) => {
                return Err(error)
                    .wrap_err_with(|| format!("failed to read {}", current.display()));
            }
        }
    }
    bail!("{} is a chain of too many links", path.display())
}

/// Hold the edit lock for `path`, so two edits cannot both read the same
/// contents and each write away the other's change.
///
/// The lock is a sibling of the file the links lead to, so two links to one
/// file share a lock. It is not the file itself, because fslock empties the
/// file it locks when it lets go.
fn lock(path: &Path) -> Result<fslock::LockFile> {
    let target = link_target(path)?;
    let (Some(parent), Some(name)) = (target.parent(), target.file_name()) else {
        bail!("{} has no parent directory", target.display());
    };
    std::fs::create_dir_all(parent)
        .wrap_err_with(|| format!("failed to create {}", parent.display()))?;
    let lock_path = parent.join(format!(".{}.lock", name.to_string_lossy()));
    let mut lock = fslock::LockFile::open(&lock_path)
        .wrap_err_with(|| format!("failed to open {}", lock_path.display()))?;
    lock.lock()
        .wrap_err_with(|| format!("failed to lock {}", lock_path.display()))?;
    Ok(lock)
}

fn note_environment(meta: &PropMeta) {
    for env in meta.envs {
        if std::env::var_os(env).is_some() {
            log::warn!("{env} is set and takes precedence over the configuration file");
        }
    }
}
