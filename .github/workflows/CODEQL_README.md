# CodeQL Security Analysis for Cosmopolitan

This directory contains GitHub Actions workflows for automated security scanning using CodeQL.

## Active Workflows

### `codeql.yml` - Standard Analysis (Enabled)
- **Runs on:** PRs, pushes to master, weekly on Mondays
- **Duration:** ~10-15 minutes
- **Scope:** Core C library, APE loader, Lua integration
- **Excludes:** third_party, test code
- **Best for:** Continuous security monitoring

## Optional Workflows

### `codeql-comprehensive.yml.example` - Deep Analysis (Disabled by default)
- **Runs on:** Monthly + manual trigger
- **Duration:** ~45-90 minutes
- **Scope:** Everything except third_party
- **Includes:** Test code, both architectures (x86_64 + aarch64)
- **Query suite:** security-and-quality (more thorough)
- **To enable:** Rename to `codeql-comprehensive.yml`

## What CodeQL Finds

CodeQL detects security vulnerabilities and coding errors:

### Memory Safety Issues
- Buffer overflows / out-of-bounds access
- Use-after-free
- Double-free
- Memory leaks
- Null pointer dereferences

### Security Vulnerabilities
- Command injection
- SQL injection (if database code exists)
- Path traversal
- Format string vulnerabilities
- Integer overflows leading to security issues
- Uncontrolled recursion
- Missing input validation

### Concurrency Issues
- Data races
- Deadlocks
- Missing synchronization

### Code Quality
- Dead code
- Unused variables
- Incorrect error handling
- Resource leaks (file descriptors, sockets)

## Viewing Results

### In GitHub UI
1. Go to **Security** tab → **Code scanning**
2. View alerts grouped by severity: Critical, High, Medium, Low
3. Click any alert to see:
   - Source code location
   - Data flow visualization
   - Remediation advice

### In Pull Requests
- CodeQL comments directly on PR diffs
- Shows new issues introduced by the PR
- Prevents merge if critical issues found (optional)

## Customizing Analysis

### Include/Exclude Paths

Edit the `config:` section in the workflow:

```yaml
config: |
  paths-ignore:
    - third_party/**
    - test/**
  paths:
    - libc/**
    - tool/**
```

### Query Suites

Change the query suite for different coverage levels:

```yaml
# Default (fastest, security-focused)
# queries: (omit this line)

# Security + quality checks (recommended)
queries: security-and-quality

# Everything (slowest, most thorough)
queries: security-extended
```

### Custom Queries

Add your own CodeQL queries:

1. Create `.github/codeql/custom-queries.ql`
2. Reference in workflow:
   ```yaml
   queries:
     - uses: ./custom-queries.ql
   ```

## Performance Tips

### Faster Builds
- Build only what's needed for analysis
- Use `m=x86_64` (single architecture)
- Exclude test code if not security-critical

### Slower but More Thorough
- Add `queries: security-and-quality`
- Build both architectures
- Include test code
- Build all tool targets

## Disabling CodeQL

If you want to temporarily disable:

1. **For PRs only:** Add `paths-ignore: '**'` to the workflow
2. **Completely:** Delete or rename `codeql.yml` to `codeql.yml.disabled`
3. **For specific files:** Add to `paths-ignore` in config

## Common Issues

### Build Timeout
If builds take >60 minutes, CodeQL times out:
- Solution: Reduce build targets or increase `timeout-minutes`

### Too Many Alerts
First run might show hundreds of findings:
- **Normal!** Existing codebases often have legacy issues
- Triage and dismiss false positives in Security tab
- Focus on "High" and "Critical" severity first

### False Positives
CodeQL is conservative and may flag safe code:
- Dismiss in GitHub UI with explanation
- Dismissed alerts won't reappear

## Resources

- [CodeQL Documentation](https://codeql.github.com/docs/)
- [C/C++ Query Reference](https://codeql.github.com/codeql-query-help/cpp/)
- [Writing Custom Queries](https://codeql.github.com/docs/writing-codeql-queries/)
- [GitHub Code Scanning](https://docs.github.com/en/code-security/code-scanning)
