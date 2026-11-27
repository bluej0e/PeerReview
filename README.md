# Social Score

Player ratings for World of Warcraft: Forever. After a group, give each player a thumbs up, neutral or thumbs down. Ratings are shared directly between players who run the addon and shown in tooltips as "87% would group again".

- A vote is only accepted from the player who cast it, so nobody can vote in someone else's name.
- Rage votes are ignored, scores need three voters, votes expire after 180 days.
- No server, no account, no companion app.

Install from CurseForge, or copy this folder to `World of Warcraft/_forever_/Interface/AddOns/PeerReview`.

Commands: `/score`, `/score list`, `/score me`, `/score rate`, `/score pending`, `/score preview`, `/score feedback`, `/score Name`. Formerly Peer Review; `/peer` still works.

## Development

Logic tests run against a stubbed game client:

    pip install lupa
    python tests/run.py

See `RELEASING.md` for how a release reaches CurseForge.
