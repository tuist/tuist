// Copyright 2026 Tuist GmbH
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Rejects queries nested too deeply to process.
//!
//! Planning, cloning, displaying and dropping a query recurse once per level of
//! nesting, and an 8 MiB worker stack overflows after a few dozen PromQL levels or
//! a few thousand SQL levels. A stack overflow aborts the whole process, so any
//! reader could stop the database with a short query. The parsers' own recursion
//! limits do not help: they build operator chains (`a + b + ...`,
//! `SELECT ... UNION ALL SELECT ...`) in a loop. These checks run right after
//! parsing, before anything else walks the tree.

use std::ops::ControlFlow;

use promql_parser::parser::Expr as PromExpr;
use sqlparser::ast::{Expr, Query, SetExpr, Visit, Visitor};

/// Deepest SQL expression accepted, the same as the query analyzer's limit.
pub const MAX_SQL_EXPR_DEPTH: usize = 128;
/// Longest chain of set operations (UNION, INTERSECT, EXCEPT) in one query.
/// Pulse v1.3.0 overflowed at 256 chained `UNION ALL`s.
pub const MAX_SQL_SET_OPERATION_DEPTH: usize = 64;
/// Deepest PromQL expression accepted, counting every node. Planning a level
/// takes up to about 100 KiB of stack: Pulse v1.3.0 overflowed an 8 MiB
/// stack at 72 chained binary operators (through TQL) and 48 nested subqueries.
pub const MAX_PROMQL_DEPTH: usize = 32;
/// Most PromQL operators, parentheses and brackets accepted in one query. Each
/// inner node of the tree needs one, so this bounds what the parser builds before
/// the depth check, and the parser's time, which grows with the square of a
/// chain's length.
pub const MAX_PROMQL_NODES: usize = 4096;
/// Stack reserved per byte of SQL for parsing and dropping its tree. The longest
/// chains take 2 bytes per level and 70 bytes of stack per level.
const SQL_PARSE_STACK_PER_BYTE: usize = 128;
const SQL_PARSE_STACK_BASE: usize = 1024 * 1024;
/// Largest stack set aside for parsing one SQL text, which caps SQL at 8 MiB.
const MAX_SQL_PARSE_STACK: usize = 1024 * 1024 * 1024;

/// Parses PromQL, rejecting queries nested deeper than [`MAX_PROMQL_DEPTH`].
pub fn parse_promql(query: &str) -> Result<PromExpr, String> {
    if promql_node_bound(query) > MAX_PROMQL_NODES {
        return Err(format!(
            "query has more than {MAX_PROMQL_NODES} operators, parentheses and brackets"
        ));
    }
    let expr = promql_parser::parser::parse(query)?;
    if promql_depth(&expr) > MAX_PROMQL_DEPTH {
        return Err(format!(
            "query is nested more than {MAX_PROMQL_DEPTH} levels deep"
        ));
    }
    Ok(expr)
}

/// An upper bound on the inner nodes of the query's tree: its operator
/// characters, operator keywords, parentheses and brackets, outside strings,
/// label matchers and comments.
fn promql_node_bound(query: &str) -> usize {
    let bytes = query.as_bytes();
    let mut count = 0;
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            quote @ (b'"' | b'\'' | b'`') => i = skip_string(bytes, i + 1, quote),
            // Label matchers hold no expressions, only names and strings.
            b'{' => {
                i += 1;
                while i < bytes.len() && bytes[i] != b'}' {
                    match bytes[i] {
                        quote @ (b'"' | b'\'' | b'`') => i = skip_string(bytes, i + 1, quote),
                        _ => i += 1,
                    }
                }
                i += 1;
            }
            b'#' => {
                while i < bytes.len() && bytes[i] != b'\n' {
                    i += 1;
                }
            }
            b'(' | b'[' | b'+' | b'-' | b'*' | b'/' | b'%' | b'^' | b'=' | b'!' | b'<' | b'>' => {
                count += 1;
                i += 1;
            }
            byte if byte.is_ascii_alphabetic() || byte == b'_' => {
                let start = i;
                while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                    i += 1;
                }
                let word = &query[start..i];
                if ["and", "or", "unless", "atan2"]
                    .iter()
                    .any(|keyword| word.eq_ignore_ascii_case(keyword))
                {
                    count += 1;
                }
            }
            _ => i += 1,
        }
    }
    count
}

/// Returns the index after the string's closing quote. Only backticks lack escapes.
fn skip_string(bytes: &[u8], mut i: usize, quote: u8) -> usize {
    while i < bytes.len() {
        match bytes[i] {
            b'\\' if quote != b'`' => i += 2,
            byte if byte == quote => return i + 1,
            _ => i += 1,
        }
    }
    i
}

/// The number of nodes on the longest path from the root, without recursion.
fn promql_depth(expr: &PromExpr) -> usize {
    let mut deepest = 0;
    let mut pending = vec![(expr, 1)];
    while let Some((expr, depth)) = pending.pop() {
        deepest = deepest.max(depth);
        match expr {
            PromExpr::Aggregate(aggregate) => {
                pending.push((&aggregate.expr, depth + 1));
                if let Some(param) = &aggregate.param {
                    pending.push((param, depth + 1));
                }
            }
            PromExpr::Unary(unary) => pending.push((&unary.expr, depth + 1)),
            PromExpr::Binary(binary) => {
                pending.push((&binary.lhs, depth + 1));
                pending.push((&binary.rhs, depth + 1));
            }
            PromExpr::Paren(paren) => pending.push((&paren.expr, depth + 1)),
            PromExpr::Subquery(subquery) => pending.push((&subquery.expr, depth + 1)),
            PromExpr::Call(call) => {
                pending.extend(call.args.args.iter().map(|arg| (arg.as_ref(), depth + 1)))
            }
            PromExpr::NumberLiteral(_)
            | PromExpr::StringLiteral(_)
            | PromExpr::VectorSelector(_)
            | PromExpr::MatrixSelector(_)
            | PromExpr::Extension(_) => {}
        }
    }
    deepest
}

/// Runs `parse` on a stack large enough to parse and drop any tree that
/// `sql_len` bytes of SQL describe, or returns `None` when the SQL is too large.
pub(crate) fn with_sql_parse_stack<R>(sql_len: usize, parse: impl FnOnce() -> R) -> Option<R> {
    let stack = sql_len
        .saturating_mul(SQL_PARSE_STACK_PER_BYTE)
        .saturating_add(SQL_PARSE_STACK_BASE);
    (stack <= MAX_SQL_PARSE_STACK).then(|| stacker::maybe_grow(stack, stack, parse))
}

/// Checks a parsed statement against [`MAX_SQL_EXPR_DEPTH`] and
/// [`MAX_SQL_SET_OPERATION_DEPTH`]. The walk stops at the first level over a limit,
/// so it never recurses deeper than the limits.
pub(crate) fn check_sql<T: Visit>(statement: &T) -> Result<(), String> {
    match statement.visit(&mut SqlDepth { expr_depth: 0 }) {
        ControlFlow::Continue(()) => Ok(()),
        ControlFlow::Break(reason) => Err(reason),
    }
}

struct SqlDepth {
    expr_depth: usize,
}

impl Visitor for SqlDepth {
    type Break = String;

    fn pre_visit_query(&mut self, query: &Query) -> ControlFlow<String> {
        // The body is visited after this, so check its chain without recursion.
        let mut pending = vec![(query.body.as_ref(), 0)];
        while let Some((body, depth)) = pending.pop() {
            if depth > MAX_SQL_SET_OPERATION_DEPTH {
                return ControlFlow::Break(format!(
                    "query chains more than {MAX_SQL_SET_OPERATION_DEPTH} set operations"
                ));
            }
            match body {
                SetExpr::SetOperation { left, right, .. } => {
                    pending.push((left, depth + 1));
                    pending.push((right, depth + 1));
                }
                SetExpr::Query(query) => pending.push((&query.body, depth)),
                _ => {}
            }
        }
        ControlFlow::Continue(())
    }

    fn pre_visit_expr(&mut self, _: &Expr) -> ControlFlow<String> {
        self.expr_depth += 1;
        if self.expr_depth > MAX_SQL_EXPR_DEPTH {
            return ControlFlow::Break(format!(
                "expression is nested more than {MAX_SQL_EXPR_DEPTH} levels deep"
            ));
        }
        ControlFlow::Continue(())
    }

    fn post_visit_expr(&mut self, _: &Expr) -> ControlFlow<String> {
        self.expr_depth -= 1;
        ControlFlow::Continue(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dialect::PulseDialect;
    use crate::parser::{ParseOptions, ParserContext};

    fn promql_chain(terms: usize) -> String {
        "vector(1)+".repeat(terms - 1) + "vector(1)"
    }

    #[test]
    fn promql_depth_limit() {
        // A chain of n terms is n + 1 deep: n - 1 operators, the call and its literal.
        assert!(parse_promql(&promql_chain(MAX_PROMQL_DEPTH - 1)).is_ok());
        let err = parse_promql(&promql_chain(MAX_PROMQL_DEPTH)).unwrap_err();
        assert!(err.contains("nested more than"), "{err}");
        // Nesting through parentheses, calls, aggregations and subqueries counts too.
        let nested = |open: &str, close: &str, levels: usize| {
            open.repeat(levels) + "up" + &close.repeat(levels)
        };
        assert!(parse_promql(&nested("(", ")", MAX_PROMQL_DEPTH - 1)).is_ok());
        assert!(parse_promql(&nested("(", ")", MAX_PROMQL_DEPTH)).is_err());
        assert!(parse_promql(&nested("sum(", ")", MAX_PROMQL_DEPTH)).is_err());
        assert!(parse_promql(&nested("max_over_time(", "[5m:1m])", MAX_PROMQL_DEPTH / 2)).is_err());
        // A right-nested chain is as deep as a left-nested one.
        assert!(parse_promql(&nested("up+(", ")", MAX_PROMQL_DEPTH)).is_err());
    }

    #[test]
    fn promql_dashboard_query_passes() {
        // One of the deepest queries in Tuist's dashboards, 12 levels deep.
        let query = r#"max_over_time((sum by (cluster, region, node) (label_replace(sum by (cluster, instance) (rate(node_network_transmit_bytes_total{device=~"e(n|th).*", env="x"}[30m])) * 8 / 1e6 * on (cluster, instance) group_left(region) label_replace(x, "instance", "$1", "node", "(.*)"), "node", "$1", "instance", "(.*)")) / sum by (cluster, region, node) (max by (cluster, node) (kube_node_status_capacity{resource="tuist_dev_egress_mbps", env="x"}) * on (cluster, node) group_left(region) x))[5m:5m])"#;
        assert_eq!(
            parse_promql(query).unwrap(),
            promql_parser::parser::parse(query).unwrap()
        );
    }

    #[test]
    fn promql_node_bound_rejects_before_parsing() {
        // 100k operators would take the parser minutes and build a tree deep
        // enough to overflow while it is dropped.
        let err = parse_promql(&"1+".repeat(100_000)).unwrap_err();
        assert!(err.contains("operators"), "{err}");
        // Operators inside strings, label matchers and comments do not count.
        let quoted = format!(
            "label_replace(up{{job=~\"{0}\"}}, \"x\", \"{0}\", \"job\", \"(.*)\") # {0}",
            "-".repeat(10_000)
        );
        assert_eq!(promql_node_bound(&quoted), 1);
        assert!(parse_promql(&quoted).is_ok());
    }

    fn parse_sql(sql: &str) -> crate::error::Result<Vec<crate::statements::statement::Statement>> {
        ParserContext::create_with_dialect(sql, &PulseDialect {}, ParseOptions::default())
    }

    #[test]
    fn sql_expression_depth_limit() {
        // `SELECT 1+...+1` with n terms has n - 1 operators above the deepest literal.
        let chain = |terms: usize| format!("SELECT {}1", "1+".repeat(terms - 1));
        assert!(parse_sql(&chain(MAX_SQL_EXPR_DEPTH)).is_ok());
        let err = parse_sql(&chain(MAX_SQL_EXPR_DEPTH + 1)).unwrap_err();
        assert!(err.to_string().contains("nested more than"), "{err}");
        let and_chain = format!("SELECT * FROM t WHERE {}true", "a = 1 AND ".repeat(200));
        assert!(parse_sql(&and_chain).is_err());
        // Depth carries into subqueries: this one sits under 65 operators.
        let half = "1+".repeat(MAX_SQL_EXPR_DEPTH / 2);
        assert!(parse_sql(&format!("SELECT (SELECT {half}1)+{half}1")).is_err());
        // Statements other than queries are checked too.
        assert!(parse_sql(&format!("EXPLAIN {}", chain(1000))).is_err());
        assert!(parse_sql(&format!("SELECT 1; {}", chain(1000))).is_err());
    }

    #[test]
    fn sql_set_operation_limit() {
        let union = |selects: usize| vec!["SELECT 1, 2"; selects].join(" UNION ALL ");
        assert!(parse_sql(&union(MAX_SQL_SET_OPERATION_DEPTH + 1)).is_ok());
        let err = parse_sql(&union(MAX_SQL_SET_OPERATION_DEPTH + 2)).unwrap_err();
        assert!(err.to_string().contains("set operations"), "{err}");
        // A chain inside a subquery is checked too.
        assert!(parse_sql(&format!("SELECT * FROM ({})", union(1000))).is_err());
    }

    #[test]
    fn sql_parse_survives_long_chains_on_a_small_stack() {
        // 300k chained terms overflow an 8 MiB stack while parsing or dropping.
        let sql = format!("SELECT {}1", "1+".repeat(300_000));
        let result = std::thread::Builder::new()
            .stack_size(2 * 1024 * 1024)
            .spawn(move || parse_sql(&sql).map(|_| ()).map_err(|err| err.to_string()))
            .unwrap()
            .join()
            .unwrap();
        assert!(result.unwrap_err().contains("nested more than"));
        let err = parse_sql(&format!("SELECT '{}'", "x".repeat(9 * 1024 * 1024))).unwrap_err();
        assert!(err.to_string().contains("too large"), "{err}");
    }
}
