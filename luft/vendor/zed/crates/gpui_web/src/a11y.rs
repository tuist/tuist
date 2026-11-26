//! Accessibility for the browser platform.
//!
//! GPUI draws into one canvas, which assistive technology cannot read. This
//! adapter mirrors GPUI's AccessKit tree into transparent DOM elements with
//! ARIA roles, positioned over what the canvas draws, the approach Flutter's
//! web engine takes. Screen readers read and activate those elements; a DOM
//! click becomes an AccessKit `Click` request that GPUI handles like a native
//! adapter's. The elements ignore the pointer, so mouse input still reaches
//! the canvas.

use std::collections::{HashMap, HashSet};

use accesskit::{Action, ActionRequest, Node, NodeId, Rect, Role, TreeId, TreeUpdate};
use gpui::A11yCallbacks;
use wasm_bindgen::{JsCast, closure::Closure};

const HOST_STYLE: &str = "position:fixed;inset:0;pointer-events:none;overflow:hidden;\
     color:transparent;background:transparent;";
const NODE_STYLE: &str = "position:fixed;margin:0;padding:0;border:0;box-sizing:border-box;\
     overflow:hidden;color:transparent;background:transparent;white-space:pre;";

type ActionCallback = std::rc::Rc<dyn Fn(ActionRequest) + Send>;

struct Mirrored {
    element: web_sys::HtmlElement,
    children: Vec<NodeId>,
    bounds: Option<Rect>,
    on_click: Option<Closure<dyn FnMut(web_sys::Event)>>,
}

pub(crate) struct WebA11y {
    document: web_sys::Document,
    host: web_sys::HtmlElement,
    action: ActionCallback,
    nodes: HashMap<NodeId, Node>,
    root: Option<NodeId>,
    mirrored: HashMap<NodeId, Mirrored>,
}

impl WebA11y {
    /// Activates GPUI's accessibility tree at once: a browser cannot tell
    /// the page whether a screen reader is running.
    pub(crate) fn new(
        document: web_sys::Document,
        callbacks: A11yCallbacks,
        scale_factor: f32,
    ) -> Option<Self> {
        let host: web_sys::HtmlElement = document.create_element("div").ok()?.dyn_into().ok()?;
        host.set_attribute("style", HOST_STYLE).ok()?;
        host.set_attribute("data-gpui-accessibility", "").ok()?;
        document.body()?.append_child(&host).ok()?;
        let mut this = Self {
            document,
            host,
            action: callbacks.action.into(),
            nodes: HashMap::new(),
            root: None,
            mirrored: HashMap::new(),
        };
        if let Some(initial) = (callbacks.activation)() {
            this.update(initial, scale_factor);
        }
        Some(this)
    }

    pub(crate) fn update(&mut self, update: TreeUpdate, scale_factor: f32) {
        if let Some(tree) = &update.tree {
            self.root = Some(tree.root);
        }
        for (id, node) in update.nodes {
            self.nodes.insert(id, node);
        }
        let Some(root) = self.root else { return };
        let mut seen = HashSet::new();
        self.sync(root, scale_factor, &mut seen);
        if let Some(root) = self.mirrored.get(&root)
            && !is_child_of(&root.element, &self.host)
        {
            let _ = self.host.append_child(&root.element);
        }
        self.mirrored.retain(|id, mirrored| {
            let keep = seen.contains(id);
            if !keep {
                mirrored.element.remove();
            }
            keep
        });
        self.nodes.retain(|id, _| seen.contains(id));
    }

    /// Brings one node's element and its subtree up to date, reusing
    /// elements by node ID so the screen reader's position survives frames.
    fn sync(&mut self, id: NodeId, scale_factor: f32, seen: &mut HashSet<NodeId>) {
        let Some(node) = self.nodes.get(&id).cloned() else {
            return;
        };
        if !seen.insert(id) {
            return;
        }
        if !self.mirrored.contains_key(&id) {
            let Some(element) = self
                .document
                .create_element("div")
                .ok()
                .and_then(|element| element.dyn_into::<web_sys::HtmlElement>().ok())
            else {
                return;
            };
            let _ = element.set_attribute("style", NODE_STYLE);
            self.mirrored.insert(
                id,
                Mirrored {
                    element,
                    children: Vec::new(),
                    bounds: None,
                    on_click: None,
                },
            );
        }

        let children = node.children().to_vec();
        for child in &children {
            self.sync(*child, scale_factor, seen);
        }

        let action = self.action.clone();
        let mirrored = self.mirrored.get_mut(&id).expect("created above");
        let element = mirrored.element.clone();
        apply_attributes(&element, &node);

        let bounds = node.bounds();
        if bounds != mirrored.bounds {
            mirrored.bounds = bounds;
            let style = element.style();
            if let Some(bounds) = bounds {
                let scale = scale_factor as f64;
                let _ = style.set_property("left", &format!("{}px", bounds.x0 / scale));
                let _ = style.set_property("top", &format!("{}px", bounds.y0 / scale));
                let _ = style.set_property("width", &format!("{}px", bounds.width() / scale));
                let _ = style.set_property("height", &format!("{}px", bounds.height() / scale));
            }
        }

        let clickable = node.supports_action(Action::Click) && !node.is_disabled();
        if clickable && mirrored.on_click.is_none() {
            let closure = Closure::<dyn FnMut(web_sys::Event)>::new(move |event: web_sys::Event| {
                event.prevent_default();
                action(ActionRequest {
                    action: Action::Click,
                    target_tree: TreeId::ROOT,
                    target_node: id,
                    data: None,
                });
            });
            let _ = element
                .add_event_listener_with_callback("click", closure.as_ref().unchecked_ref());
            mirrored.on_click = Some(closure);
        } else if !clickable && let Some(closure) = mirrored.on_click.take() {
            let _ = element
                .remove_event_listener_with_callback("click", closure.as_ref().unchecked_ref());
        }

        let reorder = mirrored.children != children
            || children.iter().any(|child| {
                self.mirrored
                    .get(child)
                    .is_some_and(|child| !is_child_of(&child.element, &element))
            });
        if reorder {
            for child in &children {
                if let Some(child) = self.mirrored.get(child) {
                    let _ = element.append_child(&child.element);
                }
            }
            self.mirrored.get_mut(&id).expect("created above").children = children;
        }
    }
}

fn is_child_of(child: &web_sys::HtmlElement, parent: &web_sys::HtmlElement) -> bool {
    child
        .parent_node()
        .is_some_and(|node| node.is_same_node(Some(parent)))
}

fn set_attribute(element: &web_sys::HtmlElement, name: &str, value: Option<&str>) {
    match value {
        Some(value) if element.get_attribute(name).as_deref() != Some(value) => {
            let _ = element.set_attribute(name, value);
        }
        None if element.has_attribute(name) => {
            let _ = element.remove_attribute(name);
        }
        _ => {}
    }
}

fn apply_attributes(element: &web_sys::HtmlElement, node: &Node) {
    let role = aria_role(node.role());
    set_attribute(element, "role", role);
    set_attribute(element, "aria-label", node.label());
    set_attribute(element, "aria-description", node.description());
    let level = node.level().map(|level| level.to_string());
    set_attribute(element, "aria-level", level.as_deref());
    set_attribute(element, "aria-disabled", node.is_disabled().then_some("true"));
    set_attribute(element, "aria-hidden", node.is_hidden().then_some("true"));

    // Text nodes carry their text as a value and have no ARIA role; the
    // element's text content is what a screen reader reads.
    if node.role() == Role::Label && node.children().is_empty() {
        let text = node.value().or(node.label()).unwrap_or_default();
        if element.text_content().as_deref() != Some(text) {
            element.set_text_content(Some(text));
        }
    }
}

fn aria_role(role: Role) -> Option<&'static str> {
    Some(match role {
        Role::Button | Role::DefaultButton => "button",
        Role::Heading => "heading",
        Role::Link => "link",
        Role::Image => "img",
        Role::TextInput | Role::MultilineTextInput | Role::SearchInput => "textbox",
        Role::CheckBox => "checkbox",
        Role::Switch => "switch",
        Role::RadioButton => "radio",
        Role::List => "list",
        Role::ListItem => "listitem",
        Role::Form => "form",
        Role::Dialog => "dialog",
        Role::Menu => "menu",
        Role::MenuItem => "menuitem",
        Role::Tab => "tab",
        Role::TabList => "tablist",
        Role::TabPanel => "tabpanel",
        Role::Navigation => "navigation",
        Role::Main => "main",
        Role::Group => "group",
        Role::Status => "status",
        Role::Alert => "alert",
        _ => return None,
    })
}
