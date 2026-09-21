---
name: security-audit
description: Use when the user asks for a security audit, security review, vulnerability scan, or hardening of shell scripts, system utilities, or CLI tools. Covers command injection, symlink races, TOCTOU, unsafe temp files, input validation, privilege escalation, and defense-in-depth.
---

# Security Audit Skill

Systematic methodology for auditing shell scripts and system utilities for security vulnerabilities. Designed for tools that run with elevated privileges (root, sudo) and interact with system files, package managers, and user input.

## Audit Methodology

### Phase 1: Threat Model

Before reading code, establish the threat model:

1. **Privilege level**: Does the tool run as root? As a dedicated user? Both?
2. **Attack surface**: What inputs does it accept? (config files, CLI args, environment vars, downloaded content, user-supplied paths)
3. **Trust boundaries**: Where does trusted input end and untrusted begin?
4. **What's inherent**: Some risks are fundamental to the program's purpose. An Arch Linux update tool *must* run as root and *must* install packages. Don't report these — focus on what can be mitigated.

### Phase 2: File-by-File Scan

Read every source file. For each file, check for:

#### Command Injection & Shell Safety
- Unquoted variable expansions in command arguments
- `eval`, `exec`, `source` with user-controlled input
- Word splitting on values passed to commands (especially `pacman`, `sudo`, `runuser`)
- Glob injection in `find -name`, `ls`, or pattern-matching contexts
- `set -e` not set in scripts that should fail fast

#### Symlink & Path Attacks
- `rm -rf` on paths that could be symlinks (always check `[ -L "$path" ]` before `rm -rf`)
- `cat`, `cp`, `mv` on files without symlink rejection
- TOCTOU between checking a path and operating on it
- Predictable filenames in shared directories (`/tmp`, `/var/log`)

#### Temp File Safety
- Predictable temp filenames (use `mktemp`)
- Temp files in world-writable directories without `chmod 700`
- Race between creating temp file and using it

#### Input Validation
- Regex patterns that are too permissive (e.g., allowing `.` and `/` in usernames)
- `case` glob patterns that accidentally use regex syntax (`^`, `$`, `+` are literals in `case`)
- Missing validation on function parameters
- Config values used without bounds checking

#### Privilege & Permission Handling
- `chown`, `chmod` without error handling (or with silent `|| true`)
- Sudoers rules that are too broad
- Running untrusted code as root
- Missing privilege checks before privileged operations

#### Atomicity & Integrity
- Multiple non-atomic file operations (use `flock` or single `mv`)
- Validation after commit instead of before
- Silent failure masking real errors

#### Early Exit

If no vulnerabilities are found after scanning all files, report that the codebase is clean and stop. Do not fabricate findings or pad the report with low-value nitpicks. A clean audit is a good audit.

### Phase 3: Severity Classification

Classify each finding:

| Severity | Criteria |
|----------|----------|
| CRITICAL | Actively exploitable, defeats security mechanisms, or allows privilege escalation |
| HIGH | Requires specific conditions but has real impact |
| MEDIUM | Defense-in-depth improvement, reduces attack surface |
| LOW | Best practice, minimal practical risk |
| INFO | Inherent to the program's design, cannot be mitigated |

### Phase 4: Plan & Fix

1. Group fixes by file to minimize context switching
2. Order by severity (critical first)
3. For each fix, note which tests might break and why
4. Apply fixes, then run lint and tests
5. Fix any test breakage that is legitimate (test was testing wrong behavior)

### Phase 5: Tests

If a fix changes observable behavior (new error messages, new validation, changed control flow), add or update tests to cover the new behavior:

- **Unit tests** (`tests/bats/`): Add tests for new validation rules, error paths, and edge cases. Test both the happy path and the rejection case.
- **Integration tests** (`tests/integration/`): Add integration tests if the fix affects install, uninstall, update, or reconfigure flows.
- Don't add tests for purely internal changes (e.g., reordering operations) unless the change affects external behavior.

### Phase 6: Commit & Push

Once all fixes are applied, tests pass, and the build is clean:

1. `make lint` — no warnings
2. `make test` — all unit tests pass
3. `make integration` — all integration tests pass
4. `make` — build succeeds
5. Commit with a descriptive message covering what was fixed and why
6. Push to the remote

## Common Patterns to Watch For

### Shell-specific gotchas
```bash
# BAD: case uses glob, not regex — ^, $, + are literal
case "$val" in
  ^[0-9]+$) ;;  # NEVER matches — requires literal ^, +, $
esac

# GOOD: use [[ =~ ]] for regex
if ! [[ "$val" =~ ^[0-9]+$ ]]; then
  echo "invalid" >&2; exit 1
fi
```

```bash
# BAD: rm -rf follows symlinks
rm -rf "$path"

# GOOD: check first
[ -L "$path" ] && echo "refusing symlink" >&2 && exit 1
rm -rf "$path"
```

```bash
# BAD: predictable temp file
log="/tmp/myapp.$(date +%s).log"

# GOOD: mktemp
log="$(mktemp /tmp/myapp.XXXXXX.log)"
```

```bash
# BAD: validate after commit
mv "$tmp" "$final"
validate "$final" || true  # too late, file is already placed

# GOOD: validate before commit
validate "$tmp" || { rm -f "$tmp"; return 1; }
mv "$tmp" "$final"
```

```bash
# BAD: two non-atomic operations
mv "$tmp_a" "$dest_a"
mv "$tmp_b" "$dest_b"  # crash between these = inconsistent state

# GOOD: atomic under flock
(
  flock -w 5 9 || exit 1
  mv "$tmp_a" "$dest_a"
  mv "$tmp_b" "$dest_b"
) 9>"$lockfile"
```

### Regex vs Glob confusion

When auditing `case` statements, remember:
- `case` uses **glob** patterns (wildcards only: `*`, `?`, `[...]`)
- `^`, `$`, `+`, `.` are **literal** characters in glob
- For regex matching, use `[[ string =~ pattern ]]`

### Validation depth

A regex allowlist on input is good but not sufficient. Check if the value is also:
- Quoted when used in command arguments
- Passed through `printf '%s'` rather than bare expansion
- Used in contexts where word splitting could occur

## What NOT to Report

Skip issues that are fundamental to the program's function:
- "This program runs as root" (if it must for its purpose)
- "AUR packages are untrusted" (inherent to AUR helper design)
- "This program modifies system files" (that's its job)
- "Package manager has root access" (required for system updates)
- Self-signed integrity checks (inherent to self-distributed tools)

## Updating This Skill

When performing a security audit, you may discover new vulnerability patterns, anti-patterns, or shell-specific gotchas not yet documented here. When that happens:

1. Add the new pattern to "Common Patterns to Watch For" with a BAD/GOOD code example.
2. If the new pattern changes the audit workflow, update the relevant phase.
3. If the fix required a non-obvious test change, add it as an example in the verification section.
4. Keep the skill concise — prefer a one-liner and code example over a paragraph of explanation.
