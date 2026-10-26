# petasus-ai/.github

Shared CI pieces for Petasus repositories.

## actions/publish-chart

Publishes a Helm chart to [petasus-ai/edgestack-helm](https://github.com/petasus-ai/edgestack-helm):

- `channel: dev` — version `0.0.0-dev` on the `dev` branch, replaced by every build of a
  component's main branch.
- `channel: stable` — a release version on `master`, which never changes: a rerun with
  the same contents is skipped, other contents fail.

```yaml
- uses: petasus-ai/.github/actions/publish-chart@<commit>
  with:
    chart: charts/my-component
    channel: dev                 # or stable, with version: ${{ github.ref_name }}
    token: ${{ secrets.MY_TOKEN }}
```

GitLab jobs run the same `publish-chart.sh`, fetched at a pinned commit, through the
template in `PETASUS/ci-templates`.

## actions/guard-release-tag

Fails unless the tag is `vX.Y.Z`, `vX.Y.Z-rc.N` or, for a fork of an upstream project,
`vX.Y.Z-petasus.N` (on top of upstream `vX.Y.Z`), and its commit is on the `release-X.Y`
branch, the same rule as the release template in `PETASUS/ci-templates`. Run it before
publishing anything from a tag:

```yaml
on:
  push:
    tags: ["v*"]
steps:
  - uses: actions/checkout@v4
  - uses: petasus-ai/.github/actions/guard-release-tag@<commit>
  - uses: petasus-ai/.github/actions/publish-chart@<commit>
    with:
      chart: .
      channel: stable
      version: ${{ github.ref_name }}
      token: ${{ secrets.MY_TOKEN }}
```

## .github/workflows/image.yml

A reusable workflow for a repository that ships one container image: the default branch
publishes `:dev`, a release tag `vX.Y.Z` on `release-X.Y` (checked by
`guard-release-tag`) publishes `:vX.Y.Z` once and `latest` when it is the newest final
release, and other branches and pull requests only build. Each architecture builds on
its own runner and the images carry the OCI revision/version/source labels.

```yaml
on:
  push:
    branches: [main]
    tags: ["v*"]
  pull_request: {}
jobs:
  image:
    uses: petasus-ai/.github/.github/workflows/image.yml@<commit>
    with:
      image: quay.io/edgestack/my-component
    secrets:
      registry-password: ${{ secrets.QUAY_CI_BOT_SECRET }}
```
