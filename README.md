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
