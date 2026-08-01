# discourse-arcade

An arcade of self-hosted HTML5 games with per-game leaderboards, tied to real
forum accounts.

- `/arcade` lists the games, your best score per game, and who holds the record.
- `/arcade/g/:slug` is the game page: the game itself plus the top 10.

## Setup

```bash
bin/rails db:migrate
bin/rake arcade:seed
```

`arcade:seed` is idempotent. Re-run it after changing the catalogue in
`lib/tasks/arcade.rake`; it updates metadata and leaves scores alone.

## The games

| Slug | Score | Controls |
| --- | --- | --- |
| `2048` | points | swipe, arrows, WASD |
| `snake` | points | swipe, arrows, WASD |
| `breakout` | points | drag anywhere, arrows |
| `penalty` | goals | drag from the ball to aim and shoot |
| `keepie` | touches | tap the ball |
| `dribble` | metres | slide to steer, arrows |
| `holdtheline` | points | slide to move, arrows; fire is automatic |

All seven are built for a square frame.

## Adding a game

1. Drop the game's files in `public/games/<name>/`. Everything must be local:
   no CDN scripts, no external requests.
2. Make the game speak the two-message contract below.
3. Add an entry to `ARCADE_GAMES` in `lib/tasks/arcade.rake` and re-run
   `bin/rake arcade:seed`.
4. Add a 16:9 thumbnail to `public/images/thumbs/`. Leave its background
   transparent and use mid-tone colours, so it reads on light and dark themes.
5. Add the game to `spec/system/games_spec.rb`. That spec drives every game to
   game over in a real browser and checks it reports exactly one score.

### The shared shell (optional)

`public/games/_shared/arcade.css` and `arcade.js` carry the parts every game we
write needs anyway: theme colours, the score bar, a square stage, a canvas
sized for the device pixel ratio, swipe/key/drag/aim/tap input, a fixed-step
loop, and `Arcade.submit()`. Every game except `2048` uses it.

It is a convenience, not part of the contract. A third-party game only has to
post the two messages. `2048` was written before the shared shell and still has
its own markup and CSS, which is why `games_spec.rb` takes a stage selector per
game.

### Test hooks

Three games expose a small read-only object so a spec can check the thing that
"it ends and reports a score" cannot: `window.Game2048.collapse` for the merge
rules, `window.Keepie.state()` to tap the ball accurately, and
`window.Dribble.buildRow` to prove every row leaves a passable gap.

These read state or generate a row; none of them set a score. A player already
has the whole game in front of them in view-source, and scores are validated
server side, so the hooks hand nobody anything. Do not add a hook that mutates
game state.

### The contract

The game runs inside an iframe with `sandbox="allow-scripts"`, so it has an
opaque origin and cannot reach the forum page, its cookies, or `localStorage`.
It talks to the host with exactly two messages:

```js
// once, when the game is playable
parent.postMessage({ type: "arcade:ready" }, "*");

// once, when the run is over
parent.postMessage({ type: "arcade:score", score: 1234 }, "*");
```

`score` must be a whole number. The host ignores any second score for the same
run, so a game must not offer its own restart button. One run is one score, and
a replay goes through the host so the server can issue a fresh token.

The host passes the forum's colour scheme in the query string (`bg`, `fg`,
`accent`, `muted`, `low`) so a game can match the active theme. Validate those
values before using them, as `twentyfortyeight/game.js` does.

## How scores are trusted

A browser game cannot be trusted to report an honest score, so the defences are
deliberately cheap and layered:

- **Run tokens.** The server issues a one-time token when a game starts. A
  score without a valid, unredeemed, unexpired token of your own is rejected.
  A unique index on `arcade_scores.arcade_run_id` enforces one score per run at
  the database level.
- **Server-measured time.** Elapsed time comes from the server clock, not the
  browser. A run shorter than the game's `min_run_seconds` is rejected.
- **Plausibility ceiling.** Scores above the game's `max_plausible_score` are
  rejected outright.
- **Rate limiting.** `arcade_max_runs_per_hour` caps how many runs one account
  can start.
- **Moderation.** Staff see a remove button on every leaderboard row. Removal is
  a soft reject, so the row stays in the table with a reason and a moderator id.

This stops casual tampering. It is not proof. Replay verification, where the
game sends its seed and inputs and the server replays the run, is the next step
if a game ever needs a real guarantee, and it is only practical for
deterministic games.

Arcade scores are deliberately **not** connected to the Bookie wallet. As soon
as cheating pays out coins, the incentive to cheat gets a lot stronger.

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| `arcade_enabled` | on | Master switch |
| `arcade_max_runs_per_hour` | 60 | Runs one account may start per hour |
| `arcade_run_token_ttl_minutes` | 180 | How long a run stays redeemable |
| `arcade_leaderboard_size` | 10 | Rows on a game leaderboard |

## Discourse version notes

Written against 3.2-era plugin conventions, and verified working on
`v2026.8.0-latest`: `.hbs` route templates and colocated component templates
under `assets/javascripts` are still compiled automatically, and classic
`@ember/component`, `*-route-map.js`, plugin `controllers/`, `{{eq}}`,
`inject as service`, `ajax` and `dialog.yesNoConfirm` all still resolve.

Two deliberate choices come out of that:

- Icons use `{{fa-icon "…"}}` rather than `{{d-icon}}`. Current Discourse
  has no ambient `d-icon` helper, only an importable one for `.gjs`, and an
  unresolved helper in a classic template takes the whole page down rather than
  just dropping the glyph. `fa-icon` exists in both old and current Discourse
  and renders the same sprite with the same `d-icon` CSS classes. It logs a
  deprecation warning in the console, which is the price of one file working
  across both.
- The frontend is not `.gjs`. Discourse's own plugins have moved over, and a
  future port would drop the deprecation and let icons and truth helpers be
  imported properly. Around seven files: the three route templates, the frame
  component, and the nesting of the route and controller files. The Ruby side,
  the data model, the stylesheet and all six games are unaffected.

The arcade uses `gamepad` for its own heading and `star` for a new personal
best. The trophy is Bookie's mark and is deliberately left alone.

## Known limits

- The frame is a fixed 1:1 aspect ratio. A game needing another shape needs an
  aspect field on `arcade_games`.
- The catalogue has no admin UI. Enabling or disabling a game is a rake task or
  a console one-liner.
- Games that animate use `requestAnimationFrame`, which browsers suspend in a
  hidden tab. That is the behaviour you want, but it does mean an automated
  check has to run in a visible or headless-Chrome page, not a background tab.
