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

<iframe src="/blog/2025/11/6/zero-to-many/iframe.html?id=lone_wolf" width="100%" height="400" frameborder="0" data-visualization loading="lazy"></iframe>

But your app is growing. Users are signing up. And one bad commit ships a critical bug in your weekly release because there was no safety net. That's when you realize: pure velocity without quality control is just recklessness in disguise.

## Phase 2: Adding Safety Nets

You set up GitHub Actions. You create a branch called "develop" and promise yourself you'll only merge to main after tests pass. You hire your first engineer, Marcus, who's also using AI coding tools to write code faster. Now when you want to ship a feature, you open a pull request. The CI kicks off, running tests and linting. It takes eight minutes. Marcus reviews your code over lunch, another 20 minutes. Then it merges. When Marcus ships code, you review. Another 20 minutes. CI runs. Eight minutes. Merge.

You're still moving fast. About 11 commits a day make it to main, down slightly from your solo peak but way safer. Once or twice a week you run into a merge conflict because you both touched the same file, but it's quick to resolve. Occasionally a test fails randomly, and you just rerun the CI. Your team of two, each augmented with a couple of AI coding assistants, has added 15 to 20 minutes of overhead per commit. But you've also stopped shipping bugs to production.

<iframe src="/blog/2025/11/6/zero-to-many/iframe.html?id=safety_nets" width="100%" height="400" frameborder="0" data-visualization loading="lazy"></iframe>

The app is growing. Revenue is growing. You raise a seed round and decide it's time to build a real team.

## Phase 3: The Team Multiplier

Six months later, you have five engineers. Everyone has AI assistants helping them write code. The roadmap is ambitious. The team is talented. The codebase has tripled in size. Each developer, amplified by AI, can individually write code for eight or nine features a day. That should mean 40 commits a day hitting main. That's 4× what you and Marcus were doing alone. But that's not what happens.

Li opens a PR at 9am. It sits waiting for review because you're in meetings and Marcus is deep in his own feature. Three hours later, you finally review it. You request changes, there's a naming inconsistency and a missing edge case. Li makes the updates, but now the CI is taking 22 minutes because the test suite has grown. And when it finishes, there's a merge conflict because Marcus merged something that touched the same service. Li resolves it, reruns CI, another 22 minutes. It's 3pm. One commit, six hours.

This happens to everyone, all day long. PRs sit in review queues. Merge conflicts happen on one in five merges now that five people are touching overlapping code. The CI occasionally has a flaky test, and nobody's quite sure which test it is, so they just click "retry." About a third of PRs come back with requested changes, adding another round trip. The merge throughput isn't 40 commits a day. It's six.

And then there's the CI bottleneck. Your provider asked you to estimate how many runners you'd need. That works when your workload is predictable, but it's not. Nobody's is. During peak hours, PRs pile up waiting for available runners. Your team sits idle, watching the queue grow. The provider is just leaking the pain of hosting Mac minis to you. They can't absorb your elastic demand because they don't operate at the scale you need. You're not blocked by budget. You're blocked by infrastructure that can't keep up.

<iframe src="/blog/2025/11/6/zero-to-many/iframe.html?id=team_multiplier" width="100%" height="650" frameborder="0" data-visualization loading="lazy"></iframe>

You hired three more people and throughput improved, but not nearly as much as you expected. This isn't what growth is supposed to look like.

## Phase 4: The Complexity Wall

Two years in, your mobile team has grown to 30 engineers. Everyone is shipping code, everyone has AI tools making them more productive than ever, and the feature velocity should be incredible. The CI now takes 15 minutes. Sometimes 25 if you're unlucky with the test runner allocation, which takes a few minutes just to start because the queue is backed up. Nobody remembers who wrote half the tests in the suite. One in five CI runs fails because of a flaky test, and debugging which test is flaky wastes hours.

PRs sit for four to six hours waiting for review because reviewers are context-switching between their own features, meetings, and the three other PRs in their queue. When reviews finally happen, 40% come back with requested changes. More waiting. More CI runs. Merge conflicts happen on two out of every five merges now. When someone finally resolves a conflict and merges, they hold their breath hoping nobody else merged in the 15 minutes the CI was running. If they did, back to square one.

The math is brutal: 30 developers, each capable of producing eight features a day individually, should be generating 240 commits. The actual merge throughput is 70 commits a day.

<iframe src="/blog/2025/11/6/zero-to-many/iframe.html?id=complexity_wall" width="100%" height="500" frameborder="0" data-visualization loading="lazy"></iframe>

You're paying €4.2 million a year in engineering salaries and getting the output of six developers. The efficiency is 29%. The waste is €3 million a year, just in idle time waiting for CI, reviews, and conflict resolution. The board asks why feature delivery has slowed down. You don't have a good answer.

## Phase 5: The Brute Force Trap

Your VP of Engineering has a plan. Three plans, actually. Each one sounds reasonable in isolation, but none of them address the root problem:

**Option 1: Faster Machines**
"We'll upgrade to the beefiest CI runners GitHub offers," he says. Sixteen cores instead of four. The cost is €300,000 a year, but it'll cut the 15-minute CI down to maybe 8 minutes. Your team calculates: that's a 14% improvement in throughput. Seventy commits a day becomes eighty. For €300K.

**Option 2: More People**
Your CFO suggests hiring 10 more developers to "parallelize the work." Another €1.4 million in salary. But you've learned the math by now. More people means more conflicts, longer review queues, even slower CI. Throughput might not move at all. It might even go down.

**Option 3: Technology Rewrite**
A CTO from your previous company suggests you rewrite everything in React Native. "No compilation step," he says. "Way faster iteration." The rewrite would take eight months, cost your entire team's focus, and about €2.8 million in opportunity cost. And at the end, you'd inherit a new set of problems:

- **A brittle foundation built on constantly-evolving packages.** The ecosystem moves fast, breaking changes are common, and keeping dependencies up to date becomes a perpetual maintenance burden. What works today might require rewrites tomorrow.

- **A massively expanded security surface.** Instead of relying on platform APIs maintained by Apple and Google, you now depend on hundreds of npm packages, each with their own maintainers, each a potential entry point for supply chain attacks.

- **Platform features become harder to access.** Every time iOS or Android releases a new API, you wait for someone in the community to write a bridge. Native features that should take hours now take days or weeks, assuming someone builds the bridge at all.

- **Performance optimization becomes the default state.** Instead of focusing on building features, your team spends cycles debugging why lists scroll slowly, why animations drop frames, why the app uses too much memory. The abstraction layer adds overhead that you constantly fight against.

But you'd still have the same coordination problems at 30 people.

You pick the faster machines because it's the cheapest mistake. Throughput edges up to eighty commits a day. You're paying €300,000 a year to improve efficiency from 29% to 33%. You know you're treating symptoms, not the disease. The disease is that you're building and testing everything, every time, for every change, no matter how small. But you don't know what else to do.

## Phase 6: Smart Optimization

But there's an elephant in the room. Something that would be cheaper than all three options, and would have a dramatically better impact.

What if you didn't compile and test everything every time? What if you could diff the changes to be selective about what to compile and what to test? When Li changes the authentication module, why are you rebuilding the 47 other modules that didn't change? When someone touches a networking utility, why are you running the entire 3,400-test suite instead of just the 200 tests that actually depend on that code?

Then you talk to an engineering leader at another company who faced the same wall. "We implemented Tuist," he says. "[Binary caching](https://docs.tuist.dev/en/guides/develop/build/cache) and [selective testing](https://docs.tuist.dev/en/guides/develop/test/smart-runner). Changed everything." The idea is simple: only rebuild what changed, only test what's affected, and share the cached results across your entire team and CI.

Your team spends a month implementing Tuist. You set up [binary caching](https://docs.tuist.dev/en/guides/develop/build/cache) so when Li changes the authentication module, the other 47 modules use cached builds from the last time they were compiled. You implement [selective testing](https://docs.tuist.dev/en/guides/develop/test/smart-runner) so the CI only runs the 200 tests affected by the change, not all 3,400. The first PR after the optimization merges in 4 minutes. The second takes three. A complex change touching multiple modules takes 6 minutes.

Your CI time drops from 15 minutes to 3 minutes on average. The queue disappears because jobs finish faster. Review time drops to two hours because fast feedback means reviewers can stay in context. Merge conflicts drop to 25% because the faster cycle time means less overlapping work. The merge throughput climbs. Eighty commits a day. Then 110. Then 140. It stabilizes around 150 commits a day. 

You're still paying €4.2 million for 30 developers. But now you're getting output equivalent to 19 developers instead of nine. The efficiency went from 29% to 63%. You unlocked €1.4 million in value. The investment was roughly a third of a single engineer's salary per year for Tuist and one month of eng time. The payback period was measured in days, not years.

## What Just Happened

Let's trace your journey in numbers. At one developer, you had 100% efficiency. Eleven commits a day from one person's work. At two developers, efficiency dropped to 83%. Fifteen commits from two people. At five developers, efficiency fell to 56%. Twenty-five commits from five people. At thirty developers, efficiency crashed to 29%. Seventy commits from thirty people who should be producing 240. 

After optimization, with the same thirty developers, you climbed to 63% efficiency. One hundred and fifty commits a day. Not perfect, but more than double where you were. And here's the key insight: **you optimized workflows first, not hardware**. Instead of spending €300,000 per year to make your waste happen slightly faster, you spent a third of one engineer's salary to eliminate the waste itself. The hardware approach would have given you 10 more commits per day. The workflow approach gave you 80 more commits per day.

## Why Most Companies Get This Wrong

Here's the pattern we see repeatedly: companies optimize in the wrong order and waste millions before discovering the right solution.

**The typical sequence looks like this:**

**Year 1:** Team hits 15-minute CI times. Leadership approves €300K/year for faster runners. CI drops to 8 minutes. Everyone celebrates the "30% improvement" while ignoring that throughput barely moved. The team is still building and testing everything, just slightly faster.

**Year 2:** Throughput is still terrible. Leadership hires 10 more developers for €1.4M/year, expecting output to increase proportionally. Instead, coordination overhead grows faster than output. More merge conflicts. Longer review queues. CI queue times increase because now 40 people are pushing to the same runners. Efficiency drops further.

**Year 3:** Someone suggests a technology rewrite. "React Native has no compile times!" Six months and €2.8M in opportunity cost later, they've traded Swift compile times for JavaScript bundle times and inherited a fragile dependency tree. The coordination problems are identical. They just happen in a different language.

**Total spend over three years:** €4.5M in direct costs, plus countless hours of engineering time, and throughput improved maybe 20%.

**The alternative sequence that actually works:**

**Month 1:** Implement [binary caching](https://docs.tuist.dev/en/guides/develop/build/cache) and [selective testing](https://docs.tuist.dev/en/guides/develop/test/smart-runner). When a developer changes one module, the other 47 use cached builds. When someone touches authentication code, only the 200 affected tests run, not all 3,400.

**The result:** CI drops from 15 minutes to 3 minutes. Not by building faster, but by building less. Only what changed. Only what matters. The cost is a third of one engineer's salary per year. The gain is 10 engineers worth of output. The payback happens in days.

The difference isn't just the ROI, though that's dramatic. The difference is that one approach treats symptoms while the other fixes the disease. Faster hardware makes waste happen faster. Better workflows eliminate the waste entirely.

## Calculate Your Own Numbers

Use the calculator below to model your organization's efficiency and see the potential impact of workflow optimization. Enter your team size, current CI time, and other factors to understand where you stand and what optimization could unlock.

<div phx-update="ignore">
  <iframe src="/blog/2025/11/6/zero-to-many/iframe.html?id=calculator" width="100%" height="850" frameborder="0" data-visualization loading="lazy"></iframe>
</div>

The patterns are consistent across organizations: efficiency drops as coordination overhead increases, and traditional solutions (more hardware, more people, technology rewrites) barely move the needle. The cost of slow builds isn't developer frustration, though that's real. The cost is millions of euros in wasted salary and missed market opportunities. Features that ship next quarter instead of this quarter. Competitors who move faster. Customers who leave because the bug fix took too long.

**Here's the fundamental insight**: optimize workflows before hardware. A faster machine makes your waste happen faster. A better workflow eliminates the waste. One costs 6 times more and gives you 14% improvement. The other costs a fraction and gives you 117% improvement. This story is every company's story. The only question is which chapter you're in, and whether you'll choose to optimize the right thing.

[Get started with Tuist](https://tuist.io) and see the difference in days, not months.

<script>
  // Intersection Observer to pause/resume iframe animations when they leave/enter viewport
  const observerOptions = {
    root: null,
    rootMargin: '50px',
    threshold: 0.1
  };

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      const iframe = entry.target;
      if (entry.isIntersecting) {
        // Resume animation when iframe is visible
        iframe.contentWindow?.postMessage({ action: 'resume' }, '*');
      } else {
        // Pause animation when iframe is not visible
        iframe.contentWindow?.postMessage({ action: 'pause' }, '*');
      }
    });
  }, observerOptions);

  // Observe all visualization iframes
  document.addEventListener('DOMContentLoaded', () => {
    const iframes = document.querySelectorAll('iframe[data-visualization]');
    iframes.forEach(iframe => {
      observer.observe(iframe);
    });
  });
</script>
