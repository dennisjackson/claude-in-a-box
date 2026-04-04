---
name: nss-triage
description: Triage an NSS/NSPR bug for exploitability and impact. Use when the user says "/nss-triage BUGNUM", "triage bug XXXXX", or similar. Reads bug reports from bugs/, analyzes the vulnerable code, maps all triggering code paths and configurations, and writes a triage report.
version: 1.0.0
---

# NSS Bug Triage

Triage bug: $ARGUMENTS

Follow each phase below in order. Be terse: if a phase completes without issues, just record the outcome and move on. Only provide detail when something is ambiguous or needs the user's attention.

**Report requirement**: You MUST write the report file when you complete the final phase. If the user continues the conversation and subsequent discussion reveals new information — corrections, additional triggering paths, revised severity, new understanding of exploitability — update the report file to reflect the current best understanding. The report should always represent the most accurate and complete picture available.

**Before starting**, record the wall-clock start time:
```sh
date -u +%s
```

---

## Phase 0: Read the Bug

### 0a. Parse arguments

Parse `$ARGUMENTS` to extract one or more bug numbers. Accepted forms: `1234567`, `bug-1234567`, `bug 1234567`. If multiple bugs are given, process them together (they may be related).

Set `BUGNUM` to the primary bug number (first one given, or only one). If `$ARGUMENTS` is empty, use the latest folder under `/workspaces/nss-dev/bugs/` sorted by name.

### 0b. Read all bug context

Locate the bug folder by globbing for the bug number:
```sh
BUG_DIR=$(ls -d /workspaces/nss-dev/bugs/*${BUGNUM}*/ 2>/dev/null | head -1)
```
This matches both new-style folders (`1234567-heap-buffer-overread/`) and legacy ones (`bug-1234567/`). If no match is found, **stop and ask the user** to fetch the bug data first. Do not proceed without bug context.

Once located, read everything available. Fetched content lives in `$BUG_DIR/input/`; reports go to `$BUG_DIR/reports/`:
- `input/bug.md`, `input/comments.md` — read in full
- All files in `input/attachments/` — read patches, test cases, crash logs, stack traces
- Any existing reports in `reports/` (`bugfix-report.md`, `bigger-picture.md`, `review.md`) — these contain prior analysis that saves re-deriving the defect class and code paths
- If multiple bugs were given, read all of them

### 0c. Summarize the reported problem

After reading, produce a concise internal summary:
1. **What is the reported defect?** (e.g., buffer overread, use-after-free, integer overflow, NULL dereference, logic error, race condition)
2. **What input or state triggers it?** (e.g., malformed TLS extension, specific certificate field, particular API call sequence)
3. **Which file(s) and function(s) are mentioned?**
4. **Is there a stack trace or crash log?** If so, note the crashing function and the call chain.

---

## Phase 1: Understand the Vulnerable Code

Read the actual source code in `/workspaces/nss-dev/nss/` to confirm and deepen your understanding. Triage is a read-only analysis — reading from the main checkout is safe here. No worktree is needed unless you need to build or modify code.

### 1a. Locate the defect site

Using the bug report's pointers (file names, function names, stack traces, patches), read the relevant source files. Identify:
- The **exact function** containing the defect
- The **exact lines** where the bug manifests (e.g., the unchecked length, the dangling pointer dereference, the missing bounds check)
- The **data flow**: where does the attacker-controlled or malformed input enter, and how does it reach the defect site?

### 1b. Characterize the defect

Determine:
- **Defect class**: buffer overread, buffer overwrite, use-after-free, double-free, integer overflow/underflow, NULL dereference, type confusion, logic error, race condition, uninitialized memory read, other
- **Preconditions**: What state must the library be in for the bug to be reachable? (e.g., TLS handshake in progress, specific cipher suite negotiated, PKCS#12 decoding active)
- **Attacker control**: How much control does an attacker have over the triggering input? Can they control the overread length, the overwrite content, the freed object's type?

### 1c. Determine the consequence

What happens when the bug triggers?
- **Crash / DoS**: Does it reliably crash the process? Under what conditions?
- **Information disclosure**: Can an attacker read memory beyond intended bounds? What data might leak? (keys, session state, heap metadata)
- **Code execution**: Could an attacker achieve arbitrary code execution? What mitigations (ASLR, stack canaries, heap hardening) would they need to bypass?
- **Authentication/authorization bypass**: Does the bug allow skipping verification steps?
- **Other**: State corruption, protocol downgrade, etc.

State the **worst realistic consequence** — not the theoretical maximum, but what an attacker could plausibly achieve given NSS's typical deployment context (browsers, email clients, VPN, server TLS termination).

---

## Phase 2: Map Triggering Code Paths

This is the core of the triage. Systematically identify every way the vulnerable code can be reached.

### 2a. Direct callers

Find all direct callers of the vulnerable function:
```sh
cd /workspaces/nss-dev/nss
grep -rn "function_name" lib/ cmd/ --include='*.c' --include='*.h'
```

For each caller, determine:
- Can the caller pass attacker-controlled input to the vulnerable function?
- Does the caller add any validation or bounds checking that would prevent the bug?
- Is the caller itself reachable from a public API or protocol handler?

### 2b. Trace to entry points

Follow the call chain upward from the vulnerable function to identify the **entry points** — the public APIs or protocol message handlers where untrusted input enters NSS. Common entry points include:

- **TLS handshake messages**: ClientHello, ServerHello, Certificate, CertificateVerify, EncryptedExtensions, NewSessionTicket, etc. Trace through `ssl3_HandleHandshakeMessage` and friends.
- **Certificate parsing**: `CERT_DecodeCertFromPackage`, `SEC_ASN1Decode*`, PKIX chain validation
- **PKCS#7/CMS**: `SEC_PKCS7Decode*`, S/MIME message handling
- **PKCS#12**: `SEC_PKCS12Decode*`
- **Crypto operations**: `PK11_*`, `SGN_*`, `VFY_*`
- **OCSP**: `CERT_CheckOCSPStatus*`

For each entry point that can reach the vulnerable code, note:
1. The function name and file
2. The protocol or API context (e.g., "TLS 1.3 server processing ClientHello extensions")
3. Whether an attacker can trigger this remotely, locally, or only via specific API usage

Use `grep`, `weggli`, or direct code reading as needed. Follow the call chains — don't guess.

### 2c. Protocol and configuration variants

Determine which protocol versions and configurations expose the bug:

- **TLS versions**: TLS 1.0, 1.1, 1.2, 1.3, DTLS 1.0, 1.2, 1.3 — does the vulnerable code path exist in all versions or only specific ones?
- **Role**: Client only, server only, or both?
- **Cipher suites / key exchange**: Is the bug only reachable with specific cipher suites (e.g., RSA key exchange, ECDHE, PSK)?
- **Extensions**: Is the bug in extension handling? Which extensions?
- **Handshake modes**: Full handshake, session resumption, 0-RTT, HelloRetryRequest, post-handshake auth?
- **Certificate types**: RSA, ECDSA, EdDSA? Specific curve or key size?
- **Configuration flags**: Are there NSS configuration options (e.g., `SSL_OptionSet` flags, policy settings) that enable or disable the vulnerable code path?

### 2d. Compile the trigger map

For each distinct triggering path, record:
1. **Entry point**: The function/handler where the attack begins
2. **Call chain**: Key intermediate functions (keep it short — 3-5 functions max)
3. **Trigger condition**: What specific input or state triggers the bug via this path
4. **Attacker position**: Remote (network), local (shared machine), or API-only (must be called programmatically)
5. **Configuration required**: What settings must be active for this path to be reachable
6. **Likelihood**: How likely is this configuration in real deployments? (e.g., "default TLS server config" vs. "requires explicitly enabling deprecated cipher suite")

---

## Phase 3: Firefox Impact Assessment

Determine how this bug affects Firefox specifically. Firefox is the highest-profile NSS consumer and has its own integration layers, configuration, and sandboxing that shape real-world impact.

### 3a. Find Firefox's NSS call sites

Using the NSS entry points identified in Phase 2, search for how Firefox calls into the vulnerable code paths. Use both the local reference checkout and Searchfox:

```sh
# Search the local Firefox checkout for references to the vulnerable NSS function(s)
grep -rn "function_name" /workspaces/nss-dev/reference/repos/firefox/security/ \
     --include='*.cpp' --include='*.h' --include='*.js'

# Search broader Firefox for the same (may find consumers outside security/)
searchfox query "function_name" --repo mozilla-central
```

Key Firefox directories to check:
- `security/manager/ssl/` — PSM (Personal Security Manager): Firefox's main NSS integration layer
- `security/certverifier/` — Certificate verification logic
- `security/nss/` — Build system integration and NSS configuration
- `netwerk/` — Networking stack (TLS socket setup, certificate callbacks)
- `dom/crypto/` — WebCrypto API (if the bug is in crypto primitives)
- `mailnews/mime/` — Thunderbird S/MIME (if the bug is in CMS/PKCS#7)

### 3b. Determine Firefox triggering scenarios

For each Firefox call site that can reach the vulnerable code, determine:
1. **User action or event**: What would a user be doing when this triggers? (browsing to a malicious site, receiving an email, installing an add-on, visiting a site with a malformed certificate)
2. **Content process vs. parent process**: Does the vulnerable code run in a sandboxed content process or the privileged parent process? This dramatically affects exploitability.
   - TLS connections for page loads typically run in the **socket process** (if enabled) or **parent process**
   - Certificate verification may run in the **content process** depending on the path
   - Use `searchfox query "NECKO_SOCKET_PROCESS" --repo mozilla-central` or check `security/manager/ssl/` to determine process boundaries
3. **Sandbox constraints**: If the code runs in a content process, what sandbox level applies? Can the bug escape the sandbox or is the impact contained to a crash?
4. **Firefox configuration**: Does Firefox enable/disable relevant NSS features by default? Check `security/manager/ssl/nsNSSComponent.cpp` for `SSL_OptionSet` calls and default cipher suite configuration.

### 3c. Check for Firefox-specific mitigations

Determine whether Firefox has any additional protections beyond NSS's own:
- **Certificate Transparency enforcement** — may limit certificate-based attack vectors
- **HSTS/HPKP preload** — may prevent downgrade attacks for major sites
- **Safe Browsing / content filtering** — may block some delivery vectors
- **Firefox-specific SSL preferences** — `about:config` settings in `security.ssl.*` that override NSS defaults
- **Process isolation / sandboxing** — Fission, site isolation, sandbox levels

Search for relevant preferences:
```sh
searchfox query "security.ssl" --repo mozilla-central
grep -rn "security.ssl" /workspaces/nss-dev/reference/repos/firefox/modules/libpref/
```

### 3d. Compile Firefox impact summary

Record:
1. **Reachable in Firefox?** Yes/No — and via which scenario(s)
2. **Default Firefox config?** Does Firefox's default configuration expose the vulnerable code path?
3. **Process context**: Which Firefox process(es) run the vulnerable code?
4. **Sandbox effectiveness**: Does the sandbox contain the impact? Would the attacker need a sandbox escape?
5. **Firefox-specific severity adjustment**: Does Firefox's context make the bug more or less severe than the generic NSS assessment? (e.g., a pre-auth remote bug in NSS might only run in a sandboxed content process in Firefox, reducing effective severity)

---

## Phase 4: Thunderbird Impact Assessment

Determine how this bug affects Thunderbird. Thunderbird exercises NSS code paths that browsers rarely touch — particularly S/MIME (CMS/PKCS#7), PKCS#12 certificate import/export, and email-specific TLS configurations. Bugs in these areas may have their highest real-world impact in Thunderbird rather than Firefox.

### 4a. Find Thunderbird's NSS call sites

Using the NSS entry points identified in Phase 2, search for how Thunderbird calls into the vulnerable code paths:

```sh
# Search the local Thunderbird checkout
grep -rn "function_name" /workspaces/nss-dev/reference/repos/thunderbird-desktop/ \
     --include='*.cpp' --include='*.h' --include='*.js' --include='*.jsm'

# Search Searchfox for Thunderbird-specific code (comm-central)
searchfox query "function_name" --repo comm-central
```

Key Thunderbird directories to check:
- `mailnews/mime/` — S/MIME message decoding and verification
- `mailnews/compose/` — S/MIME signing and encryption during message composition
- `mailnews/imap/`, `mailnews/local/`, `mailnews/news/` — TLS for mail protocol connections (IMAP, POP3, SMTP, NNTP)
- `mail/components/` — Certificate and account security management UI
- `mail/extensions/smime/` — S/MIME extension code and UI

Note: Thunderbird builds on top of Firefox (gecko), so Firefox's `security/manager/ssl/` and `security/certverifier/` code is also reachable from Thunderbird. If Phase 3 already found the bug reachable via those shared paths, note that Thunderbird inherits that exposure and focus this phase on Thunderbird-specific paths.

### 4b. Determine Thunderbird triggering scenarios

For each Thunderbird call site that can reach the vulnerable code, determine:
1. **User action or event**: What would a user be doing? (receiving an S/MIME-signed email, importing a PKCS#12 certificate, connecting to a mail server with a malformed certificate, opening an encrypted attachment)
2. **Automatic vs. manual**: Does the vulnerable path trigger automatically (e.g., on message display or background mail fetch) or only via explicit user action (e.g., importing a certificate file)?
3. **Attack delivery**: How would an attacker deliver the malicious input? (send an email, compromise a mail server's TLS certificate, supply a crafted .p12 file)
4. **Process context**: Thunderbird's process model differs from Firefox. Determine whether the vulnerable code runs in the main process or a content process, and what sandbox protections apply.

### 4c. Assess S/MIME and email-specific exposure

If the bug is in certificate, CMS/PKCS#7, PKCS#12, or ASN.1 parsing code, evaluate the email-specific attack surface:
- **S/MIME message processing**: Can the bug be triggered by a received S/MIME signed or encrypted email? This is high-impact because emails can arrive unsolicited.
- **Certificate import**: Can the bug be triggered via a crafted PKCS#12 file? This requires user interaction (importing the file) but is a common operation.
- **Mail server TLS**: Can a malicious or compromised mail server trigger the bug during TLS negotiation? This affects every mail connection.
- **Address book / LDAP**: Does Thunderbird fetch certificates via LDAP for S/MIME? If so, can the bug be triggered through that path?

### 4d. Compile Thunderbird impact summary

Record:
1. **Reachable in Thunderbird?** Yes/No — and via which scenario(s)
2. **Thunderbird-specific paths?** Are there triggering paths unique to Thunderbird (S/MIME, PKCS#12 import, mail server TLS) beyond what Firefox shares?
3. **Automatic trigger?** Can the bug fire without user interaction (e.g., on email receipt/display)?
4. **Attack delivery complexity**: How hard is it for an attacker to deliver the malicious input? (send an email = easy; compromise a mail server = hard)
5. **Thunderbird-specific severity adjustment**: Does Thunderbird's context change severity? (e.g., a CMS parsing bug that is only reachable via S/MIME may be unexploitable in Firefox but critical in Thunderbird)

---

## Phase 5: Assess Exploitability

### 5a. Attack surface classification

Based on Phases 2, 3, and 4, classify the overall attack surface:
- **Remote, pre-auth, default config**: The bug can be triggered by a network attacker against a default NSS deployment. This is the most critical category.
- **Remote, pre-auth, non-default config**: Requires specific configuration but no authentication.
- **Remote, post-auth**: The attacker must first establish a valid TLS session or present a valid certificate.
- **Local / API-only**: The attacker must have local access or control an application that calls NSS APIs directly.
- **Not practically exploitable**: The code path is dead, unreachable in practice, or requires conditions that cannot occur.

### 5b. Exploitability factors

Evaluate factors that affect real-world exploitability:
- **Reliability**: Can the bug be triggered deterministically, or does it depend on heap layout, timing, or other non-deterministic factors?
- **Detectability**: Would triggering the bug produce observable side effects (alerts, connection failures, log entries) before exploitation succeeds?
- **Mitigations**: What platform mitigations apply? (ASLR, stack canaries, CFI, heap hardening, sandboxing in browsers)
- **Complexity**: How much reverse engineering, heap grooming, or protocol manipulation is needed?

### 5c. Impact assessment

Assign an overall severity:
- **Critical**: Remote code execution or key extraction, pre-auth, default config
- **High**: Remote crash/DoS pre-auth default config, or code execution requiring non-default config
- **Medium**: Information disclosure, DoS requiring non-default config, or local exploitation
- **Low**: Requires unlikely configurations, minimal impact, or is mitigated by standard platform defenses
- **Informational**: Code quality issue, theoretical concern, or dead code path

Justify the rating in 2-3 sentences.

---

## Phase 6: Write Triage Report

**Record the end time:**
```sh
date -u +%s
```
Calculate elapsed wall-clock time from the start time recorded before Phase 0.

Create the reports directory if needed. Use `$BUG_DIR` resolved in Phase 0b:
```sh
REPORTS_DIR=$BUG_DIR/reports
mkdir -p "$REPORTS_DIR"
```

Write the report to `$REPORTS_DIR/triage-report.md`:

```
# NSS Bug <BUGNUM> — Triage Report

**Severity**: [Critical / High / Medium / Low / Informational]
**Attack surface**: [Remote pre-auth default / Remote pre-auth non-default / Remote post-auth / Local-API only / Not exploitable]
**Defect class**: [buffer overread / overwrite / use-after-free / etc.]

## Bug Summary

[2-3 sentence description of the bug: what the defect is, where it lives, and what triggers it.]

## Vulnerable Code

**Function**: `function_name` in `lib/path/file.c`
**Defect site**: [file:line — describe what goes wrong]
**Data flow**: [1-2 sentences: how attacker input reaches the defect site]

## Consequence

**Immediate effect**: [crash / overread of N bytes / overwrite of N bytes / etc.]
**Worst realistic outcome**: [DoS / info disclosure / code execution / auth bypass — with brief justification]
**Attacker control**: [What does the attacker control? Length, content, type of corrupted data?]

## Triggering Code Paths

### Path 1: [short description, e.g., "TLS 1.3 server ClientHello"]

- **Entry point**: `function_name` (`file.c`)
- **Call chain**: `entry` → `intermediate1` → `intermediate2` → `vulnerable_function`
- **Trigger**: [what specific input triggers the bug via this path]
- **Attacker position**: [remote / local / API]
- **Config required**: [default / specific settings needed]
- **Deployment likelihood**: [common / uncommon / rare]

### Path 2: [repeat for each distinct path]

[...]

## Configuration Exposure

| Setting / Mode | Exposes bug? | Notes |
|---|---|---|
| TLS 1.3 server (default) | Yes / No | |
| TLS 1.2 server | Yes / No | |
| TLS 1.3 client | Yes / No | |
| TLS 1.2 client | Yes / No | |
| DTLS | Yes / No | |
| [other relevant modes] | Yes / No | |

## Firefox Impact

**Reachable in Firefox?**: [Yes / No]
**Triggering scenario**: [e.g., "Browsing to a malicious site that sends a crafted certificate"]
**Firefox call path**: `Firefox function` → ... → `NSS vulnerable function`
**Process context**: [content process / parent process / socket process]
**Sandbox contains impact?**: [Yes — crash only / No — parent process / Partial — requires sandbox escape for full impact]
**Default Firefox config exposes bug?**: [Yes / No — and why]
**Firefox-specific mitigations**: [CT, process isolation, sandbox level, etc.]
**Firefox severity adjustment**: [Same as generic / Higher because ... / Lower because ...]

## Thunderbird Impact

**Reachable in Thunderbird?**: [Yes / No]
**Thunderbird-specific paths?**: [Yes — S/MIME, PKCS#12 import, etc. / No — shared gecko paths only]
**Triggering scenario**: [e.g., "Receiving an S/MIME signed email with a crafted certificate"]
**Thunderbird call path**: `Thunderbird function` → ... → `NSS vulnerable function`
**Automatic trigger?**: [Yes — fires on email receipt/display / No — requires user action]
**Attack delivery**: [send an email / compromise mail server / supply crafted file / etc.]
**Process context**: [main process / content process]
**Thunderbird severity adjustment**: [Same as generic / Higher because ... / Lower because ...]

## Exploitability Assessment

**Reliability**: [deterministic / probabilistic / requires heap grooming / etc.]
**Complexity**: [low — single malformed message / medium / high — requires multi-step interaction]
**Mitigations**: [ASLR, sandboxing, etc. — and whether they are effective here]
**Detectability**: [silent / causes observable errors / logged]

## Timing

| Metric | Value |
|---|---|
| Wall time | [Xm Ys] |
```

**Update the bug log.** Append a one-line verdict to `$BUG_DIR/LOG.md`:
```sh
NOW=$(date -u +"%Y-%m-%d %H:%M UTC")
LOG_FILE="$BUG_DIR/LOG.md"
if [ ! -f "$LOG_FILE" ]; then
  printf "# Log: Bug %s\n\n" "$BUGNUM" > "$LOG_FILE"
fi
# Verdict: terse one-line summary — severity, attack surface, defect class
echo "- $NOW — /nss-triage: <severity>, <attack surface>, <defect class>" >> "$LOG_FILE"
```

After writing the report, print:
1. The path to the saved report file.
2. A brief (3-4 sentence) summary of the key findings: severity, worst-case consequence, most dangerous triggering path, and whether the bug is reachable in default configurations.
