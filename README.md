# Ralph Mode

A minimal pi-based Ralph executor for running through `prd.json` one user story at a time.

This MVP is based on the official Ralph workflow, especially [`CLAUDE.md`](https://github.com/snarktank/ralph/blob/main/CLAUDE.md), adapted for pi and `plan-mode`.

## Relationship to plan-mode

Ralph-mode is the executor half of this workflow:

| Phase | Tool | Output |
|---|---|---|
| Plan | `pi --plan` + `/compile-prd` | `prd.json` |
| Execute | `./ralph-mode/run.sh --model <model>` | Implemented stories, commits, progress memory |

## Quick Start

From your project root:

```bash
# 1. Produce prd.json with plan-mode
pi --plan
# then run /compile-prd inside pi

# 2. Execute stories with Ralph Mode
./ralph-mode/run.sh --model gpt-5.5

# Or set/pass max iterations
MAX_ITERATIONS=10 ./ralph-mode/run.sh --model gpt-5.5
./ralph-mode/run.sh --model gpt-5.5 10
```

`--model <model>` is required and is passed through to `pi --model`. Default `MAX_ITERATIONS` is `20`.

## Required `prd.json` Shape

`run.sh` expects `prd.json` in the current working directory where you run the script.

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature-name",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Short title",
      "description": "As a user, I want a feature so that I get value.",
      "acceptanceCriteria": [
        "Specific verifiable criterion",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

## How It Works

Each iteration starts a fresh pi instance using:

```bash
pi --model <model> -p "$(cat ralph-mode/prompt.md)"
```

The agent then follows the official Ralph-style flow:

1. Read `prd.json`
2. Read `progress.txt`, especially `## Codebase Patterns`
3. Check out/create the PRD `branchName`
4. Select the highest-priority story where `passes: false`
5. Implement exactly one story
6. Run acceptance checks and quality gates
7. Update reusable learnings in nearby `CLAUDE.md` files when useful
8. Set `passes: true` and update `notes` in `prd.json` if checks pass
9. Append progress/learnings to `progress.txt`
10. Commit with `feat: [Story ID] - [Story Title]`
11. Stop after one story

The outer loop exits successfully when either:

- pi outputs the official Ralph completion signal: `<promise>COMPLETE</promise>`
- or `run.sh` independently verifies every story has `passes: true`

## Environment Variables

| Variable | Default | Description |
|---|---:|---|
| `MAX_ITERATIONS` | `20` | Maximum fresh pi iterations to run |

## Key Files

| File | Purpose |
|---|---|
| `run.sh` | Outer loop runner |
| `prompt.md` | pi executor prompt adapted from official `CLAUDE.md` |
| `prd.json` | Story list and pass/fail state in your project root |
| `progress.txt` | Progress memory and reusable codebase patterns |
| `CLAUDE.md` | Optional nearby memory files updated with reusable learnings |

## Limitations of Option A

This is only an outer-loop shell script, not a native pi TUI extension.

Limitations:

- Every iteration starts with fresh context
- State persistence depends on git history, `prd.json`, and `progress.txt`
- No structured progress UI
- Recovery from partial/failed iterations depends on notes and progress memory

## Future Option B

A future `pi --run` or native pi extension could provide:

- Persistent structured state across iterations
- Better progress UI
- More reliable error recovery
- Native story selection and status tracking

Use this Option A MVP to validate whether the Ralph workflow is useful before investing in that richer implementation.
