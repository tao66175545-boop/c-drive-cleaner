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

## Quantified target

| Area | Target |
| --- | --- |
| Safety | Unknown IDs, stale plans, rule drift, and changed user content always fail closed. |
| Rules | 100% of cleanup and diagnostic targets load from a versioned schema. |
| Events | Scan and cleanup expose versioned NDJSON events without parsing console prose. |
| Responsiveness | UI receives progress within 500 ms and cancellation acknowledgement within 2 s. |
| Performance | Warm repeat scan is at least 3x faster where an incremental provider is supported; fallback remains correct. |
| Recovery | User-content attachments are sent to the Windows Recycle Bin and cannot be selected in the same operation as recycle-bin purging. |
| AI | Core functionality works with AI disabled; every action is a schema-bound allowlisted tool. |
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

P6 currently defers a full rewrite. Directory sizing and child-process control
already use focused C# implementations, while the PowerShell contracts retain
the tested rule, plan, journal, and cleanup safeguards. The measurable triggers
and rollback paths for any future migration are in `migration-decision.json`.

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
