mod route;

pub use route::{Preview, Route, RouteError};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Tab {
    #[default]
    Previews,
    Profile,
}

#[derive(Debug, Default)]
pub struct Navigation {
    pub tab: Tab,
    pub preview: Option<Preview>,
    pub error: Option<RouteError>,
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

    pub fn navigate(&mut self, route: Route) {
        self.error = None;
        match route {
            Route::Previews => {
                self.tab = Tab::Previews;
                self.preview = None;
            }
            Route::Profile => self.tab = Tab::Profile,
            Route::Preview(preview) => {
                self.tab = Tab::Previews;
                self.preview = Some(preview);
            }
        }
    }

    pub fn reset(&mut self) {
        self.tab = Tab::Previews;
        self.preview = None;
        self.error = None;
    }
}

#[cfg(test)]
mod tests;
