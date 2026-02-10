# Project Detection Reference

How Forge detects what it's working with. This is guidance, not a hardcoded mapping — read files and infer.

## What to Scan

### Step 1: List the Root
List all files and directories at the project root. Look for config/manifest/build files. Common examples (not exhaustive):

- `package.json` — Node.js ecosystem (npm, pnpm, yarn)
- `pyproject.toml`, `setup.py`, `requirements.txt` — Python ecosystem
- `mix.exs` — Elixir
- `go.mod` — Go
- `Cargo.toml` — Rust
- `Gemfile` — Ruby
- `pom.xml`, `build.gradle`, `build.gradle.kts` — JVM (Java, Kotlin, Scala)
- `composer.json` — PHP
- `deno.json`, `deno.jsonc` — Deno
- `bun.lockb`, `bunfig.toml` — Bun
- `rebar.config` — Erlang
- `build.zig` — Zig
- `gleam.toml` — Gleam
- `Makefile` — could be anything, read it
- `Dockerfile`, `docker-compose.yml` — containerized
- `flake.nix`, `shell.nix` — Nix-based
- `.tool-versions`, `.mise.toml` — version management (asdf, mise)

If you see something you don't recognize, **read it** — the contents will tell you what it is.

### Step 2: Check Subdirectories
Look one level deep for multi-repo/monorepo signals:

- Multiple directories each with their own manifest files → multi-repo or monorepo
- `packages/`, `apps/`, `services/`, `libs/` directories → monorepo
- `pnpm-workspace.yaml`, `lerna.json`, `nx.json`, `turbo.json` → monorepo tooling
- Separate git repos side-by-side in the workspace → multi-repo

### Step 3: Read and Extract

For each config file found, read it and extract:

**Lint commands** — look in:
- `package.json` → `scripts.lint`, `scripts.format`, `scripts.check`
- `pyproject.toml` → `[tool.ruff]`, `[tool.flake8]`, `[tool.black]`
- `Makefile` → `lint:`, `format:`, `check:` targets
- `mix.exs` → deps like `:credo`, `:dialyxir`
- `.pre-commit-config.yaml` → hooks listed

**Test commands** — look in:
- `package.json` → `scripts.test`, `scripts.test:unit`, `scripts.test:e2e`
- `pyproject.toml` → `[tool.pytest]`
- `Makefile` → `test:` target
- `mix.exs` → `mix test` is the standard

**Build commands** — look in:
- `package.json` → `scripts.build`
- `Dockerfile` → build steps
- `Makefile` → `build:` target
- Language-specific: `cargo build`, `go build`, `mix compile`

**Don't guess commands.** If you can't find an explicit command in the config files, note it as "not configured" and let gap detection handle it.

## Monolith vs Multi-Repo vs Monorepo

| Signal | Interpretation |
|--------|---------------|
| Single manifest at root, no sub-packages | Monolith |
| Multiple dirs with separate manifests, same git repo | Monorepo |
| User has added multiple working directories with separate git repos | Multi-repo |
| Workspace config (`pnpm-workspace.yaml`, `lerna.json`, `turbo.json`) | Monorepo with tooling |

## What to Present to the User

After detection, present a summary like:

```
Detected stack:
- Language: Python 3.12, TypeScript 5.x
- Frameworks: FastAPI (backend), SvelteKit (frontend)
- Package managers: uv (backend), npm (frontend)
- Lint: `uv run ruff check` (backend), `npm run lint` (frontend)
- Test: `uv run pytest` (backend), `npm run test` (frontend)
- Build: Docker Compose (backend), `npm run build` (frontend)
- Structure: Multi-repo (2 working directories)

Is this correct? Any adjustments?
```

Let the user confirm or correct before storing.
