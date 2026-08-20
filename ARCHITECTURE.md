# C Drive Cleaner Target Architecture

## Challenger corrections

The project will not start with a full WinUI or .NET rewrite. A rewrite would
replace already tested deletion safeguards before equivalent contracts exist.
The migration uses a strangler pattern: stabilize data and process contracts,
then replace one implementation boundary at a time.

The following capabilities are optional accelerators, never hard dependencies:

- NTFS MFT/USN scanning: use only when the volume, privileges, and platform
  support it; retain a normal filesystem enumeration fallback.
- Local AI: use only when a compatible runtime and model are available and the
  user has consented to any model download.
- Cloud AI: opt-in only; send redacted structured summaries, never file content
  or raw private paths by default.
- Downloadable rule packs: accept only signed, schema-valid, version-compatible
  packs. The built-in rules remain the safe fallback.

## Runtime boundaries

```text
Desktop UI
  -> Application orchestrator
      -> Scan provider (filesystem fallback; future NTFS accelerator)
      -> Signed rule catalog and deterministic recommendation policy
      -> Cleanup plan validator
      -> Execution broker (future isolated/elevated process)
      -> Event stream and report store
      -> AI copilot (optional explanation/orchestration layer)
      -> Travel provider (optional FlyAI read-only search process)
```

The model is outside the deletion trust boundary. It may read redacted scan
results, explain known item IDs, propose a selection, or open confirmation. It
may not submit paths, shell commands, or final deletion approval.

The read-only copilot has a deterministic offline core. It constructs a new
field-allowlisted summary from scan results instead of attempting to redact the
original JSON. Optional cloud prompts require explicit consent and receive only
stable IDs, byte counts, risk classes, and recovery modes.

Assistant requests pass through an allowlisted tool router. Text that contains
paths, shell commands, rule-bypass instructions, or delegated cleanup approval
is rejected before dispatch. Selection tools can only return stable IDs and
change reversible UI state; they cannot start the cleanup process.

Travel search is a separate optional trust domain. The desktop app passes only
the user's current travel question to an isolated FlyAI process after explicit
session consent. Scan results, paths, logs, machine identity, and cleanup plans
are never included. FlyAI results may contain HTTPS detail or booking links,
but the application never purchases, books, or submits traveler data.

Travel rendering never executes provider HTML or Markdown. The isolated host
converts provider output into a typed display model; HTTPS links remain explicit
user actions. Optional preview images accept only FlyAI/Alibaba CDN hosts, are
bounded by count, size, time, content type, and decoded dimensions, and are
copied to temporary local PNG files before the desktop UI loads them.

## Quantified target

| Area | Target |
| --- | --- |
| Safety | Unknown IDs, stale plans, rule drift, and changed user content always fail closed. |
| Rules | 100% of cleanup and diagnostic targets load from a versioned schema. |
| Events | Scan and cleanup expose versioned NDJSON events without parsing console prose. |
| Responsiveness | UI receives progress within 500 ms and cancellation acknowledgement within 2 s. |
| Performance | Warm repeat scan is at least 3x faster where the NTFS USN provider is readable; journal reset, permission failure, oversized indexes, and unsupported volumes fall back to correct filesystem enumeration. |
| Recovery | User-content attachments are sent to the Windows Recycle Bin and cannot be selected in the same operation as recycle-bin purging. |
| AI | Core functionality works with AI disabled; every action is a schema-bound allowlisted tool. |
| Travel | FlyAI is optional, read-only, consented per app session, and cannot call cleanup tools or complete bookings. |
| Privacy | Cloud mode sends no raw path, user name, log, or file content unless separately previewed and approved. |
| Release | Candidate SHA, source fingerprint, tests, package, and Release remain auditable. |

## Migration phases

1. P0 Contracts: external rule catalog, event protocol, AI tool boundary, loop gate.
2. P1 Process: structured child-process IPC, progress, cancellation, typed errors.
3. P2 Scan providers: filesystem baseline, benchmark corpus, optional NTFS index.
4. P3 Execution broker: least privilege, operation journal, recovery feasibility.
5. P4 Read-only copilot: explain results and answer questions from local data.
6. P5 Constrained agent: scan and selection tools; UI confirmation remains final.
7. P6 Shell migration: move proven core boundaries to .NET only where metrics justify it.
8. P7 Incremental scan: consume NTFS USN deltas through a bounded, path-free stable-ID index and preserve full-scan and deletion-time verification fallbacks.
9. P8 Provider foundation: isolate model calls in Agent Host and protect BYOK credentials with Windows DPAPI CurrentUser.
10. P9 Streaming chat: render NDJSON/SSE responses without blocking WinForms and preserve deterministic offline fallback.
11. P10 Strict tools: support Responses and Chat Completions tool calls through schema v2; text-only providers remain read-only.
12. P11 Reversible UI: broker navigation, scan control, and stable-ID selection with replay rejection and hard loop limits.
13. P12 Confirmation bridge: route Agent cleanup intent through the same native selection checks and user confirmation as the toolbar.
14. P13 Hardening: verify privacy request snapshots, credential removal, injection rejection, UI cancellation, packaging, and full release gates.
15. P14 Conversational cleanup and travel: accept explicit affirmative cleanup requests, select only recommended stable IDs, preserve native final confirmation, use a fixed user avatar, and isolate consented FlyAI read-only travel search from all cleanup data.
16. P15 Conversational UI control: map deterministic local-language commands to the existing allowlisted UI broker for navigation, scan control, stable-ID selection, reports, settings, comparison, and native cleanup confirmation.
17. P16 Structured travel results: parse FlyAI Markdown into a typed local display model, render readable itinerary sections and explicit detail links, and optionally cache at most three validated FlyAI/Alibaba CDN preview images through the isolated Travel Host.

P6 currently defers a full rewrite. Directory sizing and child-process control
already use focused C# implementations, while the PowerShell contracts retain
the tested rule, plan, journal, and cleanup safeguards. The measurable triggers
and rollback paths for any future migration are in `migration-decision.json`.

## Incremental scan boundary

- The first eligible scan records NTFS file reference numbers against stable
  cleanup item IDs. The index stores no path, file name, user name, or content.
- A repeat scan reads USN records from the saved cursor and rescans only item
  IDs whose indexed file or parent reference changed.
- User-content rules are never indexed. Cleanup mode never reuses cached sizes;
  it rescans the selected stable IDs before the execution broker can delete.
- The index is integrity hashed and bounded to 64 MB, 100 entries, 250,000
  identities per item, and 1,000,000 identities total.
- Missing privileges, non-NTFS volumes, journal replacement or wrap, unsupported
  records, corrupt indexes, and budget overflow fail closed to the fast normal
  filesystem provider. The application does not request automatic elevation.

## Architecture loop

Each iteration follows the same state machine:

```text
OBSERVE -> CHALLENGE -> SELECT -> IMPLEMENT -> VERIFY -> MEASURE -> DECIDE
     ^                                                              |
     +---------------- regression / unmet metric --------------------+
```

- `OBSERVE`: collect code, test, runtime, and user-experience evidence.
- `CHALLENGE`: list unsafe assumptions and cheaper alternatives.
- `SELECT`: choose one bounded capability with explicit acceptance criteria.
- `IMPLEMENT`: change only the selected boundary.
- `VERIFY`: run safety, contract, UI, packaging, and architecture gates.
- `MEASURE`: record correctness and performance evidence.
- `DECIDE`: advance only when all exit criteria pass; otherwise repair the same
  iteration or revise the assumption.

## Execution and recovery policy

- Cleanup requires a fresh, manifest-bound selection plan; direct `-Clean`
  without a plan fails closed.
- The execution broker resolves every action from the trusted catalog by stable
  ID. Callers cannot provide a cleanup path or substitute rule fields.
- The application runs at the caller's current privilege and never triggers
  automatic UAC elevation. Admin-only items are skipped and journaled.
- Standard cache cleanup is permanent. The two opt-in WeChat/QQ media rules use
  the Windows Recycle Bin, report staged bytes separately from freed bytes, and
  cannot be combined with recycle-bin cleanup.
- Cleanup operations produce schema-versioned NDJSON journals under
  `%LOCALAPPDATA%\CDriveCleaner\journals`. Journals contain stable IDs and
  outcomes, not raw cleanup paths or file content.

The machine-readable state is stored in `architecture-loop.json`. Run
`tools/Invoke-ArchitectureLoop.ps1` to evaluate the current gate.
