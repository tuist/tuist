const staffTeams = ['company', 'external'];
// Legacy automation accounts can have GitHub's "User" type.
const botLogins = new Set(['tuistit']);

async function communityNotification({ github, context, hasTeamToken }) {
  if (context.repo.owner !== 'tuist' || context.repo.repo !== 'tuist') return null;
  if (context.payload.action !== 'opened') return null;

  const isPullRequest = context.eventName === 'pull_request_target';
  if (!isPullRequest && context.eventName !== 'issues') return null;
  const item = isPullRequest ? context.payload.pull_request : context.payload.issue;
  if (!item || (!isPullRequest && item.pull_request)) return null;

  const author = item.user;
  const login = author.login.toLowerCase();
  if (author.type === 'Bot' || login.endsWith('[bot]') || botLogins.has(login)) return null;

  if (!hasTeamToken) {
    throw new Error('TUIST_APP_GITHUB_TOKEN must have organization Members: read permission.');
  }

  for (const team of staffTeams) {
    // Listing members also verifies team visibility: a missing team or permission
    // must fail the run, not misclassify every employee as a community author.
    const members = await github.paginate(github.rest.teams.listMembersInOrg, {
      org: 'tuist',
      team_slug: team,
      per_page: 100,
    });
    if (members.some((member) => member.login.toLowerCase() === login)) return null;
  }

  const kind = isPullRequest ? (item.draft ? 'draft pull request' : 'pull request') : 'issue';
  const url = `https://github.com/tuist/tuist/${isPullRequest ? 'pull' : 'issues'}/${item.number}`;
  const summary = `New community ${kind} #${item.number} by ${author.login}`;

  return {
    text: summary,
    unfurl_links: false,
    unfurl_media: false,
    blocks: [
      { type: 'header', text: { type: 'plain_text', text: `New community ${kind}`, emoji: true } },
      // Contributor content stays plain text so titles cannot ping Slack users
      // or inject links. GitHub titles are shorter than Slack's 3,000-char limit.
      { type: 'section', text: { type: 'plain_text', text: item.title, emoji: false } },
      { type: 'context', elements: [{ type: 'plain_text', text: `tuist/tuist #${item.number} · ${author.login}` }] },
      {
        type: 'actions',
        elements: [{
          type: 'button',
          text: { type: 'plain_text', text: isPullRequest ? 'Review pull request' : 'Triage issue' },
          url,
          action_id: 'open_community_contribution',
        }],
      },
    ],
  };
}

module.exports = { communityNotification };
