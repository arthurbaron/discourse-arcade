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
| `darts` | points | tap to lock each sweeping line |
| `stack` | layers | tap to drop the sliding slab |

All of them are built for a square frame.

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

Anything you add on the Ember side must be `.gjs`. The `.hbs` extension is
deprecated and support for it is being removed during the `2026.8` cycle.

```bash
pnpm i        # once, in this directory
pnpm lint     # js, prettier, css and types in one go
pnpm lint:fix
```

`pnpm lint` deliberately covers the Ember side only, not `public/games`. The
plugin's prettier is a newer major than the one in a Discourse checkout and
formats these files differently, so pointing it at the games would rewrite all
eleven of them for no gain. Game files follow each other; check a new one with
the prettier in your Discourse checkout, which is what the existing ones pass.

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
  the way a player has to, plus the shots already in the air, the open blasts and
  the live difficulty knobs. Without the first two nothing can tell whether a
  missile is already dealt with, which made the game unmeasurable; without the
  last, a curve that stopped rising could only be found by playing for ten
  minutes, and a player found it first.
- `window.Debris.state()` to steer at a real rock. A stationary ship auto-fires
  and destroys the rocks that would have hit it, so a spec that waits to be hit
  can wait forever, and one did.
- `window.Darts.rules.hitAt()` for the board maths, walked point by point: a
  board with sector 12 where 9 belongs still "reports a score", so only
  geometry checks catch it.

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

### Caching, and why every asset URL carries `?v=`

Production nginx serves everything under `/plugins/` with a year of
`Cache-Control: public, immutable`: cache it and never ask again. That is right
for Discourse's own bundles, which get a digest in their filename on every
build, but these game files keep the same URL forever. A browser that played
one game once would hold that copy for a year, straight through every deploy.

That is not hypothetical. Debris shipped together with a new function in
`_shared/arcade.js`, and phones that had cached the helper earlier ran new game
code against the old helper: an immediate crash, a grey stage, iOS only,
because those phones had played the arcade before and desktops had not.

So the server computes a short hash of the games tree (`ArcadeAssetsVersion`,
exposed as `assets_version` in the game JSON), the frame appends it to the
game URL as `v=`, and a small loader in each game's `index.html` carries it
onto the stylesheet and scripts it loads. Changed files get a new URL, which
makes the year of caching harmless; unchanged files keep their warm caches.
The loader only accepts a plain hex stamp, since the value arrives in a URL
and is written into the document.

Two rules follow. A new game's `index.html` must load its assets through that
same loader snippet (copy it from any game). And nothing under `public/` may
ever be referenced by a bare URL from the app without a stamp: not scripts,
not stylesheets, not thumbnails. `spec/system/asset_stamp_spec.rb` walks the
whole chain in a real browser.

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

### Walk the boundary, do not patch holes

This game has had two free goals, both the same shape. First the keeper could not
leave the ground, so the top corners could not be defended. Then `targetVerdict`
checked the crossbar and the posts and forgot the goal line, so the strip of
ground between the line and the ball counted as a shot on target, and the
keeper's box bottoms out on the line and can never come below it.

Both were a boundary that nobody checked, and both were found by a player rather
than a spec, because a spec asking "does the game report a score" is perfectly
happy either way.

`penalty_bounds_spec.rb` exists so there is no third one. It states the property
rather than the symptom:

- every point outside the mouth is a miss, above, below and to either side
- every point inside it can be saved with the keeper lined up under it

If a future change opens a gap anywhere on that boundary, one of those eleven
examples goes red. Aim points keep a margin from the edges, since shots carry
spread deliberately and a point sitting exactly on a line may legitimately land
either side of it.

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

**And it stopped getting harder, which players found before any test did.** The
report was that past a quarter of a million points it turned into plain sailing.
It was true and slightly worse than described. Every knob flattened out early:
ammo by wave 8, missiles per wave by 9, spawn gap by 13, incoming speed by 26. So
from wave 27 the waves were byte-for-byte identical forever, while a kill still
paid 25 x the wave number, which kept climbing. The game paid more and more for
waves that asked less and less, which is endurance dressed up as skill.

Two things had made it invisible. The first is that no test could catch it: a game
that stops escalating still ends and still reports a score, which is all the
contract spec ever checked. The curve is now exposed as pure functions of the wave
and walked directly, the same treatment Stack's slice and margin get. The second
is that the game was not measurable at all. `state()` reported incoming missiles
but not the player's own shots in flight or the blasts already open, so nothing
outside could tell whether a target was already dealt with; a harness written
against it double-fires, runs dry and loses its cities in the second wave, which
is exactly what happened on the first attempt to measure this. Those are reported
now.

Pressure continues through the knob the game was already built around. Its own
design note says ammo is what stops you tapping your way out of trouble, so from
wave 20 the ratio of targets to shots keeps tightening: more missiles per wave,
more of them splitting, arriving closer together, and the magazine slowly giving
back what it grew. Nothing accelerates. Speed is deliberately held, because
incoming fire approaching the counter-missile's own speed cannot be reached in
time no matter how well you play, and an unreadable game is not a hard one. The
result is a demand that rises from 1.6 kills per shot at wave 20 to 4.3 at wave
40 and 14 at wave 70, all at the same missile speed.

The multiplier now stops where the difficulty does, at wave 78. Otherwise the
complaint would simply move: flat waves paying an ever larger rate is the bug,
wherever it sits. A spec asserts that no knob still moves past that wave, so
retuning the curve without revisiting the number fails the build instead of
quietly reintroducing paid endurance.

`max_plausible_score` was the urgent part. It sat at 500,000 against a standing
record of 479,200, so the next good run would have been refused as implausible and
thrown away, the same silent loss as the play-again bug and about one run from
happening. Clearing every wave with all six cities up to the difficulty peak is
worth 6.7M, and the ceiling is set at 25M rather than snugly against that: this
guard exists to reject a tampered client posting an absurd number, not to
adjudicate superhuman play, and a false rejection is the worse failure of the two.

## Dying in Debris used to cost two lives

Reported from play: you die, you blink for a bit, but somewhere in there the ship
vanishes completely for a few seconds while still answering the controls, and
then you are suddenly somewhere else with another life gone.

All of it traced back to one counter doing two jobs. `respawn` counted 70 steps
down to 1 and then held at 1 until the middle of the field was clear, and the
blink test read `floor(respawn / 6) % 2 === 0`, which at 1 is true: the wait was
spent completely invisible rather than blinking. `advanceShip()` ran the whole
time, so a finger still on the glass flew a ship nobody could see, while the
clear-the-middle check watched the middle the ship had long since left. When the
counter finally reached zero you turned solid wherever you had drifted to.

Measured on the old code, holding the finger through a death: 2.48 field-widths
of travel in three seconds, thrusting in 120 of 120 samples, second life gone
inside the window.

It is now two separate things. `returning` is a fixed beat with the ship off the
field: not drawn, not moving, deaf to input. `shield` is the grace period after
it, on the field and playable, and only that phase blinks, so no state can leave
the ship hidden. The spot is chosen when you die and marked with a faint outline
for the whole wait, so you watch where you are about to be.

The wait is deliberately fixed rather than "until the middle is clear". That
condition was not just badly wired, it was the wrong idea here: the ship does not
shoot while it is away, so nothing clears the middle, and a traced run sat there
for two full seconds without returning. The original arcade waited because it had
no invulnerability to fall back on. We do, so the shield carries the fairness and
`chooseReturnSpot` picks the middle when there is room and a spot on a small ring
around it when there is not.

`debris_respawn_spec.rb` pins the invariants that matter: the ship does not move
while it is away, it always returns and quickly, it lands where the marker
promised with room around it, and no life is lost while away or shielded. The
last example reads canvas pixels rather than game state, so a marker that was
calculated but never painted still fails.

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
    templates/arcade/index.gjs    not  templates/arcade-index.gjs

`templates/arcade.gjs` stays where it is, since route `arcade` asks for
`template:arcade` and that already matches.

`template_paths_spec.rb` reads the browser console and fails on any of these
warnings, which is the only way to see them: the pages render perfectly either
way. It earned its keep immediately. The first attempt renamed only the templates
and the spec caught that routes and controllers had the same problem, so without
it a half fix would have shipped and the notice would have stayed exactly where
it was.

## Everything is .gjs, and why that was not optional

`discourse.hbs-extension` was the second deprecation to nag an admin on every
page load, and unlike the first it came with a clock: support for `.hbs` is
being removed during the `2026.8` cycle, which is the release track this forum
already runs. So this was a deadline, not tidying.

The conversion itself is mechanical for route templates. They become
`export default <template>...</template>`, and every `this.foo` becomes
`@controller.foo` because a route template now receives the controller as an
argument rather than being bound to it. Helpers stop being ambient and get
imported: `on` from `@ember/modifier`, `fn` from `@ember/helper`, `LinkTo` from
`@ember/routing`, `eq` from `discourse/truth-helpers`, `icon` from
`discourse/ui-kit/helpers/d-icon`.

`arcade-frame` was the real work, and it hid a trap worth remembering. It was a
classic `@ember/component`, which brings its own wrapper element, and the call
site put `class="arcade-frame"` on it. A Glimmer component is tagless, so that
class simply lands nowhere. `.arcade-frame` is `position: relative` with a fixed
aspect ratio and both the canvas and the overlay are absolutely positioned
inside it, so the whole game page would have collapsed. The component now renders
its own wrapper with `...attributes`, and owns that class rather than trusting a
caller to pass it.

Two other things had to change with it. `this.element` does not exist on a
Glimmer component, so the iframe registers itself through `didInsert` instead of
being found by a DOM query, which is also more honest about the fact that this
component only ever wants the one element it owns. And `didInsertElement` /
`willDestroyElement` became the constructor and `willDestroy`; missing that
second one leaks a `message` listener for every game page a member visits.

There is an official codemod (`pnpm dlx https://github.com/discourse/discourse-gjs-codemod`)
which is the right starting point for a bigger plugin. It expects a plugin that
already lints clean, which this one did not: the classic component tripped
`ember/no-classic-components`, and that had to be resolved by hand first, at
which point the remaining templates were small enough to convert directly.

The plugin now carries its own `package.json`, `eslint.config.mjs`,
`.prettierrc.cjs` and `stylelint.config.mjs`, copied from the plugin skeleton.
That is worth having beyond this migration: linting used to run from whichever
Discourse checkout happened to be handy, and the two on this machine disagreed,
one reporting a clean tree and the other forty-one offences in the same files.
`pnpm lint` in the plugin directory is now the answer.

## Switching games on and off from admin

Admin, Plugins, Arcade, then the Games tab: a row per game with its thumbnail,
name, tagline and score count, and a switch.

Almost none of this needed new machinery. `arcade_games.enabled` and the `listed`
scope were already there, `ArcadeRecordHolders` already built from `listed`, and
the model already cleared the flair cache on `after_commit`. So switching a game
off takes it off `/arcade` and removes its record holder's trophy from every post
without a line of new logic. No migration.

Three things worth keeping straight:

- **Disabling keeps every score.** Switch a game back on and its leaderboard is
  exactly as it was.
- **A run already in progress still counts.** Submission finds the game through
  the run token rather than through `listed`, so someone playing when the switch
  flips can finish and have their score stored. Starting a *new* run on a
  disabled game 404s. Both are pinned in `admin_arcade_controller_spec.rb`.
- **`arcade:seed` will not switch anything back on.** `enabled` is excluded from
  the update entirely and set only when the row is created, so a rebuild refreshes
  every other field and leaves your choices alone. A game can also ship switched
  off by putting `enabled: false` in its catalogue entry, which is how Debris
  arrives: it appears in this list rather than on the arcade, waiting to be turned
  on by hand. `spec/lib/arcade_seed_spec.rb` pins all of that, since the seed runs
  on every deploy and quietly undoing an admin's choice is the obvious way for it
  to go wrong.

Two traps cost time here, both invisible until you look:

The admin JSON lives at `/arcade/api/admin/games` with the rest of the plugin's
API, not under `/admin/plugins/`, so it cannot shadow Discourse's own plugin
routes. And the *page* needs its own Rails route: Discourse only serves
`/admin/plugins/:plugin_id` and `/settings`, so a child route of the admin SPA
works when clicked but 404s on a hard load or a pasted URL until it is named.

Admin styling is a separate file registered with the `:admin` target. Plugin
stylesheets registered the ordinary way are not loaded on admin pages, and the
symptom is a page that renders as a bulleted list with everything stacked.

## Darts: timing, never pointer precision

Fifteen darts at a real board, highest total. The one decision everything else
follows from: darts do not land where you click. If they did, a desktop mouse
would sit on the treble twenty all day and the leaderboard would rank input
devices instead of players, so aiming is two timed taps: a line sweeps across
the board, a tap locks it, the other axis sweeps, a tap throws. Identical on a
phone and on a mouse, and the same one-input-everywhere rule the rest of the
arcade follows.

The board is the real one: DRA ring radii and the true sector order, drawn in
theme colours (sectors in two greys, rings alternating accent and muted). That
buys the balance for free. The 20 sits between the 1 and the 5, so hunting the
treble is a genuine gamble, and the interesting result from the balance
simulation (200,000 throws per cell): a sloppy player scores measurably better
aiming at the fat single twenty (16.7 per dart) than at the treble (13.1),
while a skilled one flips that (28.7 at the treble, 24% trebles). Risk it or
bank it, and the board itself asks the question.

Sweep speed is the whole difficulty and was chosen from a simulation: 60 steps
edge to edge, which said skilled runs average about 432 of the 900 and the best
of 60,000 was 740, so a perfect card was structurally out of reach. **That
simulation was wrong, and players proved it.** It modelled a thumb with a random
timing error. The real game rewards something else entirely: the sweep restarts
at the same edge at the same speed for every dart, so the rhythm can be
memorised, and once it is there is no error left to model. Driven against the
real page, perfect timing throws fifteen trebles out of fifteen, every single
time. A small landing wobble (0.015 of the board radius, a disc so it cannot
favour an axis) cannot save it, because the best reachable stop sits further
inside the treble than the wobble can reach.

Fifteen darts are five real visits of three, and three treble twenties in one
visit is a 180: a huge blinking shout across the board and a +50 bonus. Visits
are aligned exactly as at the oche, so three trebles spanning a visit boundary
score their points and nothing more. That puts the ceiling at 1,150.

That alignment rule shipped invisible, and it was reported from play as a bug:
three trebles in a row paid nothing, because they crossed a boundary. The rule
was right and unknowable, which for a player is the same thing as wrong. Three
slots along the top now show the current visit's darts, the one you are about
to throw is outlined, and when two trebles are already in, the empty slot turns
accent so the maximum announces itself before the dart rather than after it.
The hint line names the visit and the dart within it. Any rule a bonus depends
on has to be on screen; a correct invisible rule is a bug report waiting to
happen.

Two drawing lessons from the same session. The visit slots use plain
`fillRect`, not `roundRect`, which only landed in Safari 16.4 and this codebase
has already shipped one iOS blank screen by assuming a browser had something.
And the vertical aim phase was drawing no horizontal line at all: it opened one
path, added the line, then called `beginPath` again for the landing dot, which
discarded the line before the single `stroke` at the end. The whole second aim
was played with a dot and no line. Proved by counting accent pixels along the
sweep's row: 106 of 1,120 broken against 1,120 fixed, and pinned that way, since
"it reports a score" can never see a missing line. Worth noting how the first
attempt at that measurement fooled itself: it read the canvas immediately after
the tap, which reads the frame drawn *before* the phase changed, and reported a
pass for the broken code. The check now samples state and pixels inside the
same animation frame.

## Darts had a wall at 1,150, and players hit it before any test did

Reported from the forum, in players' own words: "if you don't hit 5 treble 20s
in the first 6 it's not worth finishing", "you need 4 maximums", and a request
for a tie-breaker "because it definitely might happen that someone hits all".
The record stood at 980. All of that is one problem: 1,150 was not a record, it
was a wall that everyone who practised would eventually stand on, ranked by who
got there first.

Two fixes were tried and measured before the one that shipped, and both failed
in ways worth keeping:

**A faster sweep is not reliably harder.** Whether a treble can be hit with
certainty depends on whether one of the sweep's reachable stops lands far enough
inside the ring for the wobble to be harmless, and that is an alignment
coincidence rather than a difficulty. Measured: 60 steps leaves 0.0161 of room
and 30 steps leaves exactly the same, while 36 and 40 leave none at all. A
difficulty ladder built on that would jump between impossible and trivial.

**Naming a harder target does not work either.** The guess was that the 20 is
easy because it sits straight up and only needs one axis to cooperate, while an
off-axis treble needs both at once. Checked against every sector: all twenty
trebles can be hit with certainty. The grid is 61 stops per axis, nearly 4,000
reachable points, far too fine for a board with sectors this size.

Which leaves one honest conclusion: with a grid that fine, determinism cannot
produce difficulty. Only variation can. But *which* variation matters enormously.
Randomising the landing makes a correct tap fail sometimes, and then the
leaderboard measures how many runs someone is willing to start: at 70% per dart,
1,150 still comes up in half of all runs. Randomising the *rhythm* instead means
the sweep has to be watched rather than recited, which is still skill, just a
different one.

So the card of fifteen is left bit-for-bit alone, and **every score already on
the board stays valid**, because all of them are under the threshold. Reach 1,000
on that card and sudden death opens: you keep throwing, a visit at a time, for as
long as every visit is a maximum. Extra visits start the sweep somewhere random
and coarsen its grid by four steps a visit down to a floor of sixteen. The random
start is what stops the rhythm being recited, and it is also what makes the
coarsening *monotonic*: averaged over a random start, the chance a stop lands in
the ring is the ring width over the step size, and the alignment coincidence that
sank the first attempt washes out.

Measured against the real page, fourteen runs by a tracker with perfect
reactions: median 1,750, best 2,440, and it always ended on its own. Surviving
ten extra visits is about two chances in a hundred billion, so
`max_plausible_score` sits at 10,000 rather than snug against 3,620.

One thing this deliberately does not fix. The complaint that a bad start makes a
run not worth finishing gets slightly worse, because the bar to compete is now a
perfect card. That is only fixable by rebalancing all fifteen darts, which would
make every existing score incomparable, and that is a decision about wiping the
leaderboard rather than a bug to fix.

`darts_spec.rb` walks the geometry point by point (bull, rings, boundaries at
exactly nine degrees, the full twenty-sector order) and pins the input rules:
a tap locks one axis while the other keeps sweeping, the dart lands within the
advertised wobble of the locked crossing, taps during the result pause are
ignored so a double tap cannot burn a dart, and the total is exactly the sum
of the fifteen hits plus fifty per 180. The 180 spec is worth a note: the
sweep's positions form a fixed grid, and one grid position sits close enough
to the treble twenty's centre that a script watching `state().sweep` and
tapping on the right step hits T20 every time, wobble included. That is how the
spec forces a 180 on demand. It was written up here as a demonstration that
"scripts can do what thumbs cannot", and that reading was wrong: a thumb that
learns the rhythm does exactly the same thing, which is how the wall above got
built. The spec for sudden death drives that same perfect card on purpose, since
the only reason any of it is needed is that a perfect card is achievable.

## Stack, and a margin that has to run out

A slab slides across the top of a tower, a tap drops it, and whatever hangs over
the slab below is sliced away. What survives is the width the next slab gets, so
a perfect drop costs nothing and a sloppy one costs you for the rest of the run.
Score is layers standing. One tap, timing not aiming, identical on a thumb and a
mouse, same fairness rule the rest of the arcade follows.

The whole game is two functions. `sliceFor` takes where the slab landed and
where the one below sits and returns what is left, and `marginAt` decides how
much slack a near-perfect drop is forgiven. Both are invisible from outside: a
tower that slices the wrong side away still loads and still reports a score, so
`stack_spec.rb` walks them directly, including that the slice is symmetric, that
the survivor leans towards the side you landed on, and that the scrap flies off
the side that overhung.

**The margin is the design, and a fixed one has no ceiling.** Some forgiveness
is essential, or every layer sheds a sliver however well you play and the game
is joyless. But simulated with a fixed 14%, an expert-level player ran straight
into a 5,000 layer runaway guard: unbounded, and unlike Darts there is no
natural cap to fall back on. So the margin shrinks with height and reaches zero.
Forgiving while you learn, unforgiving once you are good, and the run always
ends. Over 20,000 simulated runs per skill level: an expert averages 63 layers
with a best of 79, a decent player 38, a casual one 21. That spread is what
makes the leaderboard worth climbing.

The opening was tuned twice, and the second pass came from playing it. At 14%
decaying 0.006 a skilled player stacked a **median of nineteen layers without
shedding a single sliver**, which is more layers than fit on the board, so the
tower never actually looked like a tower: just a rectangle with lines in it. The
run length was fine, the feel was not. At 9% decaying 0.007 that free ride halves
to ten layers and the narrowing starts before the tower fills the screen, at a
cost of about five layers off every skill level. Worth measuring the free-layer
count directly rather than only run length, because run length barely moved
between the two and would have said nothing was wrong.

That still leaves a script with no timing error at all, which no margin rule can
touch. It stops itself, and this is the part worth remembering: the slab moves
in discrete steps, so the positions it can occupy form a grid, and once the
margin is gone the closest reachable position is still half a step off centre.
A perfect script therefore sheds a sliver every layer too. That number has to be
measured against the real game, not a hand-derived model of it: an earlier
estimate said 92, and running an actual tap-bot against the live page instead
said 147, just three layers under `max_plausible_score` at the time. The bot now
dies at layer 192, and the ceiling sits at 300. The headroom is deliberate,
because that figure moves every time the sweep is retuned, and three layers of
slack is no slack at all.

**The endgame was reported as unfair twice, and both reports were right.** A
small slab felt like it was called a miss too early, and never got to be
genuinely small. Two independent causes. Game over is an *absolute* floor on what
survives a drop, so near that floor it stops judging the drop and starts judging
the leftover: at the old floor of 0.035, landing 85% of a 0.04 slab on the one
below still ended the run. Separately, a player's timing error is a number of
*frames*, so the distance they miss by is frames times step, and a step that
keeps growing with height while the slab shrinks eventually makes one frame of
hesitation wider than the whole target. By layer 50 a single frame covered 65% of
the slab, which is a coin toss and not a test of timing. Between them the slab
could never actually become small, because the run ended first. So the floor
dropped to 0.012, and the step is capped at a fifth of the slab, which only binds
once the slab is under about a tenth of the board and leaves everything before
that untouched. A typical expert run now ends holding a slab 0.013 wide: a
sliver, as it should be.

The tower starts on the floor of the board and genuinely grows upward; the camera
only takes over once the top reaches the action line, about fifteen layers in,
and from then on pushes everything down to hold it there. Anchoring slabs to the
base rather than the top is what makes that work: during the growth phase the
slabs already placed do not move at all. The first version placed the top at a
fixed height from layer one, which read as a strip already floating mid-board
rather than a tower rising.

The sweep was slowed to 80% of its original speed on request, easier to read at
a small cost in challenge, and the numbers above already reflect it. Nothing
about the margin schedule changed, only how fast the slab covers the board.

`min_run_seconds` is 1, deliberately low. One good drop is one point and can
happen inside a second, and guessing high on that field is what once told
members their genuine scores were fake.

## Known limits

- The frame is a fixed 1:1 aspect ratio. A game needing another shape needs an
  aspect field on `arcade_games`.
- The catalogue has no admin UI. Enabling or disabling a game is a rake task or
  a console one-liner.
- Games that animate use `requestAnimationFrame`, which browsers suspend in a
  hidden tab. That is the behaviour you want, but it does mean an automated
  check has to run in a visible or headless-Chrome page, not a background tab.
