mod route;

pub use route::{Preview, Route, RouteError};
pub use tuist_app_core::Tab;

#[derive(Debug, Default)]
pub struct Navigation {
    pub tab: Tab,
    pub preview: Option<Preview>,
    pub error: Option<RouteError>,
    pub luft: tuist_app_core::navigation::Navigation,
    pending: Option<Route>,
}

impl Navigation {
    pub fn receive(&mut self, value: &str, server: &url::Url) {
        // Authentication callbacks must not replace a pending navigation link.
        if value.split_once("://").is_some_and(|(scheme, rest)| {
            scheme.eq_ignore_ascii_case("tuist")
                && !rest
                    .split(['/', '?', '#'])
                    .next()
                    .unwrap_or("")
                    .eq_ignore_ascii_case("app")
        }) {
            return;
        }
        match Route::parse(value, server) {
            Ok(route) => {
                self.pending = Some(route);
                self.error = None;
            }
            Err(error) => self.error = Some(error),
        }
    }

    pub fn resume(&mut self) {
        if let Some(route) = self.pending.take() {
            self.navigate(route);
        }
    }

    /// A preview link opens its handoff page over the current tab. Luft has
    /// no previews list, so the shared previews link opens the first tab.
    pub fn navigate(&mut self, route: Route) {
        self.error = None;
        match route {
            Route::Previews => self.select(Tab::Threads),
            Route::Profile => self.select(Tab::Profile),
            Route::Preview(preview) => self.preview = Some(preview),
            Route::Luft(destination) => {
                self.luft.navigate(destination);
                self.tab = Tab::from_id(self.luft.tab).unwrap_or_default();
                self.preview = None;
            }
        }
    }

    pub fn select(&mut self, tab: Tab) {
        self.tab = tab;
        self.preview = None;
        let _ = self.luft.select(tab.id());
    }

    pub fn reset(&mut self) {
        self.tab = Tab::Threads;
        self.preview = None;
        self.error = None;
        self.pending = None;
        self.luft.reset();
    }
}

#[cfg(test)]
mod tests;
