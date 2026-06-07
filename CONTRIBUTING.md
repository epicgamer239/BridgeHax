t# Contributing to VisionBridge

## Branching (trunk-based development)

- **`main`** is the **only** long-lived branch. It is the default branch and the **single** integration target. All work lands here via **pull request** (or direct push if you have access and keep history clean).
- Use **short-lived** branches for changes, e.g. `feat/…`, `fix/…`, or `author/topic`. Branch from **`main`**, open a **PR into `main`**, merge, then **delete the branch** (GitHub: “Delete branch” on the PR, or **Settings → General → “Automatically delete head branches”**).
- The codebase is split by **folder** (e.g. `src/visual_engine/`, `ios/VisionBridgeKit/`, `AudioEngine/`, `ui/`) — not by permanent remote branches.
- **Tags** and **GitHub Releases** are the right way to mark milestones (e.g. `v0.1.0`), not long-lived `release/*` unless you outgrow a single `main` later.

## Commits and pull requests

- Prefer **small, reviewable** PRs and **clear** commit messages.
- [Conventional Commits](https://www.conventionalcommits.org/) (e.g. `feat:`, `fix:`, `docs:`) are **optional**; use them if they help the team and tooling.

## Engineering log (vision pipeline)

- Vision- and contract-related work should still be **logged** in **`docs/VISION_BRANCH_LOG.md`** (name is historical), per **PRD** maintenance. Same rule applies whether the change is on a PR branch or `main`.

## Testing

- Python: from repo root with venv, `pytest -m "not slow"` (faster) or full `pytest` as needed.
- Swift package: `cd ios/VisionBridgeKit && swift build` (macOS compiles the kit; the full iOS app follows **`ios/XCODE_SETUP.md`**).
