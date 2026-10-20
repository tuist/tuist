const assert = require('node:assert/strict');
const { test } = require('node:test');
const { communityNotification } = require('./community-notifications.cjs');

function fixture({ eventName = 'issues', login = 'contributor', type = 'User', teams = {} } = {}) {
  const calls = [];
  const item = {
    number: 123,
    title: 'Fix generated projects',
    user: { login, type },
    author_association: 'CONTRIBUTOR',
  };
  const context = {
    eventName,
    repo: { owner: 'tuist', repo: 'tuist' },
    payload: {
      action: 'opened',
      sender: { login: 'someone-else', type: 'Bot' },
      [eventName === 'pull_request_target' ? 'pull_request' : 'issue']: item,
    },
  };
  const endpoint = Symbol('listMembersInOrg');
  const github = {
    rest: { teams: { listMembersInOrg: endpoint } },
    paginate: async (method, params) => {
      assert.equal(method, endpoint);
      assert.equal(params.org, 'tuist');
      assert.equal(params.per_page, 100);
      calls.push(params.team_slug);
      return (teams[params.team_slug] || []).map((login) => ({ login }));
    },
  };
  return { github, context, hasTeamToken: true, item, calls };
}

test('notifies for a returning community issue author, using the author rather than sender', async () => {
  const input = fixture();
  const result = await communityNotification(input);
  assert.equal(result.text, 'New community issue #123 by contributor');
  assert.deepEqual(input.calls, ['company', 'external']);
  assert.equal(result.blocks.at(-1).elements[0].url, 'https://github.com/tuist/tuist/issues/123');
});

for (const draft of [false, true]) {
  test(`notifies for a fork PR when draft=${draft}`, async () => {
    const input = fixture({ eventName: 'pull_request_target' });
    input.item.draft = draft;
    input.item.head = { repo: { fork: true } };
    const result = await communityNotification(input);
    assert.match(result.text, draft ? /draft pull request/ : /community pull request/);
    assert.equal(result.blocks.at(-1).elements[0].url, 'https://github.com/tuist/tuist/pull/123');
  });
}

for (const team of ['company', 'external']) {
  test(`excludes ${team} members case-insensitively`, async () => {
    const input = fixture({ teams: { [team]: ['CONTRIBUTOR'] } });
    assert.equal(await communityNotification(input), null);
  });
}

for (const author of [
  { login: 'automation', type: 'Bot' },
  { login: 'dependabot[bot]' },
  { login: 'TUISTIT' },
]) {
  test(`excludes bot ${author.login} without needing credentials or API calls`, async () => {
    const input = fixture(author);
    input.hasTeamToken = false;
    assert.equal(await communityNotification(input), null);
    assert.deepEqual(input.calls, []);
  });
}

for (const association of ['MEMBER', 'COLLABORATOR', 'FIRST_TIME_CONTRIBUTOR', 'NONE']) {
  test(`does not confuse ${association} repository association with employment`, async () => {
    const input = fixture();
    input.item.author_association = association;
    assert.ok(await communityNotification(input));
  });
}

for (const action of ['edited', 'reopened', 'synchronize', 'ready_for_review', 'closed']) {
  test(`ignores ${action} events`, async () => {
    const input = fixture();
    input.context.payload.action = action;
    assert.equal(await communityNotification(input), null);
    assert.deepEqual(input.calls, []);
  });
}

test('ignores other repositories and unsupported events', async () => {
  const input = fixture();
  input.context.repo.owner = 'fork-owner';
  assert.equal(await communityNotification(input), null);
  input.context.repo.owner = 'tuist';
  input.context.eventName = 'pull_request';
  assert.equal(await communityNotification(input), null);
  input.context.eventName = 'issues';
  input.item.pull_request = {};
  assert.equal(await communityNotification(input), null);
  assert.deepEqual(input.calls, []);
});

test('fails visibly when the staff token is missing', async () => {
  await assert.rejects(communityNotification({ ...fixture(), hasTeamToken: false }), /Members: read/);
});

for (const status of [401, 403, 404, 429, 500]) {
  test(`fails visibly on team lookup HTTP ${status}, including failure of the second team`, async () => {
    const input = fixture();
    const error = Object.assign(new Error('Team lookup failed'), { status });
    input.github.paginate = async (_, params) => {
      if (params.team_slug === 'external') throw error;
      return [];
    };
    await assert.rejects(communityNotification(input), (actual) => actual === error);
  });
}

test('keeps hostile titles inert and builds a trusted GitHub link', async () => {
  const input = fixture();
  input.item.title = '<!channel> <@U123> & "quotes"\n$(touch /tmp/untrusted) <https://evil.example|click>';
  input.item.html_url = 'https://evil.example';
  const result = JSON.parse(JSON.stringify(await communityNotification(input)));
  assert.deepEqual(result.blocks[1].text, { type: 'plain_text', text: input.item.title, emoji: false });
  assert.equal(result.blocks.at(-1).elements[0].url, 'https://github.com/tuist/tuist/issues/123');
  assert.equal(result.unfurl_links, false);
  assert.equal(result.unfurl_media, false);
  assert.ok(!result.text.includes('<!channel>'));
});
