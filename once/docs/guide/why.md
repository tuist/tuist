# Why

Most developer automation was designed around a quiet assumption: one
process is doing the work. A developer runs a task locally, or a CI job
runs it after a push. The task starts, reads the repository, writes its
outputs, and exits. If it takes a minute, the person or pipeline waits a
minute.

That assumption shaped the tools around it. Caching, remote execution, and
distributed compute made sense for large companies with monorepos, large
teams, and enough repeated work to justify the infrastructure. Most
projects did not need that kind of machinery because their automation was
mostly serial, mostly local, and mostly driven by humans.

## Agents Change The Shape

Coding agents push against that model. They can run concurrently across
worktrees, explore several fixes at once, retry tests, regenerate outputs,
and ask for the same expensive setup from different sessions. Work that was
annoying when one developer repeated it becomes wasteful when many agents
repeat it in parallel.

That changes what feels worth optimizing. The capabilities once associated
with large enterprise build systems start to matter in ordinary
repositories: stable action identities, deterministic inputs, reusable
outputs, shared cache storage, and the option to run work somewhere other
than the current laptop.

## Infrastructure Is Fragmenting

At the same time, new caching and compute infrastructure is emerging to
serve this need. Some providers focus on artifact storage. Some focus on
remote execution. Some are tied to a build system, a CI vendor, a cloud
runtime, or an agent platform.

The result is useful, but fragmented. Teams still need a way to describe
what work should happen, what values affect it, which outputs matter, and
what an agent can inspect while that work is running, without binding every
automation workflow to one provider.

## Once Is The Narrow Waist

Once is the [narrow waist](https://en.wikipedia.org/wiki/Hourglass_model)
between automation needs and the infrastructure that can make those
workflows faster. Above Once, developers and agents describe actions:
inputs, outputs, environment, working directory, runtime metadata, and the
provider capabilities they need. Below Once, providers can supply local
cache storage, shared cache storage, remote compute, or future execution
surfaces.

Keeping that waist small matters. The action contract should be simple
enough for agents to reason about, stable enough for providers to
implement, and flexible enough for teams to keep using the tools they
already have.

We are starting with [scripts](/guide/scripts/) because scripts are
everywhere, and they already encode real repository knowledge. But the
model is not limited to scripts. Once is an interface for automation needs,
with room to grow toward build-system integrations and agent-facing
workflows where text and voice can become the way people declare what they
want the system to run, cache, inspect, or parallelize.
