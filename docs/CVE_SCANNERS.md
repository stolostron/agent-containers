# CVE Scanner Runtime

The image preinstalls pinned versions of `pip-audit` and `govulncheck`. The
executables are installed in `/usr/local/bin` and are usable by both `node` and
`sandbox` without installing scanner dependencies during an audit.

Go runtime caching uses each user's persistent default paths under their home
directory. The image does not set a shared `GOPATH` or rely on `/tmp` for
runtime scans, so uncached `govulncheck` module downloads remain writable for
both `node` and `sandbox` after image setup.

## Native Commands

Run audits against the repository being assessed, not the image's global
Python environment:

```bash
pip-audit -r requirements.txt
pip-audit -r requirements.txt --strict
govulncheck -mode=source ./...
npm audit --package-lock-only
pnpm audit --lockfile-only
yarn npm audit --all
```

Use the manifest or lockfile that belongs to the project. Do not run package
installation solely to perform an audit, and do not mutate manifests or
lockfiles unless remediation was explicitly requested. For pnpm and Yarn,
Corepack may select the package-manager version declared by the project. Yarn
Classic projects should use their supported Yarn audit command; Yarn Berry
projects should use `yarn npm audit --all`.

## Results and Failures

An audit record must include the ecosystem, exact command, scanner version,
target manifest/lockfile or Go module, UTC timestamp, advisory source, whether
the source was live or cached, outcome, and findings. Outcomes are `clean`,
`findings`, `partial`, or `infrastructure-failure`.

DNS failures, authentication failures, rate limits, unavailable advisory
services, and missing scanner executables are infrastructure failures. They
must not be reported as clean scans. A cached result is acceptable only when
the scanner explicitly supports that mode and the cache freshness requirement
has been checked and recorded.

## Advisory Data and Network Access

Scanner binary updates and advisory refreshes are separate operations. A new
scanner image is not required for each newly published advisory. Normal scans
use live services and require outbound access to:

- PyPI and the Python advisory service used by `pip-audit`.
- Go's vulnerability database services and module proxy used by `govulncheck`.
- The npm registry for npm and pnpm audits.
- The configured Yarn/npm registry for Yarn audits.

This image does not provide a managed offline advisory cache. Offline operation
must therefore be treated as incomplete unless the calling audit workflow
supplies and validates a supported, explicitly fresh cache.
