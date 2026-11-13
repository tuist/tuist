use super::*;
use gpui::{KeyUpEvent, Keystroke, TestAppContext, VisualTestContext, px, size};
use tuist_credentials::{Credentials, CredentialsStore, Directories};

fn draw(cx: &mut VisualTestContext) {
    cx.run_until_parked();
    for _ in 0..2 {
        cx.update(|window, cx| window.draw(cx).clear(cx));
    }
}

// GPUI's keystroke convenience method emits only key-down. Real buttons activate
// on key-up, so test both halves, including focus changes between them.
fn press(cx: &mut VisualTestContext, key: &'static str) {
    cx.simulate_keystrokes(key);
    cx.simulate_event(KeyUpEvent {
        keystroke: Keystroke::parse(key).unwrap(),
    });
    draw(cx);
}

fn accounts(path: &std::path::Path, signed_in: bool) -> (Accounts, Arc<Session>) {
    let directories = Directories {
        config: path.join("config"),
        state: path.join("state"),
        data: path.join("data"),
    };
    let server = Url::parse("https://tuist.dev").unwrap();
    let owner = if signed_in {
        server.clone()
    } else {
        Url::parse("https://saved.example.test").unwrap()
    };
    CredentialsStore::new(&directories.config).store(&owner, &Credentials {
            access_token: "e30.eyJzdWIiOiAiYW5hIiwgInByZWZlcnJlZF91c2VybmFtZSI6ICJhbmEiLCAiZXhwIjogNDEwMjQ0NDgwMCwgInR5cGUiOiAiYWNjb3VudCJ9.".into(),
            refresh_token: Some("fixture-only".into()),
            oauth_client_id: None,
            rejected: None,
        }).unwrap();
    let accounts = Accounts::new(directories);
    accounts.remember(&owner).unwrap();
    accounts.remember(&server).unwrap();
    let session = Arc::new(accounts.current_session(server).unwrap());
    (accounts, session)
}

#[gpui::test]
fn signed_out_keyboard_form_and_compact_scrolling(cx: &mut TestAppContext) {
    cx.update(|cx| {
        crate::keyboard::init(cx);
        crate::input::init(cx);
        init(cx);
    });
    let directory = tempfile::tempdir().unwrap();
    let (accounts, session) = accounts(directory.path(), false);
    let status = session.status().map_err(|error| error.to_string());
    let (root, cx) =
        cx.add_window_view(|window, cx| Root::new(session, accounts, status, window, cx));
    cx.update(|window, _| window.activate_window());
    cx.simulate_resize(size(px(640.), px(400.)));
    draw(cx);
    assert!(cx.debug_bounds("account-menu-trigger").is_none());
    cx.dispatch_action(ToggleAccountMenu);
    draw(cx);
    root.read_with(cx, |root, _| assert!(root.menu.is_none()));
    // Four providers followed by account/server entry. No hidden avatar stop.
    for _ in 0..5 {
        press(cx, "tab");
    }
    press(cx, "space");
    root.read_with(cx, |root, _| assert!(root.editing_accounts));
    let viewport = cx.debug_bounds("account-scroll-viewport").unwrap();
    assert!(cx.debug_bounds("server-url-field").unwrap().bottom() > viewport.bottom());
    press(cx, "tab"); // Done -> saved account -> server field.
    press(cx, "tab");
    let field = cx.debug_bounds("server-url-field").unwrap();
    assert!(
        field.top() >= viewport.top() && field.bottom() <= viewport.bottom(),
        "field: {field:?}, viewport: {viewport:?}"
    );
    press(
        cx,
        if cfg!(target_os = "macos") {
            "cmd-a"
        } else {
            "ctrl-a"
        },
    );
    cx.simulate_input("http://invalid.example.test");
    press(cx, "enter");
    assert!(cx.debug_bounds("server-url-error").is_some());
    press(cx, "escape");
    root.read_with(cx, |root, _| assert!(!root.editing_accounts));
    assert!(cx.debug_bounds("account-menu-trigger").is_none());
    // Focus returns to the first provider; reverse traversal reaches the footer
    // and account/server entry, which must still activate with Enter.
    press(cx, "shift-tab");
    press(cx, "shift-tab");
    press(cx, "enter");
    root.read_with(cx, |root, _| assert!(root.editing_accounts));
}

#[gpui::test]
fn account_menu_keyboard_exit_restore_settings_and_sign_out(cx: &mut TestAppContext) {
    cx.update(|cx| {
        crate::keyboard::init(cx);
        crate::input::init(cx);
        init(cx);
    });
    let directory = tempfile::tempdir().unwrap();
    let (accounts, session) = accounts(directory.path(), true);
    let status = session.status().map_err(|error| error.to_string());
    let (root, cx) =
        cx.add_window_view(|window, cx| Root::new(session, accounts, status, window, cx));
    cx.update(|window, _| window.activate_window());
    draw(cx);
    assert!(cx.debug_bounds("account-menu-trigger").is_some());
    press(cx, "tab");
    let opener = cx.update(|window, cx| window.focused(cx).unwrap());
    cx.deactivate_window();
    cx.update(|window, _| window.activate_window());
    // Activation synchronizes shared credentials asynchronously. A covered
    // control must lose focus until that work finishes, then regain it.
    while cx.update(|window, _| opener.is_focused(window)) && cx.executor().tick() {}
    cx.update(|window, _| assert!(!opener.is_focused(window)));
    draw(cx);
    cx.update(|window, _| assert!(opener.is_focused(window)));
    press(cx, "space");
    root.read_with(cx, |root, _| assert!(root.menu.is_some()));
    press(cx, "escape");
    press(cx, "enter");
    root.read_with(cx, |root, _| assert!(root.menu.is_some()));
    press(cx, "tab"); // Close and leave, rather than trap focus on the opener.
    root.read_with(cx, |root, _| assert!(root.menu.is_none()));
    press(cx, "tab");
    press(cx, "enter");
    root.read_with(cx, |root, cx| {
        assert_eq!(root.navigation.read(cx).tab, tuist_navigation::Tab::Profile)
    });
    press(cx, "shift-tab");
    press(cx, "space");
    root.read_with(cx, |root, cx| {
        assert_eq!(
            root.navigation.read(cx).tab,
            tuist_navigation::Tab::Previews
        )
    });
    cx.dispatch_action(ToggleAccountMenu);
    draw(cx);
    press(cx, "end");
    press(cx, "up");
    press(cx, "enter");
    root.read_with(cx, |root, _| {
        assert!(root.settings_open && root.menu.is_none())
    });
    press(cx, "escape");
    root.read_with(cx, |root, _| assert!(!root.settings_open));
    press(cx, "space"); // Escape restored the avatar, not a removed page control.
    root.read_with(cx, |root, _| assert!(root.menu.is_some()));
    press(cx, "end");
    press(cx, "enter");
    root.read_with(cx, |root, _| {
        assert!(matches!(root.status, Some(Status::SignedOut)))
    });
    // A vanished avatar must not survive as a hidden keyboard stop.
    press(cx, "shift-tab");
    press(cx, "shift-tab");
    press(cx, "enter");
    root.read_with(cx, |root, _| assert!(root.editing_accounts));
}
