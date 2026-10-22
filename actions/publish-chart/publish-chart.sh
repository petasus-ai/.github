#!/bin/sh
# Publish a chart to the Petasus chart repository (petasus-ai/edgestack-helm).
#
#   publish-chart.sh <chart directory> dev
#   publish-chart.sh <chart directory> stable <version>     e.g. 1.2.0 (no leading v)
#
# dev:    version 0.0.0-dev, appVersion dev, pushed to the dev branch, replacing the
#         previous dev build.
# stable: the given version, appVersion v<version>, pushed to master. A version that is
#         already published is never replaced: the same contents (a rerun) are skipped,
#         other contents fail.
# Both record the commit the chart was built from in annotations.petasus.io/revision.
#
# Environment:
#   CHART_REPO   where to push (default ssh://git@ssh.github.com/petasus-ai/edgestack-helm.git;
#                the caller sets GIT_SSH_COMMAND, or an https URL and CHART_REPO_AUTH)
#   CHART_REPO_AUTH   optional "Authorization: ..." header for an https CHART_REPO
#   REVISION     the commit to record (default: git rev-parse HEAD)
#   PUBLISH_CHART_REPLACE=1   stable only, while a component still republishes one version
#                (3.5.0) from its main branch: replace it instead of failing. The chart
#                repository allows that only for the charts it lists as unguarded.
# Needs helm, git, tar and diff.
set -eu

chart=$1
channel=$2
case "$channel" in
  dev) version=0.0.0-dev; app_version=dev; branch=dev ;;
  stable)
    version=${3:?publish-chart.sh: stable needs a version}
    version=${version#v}
    app_version=v$version
    branch=master ;;
  *) echo "publish-chart.sh: channel is dev or stable, not $channel" >&2; exit 2 ;;
esac
repo=${CHART_REPO:-ssh://git@ssh.github.com/petasus-ai/edgestack-helm.git}
revision=${REVISION:-$(git rev-parse HEAD)}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# git with the https credential, when there is one; it is never written to a config file
remote_git() {
  if [ -n "${CHART_REPO_AUTH:-}" ]; then
    git -c "http.extraheader=$CHART_REPO_AUTH" "$@"
  else
    git "$@"
  fi
}

# A copy of the chart with the revision annotation (Chart.yaml keeps one annotations map).
cp -R "$chart" "$work/chart"
awk -v rev="$revision" '
  /^annotations:[[:space:]]*$/ { print; print "  petasus.io/revision: \"" rev "\""; done = 1; skip = 1; next }
  skip && /^  petasus\.io\/revision:/ { next }
  /^[^[:space:]#]/ { skip = 0 }
  { print }
  END { if (!done) { print "annotations:"; print "  petasus.io/revision: \"" rev "\"" } }
' "$chart/Chart.yaml" > "$work/chart/Chart.yaml"
name=$(sed -n 's/^name:[[:space:]]*["'"'"']\{0,1\}\([^"'"'"'[:space:]]*\).*/\1/p' "$work/chart/Chart.yaml" | head -n 1)
if grep -q '^dependencies:' "$work/chart/Chart.yaml"; then
  helm dependency build "$work/chart"
fi
helm lint "$work/chart" >/dev/null
mkdir -p "$work/dist"
helm package "$work/chart" --version "$version" --app-version "$app_version" -d "$work/dist" >/dev/null
package="$name-$version.tgz"
test -f "$work/dist/$package" || { echo "publish-chart.sh: helm made no $package" >&2; exit 1; }

remote_git clone -q --depth 1 --branch "$branch" "$repo" "$work/repo"
if [ "$channel" = stable ] && [ -e "$work/repo/$package" ]; then
  mkdir "$work/published" "$work/built"
  tar -xzf "$work/repo/$package" -C "$work/published"
  tar -xzf "$work/dist/$package" -C "$work/built"
  if diff -r "$work/published" "$work/built" >/dev/null; then
    echo "$package is already published with the same contents"
    exit 0
  fi
  if [ "${PUBLISH_CHART_REPLACE:-0}" != 1 ]; then
    diff -r "$work/published" "$work/built" || true
    echo "publish-chart.sh: $package is already published with other contents; publish a new version" >&2
    exit 1
  fi
  echo "replacing the published $package (PUBLISH_CHART_REPLACE)"
fi

cp "$work/dist/$package" "$work/repo/"
cd "$work/repo"
git add "$package"
if git diff --cached --quiet; then
  echo "$package is unchanged"
  exit 0
fi
git -c user.name=edgestack-bot -c user.email=edgestack-bot@users.noreply.github.com \
  commit -q -m "$name $version ($revision)"
# The repository's workflow commits the index after every chart and other charts are
# published at the same time, so the branch may have moved.
i=0
while :; do
  remote_git pull -q --rebase origin "$branch" && remote_git push -q origin "HEAD:$branch" && break
  i=$((i + 1))
  [ "$i" -lt 5 ] || { echo "publish-chart.sh: could not push $package" >&2; exit 1; }
  sleep $((i * 5))
done
echo "published $package to $branch"
