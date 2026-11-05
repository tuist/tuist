//! Log pattern mining for Loki's `/loki/api/v1/patterns`.
//!
//! An implementation of Drain (He et al., "Drain: An Online Log Parsing
//! Approach with Fixed Depth Tree", ICWS 2017). Lines are split into word
//! tokens and punctuation tokens. Lines only cluster with templates that have
//! the same number of tokens and the same punctuation at the same positions;
//! within those, a fixed-depth tree keyed by the leading words narrows the
//! candidates, and a line joins the most similar template when enough of its
//! words match, turning differing words into the `<_>` wildcard. Each template
//! counts its lines per time step.
//!
//! Patterns are heuristics: the result depends on line order and is not
//! meant to reproduce another implementation's clusters. Rendered patterns
//! are valid LogQL `|>` line filters for the lines they summarize.
use std::collections::{BTreeMap, HashMap};

pub const WILDCARD: &str = "<_>";
const MAX_LINE_BYTES: usize = 4096;
const MAX_TOKENS: usize = 128;
const MIN_WORDS: usize = 2;
// Leading words that route a line through the tree; similarity decides the rest.
const PREFIX_DEPTH: usize = 1;
const MAX_CHILDREN: usize = 32;
const SIMILARITY: f64 = 0.4;
const MAX_CLUSTERS: usize = 500;
const PUNCTUATION: &[u8] = b"=,;()[]{}\"'";

// Token count plus every punctuation token with its position.
type Shape = (usize, Vec<(usize, Box<[u8]>)>);
/// A rendered pattern with its `(bucket_start, count)` samples.
pub type Pattern = (Vec<u8>, Vec<(i64, u64)>);

#[derive(Clone, PartialEq, Eq, Hash)]
enum Kind {
    Word,
    Punct,
}

#[derive(Clone)]
struct Token<'l> {
    text: &'l [u8],
    kind: Kind,
    space_before: bool,
}

struct Slot {
    // None is the wildcard.
    text: Option<Box<[u8]>>,
    kind: Kind,
    space_before: bool,
}

struct Cluster {
    slots: Vec<Slot>,
    counts: BTreeMap<i64, u64>,
    last_used: u64,
}

#[derive(Default)]
struct Node {
    children: HashMap<Option<Box<[u8]>>, Node>,
    clusters: Vec<usize>,
}

pub struct Miner {
    start: i64,
    step: i64,
    roots: HashMap<Shape, Node>,
    clusters: Vec<Option<Cluster>>,
    live: usize,
    clock: u64,
    skipped: u64,
}

impl Miner {
    pub fn new(start: i64, step: i64) -> Self {
        Miner {
            start,
            step: step.max(1),
            roots: HashMap::new(),
            clusters: Vec::new(),
            live: 0,
            clock: 0,
            skipped: 0,
        }
    }

    #[cfg(test)]
    /// Lines that were too long, too short or had too many tokens to cluster.
    pub fn skipped(&self) -> u64 {
        self.skipped
    }

    pub fn train(&mut self, ts: i64, line: &[u8]) {
        if line.len() > MAX_LINE_BYTES {
            self.skipped += 1;
            return;
        }
        let tokens = match tokenize(line) {
            Some(tokens) => tokens,
            None => {
                self.skipped += 1;
                return;
            }
        };
        self.clock += 1;
        let bucket = self.start + (ts - self.start).div_euclid(self.step) * self.step;
        let key = shape(&tokens);
        let id = match self.search(&key, &tokens) {
            Some(id) => {
                let cluster = self.clusters[id].as_mut().expect("live cluster");
                merge(cluster, &tokens);
                id
            }
            None => self.insert(key, &tokens),
        };
        let cluster = self.clusters[id].as_mut().expect("live cluster");
        cluster.last_used = self.clock;
        *cluster.counts.entry(bucket).or_insert(0) += 1;
    }

    fn search(&self, key: &Shape, tokens: &[Token]) -> Option<usize> {
        let mut node = self.roots.get(key)?;
        for token in words(tokens).take(PREFIX_DEPTH) {
            node = node
                .children
                .get(&Some(Box::<[u8]>::from(token.text)))
                .or_else(|| node.children.get(&None))?;
        }
        let mut best: Option<(f64, usize, usize)> = None;
        for &id in &node.clusters {
            let Some(cluster) = self.clusters[id].as_ref() else {
                continue;
            };
            let (score, wildcards) = similarity(cluster, tokens);
            let better = match best {
                None => true,
                Some((s, w, _)) => score > s || (score == s && wildcards > w),
            };
            if better {
                best = Some((score, wildcards, id));
            }
        }
        best.filter(|(score, _, _)| *score >= SIMILARITY)
            .map(|(_, _, id)| id)
    }

    fn insert(&mut self, key: Shape, tokens: &[Token]) -> usize {
        if self.live >= MAX_CLUSTERS {
            self.evict();
        }
        let id = self.clusters.len();
        self.clusters.push(Some(Cluster {
            slots: tokens
                .iter()
                .map(|t| Slot {
                    text: Some(t.text.into()),
                    kind: t.kind.clone(),
                    space_before: t.space_before,
                })
                .collect(),
            counts: BTreeMap::new(),
            last_used: self.clock,
        }));
        self.live += 1;
        let clusters = &self.clusters;
        let mut node = self.roots.entry(key).or_default();
        for token in words(tokens).take(PREFIX_DEPTH) {
            let exact: Option<Box<[u8]>> = Some(token.text.into());
            let child = if has_digit(token.text) {
                None
            } else if node.children.contains_key(&exact) || node.children.len() + 1 < MAX_CHILDREN {
                exact
            } else {
                None
            };
            node = node.children.entry(child).or_default();
        }
        node.clusters.retain(|id| clusters[*id].is_some());
        node.clusters.push(id);
        id
    }

    // Least recently used; its leaf entry is dropped lazily on the next insert.
    fn evict(&mut self) {
        let victim = self
            .clusters
            .iter()
            .enumerate()
            .filter_map(|(id, c)| c.as_ref().map(|c| (c.last_used, id)))
            .min();
        if let Some((_, id)) = victim {
            self.clusters[id] = None;
            self.live -= 1;
        }
    }

    /// `(pattern, [(bucket_start, count)])`, largest total first.
    pub fn finish(self) -> Vec<Pattern> {
        let mut out: Vec<(u64, Pattern)> = self
            .clusters
            .into_iter()
            .flatten()
            .map(|cluster| {
                let total = cluster.counts.values().sum();
                (
                    total,
                    (render(&cluster.slots), cluster.counts.into_iter().collect()),
                )
            })
            .collect();
        out.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1 .0.cmp(&b.1 .0)));
        // Equal renderings (templates that converged) report together.
        let mut merged: Vec<Pattern> = Vec::with_capacity(out.len());
        let mut index: HashMap<Vec<u8>, usize> = HashMap::new();
        for (_, (pattern, counts)) in out {
            match index.get(&pattern) {
                Some(&i) => {
                    let mut sum: BTreeMap<i64, u64> = merged[i].1.iter().copied().collect();
                    for (ts, n) in counts {
                        *sum.entry(ts).or_insert(0) += n;
                    }
                    merged[i].1 = sum.into_iter().collect();
                }
                None => {
                    index.insert(pattern.clone(), merged.len());
                    merged.push((pattern, counts));
                }
            }
        }
        merged
    }
}

fn tokenize(line: &[u8]) -> Option<Vec<Token<'_>>> {
    let mut tokens = Vec::new();
    let mut i = 0;
    let mut space = false;
    while i < line.len() {
        let b = line[i];
        if b.is_ascii_whitespace() {
            space = true;
            i += 1;
            continue;
        }
        let end = if PUNCTUATION.contains(&b) {
            i + 1
        } else {
            let mut j = i;
            while j < line.len()
                && !line[j].is_ascii_whitespace()
                && !PUNCTUATION.contains(&line[j])
            {
                j += 1;
            }
            j
        };
        tokens.push(Token {
            text: &line[i..end],
            kind: if PUNCTUATION.contains(&b) {
                Kind::Punct
            } else {
                Kind::Word
            },
            space_before: space && !tokens.is_empty(),
        });
        if tokens.len() > MAX_TOKENS {
            return None;
        }
        space = false;
        i = end;
    }
    (words(&tokens).count() >= MIN_WORDS).then_some(tokens)
}

fn words<'a, 'l>(tokens: &'a [Token<'l>]) -> impl Iterator<Item = &'a Token<'l>> {
    tokens.iter().filter(|t| t.kind == Kind::Word)
}

fn shape(tokens: &[Token]) -> Shape {
    let punct = tokens
        .iter()
        .enumerate()
        .filter(|(_, t)| t.kind == Kind::Punct)
        .map(|(i, t)| (i, t.text.into()))
        .collect();
    (tokens.len(), punct)
}

fn has_digit(text: &[u8]) -> bool {
    text.iter().any(u8::is_ascii_digit)
}

// Matching words over all words, and the template's wildcard count.
fn similarity(cluster: &Cluster, tokens: &[Token]) -> (f64, usize) {
    let (mut words, mut same, mut wildcards) = (0usize, 0usize, 0usize);
    for (slot, token) in cluster.slots.iter().zip(tokens) {
        if slot.kind != Kind::Word {
            continue;
        }
        words += 1;
        match &slot.text {
            None => wildcards += 1,
            Some(text) if **text == *token.text => same += 1,
            Some(_) => {}
        }
    }
    if words == 0 {
        return (1.0, wildcards);
    }
    (same as f64 / words as f64, wildcards)
}

fn merge(cluster: &mut Cluster, tokens: &[Token]) {
    for (slot, token) in cluster.slots.iter_mut().zip(tokens) {
        if slot.text.as_deref().is_some_and(|text| text != token.text) {
            slot.text = None;
        }
    }
}

// Adjacent wildcards without whitespace between them collapse into one, so
// the pattern stays a valid `|>` filter.
fn render(slots: &[Slot]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut previous_wildcard = false;
    for slot in slots {
        match &slot.text {
            None if previous_wildcard && !slot.space_before => continue,
            None => {
                if slot.space_before {
                    out.push(b' ');
                }
                out.extend_from_slice(WILDCARD.as_bytes());
                previous_wildcard = true;
            }
            Some(text) => {
                if slot.space_before {
                    out.push(b' ');
                }
                out.extend_from_slice(text);
                previous_wildcard = false;
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mine(lines: &[&str]) -> Vec<(String, u64)> {
        let mut miner = Miner::new(0, 10);
        for (i, line) in lines.iter().enumerate() {
            miner.train(i as i64, line.as_bytes());
        }
        miner
            .finish()
            .into_iter()
            .map(|(p, counts)| {
                (
                    String::from_utf8(p).unwrap(),
                    counts.iter().map(|(_, n)| n).sum(),
                )
            })
            .collect()
    }

    #[test]
    fn clusters_logfmt_lines_and_wildcards_variable_values() {
        let patterns = mine(&[
            "ts=1 level=info msg=\"request done\" route=/a duration=12ms",
            "ts=2 level=info msg=\"request done\" route=/b duration=9ms",
            "ts=3 level=info msg=\"request done\" route=/c duration=31ms",
            "ts=4 level=error msg=\"db timeout\" query=select",
        ]);
        assert_eq!(
            patterns,
            vec![
                (
                    "ts=<_> level=info msg=\"request done\" route=<_> duration=<_>".to_string(),
                    3
                ),
                (
                    "ts=4 level=error msg=\"db timeout\" query=select".to_string(),
                    1
                ),
            ]
        );
    }

    #[test]
    fn clusters_plain_text_and_json() {
        let patterns = mine(&[
            "GET /api/projects 200 12ms",
            "GET /api/runs 200 40ms",
            "{\"level\":\"debug\",\"id\":\"a1\",\"msg\":\"check capacity\"}",
            "{\"level\":\"debug\",\"id\":\"b2\",\"msg\":\"check capacity\"}",
        ]);
        assert_eq!(
            patterns,
            vec![
                ("GET <_> 200 <_>".to_string(), 2),
                (
                    "{\"level\":\"debug\",\"id\":\"<_>\",\"msg\":\"check capacity\"}".to_string(),
                    2
                ),
            ]
        );
    }

    #[test]
    fn different_punctuation_never_clusters() {
        let patterns = mine(&["user a=1 b=2", "user a 1 b 2"]);
        assert_eq!(patterns.len(), 2);
    }

    #[test]
    fn counts_per_step_and_skips_tiny_lines() {
        let mut miner = Miner::new(0, 10);
        for ts in [1, 5, 12, 25] {
            miner.train(ts, b"job finished ok");
        }
        miner.train(30, b"x");
        assert_eq!(miner.skipped(), 1);
        let out = miner.finish();
        assert_eq!(out[0].1, vec![(0, 2), (10, 1), (20, 1)]);
    }

    #[test]
    fn evicts_least_recently_used_templates() {
        let mut miner = Miner::new(0, 10);
        for i in 0..(MAX_CLUSTERS + 10) {
            let line = format!("{} {} {}", "w".repeat(i % 7 + 1), i, "z".repeat(i / 7 + 1));
            miner.train(i as i64, line.as_bytes());
        }
        assert!(miner.finish().len() <= MAX_CLUSTERS);
    }
}
