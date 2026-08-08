# GitHub Environment `production` — UI setup

Used by the `release` job in `.github/workflows/release.yml`.

## Create

1. Repo → **Settings** → **Environments** → **New environment**
2. Name: `production`
3. Configure protection rules (below) → **Save protection rules**

## Protection rules

### Required reviewers

- Enable **Required reviewers**
- Add: `sauravrana646` (or your release approver)
- **Prevent self-review:** leave **unchecked** if you are the sole maintainer

### Wait timer

- Optional. Use `0` unless you want a deliberate delay before signing/publishing.

### Deployment branches and tags

- Select **Selected branches and tags**
- **Add deployment branch or tag rule** → type **Tag** → pattern `v*`
- Do not allow all branches

This matches the workflow trigger `on.push.tags: ['v*.*.*']` and blocks accidental use of the environment from feature branches.

## Environment variables

On Environment `production` → **Environment variables** → Add:

| Name | Value |
|------|--------|
| `INFISICAL_IDENTITY_ID` | `b0d5c6ed-5178-416d-80d2-cec4ee521424` |
| `INFISICAL_ENV_SLUG` | `prod` |

Prefer these on the environment (not repo-wide) so only the gated release job sees them via `${{ vars.* }}`.

## Runtime behavior

1. Someone with tag permission pushes `vX.Y.Z`
2. `quality-gate` runs
3. `release` job enters **Waiting** for `production` environment approval
4. Reviewer approves in the Actions run UI
5. Job continues: GHCR push → Infisical → cosign → provenance → GitHub Release
