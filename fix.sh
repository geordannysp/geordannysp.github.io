
bash <<'ACADEMIC_PAGES_SETUP'
set -Eeuo pipefail

PROJECT="$HOME/projects/Geordanny1.github.io"
REMOTE="git@github.com:geordannysp/geordannysp.github.io.git"
BRANCH="update-academicpages"

cd "$PROJECT"

echo "== Checking repository =="

test "$(git branch --show-current)" = "$BRANCH" || {
  echo "ERROR: Switch to $BRANCH first."
  exit 1
}

test -z "$(git status --porcelain)" || {
  echo "ERROR: You have uncommitted changes. Commit or stash them first."
  exit 1
}

git show-ref --verify --quiet refs/heads/master || {
  echo "ERROR: Local master branch not found."
  exit 1
}

git merge-base --is-ancestor master HEAD || {
  echo "ERROR: master cannot be fast-forwarded to this branch."
  exit 1
}

test -f Gemfile.lock || {
  echo "ERROR: Gemfile.lock is missing."
  exit 1
}

if test -f CNAME; then
  echo "ERROR: CNAME exists. Check your custom-domain settings first."
  exit 1
fi

echo "== Checking new GitHub repository =="

git ls-remote "$REMOTE" HEAD >/dev/null || {
  echo "ERROR: Cannot access $REMOTE"
  exit 1
}

REMOTE_MAIN=$(
  git ls-remote "$REMOTE" refs/heads/main | cut -f1
)

REMOTE_MASTER=$(
  git ls-remote "$REMOTE" refs/heads/master | cut -f1
)

if test -n "$REMOTE_MAIN"; then
  echo "ERROR: New repository already has a main branch."
  echo "Stopping to avoid creating a conflicting publishing branch."
  exit 1
fi

LOCAL_MASTER=$(git rev-parse master)

if test -n "$REMOTE_MASTER" &&
   test "$REMOTE_MASTER" != "$LOCAL_MASTER"; then
  echo "ERROR: Remote master differs from local master."
  echo "Stopping to avoid overwriting existing history."
  exit 1
fi

echo "== Creating backup =="

git branch "backup-before-publish-$(date +%Y%m%d-%H%M%S)"

echo "== Updating AcademicPages configuration =="

python3 <<'PYTHON'
from pathlib import Path
import re

path = Path("_config.yml")
lines = path.read_text().splitlines(keepends=True)

settings = {
    "url": "https://geordannysp.github.io",
    "baseurl": "",
    "repository": "geordannysp/geordannysp.github.io",
}

for key, value in settings.items():
    pattern = re.compile(rf"^{re.escape(key)}\s*:")
    matches = [
        i for i, line in enumerate(lines)
        if pattern.match(line)
    ]

    if len(matches) > 1:
        raise SystemExit(f"Duplicate config key: {key}")

    replacement = f'{key}: "{value}"\n'

    if matches:
        lines[matches[0]] = replacement
    else:
        lines.append(replacement)

path.write_text("".join(lines))

publication = Path(
    "_publications/2025-06-08-paper-title-number-5.md"
)

if publication.exists():
    content = publication.read_text()
    old = "permalink: /publication/2024-02-17-paper-title-number-4"
    new = "permalink: /publication/2025-06-08-paper-title-number-5"

    if old in content:
        publication.write_text(content.replace(old, new, 1))
PYTHON

echo "== Configuring GitHub Pages deployment =="

mkdir -p .github/workflows

cat > .github/workflows/jekyll.yml <<'YAML'
name: Deploy AcademicPages

on:
  push:
    branches:
      - master
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: github-pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-24.04

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '4.0'
          bundler-cache: true

      - name: Configure GitHub Pages
        id: pages
        uses: actions/configure-pages@v5

      - name: Build Jekyll website
        env:
          JEKYLL_ENV: production
        run: |
          bundle exec jekyll build --baseurl "${{ steps.pages.outputs.base_path }}"

      - name: Upload website
        uses: actions/upload-pages-artifact@v3
        with:
          path: _site

  deploy:
    runs-on: ubuntu-24.04
    needs: build

    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    steps:
      - name: Deploy website
        id: deployment
        uses: actions/deploy-pages@v4
YAML

echo "== Verifying Ruby dependencies =="

bundle check
bundle exec jekyll --version

echo "== Testing production build =="

BUILD_LOG=$(mktemp)
trap 'rm -f "$BUILD_LOG"' EXIT

if ! JEKYLL_ENV=production bundle exec jekyll build \
    >"$BUILD_LOG" 2>&1; then
  tail -n 60 "$BUILD_LOG"
  echo "ERROR: Jekyll build failed. Nothing was pushed."
  exit 1
fi

if grep -q "Conflict:" "$BUILD_LOG"; then
  grep -A 6 "Conflict:" "$BUILD_LOG"
  echo "ERROR: Jekyll output conflicts remain. Nothing was pushed."
  exit 1
fi

echo "Production build succeeded."

echo "== Committing changes =="

git add _config.yml .github/workflows/jekyll.yml

if test -f _publications/2025-06-08-paper-title-number-5.md; then
  git add _publications/2025-06-08-paper-title-number-5.md
fi

git add -f Gemfile.lock

git diff --cached --check

if ! git diff --cached --quiet; then
  git commit -m "Configure AcademicPages for new GitHub Pages repository"
fi

echo "== Updating Git remote =="

git remote set-url origin "$REMOTE"

echo "== Publishing to master =="

git switch master
git merge --ff-only "$BRANCH"
git push -u origin master

echo ""
echo "=========================================="
echo "Push completed successfully!"
echo "Website: https://geordannysp.github.io/"
echo "Check the Actions tab for deployment status."
echo "=========================================="
ACADEMIC_PAGES_SETUP

