use super::*;
use toml_edit::DocumentMut;

fn edited(contents: &str, key: &str, value: &str) -> Result<String> {
    let mut document = contents.parse::<DocumentMut>().unwrap();
    set_value(
        &mut document,
        setting(key)?,
        value,
        Path::new("config.toml"),
    )?;
    Ok(document.to_string())
}

fn removed(contents: &str, key: &str) -> (bool, String) {
    let mut document = contents.parse::<DocumentMut>().unwrap();
    let known = setting(key).is_ok();
    let found = remove_value(&mut document, key, known, Path::new("config.toml")).unwrap();
    (found, document.to_string())
}

#[test]
fn a_new_setting_is_written_with_its_declared_type() {
    assert_eq!(
        edited("", "savings", "plain").unwrap(),
        "savings = \"plain\"\n"
    );
    assert_eq!(
        edited("", "incremental", "yes").unwrap(),
        "incremental = true\n"
    );
    assert_eq!(
        edited("", "scheduler.reserve_cpus", "2").unwrap(),
        "[scheduler]\nreserve_cpus = 2\n"
    );
    assert_eq!(
        edited("", "target.evict_first", ".claude/worktrees, tmp").unwrap(),
        "[target]\nevict_first = [\".claude/worktrees\", \"tmp\"]\n"
    );
}

#[test]
fn a_new_table_follows_existing_content_after_a_blank_line() {
    assert_eq!(
        edited("savings = \"plain\"\n", "gc.max_size", "20GiB").unwrap(),
        "savings = \"plain\"\n\n[gc]\nmax_size = \"20GiB\"\n"
    );
}

#[test]
fn replacing_a_value_keeps_the_comments_around_it() {
    let contents = "# mine\nsummary = \"full\"  # loud\n\n# collection\n[gc]\nmax_size = \"5GiB\"  # small\ninterval = \"2h\"\n";
    let contents = edited(contents, "summary", "short").unwrap();
    let contents = edited(&contents, "gc.max_size", "8GiB").unwrap();
    assert_eq!(
        contents,
        "# mine\nsummary = \"short\"  # loud\n\n# collection\n[gc]\nmax_size = \"8GiB\"  # small\ninterval = \"2h\"\n"
    );
}

#[test]
fn an_existing_dotted_or_inline_group_is_extended_in_place() {
    assert_eq!(
        edited("gc.auto = false\n", "gc.interval", "2h").unwrap(),
        "gc.auto = false\ngc.interval = \"2h\"\n"
    );
    assert_eq!(
        edited("gc = { auto = false }\n", "gc.interval", "2h").unwrap(),
        "gc = { auto = false, interval = \"2h\" }\n"
    );
}

#[test]
fn values_the_setting_cannot_hold_are_refused() {
    let refused = |key, value| edited("", key, value).unwrap_err().to_string();
    assert_eq!(
        refused("savings", "loud"),
        "invalid savings: `loud` is not one of quips, plain, off"
    );
    assert_eq!(
        refused("scheduler.pressure", "maybe"),
        "invalid scheduler.pressure: expected a boolean, found `maybe`"
    );
    assert_eq!(
        refused("http.retries", "many"),
        "invalid http.retries: expected an integer, found `many`"
    );
    assert_eq!(
        refused("verify", "true"),
        "verify can only be set in the environment, with TUIST_CARGO_CACHE_VERIFY"
    );
    assert_eq!(
        refused("linker.profiles", "x"),
        "linker.profiles is a table; edit config.toml to change it"
    );
    assert_eq!(
        edited("gc = 5\n", "gc.auto", "true")
            .unwrap_err()
            .to_string(),
        "gc in config.toml is not a table"
    );
}

#[test]
fn names_are_checked_against_the_declared_settings() {
    assert_eq!(
        setting("gc").unwrap_err().to_string(),
        "gc is a group of settings; `tuist_cargo_cache settings ls gc` lists them"
    );
    assert_eq!(
        setting("gc.max").unwrap_err().to_string(),
        "unknown setting: gc.max; `tuist_cargo_cache settings ls` lists them"
    );
}

#[test]
fn unsetting_removes_the_key_and_a_table_left_empty() {
    assert_eq!(
        removed(
            "savings = \"plain\"\n\n[gc]\nmax_size = \"20GiB\"\n",
            "gc.max_size"
        ),
        (true, "savings = \"plain\"\n".to_owned())
    );
    assert_eq!(
        removed("[gc]\nauto = false\nmax_size = \"20GiB\"\n", "gc.max_size"),
        (true, "[gc]\nauto = false\n".to_owned())
    );
    // A comment on the table's header is the user's, so the table stays.
    assert_eq!(
        removed("# collection\n[gc]\nmax_size = \"20GiB\"\n", "gc.max_size"),
        (true, "# collection\n[gc]\n".to_owned())
    );
    assert_eq!(
        removed("[gc] # collection\nmax_size = \"20GiB\"\n", "gc.max_size"),
        (true, "[gc] # collection\n".to_owned())
    );
    assert_eq!(
        removed("gc = { max_size = \"20GiB\" }\n", "gc.max_size"),
        (true, String::new())
    );
    assert_eq!(
        removed("gc = { max_size = \"20GiB\" } # retention\n", "gc.max_size"),
        (true, "gc = {} # retention\n".to_owned())
    );
    assert_eq!(
        removed(
            "# retention\ngc = { max_size = \"20GiB\" }\n",
            "gc.max_size"
        ),
        (true, "# retention\ngc = {}\n".to_owned())
    );
    assert_eq!(
        removed("savings = \"plain\"\n", "gc.max_size"),
        (false, "savings = \"plain\"\n".to_owned())
    );
}

#[test]
fn unsetting_an_undeclared_key_removes_only_a_value() {
    // How a misspelled key that stops tuist_cargo_cache from loading gets taken out.
    assert_eq!(
        removed("[gc]\nauto = false\nsavings = \"plain\"\n", "gc.savings"),
        (true, "[gc]\nauto = false\n".to_owned())
    );
    assert_eq!(
        removed("[gcc]\nauto = false\n", "gcc"),
        (false, "[gcc]\nauto = false\n".to_owned())
    );
    assert_eq!(
        removed("gcc = { auto = false }\n", "gcc"),
        (false, "gcc = { auto = false }\n".to_owned())
    );
}

#[cfg(unix)]
#[test]
fn links_are_followed_to_a_file_that_does_not_exist_yet() {
    let directory = tempfile::tempdir().unwrap();
    let real = directory.path().join("dotfiles/tuist_cargo_cache.toml");
    std::fs::create_dir_all(real.parent().unwrap()).unwrap();
    let link = directory.path().join("config.toml");
    std::os::unix::fs::symlink("dotfiles/tuist_cargo_cache.toml", &link).unwrap();
    assert_eq!(
        link_target(&link).unwrap(),
        directory.path().join("dotfiles/tuist_cargo_cache.toml")
    );
    let plain = directory.path().join("plain.toml");
    assert_eq!(link_target(&plain).unwrap(), plain);
}
