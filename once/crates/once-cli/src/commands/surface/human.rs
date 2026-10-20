use console::style;

use super::model::{ArgKind, ArgSurface, CommandSurface};

pub(super) fn render(surface: &CommandSurface) -> String {
    let mut out = String::new();
    render_command(surface, "", true, true, &mut out);
    out
}

fn render_command(
    command: &CommandSurface,
    prefix: &str,
    last: bool,
    root: bool,
    out: &mut String,
) {
    let branch = if root {
        ""
    } else if last {
        "└── "
    } else {
        "├── "
    };
    out.push_str(prefix);
    out.push_str(branch);
    out.push_str(&style(command.name.as_str()).bold().cyan().to_string());
    if let Some(about) = &command.about {
        out.push_str("  ");
        out.push_str(about);
    }
    out.push('\n');

    let child_prefix = if root {
        String::new()
    } else if last {
        format!("{prefix}    ")
    } else {
        format!("{prefix}│   ")
    };

    let arg_count = command.args.len();
    let sub_count = command.subcommands.len();
    for (index, arg) in command.args.iter().enumerate() {
        let is_last = index + 1 == arg_count && sub_count == 0;
        render_arg(arg, &child_prefix, is_last, out);
    }
    for (index, subcommand) in command.subcommands.iter().enumerate() {
        let is_last = index + 1 == sub_count;
        render_command(subcommand, &child_prefix, is_last, false, out);
    }
}

fn render_arg(arg: &ArgSurface, prefix: &str, last: bool, out: &mut String) {
    let branch = if last { "└── " } else { "├── " };
    out.push_str(prefix);
    out.push_str(branch);
    out.push_str(&style(arg.syntax.as_str()).yellow().to_string());
    out.push_str("  ");
    if arg.required {
        out.push_str(&style("required").dim().to_string());
        out.push_str("; ");
    }
    out.push_str(match arg.kind {
        ArgKind::Flag => "flag",
        ArgKind::Option => "option",
        ArgKind::Positional => "positional",
    });
    if let Some(help) = &arg.help {
        out.push_str("; ");
        out.push_str(help);
    }
    out.push('\n');
}
