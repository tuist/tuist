---
title: "From Zero to Many: The Hidden Cost of Scale"
category: "learn"
tags: ["scalability", "productivity", "roi"]
excerpt: "Discover how merge throughput evolves as your team grows, and why optimizing build and test times becomes critical for business velocity"
author: pepicrft
---

You're about to live through a story that every engineering leader eventually experiences. It's a story about growth, about success, and about an invisible tax that quietly erodes everything you've built. It starts with velocity. Then it ends with waiting.

## The Metric That Rules Everything

There's a number that determines whether your engineering organization is thriving or drowning. It's not lines of code. It's not story points. It's not even bugs per release. It's **merge throughput**: how many code changes successfully make it into your main branch each day. This single number tells you how fast features reach your customers, how quickly bugs get fixed, how rapidly you can respond to market demands. It's the heartbeat of your engineering organization.

And here's what most executives don't realize until it's too late: as your team grows, this number can actually go down. Sometimes dramatically. Let me show you what's coming.

## Phase 1: The Lone Wolf

You launch your startup on a Tuesday. You're a solo founder who codes, armed with Claude and GitHub Copilot as your pair programmers. No team. No process. No friction. You push straight to main. Ten times on Tuesday. Twelve on Wednesday. Eight on Friday because you took the afternoon off. There are no code reviews because there's nobody to review with. There are no merge conflicts because you're the only one committing. There's no CI pipeline slowing you down because every bug that slips through goes straight into the weekly release to your five beta users who are just happy the app exists.

With your AI coding assistants writing boilerplate and suggesting implementations, you're moving at a pace that would have seemed impossible five years ago. The merge throughput is pure: one developer, zero overhead, 10 to 15 commits merged to main every single day. This is the golden age. This is what velocity feels like.

<iframe src="/blog/2025/11/6/zero-to-many/iframe.html?id=lone_wolf" width="100%" height="400" frameborder="0" data-visualization></iframe>

But your app is growing. Users are signing up. And one bad commit ships a critical bug in your weekly release because there was no safety net. That's when you realize: pure velocity without quality control is just recklessness in disguise.

## Phase 2: Adding Safety Nets

You set up GitHub Actions. You create a branch called "develop" and promise yourself you'll only merge to main after tests pass. You hire your first engineer, Marcus, who's also using AI coding tools to write code faster. Now when you want to ship a feature, you open a pull request. The CI kicks off, running tests and linting. It takes eight minutes. Marcus reviews your code over lunch, another 20 minutes. Then it merges. When Marcus ships code, you review. Another 20 minutes. CI runs. Eight minutes. Merge.

You're still moving fast. About 11 commits a day make it to main, down slightly from your solo peak but way safer. Once or twice a week you run into a merge conflict because you both touched the same file, but it's quick to resolve. Occasionally a test fails randomly, and you just rerun the CI. Your team of two, each augmented with a couple of AI coding assistants, has added 15 to 20 minutes of overhead per commit. But you've also stopped shipping bugs to production.

<iframe src="/blog/2025/11/6/zero-to-many/iframe.html?id=safety_nets" width="100%" height="400" frameborder="0" data-visualization></iframe>

The app is growing. Revenue is growing. You raise a seed round and decide it's time to build a real team.

## Phase 3: The Team Multiplier

Six months later, you have five engineers. Everyone has AI assistants helping them write code. The roadmap is ambitious. The team is talented. The codebase has tripled in size. Each developer, amplified by AI, can individually write code for eight or nine features a day. That should mean 40 commits a day hitting main. That's 4× what you and Marcus were doing alone. But that's not what happens.

Li opens a PR at 9am. It sits waiting for review because you're in meetings and Marcus is deep in his own feature. Three hours later, you finally review it. You request changes, there's a naming inconsistency and a missing edge case. Li makes the updates, but now the CI is taking 22 minutes because the test suite has grown. And when it finishes, there's a merge conflict because Marcus merged something that touched the same service. Li resolves it, reruns CI, another 22 minutes. It's 3pm. One commit, six hours.

This happens to everyone, all day long. PRs sit in review queues. Merge conflicts happen on one in five merges now that five people are touching overlapping code. The CI occasionally has a flaky test, and nobody's quite sure which test it is, so they just click "retry." About a third of PRs come back with requested changes, adding another round trip. The merge throughput isn't 40 commits a day. It's six.

<iframe src="/blog/2025/11/6/zero-to-many/iframe.html?id=team_multiplier" width="100%" height="500" frameborder="0"></iframe>

You hired three more people and throughput went down. This isn't what growth is supposed to look like.

## Phase 4: The Complexity Wall

Two years in, your company has 30 engineers across four teams. Mobile, backend, platform, and data. Everyone is shipping code, everyone has AI tools making them more productive than ever, and the feature velocity should be incredible. The CI now takes 67 minutes. Sometimes 82 if you're unlucky with the test runner allocation, which takes up to 12 minutes just to start because the queue is backed up. Nobody remembers who wrote half the tests in the suite. One in five CI runs fails because of a flaky test, and debugging which test is flaky wastes hours.

PRs sit for four to six hours waiting for review because reviewers are context-switching between their own features, meetings, and the three other PRs in their queue. When reviews finally happen, 40% come back with requested changes. More waiting. More CI runs. Merge conflicts happen on two out of every five merges now. Multiple teams work in the shared authentication layer, the API gateway, the database models. When someone finally resolves a conflict and merges, they hold their breath hoping nobody else merged in the 67 minutes the CI was running. If they did, back to square one.

The math is brutal: 30 developers, each capable of producing eight features a day individually, should be generating 240 commits. The actual merge throughput is seven commits a day. The same as when you had five people.

<iframe src="/blog/2025/11/6/zero-to-many/iframe.html?id=complexity_wall" width="100%" height="500" frameborder="0"></iframe>

You're paying €4.2 million a year in engineering salaries and getting the output of seven developers. The efficiency is 2%. The waste is €3.3 million a year, just in idle time waiting for CI, reviews, and conflict resolution. The board asks why feature delivery has slowed down. You don't have a good answer.

## Phase 5: The Brute Force Trap

Your VP of Engineering has a plan. Three plans, actually. Each one sounds reasonable in isolation, but none of them address the root problem:

**Option 1: Faster Machines**
"We'll upgrade to the beefiest CI runners GitHub offers," he says. Sixteen cores instead of four. The cost is €70,000 a year, but it'll cut the 67-minute CI down to maybe 35 minutes. Your team calculates: that's a 17% improvement in throughput. Seven commits a day becomes eight. For €70K.

**Option 2: More People**
Your CFO suggests hiring 10 more developers to "parallelize the work." Another €1.4 million in salary. But you've learned the math by now. More people means more conflicts, longer review queues, even slower CI. Throughput might not move at all. It might even go down.

**Option 3: Technology Rewrite**
A CTO from your previous company suggests you rewrite everything in React Native. "No compilation step," he says. "Way faster iteration." The rewrite would take eight months, cost your entire team's focus, and about €2.8 million in opportunity cost. And at the end, you'd have different problems: package resolution instead of compilation, bundle size instead of binary size, but the same coordination problems at 30 people.

<iframe src="/blog/2025/11/6/zero-to-many/iframe.html?id=brute_force" width="100%" height="500" frameborder="0"></iframe>

You pick the faster machines because it's the cheapest mistake. Throughput edges up to eight commits a day. You're paying €70,000 a year to improve efficiency from 2% to 3%. You know you're treating symptoms, not the disease. The disease is that you're building and testing everything, every time, for every change, no matter how small. But you don't know what else to do.

## Phase 6: Smart Optimization

Then you talk to an engineering leader at another company who faced the same wall. "Stop building everything," he says. "You're compiling modules that didn't change. You're running tests for code nobody touched. Of course it takes an hour." He introduces you to build caching and selective testing. The idea is simple: only rebuild what changed, only test what's affected, and share the cached results across your entire team and CI.

Your team spends a month implementing Tuist. You set up binary caching so when Li changes the authentication module, the other 47 modules use cached builds. You implement selective testing so the CI only runs the 200 tests affected by the change, not all 3,400. You add flakiness detection that automatically quarantines unreliable tests until someone fixes them. The first PR after the optimization merges in 11 minutes. The second takes nine. A complex change touching multiple modules takes 14 minutes.

Your CI time drops from 67 minutes to 10 minutes on average. The queue disappears because jobs finish faster. Flaky tests are down to 3% because the bad ones are quarantined. Review time drops to two hours because fast feedback means reviewers can stay in context. Merge conflicts drop to 25% because the faster cycle time means less overlapping work.

<iframe src="/blog/2025/11/6/zero-to-many/iframe.html?id=smart_optimization" width="100%" height="500" frameborder="0"></iframe>

The merge throughput climbs. Fifteen commits a day. Then 28. Then 42. It stabilizes around 45 commits a day. You're still paying €4.2 million for 30 developers. But now you're getting output equivalent to 22 developers instead of seven. The efficiency went from 2% to 15%. You unlocked €2.1 million in value. The investment was €140,000 for Tuist and one month of eng time. The payback period was three weeks.

## What Just Happened

Let's trace your journey in numbers. At one developer, you had 100% efficiency. Ten commits a day from one person's work. At two developers, efficiency dropped to 55%. Eleven commits from two people. At five developers, efficiency fell to 12%. Six commits from five people. At thirty developers, efficiency collapsed to 2%. Seven commits from thirty people who should be producing 240. After optimization, with the same thirty developers, you climbed back to 15% efficiency. Forty-five commits a day. Still not perfect, but 6.5× better than where you were.

## The Choice

Every engineering organization faces this curve. You can see it in your own numbers if you look. Count your commits per day. Count your team size. Measure your CI time. Do the math. Then you have three options:

**Ignore it:** Accept 2% efficiency. Keep paying millions in salaries for work that never ships because people are waiting for builds, waiting for tests, waiting for reviews to free up because nobody can context-switch while waiting an hour for CI.

**Brute force it:** Buy faster machines for €70K a year and get 15% improvement. Hire more people for €1.4M a year and get no improvement or negative improvement. Rewrite in a different stack for €2.8M and get different problems.

**Optimize it:** Fix the actual problem, which is building and testing everything all the time regardless of what changed. Get 6× to 10× improvement. Pay back the investment in weeks.

## The Math on Your Options

Let's put real numbers on this. Your three expensive options:

- **Hiring 10 more developers** costs you €1.4 million per year. And as you've seen, it might actually make throughput worse because of increased coordination overhead.
- **Upgrading to the fastest CI machines** available costs you €70,000 per year and gives you maybe a 15% to 20% improvement. You're still building and testing everything, just slightly faster.
- **Rewriting in a different technology stack** costs you six to eight months of your entire team's time, which at 30 developers is roughly €2.8 million in opportunity cost. And you'll still have the same coordination problems, just with different build tools.

Now compare that to the smart approach: Tuist's binary caching and selective testing. With Tuist's cache, when your developers change one module out of 48, the other 47 modules use cached builds. They don't recompile. They don't rebuild. They just use the artifacts that already exist, whether from their own previous builds or from their teammates' builds, all shared through distributed caching. With Tuist's selective testing, when your developers change authentication code, the CI runs the 200 tests that actually touch authentication. Not the 3,400 tests in your entire suite. Just the ones that matter for that change.

The result: your 67-minute CI drops to 10 minutes. Your flaky tests get quarantined automatically. Your review cycles speed up because feedback is fast enough that reviewers stay in context. Your merge conflicts drop because people aren't waiting so long that they overlap. The investment is €140,000 for Tuist plus about one month of engineering time to implement it properly. Compare that to €1.4M for more people who slow you down, or €70K per year for faster machines that barely help, or €2.8M for a rewrite that doesn't solve the problem. The payback period is measured in weeks, not years.

## Model Your Own Numbers

Use the interactive calculators in each phase above to model your own organization. Adjust team size, CI turnaround time, review time, conflict probability, and flakiness rates. Watch what happens to merge throughput. Then ask yourself four questions:

- How many commits does your team merge per day?
- What's your average CI turnaround time?
- How much time do your developers spend waiting for CI instead of writing code?
- What could you ship to customers if your throughput doubled?

The cost of slow builds isn't developer frustration, though that's real. The cost is millions of euros in wasted salary and missed market opportunities. Features that ship next quarter instead of this quarter. Competitors who move faster. Customers who leave because the bug fix took too long. This story is every company's story. The only question is which chapter you're in, and how long you'll wait before writing the next one.

[Get started with Tuist](https://tuist.io) and see the difference in days, not months.
