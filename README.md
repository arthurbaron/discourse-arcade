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
| `penalty` | goals | click or drag anywhere in the goal |
| `keepie` | touches | tap the ball |
| `dribble` | metres | slide to steer, arrows |
| `holdtheline` | points | slide to move, arrows; fire is automatic |
| `recall` | rounds | tap the pads |
| `intercept` | points | tap to place a blast |
| `debris` | points | hold to steer and thrust, arrows; fire is automatic |

All ten are built for a square frame.

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

Most games expose a small read-only object so a spec can check the thing that
"it ends and reports a score" cannot:

- `window.Game2048.collapse` for the merge rules.
- `window.Keepie.state()` to tap the ball accurately.
- `window.Dribble.buildRow` to prove every row leaves a passable gap.
- `window.Penalty.state()` for the keeper's position and the outcome of a shot,
  which is drawn on the canvas and so invisible to a spec otherwise.
- `window.Recall.state()` for the sequence, since a spec cannot watch pads flash.
- `window.Intercept.state()` for the incoming tracks, so a spec can lead a shot
  the way a player has to.
- `window.Debris.state()` to steer at a real rock. A stationary ship auto-fires
  and destroys the rocks that would have hit it, so a spec that waits to be hit
  can wait forever, and one did.

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

## Record flair

With `arcade_show_record_flair` on, anyone currently holding first place on a
game gets a trophy and a count next to their name on every post, linking to
`/arcade`, with the games named in the tooltip.

The count is one glyph plus a number rather than one glyph per record: the post
header is already a full line, and a fixed width keeps it from pushing the
timestamp around on a phone.

`ArcadeRecordHolders` is what makes this cheap. The set of record holders is
tiny and global, at most one person per game forum-wide, so it is built once,
cached, and every post does a hash lookup instead of a query. The cache is
cleared when a score is submitted, when a score is removed, and when a game is
saved. The serializer leaves the field off the post entirely for anyone holding
nothing, so almost every post carries nothing extra.

**The setting is off by default.** It renders on every post, so it gets switched
on deliberately and can be switched straight back off from admin without a
rebuild.

**This feature needs current Discourse.** It renders through the
`post-meta-data-poster-name` plugin outlet, which does not exist in the 3.2-era
checkout, so `spec/system/record_flair_spec.rb` fails there. Everything else in
the plugin still passes on both. Run the suite against current Discourse from
`~/discourse-next`:

```bash
PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH" LOAD_PLUGINS=1 \
  RAILS_DB=discourse_next_test bin/rspec plugins/discourse-arcade/spec
```

Two things must be rebuilt there after editing frontend files, and forgetting
either one looks exactly like broken code: `rake assets:precompile:build_plugins`
after JS or `.gjs` changes, and `rake assets:precompile:css` after stylesheet
changes.

One trap worth remembering: `post-meta-data-poster-name` is a *wrapper* outlet.
`renderInOutlet` replaces its content, which silently removes the username from
every post on the forum. Use `renderAfterWrapperOutlet`. The spec asserts both
usernames are still on the page, because a spec that only checks the flair
appeared passes happily while the names are gone.

## Discourse version notes

Written against 3.2-era plugin conventions, and verified working on
`v2026.8.0-latest`: `.hbs` route templates and colocated component templates
under `assets/javascripts` are still compiled automatically, and classic
`@ember/component`, `*-route-map.js`, plugin `controllers/`, `{{eq}}`,
`inject as service`, `ajax` and `dialog.yesNoConfirm` all still resolve.

`{{d-icon}}` works in a plugin `.hbs` on both versions. That is worth stating
because it is easy to conclude otherwise: current Discourse has no
`app/helpers/d-icon.js` and none of its own shipped `.hbs` templates use the
helper, since they have all moved to `.gjs` and import it. Neither fact means the
ambient helper is gone. `discourse-bookie` uses `{{d-icon}}` in six places and
runs fine on `v2026.8.0-latest`. Absence of use is not absence of support, and
`{{fa-icon}}` is only a deprecated alias for the same thing.

**Run frontend specs in `~/discourse-next`, not the old checkout.** The old
checkout serves a cached frontend build to its specs and does not rebuild it when
a template changes, so a frontend assertion there can pass or fail against code
that is no longer in the file. It was still rendering a `d-icon-gamepad` in the
heading long after that markup was replaced. Its Ruby specs are trustworthy; its
frontend ones are not.

Two smaller notes on running the linters from `~/discourse-next`: eslint there
reports the classic component in `arcade-frame.js`, and rubocop there wants
newer fabricator shorthand in the specs. Both are deliberate. The shorthand in
particular would break every spec on the older checkout, which still runs this
plugin locally, for the sake of a style cop.

One deliberate choice remains:

- The frontend is not `.gjs`. Discourse's own plugins have moved over, and a
  future port would drop the deprecation and let icons and truth helpers be
  imported properly. Around seven files: the three route templates, the frame
  component, and the nesting of the route and controller files. The Ruby side,
  the data model, the stylesheet and all six games are unaffected.

The arcade heading uses a real 🎮 emoji rather than a sprite icon, to match
Bookie's 🏆 heading. That means it renders in each platform's own emoji font, so
it looks slightly different per device: the cost of matching Bookie. A `star`
marks a new personal best, and the trophy is the record flair.

## Penalty, and tuning by measurement

The keeper is the whole game, and the first version got it wrong in a way no
spec caught: he stood on the goal line and only moved sideways, so his hitbox
covered the bottom half of the goal and nothing else. Either top corner was a
certain goal. On a desktop you could click the same spot every time and never
miss.

He now dives in both axes towards the ball, from wherever the patrol has left
him, and how far he gets in the remaining flight time decides it. Shot accuracy
also falls off the further from the middle you aim, so a corner is ambitious
rather than free.

The numbers came from measuring rather than guessing, with a throwaway spec that
fired shots and counted outcomes. Worth repeating that way if the balance ever
needs revisiting, because two rounds of tuning by feel were both wrong: the
first left corners at 78% and the second made the keeper unbeatable. Where it
landed, at the start of a run:

| Shot | Goals |
| --- | --- |
| Top corner, no attention to the keeper | ~20% |
| Top corner, taken while he is at the far post | ~70% |
| Straight down the middle | ~0% |

Roughly 15% of corner attempts miss the target altogether, which is the price of
aiming there. `penalty_keeper_spec.rb` pins the two things that must stay true:
he leaves the ground for a high shot, and a shot straight at him is saved.

## Do not remove the gamepad icon registration

`plugin.rb` registers `gamepad` and nothing in the plugin renders it, so it looks
like dead code. It is not. Admins pick that icon for the sidebar link to
`/arcade`, and sidebar link icons are not one of the sources that fill the SVG
sprite, so the registration here is the only thing keeping it available. It was
removed once when the heading moved to an emoji, and the sidebar link quietly
lost its glyph and became unselectable. `spec/icons_spec.rb` guards it.

## Recall and sound

Simon is as much a tune as it is four colours, so the pads play notes. They are
generated with an oscillator rather than loaded as files, which keeps the game
self-contained.

Audio needs a gesture inside the frame before a browser will allow it, and the
gesture in the host page does not count. That is what the "Tap to begin" panel
is for: it unlocks the sound and starts round one in the same tap, so nobody
opens the arcade and is ambushed by beeping. There is a mute toggle in the bar,
which resets each run because a sandboxed frame has no storage to remember it in.

The four pads use two explicit colours each rather than one colour plus opacity.
Dimming with opacity blends into the page behind it, which left all four looking
washed out on a light theme.

Colour is never the only cue. Each pad keeps its own corner and its own note, so
the game does not depend on telling four hues apart.

## Intercept and leading the shot

Two rules carry this one, and both are worth leaving alone.

Ammo is capped per wave and refills between them. Without that you tap your way
out of every situation and the game has no shape; with it you have to hold fire
until several missiles line up. Running dry mid-wave and watching the rest land
is the point, not a bug.

The battery sits on the ground and its counter-missile has to fly up, so you aim
where a missile is going rather than where it is. Nothing connects otherwise,
which is why `intercept_spec.rb` has to solve for the intercept point by fixed
point iteration before it can fire: a spec that taps at a missile's current
position never hits anything and would pass while the game was broken.

A destroyed missile explodes in turn, so a well placed blast unzips a cluster.
That chain is where the scores come from.

## Recall was silent on iPhones

Shipped broken and nothing here caught it. The audio context was created inside
the opening tap, which is enough for Chrome, but Safari hands back a context in
the `suspended` state and leaves it there. `resume()` was never called, so every
iPhone got a silent game while every desktop worked.

It now resumes on the opening tap and on every pad tap after it, because iOS
suspends the context again whenever the page has been in the background.

The mute button also tells the truth now. It said "sound on" while the player
heard nothing, which is what turned a small bug into a confusing one. It follows
the context's own `statechange` event rather than reading the state after asking
for a resume: resume is asynchronous, and a first attempt at this reported "no
sound" while the sound was already coming back.

What it still cannot see is the iPhone's ring/silent switch, which mutes output
without touching the context. "sound on" plus silence means the switch is on.

That switch is worth a line on the start panel, and a deliberately unhelpful
generic one would not do. Android has no equivalent: its silent mode and Do Not
Disturb leave media volume alone, so Web Audio keeps playing there and a silent
Android just means the volume is down, which nobody needs telling. The whole
value is in the part that surprises people, which is that an iPhone mutes this
while their music carries on.

`recall_audio_spec.rb` drives the context into the state Safari leaves it in and
checks the game climbs back out.

## File names have to match what Ember asks for

The arcade raised `discourse.deprecated-resolver-normalization` on every page
load, which surfaces as a red admin notice on the forum. I first assumed it meant
the whole classic frontend had to be ported. It did not.

Ember asks the resolver for `route:arcade/index`, `controller:arcade/index` and
`template:arcade/index`. The files were named `arcade-index.js` and
`arcade-index.hbs`, which the resolver only finds through its last-resort "try it
all dasherized" candidate, and finding something under any name other than the
one requested is exactly what the deprecation reports. Nested routes therefore
need nested directories:

    routes/arcade/index.js        not  routes/arcade-index.js
    controllers/arcade/index.js   not  controllers/arcade-index.js
    templates/arcade/index.hbs    not  templates/arcade-index.hbs

`templates/arcade.hbs` stays where it is, since route `arcade` asks for
`template:arcade` and that already matches.

`template_paths_spec.rb` reads the browser console and fails on any of these
warnings, which is the only way to see them: the pages render perfectly either
way. It earned its keep immediately. The first attempt renamed only the templates
and the spec caught that routes and controllers had the same problem, so without
it a half fix would have shipped and the notice would have stayed exactly where
it was.

## Known limits

- The frame is a fixed 1:1 aspect ratio. A game needing another shape needs an
  aspect field on `arcade_games`.
- The catalogue has no admin UI. Enabling or disabling a game is a rake task or
  a console one-liner.
- Games that animate use `requestAnimationFrame`, which browsers suspend in a
  hidden tab. That is the behaviour you want, but it does mean an automated
  check has to run in a visible or headless-Chrome page, not a background tab.
