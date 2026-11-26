# Releasing

One-time setup

The CurseForge project exists (ID 1833344) and the ID is already in `PeerReview.toc`. Two steps remain:

1. On CurseForge, create an API token (account settings, "API tokens").
2. In the GitHub repository: Settings, Secrets and variables, Actions, "New repository secret". Name `CF_API_KEY`, value the token.

Every release after that

1. Change `## Version:` in `PeerReview.toc` (for example to `0.8.1`).
2. Add a section for that version at the top of `CHANGELOG.md`.
3. Commit, then tag and push:

       git tag v0.8.1
       git push origin main --tags

The tag starts the Release workflow: it runs the tests, builds `PeerReview-v0.8.1-forever.zip`, attaches it to a GitHub release and uploads it to CurseForge. A tag containing `-beta` or `-alpha` is uploaded as a beta or alpha file.

CurseForge still reviews each uploaded file before the app shows it.
