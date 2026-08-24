# Flight Start

Starter projects for [Flight](https://github.com/Swift-Flight/flight), and the
tutorial that builds them.

## Pick a starting point

| Template | For | Includes |
|---|---|---|
| [`skeleton`](templates/skeleton) | A new service | Configuration, DI, HTTP, health endpoints |
| [`basics`](templates/basics) | A service with a database | + entities, migrations, a repository, CRUD |
| [`demo`](templates/demo) | Reading, not starting from | + PubSub, Channels, Presence, caching, auth, the full query tour |

Copy a directory, rename the package, and build. Each one is a working
project with passing tests.

## Or follow the tutorial

[TUTORIAL.md](TUTORIAL.md) builds all three in order — Part 1 ends at
`skeleton`, Part 2 at `basics`, Part 3 at `demo`. Every stage ends with a
command and what you should see.

## Why the templates are nested

`skeleton`'s files are a subset of `basics`', and `basics`' a subset of
`demo`'s. That is checked in CI, and it is not decoration: it is what lets
each tutorial stage be a real diff between two working projects rather than
prose that slowly stops matching the code.

## Verifying

```bash
./CI/verify-templates.sh          # build and test all three tiers
./CI/verify-templates.sh basics   # or just one
./CI/verify-tutorial.sh           # check the tutorial still describes them
```

Templates ship URL dependencies, because that is what a downloaded project
must contain. `verify-templates.sh` copies each tier to a scratch directory
and rewrites those to local paths before building, so the tiers can be
checked against working copies of `flight` and `flight-data` — the templates
themselves are never modified.

CI runs both scripts, and `flight` and `flight-data` call this workflow, so a
breaking change there fails on the pull request that caused it rather than in
someone's first ten minutes with a downloaded project.
