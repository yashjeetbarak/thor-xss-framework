# Thor Command Deck UI

Thor Command Deck is a local browser interface for the existing Thor CLI.

It does **not** replace, rewrite, or duplicate the Bash workflow. The UI starts a minimal local Node.js server that invokes `../thor.sh` with explicit argument arrays and streams stdout/stderr back to the browser.

## What changed in v1.4.0

- Replaced the oversized intro with a compact command-deck header so the scan controls are visible immediately.
- Added a stronger Thor identity: Stormbreaker dark theme, iron-black workspace, ember-gold accents, electric-steel highlights, sharper cards, and more aggressive command-center spacing.
- Renamed the main flow from a generic workbench to a strike console: Rapid Strike, Balanced Hammer, and Siege Mode presets.
- Added a live scan telemetry stack next to the form so progress, URL count, subdomain count, and findings stay visible while configuring or running scans.
- Added a strike discipline panel explaining the safety defaults: scope-only input, batching, and evidence-driven reporting.
- Reduced visual clutter and improved desktop-first layout density.
- Preserved every existing CLI behavior and UI integration endpoint.

## Requirements

- Node.js 18+
- Bash
- A working Thor installation
- Kali Linux or another Linux environment capable of running Thor's CLI dependencies

## Start

From the repository root:

```bash
cd ui
npm start
```

Or:

```bash
./ui/start-ui.sh
```

Then open:

```text
http://127.0.0.1:4173
```

Optional environment variables:

```bash
THOR_UI_HOST=127.0.0.1 THOR_UI_PORT=4173 ./ui/start-ui.sh
```

## Security model

The UI is intended for local use. It binds to `127.0.0.1` by default and only exposes a controlled allow-list of Thor commands:

- scan
- doctor
- history
- resume
- report
- clean
- version

It does not execute arbitrary shell strings. Commands are invoked using argument arrays to avoid shell injection.

## Design goals

- Preserve existing CLI behavior
- Make authorized scope obvious
- Keep the UI strong, compact, and Thor-branded
- Stream live output clearly
- Show history and generated evidence
- Support copy/download actions
- Keep the interface lightweight and dependency-free
