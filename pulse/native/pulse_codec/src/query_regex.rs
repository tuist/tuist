//! Shared bounded Go/RE2-subset regex policy for metric and log queries.
//! Perl classes and word boundaries are ASCII; ordinary matching, including
//! `.`, remains Unicode/codepoint-aware. Reject Rust-only class extensions.

use std::borrow::Cow;

#[path = "query_regex_unicode.rs"]
mod unicode;

const PROGRAM_BYTES: usize = 1_048_576;

// HIR may erase captures in zero repetitions or impossible alternatives.
// Keep the source schema, not the optimized program's surviving declarations.
#[derive(Default)]
pub struct CaptureMetadata {
    pub count: usize,
    pub names: Vec<(String, usize)>,
}

impl CaptureMetadata {
    // Loki rejects repeated raw names, but numeric names are valid UTF-8
    // destinations. Normalize them once, preserving first extraction when
    // distinct names (1 and _1) normalize to the same label.
    pub fn into_parser_names(self) -> Option<Vec<(String, usize)>> {
        let mut raw = std::collections::HashSet::with_capacity(self.names.len());
        if self.names.iter().any(|(name, _)| !raw.insert(name)) {
            return None;
        }
        drop(raw);
        let mut names = std::collections::HashMap::with_capacity(self.names.len());
        for (mut name, index) in self.names {
            if name.as_bytes()[0].is_ascii_digit() {
                name.insert(0, '_');
            }
            names.entry(name).or_insert(index);
        }
        let mut names: Vec<_> = names.into_iter().collect();
        names.sort_unstable_by_key(|(_, index)| *index);
        Some(names)
    }
}

pub fn string(pattern: &str) -> Result<regex::Regex, regex::Error> {
    compile_string(pattern, false, false).map(|(regex, _)| regex)
}

pub fn string_with_metadata(
    pattern: &str,
) -> Result<(regex::Regex, CaptureMetadata), regex::Error> {
    compile_string(pattern, false, true)
}

pub fn anchored(pattern: &str) -> Result<regex::Regex, regex::Error> {
    compile_string(pattern, true, false).map(|(regex, _)| regex)
}

pub fn anchored_with_metadata(
    pattern: &str,
) -> Result<(regex::Regex, CaptureMetadata), regex::Error> {
    compile_string(pattern, true, true)
}

fn compile_string(
    pattern: &str,
    anchored: bool,
    capture_names: bool,
) -> Result<(regex::Regex, CaptureMetadata), regex::Error> {
    let (pattern, metadata) = translate(pattern, anchored, capture_names)?;
    regex::RegexBuilder::new(&pattern)
        .size_limit(PROGRAM_BYTES)
        .dfa_size_limit(PROGRAM_BYTES)
        .build()
        .map(|regex| (regex, metadata))
}

pub fn bytes(pattern: &str) -> Result<regex::bytes::Regex, regex::Error> {
    compile_bytes(pattern, false).map(|(regex, _)| regex)
}

pub fn bytes_with_metadata(
    pattern: &str,
) -> Result<(regex::bytes::Regex, CaptureMetadata), regex::Error> {
    compile_bytes(pattern, true)
}

fn compile_bytes(
    pattern: &str,
    capture_names: bool,
) -> Result<(regex::bytes::Regex, CaptureMetadata), regex::Error> {
    let (pattern, metadata) = translate(pattern, false, capture_names)?;
    regex::bytes::RegexBuilder::new(&pattern)
        .size_limit(PROGRAM_BYTES)
        .dfa_size_limit(PROGRAM_BYTES)
        .build()
        .map(|regex| (regex, metadata))
}

fn translate(
    pattern: &str,
    anchored: bool,
    capture_names: bool,
) -> Result<(Cow<'_, str>, CaptureMetadata), regex::Error> {
    const PREFIX: &str = "(?s:\\A(?:";
    const SUFFIX: &str = ")\\z)";

    let normalized = normalize(pattern)?;
    let (counted, metadata, unnamed) = reject_class_extensions(&normalized, capture_names)?;
    let normalized = unnamed.map_or(normalized, Cow::Owned);
    let needs_translation = anchored
        || normalized.as_bytes().windows(2).any(|pair| {
            pair[0] == b'\\'
                && matches!(
                    pair[1],
                    b'd' | b'D' | b'w' | b'W' | b's' | b'S' | b'b' | b'B' | b'<' | b'>'
                )
        });
    let mut translated = if needs_translation {
        let mut out = String::with_capacity(
            normalized.len()
                + if anchored {
                    PREFIX.len() + SUFFIX.len()
                } else {
                    0
                },
        );
        if anchored {
            out.push_str(PREFIX);
        }
        let mut chars = normalized.chars();
        while let Some(ch) = chars.next() {
            if ch != '\\' {
                out.push(ch);
                continue;
            }
            match chars.next() {
                Some('d') => out.push_str("[0-9]"),
                Some('D') => out.push_str("[^0-9]"),
                Some('w') => out.push_str("[A-Za-z0-9_]"),
                Some('W') => out.push_str("[^A-Za-z0-9_]"),
                Some('s') => out.push_str(r"[\t\n\f\r ]"),
                Some('S') => out.push_str(r"[^\t\n\f\r ]"),
                Some('b') => out.push_str(r"(?-u:\b)"),
                Some('B') => out.push_str(r"(?-u:\B)"),
                Some(next @ ('<' | '>')) => out.push(next),
                Some(next) => {
                    out.push('\\');
                    out.push(next);
                }
                None => out.push('\\'),
            }
        }
        Cow::Owned(out)
    } else {
        normalized
    };
    if counted {
        let raw = &translated[if anchored { PREFIX.len() } else { 0 }..];
        let ast = regex_syntax::ast::parse::Parser::new()
            .parse(raw)
            .map_err(|error| regex::Error::Syntax(error.to_string()))?;
        repetition_factor(&ast)?;
    }
    if anchored {
        translated.to_mut().push_str(SUFFIX);
    }
    Ok((expand_properties(translated)?, metadata))
}

// Only property-bearing patterns pay for this pass. Validate the original
// class grammar/schema first; generated nested classes are implementation
// syntax, not permission for callers to use Rust class extensions. Static
// Unicode 17 ranges avoid depending on regex's Unicode 16 tables or aliases.
fn expand_properties(pattern: Cow<'_, str>) -> Result<Cow<'_, str>, regex::Error> {
    if !pattern
        .as_bytes()
        .windows(2)
        .any(|pair| matches!(pair, b"\\p" | b"\\P"))
    {
        return Ok(pattern);
    }
    if pattern.len() > PROGRAM_BYTES {
        return Err(regex::Error::CompiledTooBig(PROGRAM_BYTES));
    }
    let mut out = String::new();
    let mut copied = 0;
    let mut expanded = 0usize;
    let mut folded = false;
    let mut scopes = Vec::new();
    let mut chars = pattern.char_indices().peekable();
    while let Some((offset, ch)) = chars.next() {
        match ch {
            '\\' => {
                let Some((_, kind)) = chars.next() else {
                    break;
                };
                if !matches!(kind, 'p' | 'P') {
                    continue;
                }
                let Some((start, first)) = chars.next() else {
                    return Err(regex::Error::Syntax("Missing Unicode property".into()));
                };
                let name = if first == '{' {
                    let Some((end, _)) = chars.find(|(_, c)| *c == '}') else {
                        return Err(regex::Error::Syntax("Unclosed Unicode property".into()));
                    };
                    &pattern[start + 1..end]
                } else {
                    &pattern[start..start + first.len_utf8()]
                };
                let end = chars.peek().map_or(pattern.len(), |(index, _)| *index);
                let class = property_class(name, folded, kind == 'P', &mut expanded)?;
                out.push_str(&pattern[copied..offset]);
                push_property_class(&mut out, &class, pattern.len() - end)?;
                copied = end;
            }
            '[' => {
                let mut depth = 1usize;
                while let Some((_, next)) = chars.next() {
                    match next {
                        '\\' => {
                            chars.next();
                        }
                        '[' => depth += 1,
                        ']' => {
                            depth -= 1;
                            if depth == 0 {
                                break;
                            }
                        }
                        _ => (),
                    }
                }
                let end = chars.peek().map_or(pattern.len(), |(index, _)| *index);
                let source = &pattern[offset..end];
                if !source
                    .as_bytes()
                    .windows(2)
                    .any(|pair| matches!(pair, b"\\p" | b"\\P"))
                {
                    continue;
                }
                let mut ast = regex_syntax::ast::parse::Parser::new()
                    .parse(source)
                    .map_err(|error| regex::Error::Syntax(error.to_string()))?;
                let regex_syntax::ast::Ast::ClassBracketed(ref mut bracket) = ast else {
                    unreachable!("a normalized complete bracket is a class");
                };
                let negated = bracket.negated;
                bracket.negated = false;
                let regex_syntax::ast::ClassSet::Item(ref mut item) = bracket.kind else {
                    unreachable!("original set operations were rejected");
                };
                let mut class = property_members(item, folded, &mut expanded)?;
                // Fold ordinary members separately. Folding an already-expanded
                // property again changes Go's LC table (notably U+0345).
                let rest = regex_syntax::hir::translate::TranslatorBuilder::new()
                    .case_insensitive(folded)
                    .build()
                    .translate(source, &ast)
                    .map_err(|error| regex::Error::Syntax(error.to_string()))?;
                match rest.into_kind() {
                    regex_syntax::hir::HirKind::Class(regex_syntax::hir::Class::Unicode(rest)) => {
                        class.union(&rest)
                    }
                    // HIR canonicalizes every empty class to a byte class.
                    regex_syntax::hir::HirKind::Class(regex_syntax::hir::Class::Bytes(_)) => (),
                    regex_syntax::hir::HirKind::Literal(rest) => {
                        for ch in std::str::from_utf8(&rest.0).unwrap().chars() {
                            class.push(regex_syntax::hir::ClassUnicodeRange::new(ch, ch));
                        }
                    }
                    _ => unreachable!("a Unicode bracket translates to a class or literal"),
                }
                if negated {
                    negate_property_class(&mut class);
                }
                out.push_str(&pattern[copied..offset]);
                push_property_class(&mut out, &class, pattern.len() - end)?;
                copied = end;
            }
            '(' => {
                if chars.peek().is_some_and(|(_, c)| *c == '?') {
                    let (set, clear, _, end, flag) = modifier_flags(chars.clone().skip(1))?;
                    if flag == ':' {
                        scopes.push(folded);
                    }
                    folded = set & 1 != 0 || (folded && clear & 1 == 0);
                    while chars.peek().is_some_and(|(index, _)| *index <= end) {
                        chars.next();
                    }
                } else {
                    scopes.push(folded);
                }
            }
            ')' => folded = scopes.pop().unwrap_or(false),
            _ => (),
        }
    }
    if copied == 0 {
        Ok(pattern)
    } else {
        out.push_str(&pattern[copied..]);
        Ok(Cow::Owned(out))
    }
}

fn property_class(
    name: &str,
    folded: bool,
    negated: bool,
    expanded: &mut usize,
) -> Result<regex_syntax::hir::ClassUnicode, regex::Error> {
    // Go ignores ASCII spaces, underscores, hyphens and case, not arbitrary
    // whitespace, ISO script aliases or property=value syntax. Names never
    // require a heap allocation, even with long runs of ignored bytes.
    let mut key = [0u8; 32];
    let mut len = 0;
    for byte in name.bytes().filter(|b| !matches!(b, b' ' | b'_' | b'-')) {
        if len == key.len() || !byte.is_ascii() {
            return Err(regex::Error::Syntax("Invalid Unicode property".into()));
        }
        key[len] = byte.to_ascii_lowercase();
        len += 1;
    }
    let (base, fold) = unicode::ranges(std::str::from_utf8(&key[..len]).unwrap())
        .ok_or_else(|| regex::Error::Syntax("Unknown Unicode property".into()))?;
    let ranges = base.iter().chain(if folded { fold } else { &[] });
    // Charge each declaration before union/zero-repeat simplification. The
    // maximum textual range is two 10-byte scalar escapes plus a hyphen.
    *expanded += ranges.clone().count() * 21 + 24;
    if *expanded > PROGRAM_BYTES {
        return Err(regex::Error::CompiledTooBig(PROGRAM_BYTES));
    }
    let mut class = regex_syntax::hir::ClassUnicode::new(
        ranges.map(|&(lo, hi)| regex_syntax::hir::ClassUnicodeRange::new(lo, hi)),
    );
    if negated {
        negate_property_class(&mut class);
    }
    Ok(class)
}

fn property_members(
    item: &mut regex_syntax::ast::ClassSetItem,
    folded: bool,
    expanded: &mut usize,
) -> Result<regex_syntax::hir::ClassUnicode, regex::Error> {
    use regex_syntax::ast::{ClassSetItem, ClassUnicodeKind};
    let mut class = regex_syntax::hir::ClassUnicode::empty();
    match item {
        ClassSetItem::Unicode(property) => {
            let mut one = [0u8; 4];
            let name: &str = match &property.kind {
                ClassUnicodeKind::OneLetter(ch) => ch.encode_utf8(&mut one),
                ClassUnicodeKind::Named(name) => name,
                ClassUnicodeKind::NamedValue { .. } => {
                    return Err(regex::Error::Syntax("Unsupported Unicode property".into()))
                }
            };
            class = property_class(name, folded, property.negated, expanded)?;
            *item = ClassSetItem::Empty(property.span);
        }
        ClassSetItem::Union(union) => {
            for item in &mut union.items {
                class.union(&property_members(item, folded, expanded)?);
            }
        }
        _ => (),
    }
    Ok(class)
}

fn negate_property_class(class: &mut regex_syntax::hir::ClassUnicode) {
    // regex-syntax 0.8.11's complement treats the surrogate hole as a gap
    // between scalar ranges and inverts its endpoints into two real matches.
    // Bridge adjacent scalar endpoints before complementing; no surrogate
    // becomes an accepted input or a range endpoint.
    if class
        .ranges()
        .windows(2)
        .any(|pair| pair[0].end() == '\u{d7ff}' && pair[1].start() == '\u{e000}')
    {
        class.push(regex_syntax::hir::ClassUnicodeRange::new(
            '\u{d7ff}', '\u{e000}',
        ));
    }
    class.negate();
}

fn push_property_class(
    out: &mut String,
    class: &regex_syntax::hir::ClassUnicode,
    remaining: usize,
) -> Result<(), regex::Error> {
    use std::fmt::Write;
    let maximum = class.ranges().len() * 21 + 24;
    if out.len() + remaining + maximum > PROGRAM_BYTES {
        return Err(regex::Error::CompiledTooBig(PROGRAM_BYTES));
    }
    // Disable Rust's second case-fold pass for this complete atom, including
    // unions and outer negation. Scoped noncaptures preserve capture indices.
    out.push_str("(?-i:[");
    if class.ranges().is_empty() {
        out.push_str(r"^\x{0}-\x{10ffff}");
    }
    for range in class.ranges() {
        write!(out, "\\x{{{:x}}}", u32::from(range.start())).unwrap();
        if range.start() != range.end() {
            write!(out, "-\\x{{{:x}}}", u32::from(range.end())).unwrap();
        }
    }
    out.push_str("])");
    Ok(())
}

// Normalize Go literals before interpreting classes, captures or repetition.
// Unchanged patterns borrow their input. Allocate only at an actual change,
// never a temporary allocation for each quoted run, octal character or brace.
pub(crate) fn normalize(pattern: &str) -> Result<Cow<'_, str>, regex::Error> {
    if !pattern.as_bytes().windows(2).any(|pair| {
        (pair[0] == b'\\' && matches!(pair[1], b'Q' | b'0'..=b'7'))
            || matches!(pair, b"&&" | b"~~" | b"(?")
    }) && !pattern.contains('[')
        && !pattern.contains('{')
    {
        return Ok(Cow::Borrowed(pattern));
    }
    let mut out = String::new();
    let mut copied = 0usize;
    let mut depth = 0usize;
    let mut class_atom = false;
    let mut class_range_end = false;
    let mut class_negated = false;
    let mut scalar_edges = 0u8;
    let mut ungreedy = false;
    let track_groups = pattern.contains('U') || pattern.contains("(?");
    let mut group_flags = Vec::new();
    let mut atom = None;
    let mut quantified_atom = false;
    let mut repeat_flags = (0u8, 0u8);
    let mut wraps = Vec::new();
    let last_named_end = pattern.rfind(":]");
    let mut chars = pattern.char_indices().peekable();
    while let Some((offset, ch)) = chars.next() {
        let output_offset = out.len() + offset - copied;
        if depth == 0 && !matches!(ch, '\\' | '(' | ')' | '|' | '*' | '+' | '?' | '{') {
            atom = Some((output_offset, ungreedy));
            quantified_atom = false;
            repeat_flags = (0, 0);
        }
        let range_end = class_range_end;
        if depth > 0 && ch != ']' {
            if class_negated {
                scalar_edges |= match ch {
                    '\u{d7ff}' => 1,
                    '\u{e000}' => 2,
                    _ => 0,
                };
            }
            if ch == '-' && class_atom && chars.peek().is_some_and(|(_, c)| *c != ']') {
                // A range consumes exactly one scalar at either end. A later
                // hyphen starts another member, never Rust set subtraction.
                class_atom = false;
                class_range_end = true;
                continue;
            }
            class_atom = !range_end;
            class_range_end = false;
        }
        if ch == '\\' {
            if depth == 0 && chars.peek().is_none_or(|(_, c)| *c != 'Q') {
                atom = Some((output_offset, ungreedy));
                quantified_atom = false;
                repeat_flags = (0, 0);
            }
            match chars.next() {
                Some((_, 'Q')) if depth == 0 => {
                    out.push_str(&pattern[copied..offset]);
                    while let Some((_, literal)) = chars.next() {
                        if literal == '\\' && chars.peek().is_some_and(|(_, c)| *c == 'E') {
                            chars.next();
                            break;
                        }
                        atom = Some((out.len(), ungreedy));
                        quantified_atom = false;
                        repeat_flags = (0, 0);
                        push_literal(&mut out, literal);
                    }
                    copied = chars.peek().map_or(pattern.len(), |(index, _)| *index);
                }
                Some((_, first @ '0'..='7')) => {
                    if first != '0' && !chars.peek().is_some_and(|(_, c)| matches!(c, '0'..='7')) {
                        return Err(regex::Error::Syntax("Invalid octal escape".into()));
                    }
                    let mut value = first as u32 - '0' as u32;
                    for _ in 1..3 {
                        if !chars.peek().is_some_and(|(_, c)| matches!(c, '0'..='7')) {
                            break;
                        }
                        value = value * 8 + chars.next().unwrap().1 as u32 - '0' as u32;
                    }
                    out.push_str(&pattern[copied..offset]);
                    push_literal(&mut out, char::from_u32(value).unwrap());
                    copied = chars.peek().map_or(pattern.len(), |(index, _)| *index);
                }
                Some((_, kind @ ('x' | 'p' | 'P'))) => {
                    if kind != 'x' {
                        if depth > 0 && range_end {
                            return Err(regex::Error::Syntax("Invalid character range".into()));
                        }
                        class_atom = false;
                    }
                    if chars.peek().is_some_and(|(_, c)| *c == '{') {
                        let (brace, _) = chars.next().unwrap();
                        if kind != 'x' && chars.peek().is_some_and(|(_, c)| *c == '^') {
                            // Go's leading property caret toggles p/P, even
                            // within a class. Reuse the normalization buffer;
                            // quotes and escaped backslashes never reach here.
                            let (caret, _) = chars.next().unwrap();
                            out.push_str(&pattern[copied..offset]);
                            out.push('\\');
                            out.push(if kind == 'p' { 'P' } else { 'p' });
                            out.push('{');
                            copied = caret + 1;
                        }
                        for (end, c) in chars.by_ref() {
                            if c == '}' {
                                if kind == 'x' && depth > 0 && class_negated {
                                    scalar_edges |=
                                        match u32::from_str_radix(&pattern[brace + 1..end], 16) {
                                            Ok(0xd7ff) => 1,
                                            Ok(0xe000) => 2,
                                            _ => 0,
                                        };
                                }
                                break;
                            }
                        }
                    } else {
                        for _ in 0..if kind == 'x' { 2 } else { 1 } {
                            chars.next();
                        }
                    }
                }
                Some((_, 'd' | 'D' | 's' | 'S' | 'w' | 'W')) => {
                    if depth > 0 && range_end {
                        return Err(regex::Error::Syntax("Invalid character range".into()));
                    }
                    class_atom = false;
                }
                _ => (),
            }
        } else if ch == '[' {
            if depth > 0 {
                if !range_end && posix_class(chars.clone().map(|(_, c)| c)) {
                    for (_, c) in chars.by_ref() {
                        if c == ']' {
                            break;
                        }
                    }
                    class_atom = false;
                    continue;
                }
                if !range_end
                    && chars.peek().is_some_and(|(_, c)| *c == ':')
                    && last_named_end.is_some_and(|end| end >= offset + 2)
                {
                    return Err(regex::Error::Syntax("Invalid named character class".into()));
                }
                out.push_str(&pattern[copied..offset]);
                out.push_str(r"\[");
                copied = offset + 1;
                continue;
            }
            depth += 1;
            class_atom = false;
            class_range_end = false;
            scalar_edges = 0;
            class_negated = chars.peek().is_some_and(|(_, c)| *c == '^');
            if class_negated {
                chars.next();
            }
            // Go permits a literal ] first, after optional negation.
            if let Some((index, ']')) = chars.peek().copied() {
                out.push_str(&pattern[copied..index]);
                out.push_str(r"\]");
                copied = index + 1;
                chars.next();
                class_atom = true;
            }
        } else if ch == ']' {
            if depth > 0 && class_negated && scalar_edges == 3 {
                // regex-syntax complements separate D7FF/E000 intervals by
                // reversing their empty scalar gap, reintroducing both ends.
                // Join endpoints already present: no new Unicode scalar is
                // added. Ordinary classes stay borrowed; no class expansion.
                out.push_str(&pattern[copied..offset]);
                out.push_str(r"\x{d7ff}-\x{e000}");
                copied = offset;
            }
            depth = depth.saturating_sub(1);
        } else if depth > 0
            && (ch == '-'
                || (matches!(ch, '&' | '~') && pattern.as_bytes()[offset - 1] == ch as u8))
        {
            // Escape literal members without changing actual range operators.
            out.push_str(&pattern[copied..offset]);
            out.push('\\');
            out.push(ch);
            copied = offset + 1;
        } else if ch == '(' && depth == 0 {
            // Validate raw headers before quotes/octals could turn invalid
            // Go syntax into a valid Rust capture or modifier. Quotes and
            // character-class members never enter this branch.
            let mut header = chars.clone().map(|(_, c)| c);
            if header.next() == Some('?') {
                let named = match header.next() {
                    Some('<') => true,
                    Some('P') => header.next() == Some('<'),
                    _ => false,
                };
                if named {
                    if track_groups {
                        group_flags.push((output_offset, ungreedy));
                    }
                    atom = None;
                    quantified_atom = false;
                    repeat_flags = (0, 0);
                    let mut empty = true;
                    loop {
                        match header.next() {
                            Some('>') if !empty => break,
                            Some(c) if c.is_ascii_alphanumeric() || c == '_' => empty = false,
                            _ => return Err(regex::Error::Syntax("Invalid capture name".into())),
                        }
                    }
                    for (_, c) in chars.by_ref() {
                        if c == '>' {
                            break;
                        }
                    }
                } else {
                    let (mut enabled, mut disabled, mut repeated, mut end, flag) =
                        modifier_flags(chars.clone().skip(1))?;
                    let mut tail = chars.clone();
                    while tail.peek().is_some_and(|(index, _)| *index <= end) {
                        tail.next();
                    }
                    if flag == ')' {
                        // Adjacent directives have no intervening atom. Merge
                        // once, so a following quantifier can still bind to the
                        // preceding atom instead of Rust's flag AST node.
                        loop {
                            let mut next = tail.clone();
                            if next.next().map(|(_, c)| c) != Some('(')
                                || next.next().map(|(_, c)| c) != Some('?')
                            {
                                break;
                            }
                            let Ok((set, clear, _, next_end, ')')) = modifier_flags(next.clone())
                            else {
                                break;
                            };
                            enabled = (enabled | set) & !clear;
                            disabled = (disabled | clear) & !set;
                            repeated = true;
                            end = next_end;
                            while next.peek().is_some_and(|(index, _)| *index <= end) {
                                next.next();
                            }
                            tail = next;
                        }
                    } else {
                        if track_groups {
                            group_flags.push((output_offset, ungreedy));
                        }
                        atom = None;
                        quantified_atom = false;
                        repeat_flags = (0, 0);
                    }
                    let next_ungreedy = if enabled & 8 != 0 {
                        true
                    } else {
                        ungreedy && disabled & 8 == 0
                    };
                    let mut repetition = None;
                    let mut lazy = false;
                    if flag == ')' {
                        if let Some((start, quantifier)) = tail.peek().copied() {
                            if matches!(quantifier, '*' | '+' | '?') {
                                tail.next();
                                repetition = Some((start, start + 1));
                            } else if quantifier == '{' {
                                if let Some((min, max)) =
                                    repeat_bounds(tail.clone().skip(1).map(|(_, c)| c))
                                {
                                    if min > 1000 || max.is_some_and(|max| max > 1000 || min > max)
                                    {
                                        return Err(regex::Error::Syntax(
                                            "Invalid repetition count".into(),
                                        ));
                                    }
                                    for (index, c) in tail.by_ref() {
                                        if c == '}' {
                                            repetition = Some((start, index + 1));
                                            break;
                                        }
                                    }
                                }
                            }
                            if repetition.is_some() && tail.peek().is_some_and(|(_, c)| *c == '?') {
                                tail.next();
                                lazy = true;
                            }
                        }
                    }
                    let consumed = tail.peek().map_or(pattern.len(), |(index, _)| *index);
                    let nested = repetition.is_some() && quantified_atom;
                    if nested {
                        let Some((start, _)) = atom else {
                            return Err(regex::Error::Syntax("Missing repetition argument".into()));
                        };
                        wraps.push(start);
                        // Wrapping scopes earlier moved directives. Restore
                        // their changes outside too, without changing flags
                        // the caller supplied (such as anchored DotNL).
                        let (set, clear) = (enabled, disabled);
                        enabled = (repeat_flags.0 | set) & !clear;
                        disabled = (repeat_flags.1 | clear) & !set;
                    }
                    if repeated || repetition.is_some() || (flag == ')' && enabled | disabled == 0)
                    {
                        out.push_str(&pattern[copied..offset]);
                        if let Some((start, end)) = repetition {
                            let base_ungreedy = if nested {
                                out.push(')');
                                atom.unwrap().1
                            } else {
                                ungreedy
                            };
                            out.push_str(&pattern[start..end]);
                            // Moving U past a quantifier must not change its
                            // greediness, including an explicit lazy suffix.
                            if lazy ^ (base_ungreedy != next_ungreedy) {
                                out.push('?');
                            }
                            quantified_atom = true;
                            repeat_flags = (enabled, disabled);
                        }
                        if enabled | disabled != 0 {
                            out.push_str("(?");
                            for (bits, prefix) in [(enabled, ""), (disabled, "-")] {
                                if bits != 0 {
                                    out.push_str(prefix);
                                    for (bit, name) in [(1, 'i'), (2, 'm'), (4, 's'), (8, 'U')] {
                                        if bits & bit != 0 {
                                            out.push(name);
                                        }
                                    }
                                }
                            }
                            out.push(flag);
                        }
                        copied = consumed;
                    }
                    chars = tail;
                    ungreedy = next_ungreedy;
                }
            } else {
                if track_groups {
                    group_flags.push((output_offset, ungreedy));
                }
                atom = None;
                quantified_atom = false;
                repeat_flags = (0, 0);
            }
        } else if ch == ')' && depth == 0 {
            atom = group_flags.pop();
            ungreedy = atom.is_some_and(|(_, flags)| flags);
            quantified_atom = false;
            repeat_flags = (0, 0);
        } else if ch == '|' && depth == 0 {
            atom = None;
            quantified_atom = false;
            repeat_flags = (0, 0);
        } else if matches!(ch, '*' | '+' | '?') && depth == 0 {
            quantified_atom = true;
            repeat_flags = (0, 0);
        } else if ch == '{' && depth == 0 {
            match repeat_bounds(chars.clone().map(|(_, c)| c)) {
                Some((min, max)) => {
                    if min > 1000 || max.is_some_and(|max| max > 1000 || min > max) {
                        return Err(regex::Error::Syntax("Invalid repetition count".into()));
                    }
                    chars.find(|(_, c)| *c == '}');
                    quantified_atom = true;
                    repeat_flags = (0, 0);
                }
                None => {
                    out.push_str(&pattern[copied..offset]);
                    out.push_str(r"\{");
                    copied = offset + 1;
                    atom = Some((output_offset, ungreedy));
                    quantified_atom = false;
                    repeat_flags = (0, 0);
                }
            }
        }
    }
    if copied == 0 {
        Ok(Cow::Borrowed(pattern))
    } else {
        out.push_str(&pattern[copied..]);
        if wraps.is_empty() {
            return Ok(Cow::Owned(out));
        }
        // Defer opens rather than repeatedly inserting/copying prefixes.
        // Only patterns needing nested wrappers pay this final linear copy;
        // offsets can arrive inside-out when a later repeat wraps a group.
        wraps.sort_unstable();
        let mut nested = String::with_capacity(out.len() + 3 * wraps.len());
        let mut copied = 0;
        for start in wraps {
            nested.push_str(&out[copied..start]);
            nested.push_str("(?:");
            copied = start;
        }
        nested.push_str(&out[copied..]);
        Ok(Cow::Owned(nested))
    }
}

fn modifier_flags(
    chars: impl Iterator<Item = (usize, char)>,
) -> Result<(u8, u8, bool, usize, char), regex::Error> {
    let (mut enabled, mut disabled) = (0u8, 0u8);
    let (mut negative, mut repeated) = (false, false);
    for (offset, flag) in chars {
        let bit = match flag {
            'i' => 1,
            'm' => 2,
            's' => 4,
            'U' => 8,
            '-' if !negative => {
                negative = true;
                continue;
            }
            ':' | ')' if !negative || disabled != 0 => {
                return Ok((enabled, disabled, repeated, offset, flag));
            }
            _ => return Err(regex::Error::Syntax("Invalid regex flags".into())),
        };
        repeated |= (enabled | disabled) & bit != 0;
        if negative {
            disabled |= bit;
            enabled &= !bit;
        } else {
            enabled |= bit;
        }
    }
    Err(regex::Error::Syntax("Unclosed regex flags".into()))
}

fn repeat_bounds(chars: impl Iterator<Item = char>) -> Option<(u32, Option<u32>)> {
    let mut chars = chars.peekable();
    let min = repeat_count(&mut chars)?;
    match chars.next()? {
        '}' => Some((min, Some(min))),
        ',' => {
            if chars.peek() == Some(&'}') {
                Some((min, None))
            } else {
                let max = repeat_count(&mut chars)?;
                (chars.next() == Some('}')).then_some((min, Some(max)))
            }
        }
        _ => None,
    }
}

fn repeat_count(chars: &mut std::iter::Peekable<impl Iterator<Item = char>>) -> Option<u32> {
    let first = chars.next()?;
    if !first.is_ascii_digit() || (first == '0' && chars.peek().is_some_and(char::is_ascii_digit)) {
        return None;
    }
    let mut value = first as u32 - '0' as u32;
    while let Some(c) = chars.peek().copied().filter(char::is_ascii_digit) {
        value = (value * 10 + c as u32 - '0' as u32).min(1001);
        chars.next();
    }
    Some(value)
}

// One bounded postorder walk, before HIR/automaton expansion. Inner invalid
// repeats reject even when an outer {0} would erase them. Finite {0} erases a
// valid inner factor; unbounded {0,} does not. Ordinary *, + and ? add no factor.
fn repetition_factor(ast: &regex_syntax::ast::Ast) -> Result<u32, regex::Error> {
    use regex_syntax::ast::{Ast, RepetitionKind, RepetitionRange};

    let factor = match ast {
        Ast::Repetition(repeat) => {
            let inner = repetition_factor(&repeat.ast)?;
            let count = match repeat.op.kind {
                RepetitionKind::Range(RepetitionRange::Exactly(n)) => n,
                RepetitionKind::Range(RepetitionRange::Bounded(_, max)) => max,
                RepetitionKind::Range(RepetitionRange::AtLeast(min)) => min.max(1),
                _ => 1,
            };
            inner.max(1) * count
        }
        Ast::Group(group) => repetition_factor(&group.ast)?,
        Ast::Concat(concat) => concat.asts.iter().try_fold(0, |max, sub| {
            repetition_factor(sub).map(|factor| max.max(factor))
        })?,
        Ast::Alternation(alternation) => alternation.asts.iter().try_fold(0, |max, sub| {
            repetition_factor(sub).map(|factor| max.max(factor))
        })?,
        _ => 1,
    };
    if factor > 1000 {
        Err(regex::Error::Syntax(
            "Invalid nested repetition count".into(),
        ))
    } else {
        Ok(factor)
    }
}

fn push_literal(out: &mut String, ch: char) {
    if "\\.+*?()|[]{}^$#&-~".contains(ch) {
        out.push('\\');
    }
    out.push(ch);
}

fn reject_class_extensions(
    pattern: &str,
    capture_names: bool,
) -> Result<(bool, CaptureMetadata, Option<String>), regex::Error> {
    let mut depth = 0usize;
    let mut groups = 0usize;
    let mut escaped = false;
    let mut previous = '\0';
    let mut active_counter = false;
    let mut previous_counter = false;
    let mut previous_lazy = false;
    let mut counted = false;
    let mut metadata = CaptureMetadata::default();
    let mut capture_bytes = 0;
    let mut unnamed = String::new();
    let mut copied = 0;
    let mut chars = pattern.chars();
    while let Some(ch) = chars.next() {
        if escaped {
            // Braced hex escapes are one atom, not a repetition counter.
            // Leave malformed escape validation to the regex compiler.
            if ch == 'x' && chars.clone().next() == Some('{') {
                for next in chars.by_ref() {
                    if next == '}' {
                        break;
                    }
                }
            }
            escaped = false;
            previous = '\0';
            previous_counter = false;
            previous_lazy = false;
            continue;
        }
        if ch == '\\' {
            escaped = true;
            previous = '\0';
            previous_counter = false;
            previous_lazy = false;
            continue;
        }
        if depth == 0 && ch == '(' {
            groups += 1;
            let mut flags = chars.clone();
            let mut named_header = None;
            let capture = if flags.next() == Some('?') {
                let mut header = flags.clone();
                let named = match header.next() {
                    Some('<') => true,
                    Some('P') => header.next() == Some('<'),
                    _ => false,
                };
                if named {
                    named_header = Some(header);
                }
                for flag in flags {
                    match flag {
                        'i' | 'm' | 's' | 'U' | '-' => (),
                        'u' | 'x' | 'R' => {
                            return Err(regex::Error::Syntax("Unsupported regex flag".into()))
                        }
                        _ => break,
                    }
                }
                named
            } else {
                true
            };
            if capture {
                metadata.count += 1;
                // Zero-repeat simplification can hide an arbitrarily large
                // schema from the compiled-program limit. Bound its logical
                // size independently: 32 bytes/group plus raw name bytes,
                // even for predicates that do not allocate capture names.
                capture_bytes += 32;
                if capture_bytes > PROGRAM_BYTES {
                    return Err(regex::Error::CompiledTooBig(PROGRAM_BYTES));
                }
                if let Some(header) = named_header {
                    // normalize already validated these raw ASCII headers.
                    let name = header.take_while(|&ch| ch != '>');
                    let len = name.clone().count();
                    if len > PROGRAM_BYTES - capture_bytes {
                        return Err(regex::Error::CompiledTooBig(PROGRAM_BYTES));
                    }
                    capture_bytes += len;
                    if capture_names {
                        metadata.names.push((name.collect(), metadata.count));
                    }
                    // Go permits numeric/repeated names that Rust rejects.
                    // Retain the schema above but compile ordinary captures;
                    // this single lazy copy never changes capture positions.
                    unnamed.push_str(&pattern[copied..pattern.len() - chars.as_str().len()]);
                    for next in chars.by_ref() {
                        if next == '>' {
                            break;
                        }
                    }
                    copied = pattern.len() - chars.as_str().len();
                }
            }
        }
        if depth == 0 && ch == ')' {
            // A malformed raw pattern must not balance against our anchoring
            // wrapper. Check scope in this existing pass, not a second compile.
            groups = groups
                .checked_sub(1)
                .ok_or_else(|| regex::Error::Syntax("Unbalanced regex group".into()))?;
        }
        let follows_repetition = matches!(previous, '*' | '+' | '?') || previous_counter;
        if depth == 0 && ch == '{' {
            active_counter = repetition_counter(chars.clone());
            counted |= active_counter;
            if active_counter && follows_repetition {
                return Err(regex::Error::Syntax("Unsupported nested repetition".into()));
            }
        }
        if depth == 0
            && ((matches!(ch, '*' | '+') && follows_repetition) || (ch == '?' && previous_lazy))
        {
            return Err(regex::Error::Syntax(
                "Unsupported nested/possessive repetition".into(),
            ));
        }
        if (depth > 0 && ch == previous && matches!(ch, '&' | '-' | '~'))
            || (depth > 0 && ch == '[' && !posix_class(chars.clone()))
        {
            return Err(regex::Error::Syntax(
                "Unsupported character-class extension".into(),
            ));
        }
        if ch == '[' {
            depth += 1;
        }
        if ch == ']' {
            depth = depth.saturating_sub(1);
        }
        previous_lazy = depth == 0 && ch == '?' && follows_repetition;
        previous_counter = ch == '}' && active_counter;
        if ch == '}' {
            active_counter = false;
        }
        previous = ch;
    }
    if groups != 0 {
        return Err(regex::Error::Syntax("Unbalanced regex group".into()));
    }
    let unnamed = if copied == 0 {
        None
    } else {
        unnamed.push_str(&pattern[copied..]);
        Some(unnamed)
    };
    Ok((counted, metadata, unnamed))
}

fn repetition_counter(mut chars: impl Iterator<Item = char>) -> bool {
    if !chars.next().is_some_and(|ch| ch.is_ascii_digit()) {
        return false;
    }
    let mut comma = false;
    for ch in chars {
        match ch {
            '0'..='9' => (),
            ',' if !comma => comma = true,
            '}' => return true,
            _ => return false,
        }
    }
    false
}

fn posix_class(chars: impl Iterator<Item = char>) -> bool {
    let mut chars = chars.peekable();
    if chars.next() != Some(':') {
        return false;
    }
    if chars.peek() == Some(&'^') {
        chars.next();
    }
    // The longest supported name is xdigit. Inspect at most six ASCII bytes
    // on the stack instead of allocating a lookahead string per class.
    let mut name = [0u8; 6];
    let mut len = 0;
    loop {
        match chars.next() {
            Some(':') if chars.next() == Some(']') => break,
            Some(ch) if ch.is_ascii_lowercase() && len < name.len() => {
                name[len] = ch as u8;
                len += 1;
            }
            _ => return false,
        }
    }
    matches!(
        &name[..len],
        b"alnum"
            | b"alpha"
            | b"ascii"
            | b"blank"
            | b"cntrl"
            | b"digit"
            | b"graph"
            | b"lower"
            | b"print"
            | b"punct"
            | b"space"
            | b"upper"
            | b"word"
            | b"xdigit"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn byte_and_string_engines_share_codepoints_ascii_classes_and_strict_end() {
        for pattern in [
            "(?u).",
            "(?ix)a",
            "(?R)$",
            r"[\Qx\E]",
            r"\Q\E*",
            r"\1",
            r"\8",
            r"\E",
            "^a*+a$",
            "a{2}+",
            "a**",
            "a{2}{3}",
            "a*{2}",
            "a+{2}",
            "a?{1}",
            r"\x{}",
            r"\x{61",
            r"\x{110000}",
            r"\x{zz}",
            r"\x{61}{2}+",
            r"\x{61}*{2}",
            r"\\x{2}+",
            "a???",
            "a{2}??",
            r"\x{61}{2}??",
            r"\x{61}???",
            r"\x{61}+??",
            r"\x{61}*??",
        ] {
            assert!(string(pattern).is_err());
            assert!(bytes(pattern).is_err());
        }
        for (pattern, value, expected) in [
            (r"^.$", "é", true),
            (r"^\d$", "٣", false),
            (r"^\w$", "é", false),
            (r"\bfoo\b", "éfooé", true),
            (r"^.$", "a\n", false),
            (r"(?s)^.$", "\n", true),
            (r"^\s$", "\u{b}", false),
            (r"^[\S]$", "\u{b}", true),
            (r"(?i)^[\W]$", "K", false),
            (r"\<foo", "a foo", false),
            (r"\<foo", "<foo", true),
            (r"^[[:alpha:]]$", "a", true),
            (r"^[^]]$", "a", true),
            (r"^[^]]$", "]", false),
            (r"^[^]\d]$", "a", true),
            (r"^[a^]$", "^", true),
            (r"^a}*$", "a}}", true),
            (r"^\{2}*$", "{2}}", true),
            (r"^[\W^]$", "b", false),
            (r"^[\W^]$", "^", true),
            (r"^a{2}\*+$", "aa***", true),
            (r"^a{2}\d+$", "aa123", true),
            (r"^\x{61}+$", "aa", true),
            (r"^\x{61}{2}$", "a", false),
            (r"^\x{61}{2}$", "aa", true),
            (r"^\x{61}{2}$", "aaa", false),
            (r"^\x{61}??$", "", true),
            (r"^\x{61}??$", "a", true),
            (r"^\x{61}??$", "aa", false),
            (r"^\x{61}{2}?$", "aa", true),
            (r"^a??\??$", "?", true),
            (r"^a??\??$", "??", false),
        ] {
            assert_eq!(string(pattern).unwrap().is_match(value), expected);
            assert_eq!(bytes(pattern).unwrap().is_match(value.as_bytes()), expected);
        }
    }
}
