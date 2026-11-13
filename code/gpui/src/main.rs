mod accessibility;
mod accounts;
mod assets;
mod input;
mod instance;
mod keyboard;
mod login;
mod root;
mod theme;
mod updates;
mod workspace;

use std::sync::{Arc, Mutex};

use gpui::{
    App, Bounds, KeyBinding, Menu, MenuItem, TitlebarOptions, WindowBounds, WindowOptions, actions,
    point, prelude::*, px, size,
};
use tuist_session::Accounts;

use assets::Assets;
use instance::Instance;
use root::Root;

actions!(tuist_desktop, [Quit]);

#[cfg(target_os = "macos")]
fn set_dock_icon() {
    use objc2::AllocAnyThread;
    use objc2_app_kit::{NSApplication, NSImage};
    use objc2_foundation::{MainThreadMarker, NSData};

    let Some(main_thread) = MainThreadMarker::new() else {
        return;
    };
    let data = NSData::with_bytes(assets::ICON);
    if let Some(image) = NSImage::initWithData(NSImage::alloc(), &data) {
        // SAFETY: a non-nil image on the main thread, after gpui created NSApp.
        unsafe {
            NSApplication::sharedApplication(main_thread).setApplicationIconImage(Some(&image))
        };
    }
}

#[cfg(target_os = "macos")]
const QUIT_KEYSTROKE: &str = "cmd-q";
#[cfg(not(target_os = "macos"))]
const QUIT_KEYSTROKE: &str = "ctrl-q";

fn main() -> anyhow::Result<()> {
    let urls = std::env::args()
        .skip(1)
        .filter(|value| value != "--")
        .collect();
    let Some(instance) = Instance::start(&tuist_credentials::Directories::from_env().state, urls)?
    else {
        return Ok(());
    };
    let accounts = Accounts::new(tuist_credentials::Directories::from_env());
    let session = Arc::new(accounts.session_from_env()?);
    // Startup reads happen before the UI event loop. Later session work runs
    // on the background executor so a peer's refresh lock cannot freeze input.
    accounts.preserve(session.server())?;
    let status = session.status().map_err(|error| error.to_string());
    let (platform_sender, platform_links) = async_channel::bounded(16);
    let application = gpui_platform::application().with_assets(Assets);
    application.on_open_urls(move |urls| {
        let _ = platform_sender.try_send(urls);
    });
    let instance_links = instance.links.clone();
    let pending_install = Arc::new(Mutex::new(None));
    let pending = pending_install.clone();
    application.run(move |cx: &mut App| {
        theme::init(cx);
        input::init(cx);
        keyboard::init(cx);
        root::init(cx);
        #[cfg(target_os = "macos")]
        set_dock_icon();
        cx.on_action(|_: &Quit, cx| cx.quit());
        cx.bind_keys([KeyBinding::new(QUIT_KEYSTROKE, Quit, None)]);
        cx.set_menus(vec![Menu {
            name: "Tuist Code".into(),
            disabled: false,
            items: vec![
                MenuItem::action("Check for updates…", updates::CheckForUpdates),
                MenuItem::action("Quit Tuist Code", Quit),
            ],
        }]);
        cx.on_window_closed(|cx, _| {
            if cx.windows().is_empty() {
                cx.quit();
            }
        })
        .detach();

        let bounds = Bounds::centered(None, size(px(960.), px(640.)), cx);
        let window = cx
            .open_window(
                WindowOptions {
                    window_bounds: Some(WindowBounds::Windowed(bounds)),
                    window_min_size: Some(size(px(640.), px(400.))),
                    titlebar: Some(TitlebarOptions {
                        title: Some("Tuist Code".into()),
                        appears_transparent: true,
                        traffic_light_position: Some(point(px(12.), px(12.))),
                    }),
                    app_id: Some("dev.tuist.code".into()),
                    ..Default::default()
                },
                |window, cx| cx.new(|cx| Root::new(session, accounts, status, window, cx)),
            )
            .expect("open the Tuist window");
        updates::init(window.into(), pending, cx);
        for links in [platform_links, instance_links] {
            cx.spawn(async move |cx| {
                while let Ok(urls) = links.recv().await {
                    if window
                        .update(cx, |root, window, cx| {
                            root.receive_urls(urls, cx);
                            window.activate_window();
                            cx.activate(true);
                        })
                        .is_err()
                    {
                        break;
                    }
                }
            })
            .detach();
        }
        cx.activate(true);
    });
    // Windows installers can restart immediately. Release the lock and stop
    // forwarding before handing off, rather than forwarding to the old process.
    drop(instance);
    let prepared = pending_install.lock().unwrap().take();
    if let Some(prepared) = prepared {
        prepared.install_and_restart()?;
    }
    Ok(())
}
