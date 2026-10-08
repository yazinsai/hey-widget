# HeyDay

macOS desktop day-view widget for HEY Calendar. Single SwiftUI file (`Sources/HeyDay.swift`) that shells out to the `hey` CLI (`--json`). Build with `./build.sh`, install with `./build.sh install`.

## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
