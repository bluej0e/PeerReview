# Releasing

One-time setup

The CurseForge project exists (ID 1833344) and the ID is already in `PeerReview.toc`. Two steps remain:

1. On CurseForge, create an API token (account settings, "API tokens").
2. In the GitHub repository: Settings, Secrets and variables, Actions, "New repository secret". Name `CF_API_KEY`, value the token.

Every release after that

1. Change `## Version:` in `PeerReview.toc` (for example to `0.8.2`) and the fallback `ns.VERSION` in `Core.lua`.
2. Add a section for that version at the top of `CHANGELOG.md`.
3. Set `release-type` to `beta` or `release`.
4. Commit and push to `main`.

The push starts the Release workflow: it runs the tests, tags the commit (`v0.8.2-beta` or `v0.8.2`), builds the zip, attaches it to a GitHub release and uploads it to CurseForge. If the tag already exists nothing is released, so pushes that do not change the version are safe.

To promote a tested beta to a full release without code changes, change `release-type` to `release` and push.

CurseForge still reviews each uploaded file before the app shows it.
