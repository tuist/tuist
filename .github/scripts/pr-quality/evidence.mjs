import metrics from './metrics.json' with { type: 'json' };

const checks = metrics.filter((metric) => ['maliciousBehavior', 'promptInjection'].includes(metric.key));

// Select evidence from known changed lines instead of asking the model to invent locations.
export function changedLines(diff) {
  const candidates = [];
  let oldPath, newPath, oldLine, newLine;
  const path = (header) => (header.startsWith('"') ? JSON.parse(header) : header.replace(/\t$/, '')).replace(/^[ab]\//, '');
  for (const [diffLine, text] of diff.split('\n').entries()) {
    if (text.startsWith('diff --git ')) {
      oldPath = newPath = undefined;
      oldLine = newLine = undefined;
    } else if (oldLine === undefined && text.startsWith('--- ')) {
      oldPath = path(text.slice(4));
    } else if (oldLine === undefined && text.startsWith('+++ ')) {
      newPath = path(text.slice(4));
    } else if (text.startsWith('@@ ')) {
      const hunk = text.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
      if (!hunk) throw new Error('Unsupported diff hunk.');
      oldLine = Number(hunk[1]);
      newLine = Number(hunk[2]);
    } else if (oldLine !== undefined) {
      if (text.startsWith('+')) {
        candidates.push({ diffLine, file: newPath, line: newLine++, side: 'head', source: text.slice(1) });
      } else if (text.startsWith('-')) {
        candidates.push({ diffLine, file: oldPath, line: oldLine++, side: 'base', source: text.slice(1) });
      } else if (text.startsWith(' ')) {
        oldLine++;
        newLine++;
      }
    }
  }
  if (candidates.some((item) => !item.file || item.file === '/dev/null' || item.line < 1)) {
    throw new Error('Invalid changed-line location.');
  }
  return candidates;
}

export function evidenceQuestions(candidates) {
  const questions = {};
  // Jev accepts at most 255 choices. Include a no-issue option in every group.
  for (let offset = 0; offset < candidates.length; offset += 254) {
    const criteria = Object.fromEntries(candidates.slice(offset, offset + 254).map((item, index) => [
      `line_${offset + index}`, `${item.side === 'head' ? 'Added' : 'Removed'} ${item.file}:${item.line}; evidence marker line_${offset + index} in state.diff`,
    ]));
    for (const check of checks) {
      questions[`${check.key}_evidence_${offset}`] = {
        type: 'choice',
        instructions: `Select the changed line with the strongest concrete evidence of ${check.label} concerns in this group, using the complete diff for context. Choose no_material_issue if no line supports a concern. A removal can introduce a risk by removing protection; do not flag removal of malicious code itself. ${check.guidance}`,
        criteria: { no_material_issue: 'None of these changed lines evidences a concern; do not force a finding.', ...criteria },
      };
    }
  }
  return questions;
}

export function evaluateEvidence(response, questions, candidates) {
  return Object.entries(questions).flatMap(([id, question]) => {
    const answer = response?.answers?.[id];
    if (answer?.type !== 'choice' || !Object.hasOwn(question.criteria, answer.choice)
      || !Number.isFinite(answer.confidence) || answer.confidence < 0 || answer.confidence > 1) {
      throw new Error('Invalid or missing Jev evidence answer.');
    }
    if (answer.choice === 'no_material_issue') return [];
    const check = checks.find((item) => id.startsWith(`${item.key}_evidence_`));
    const { diffLine, ...location } = candidates[Number(answer.choice.slice(5))];
    return [{ check: check.label, confidence: answer.confidence, ...location }];
  });
}

export function annotateDiff(diff, candidates) {
  const lines = diff.split('\n');
  candidates.forEach((item, index) => { lines[item.diffLine] = `[line_${index}] ${lines[item.diffLine]}`; });
  return lines.join('\n');
}
