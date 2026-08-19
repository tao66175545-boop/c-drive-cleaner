# C Drive Cleaner Agent Instructions

## GitHub update approval protocol

- Never ask the user to open GitHub or click Merge for a routine project update.
- After finishing a feature or release change, run `tools/Submit-UpdateCandidate.ps1`, wait for the PR validation check, and fix failures in the same PR before asking for approval.
- Present one approval summary in the Codex conversation containing the PR number, version, exact head commit SHA, source fingerprint, test result, and a concise change summary.
- Ask the user to reply `同意` in the Codex conversation. A generic `继续`, a request to inspect status, or approval for a different candidate is not release approval.
- Approval applies only to the exact PR head SHA and source fingerprint shown in the approval summary. Any file or candidate commit change invalidates prior approval and requires a new summary and approval.
- After explicit approval, run `tools/Complete-ApprovedCandidate.ps1` with the displayed PR number, head SHA, and fingerprint. Do not ask for another GitHub-side action.
- The completion script must merge through the protected PR, monitor Validate, Publish Release, and Verify Published Release, and verify remote `main` against the approved fingerprint.
- If a post-approval failure can be retried without changing candidate content, retry it automatically. If code or candidate content must change, stop, prepare a new candidate, and request approval again.
- Never delete or overwrite an existing release or tag. A correction to a published product version requires a new semantic version.

## Project safety rules

- Scanning must not delete files.
- Cleanup must execute only stable item IDs selected by the user; never accept arbitrary deletion paths from UI input.
- WeChat and QQ media remain separate cautious items and are unchecked by default.
- Run `tools/Invoke-ProjectValidation.ps1` for changes that can affect runtime, packaging, workflows, or release behavior.

## Architecture loop

- Read `ARCHITECTURE.md` and `architecture-loop.json` before advancing an architecture phase.
- Use the sequence OBSERVE, CHALLENGE, SELECT, IMPLEMENT, VERIFY, MEASURE, DECIDE.
- Do not advance a phase while `tools/Invoke-ArchitectureLoop.ps1 -FullValidation` fails or an exit metric lacks evidence.
- Preserve the filesystem enumeration fallback; NTFS MFT/USN acceleration is optional.
- AI must remain optional and outside the deletion trust boundary. It may propose stable item IDs, but it may not supply paths, commands, or final cleanup approval.
