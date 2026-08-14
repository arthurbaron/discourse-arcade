# frozen_string_literal: true

# The catalogue lives here rather than in an admin screen: adding a game means
# shipping its files, so it is a deploy anyway. Re-running this task updates
# metadata in place and never touches existing scores.
#
# min_run_seconds is the shortest a run can be and still have put points on the
# board, so it only ever applies to a score above zero. The first values here
# were guesses several times too high, which rejected ordinary play and told
# people their scores were fake.
ARCADE_GAMES = [
  {
    slug: "2048",
    name: "2048",
    tagline: "Slide tiles together and chase a bigger number.",
    entry_path: "twentyfortyeight/index.html",
    thumbnail: "twentyfortyeight.svg",
    score_direction: "high",
    score_unit: "points",
    max_plausible_score: 400_000,
    min_run_seconds: 2,
    position: 1,
  },
  {
    slug: "snake",
    name: "Snake",
    tagline: "Eat, grow, and try not to run into yourself.",
    entry_path: "snake/index.html",
    thumbnail: "snake.svg",
    score_direction: "high",
    score_unit: "points",
    # A perfect board is 321 pieces of food at 10 points each.
    max_plausible_score: 4_000,
    min_run_seconds: 1,
    position: 2,
  },
  {
    slug: "breakout",
    name: "Breakout",
    tagline: "Clear the wall. Every level the ball gets quicker.",
    entry_path: "breakout/index.html",
    thumbnail: "breakout.svg",
    score_direction: "high",
    score_unit: "points",
    max_plausible_score: 100_000,
    min_run_seconds: 2,
    position: 3,
  },
  {
    slug: "penalty",
    name: "Penalty",
    tagline: "Beat the keeper on timing and placement. Three lives.",
    entry_path: "penalty/index.html",
    thumbnail: "penalty.svg",
    score_direction: "high",
    score_unit: "goals",
    max_plausible_score: 500,
    min_run_seconds: 2,
    position: 4,
  },
  {
    slug: "keepie",
    name: "Keepie Uppie",
    tagline: "Keep the ball off the floor. One miss and you are out.",
    entry_path: "keepie/index.html",
    thumbnail: "keepie.svg",
    score_direction: "high",
    score_unit: "touches",
    max_plausible_score: 2_000,
    min_run_seconds: 1,
    position: 5,
  },
  {
    slug: "dribble",
    name: "Dribble",
    tagline: "Weave through the defenders for as long as you can.",
    entry_path: "dribble/index.html",
    thumbnail: "dribble.svg",
    score_direction: "high",
    score_unit: "metres",
    max_plausible_score: 100_000,
    min_run_seconds: 1,
    position: 6,
  },
  {
    slug: "holdtheline",
    name: "Hold the Line",
    tagline: "Thin out the formation before it reaches you.",
    entry_path: "holdtheline/index.html",
    thumbnail: "holdtheline.svg",
    score_direction: "high",
    score_unit: "points",
    max_plausible_score: 200_000,
    min_run_seconds: 2,
    position: 7,
  },
  {
    slug: "recall",
    name: "Recall",
    tagline: "Watch the sequence, repeat it, and watch it grow.",
    entry_path: "recall/index.html",
    thumbnail: "recall.svg",
    score_direction: "high",
    score_unit: "rounds",
    # A very good player reaches the twenties from memory.
    max_plausible_score: 100,
    min_run_seconds: 1,
    position: 8,
  },
  {
    slug: "intercept",
    name: "Intercept",
    tagline: "Blow the incoming out of the sky. Ammo runs out.",
    entry_path: "intercept/index.html",
    thumbnail: "intercept.svg",
    score_direction: "high",
    score_unit: "points",
    max_plausible_score: 500_000,
    min_run_seconds: 2,
    position: 9,
  },
  {
    slug: "debris",
    name: "Debris",
    # Arrives switched off, so it appears in the admin list and gets turned on
    # by hand rather than showing up on the arcade the moment it deploys.
    enabled: false,
    tagline: "Break the rocks, and fight your own momentum.",
    entry_path: "debris/index.html",
    thumbnail: "debris.svg",
    score_direction: "high",
    score_unit: "points",
    max_plausible_score: 500_000,
    min_run_seconds: 2,
    position: 10,
  },
  {
    slug: "darts",
    name: "Darts",
    # Ships switched off, like every game since the admin toggle: it appears in
    # the admin list and gets turned on by hand. Position 13 leaves room for the
    # games still on their own branches.
    enabled: false,
    tagline: "Fifteen darts. The treble is thin and its neighbours are cruel.",
    entry_path: "darts/index.html",
    thumbnail: "darts.svg",
    score_direction: "high",
    score_unit: "points",
    # Fifteen perfect treble twenties plus five 180 bonuses. The sweep makes
    # that unreachable: the best of 60,000 simulated skilled runs was 740
    # before bonuses.
    max_plausible_score: 1_150,
    min_run_seconds: 5,
    position: 13,
  },
  {
    slug: "stack",
    name: "Stack",
    # Ships switched off, like every game since the admin toggle.
    enabled: false,
    tagline: "Drop each slab dead centre, or lose what hangs over.",
    entry_path: "stack/index.html",
    thumbnail: "stack.svg",
    score_direction: "high",
    score_unit: "layers",
    # Simulated: an expert averages 54 layers with a best of 71 over 40,000
    # runs. A perfect tap-bot, run against the real game rather than guessed
    # at, dies at layer 161, because once the forgiveness margin is gone the
    # discrete sweep cannot land exactly on centre. 220 sits clear of that
    # without ever rejecting a human.
    max_plausible_score: 220,
    # One good drop is one point and can happen inside a second, so this stays
    # low. Guessing high here is what once told people their real scores were
    # fake.
    min_run_seconds: 1,
    position: 14,
  },
].freeze

desc "Create or update the arcade game catalogue"
task "arcade:seed" => :environment do
  ARCADE_GAMES.each do |attrs|
    game = ArcadeGame.find_or_initialize_by(slug: attrs[:slug])

    # enabled is deliberately excluded from the update. It is set once, when the
    # game is created, and never touched again, so re-seeding after a rebuild
    # cannot undo what an admin switched off. Everything else is refreshed.
    game.assign_attributes(attrs.except(:slug, :enabled))
    game.enabled = attrs.fetch(:enabled, true) if game.new_record?
    game.save!

    state = game.enabled ? "on" : "off"
    puts "#{game.persisted? ? "ok" : "failed"}  #{game.slug.ljust(12)} #{state}"
  end

  puts "\n#{ArcadeGame.listed.count} game(s) live."
end

desc "List arcade games with their score counts"
task "arcade:list" => :environment do
  ArcadeGame.order(position: :asc).each do |game|
    state = game.enabled ? "enabled" : "disabled"
    puts format(
           "%-14s %-10s %4d scores  %s",
           game.slug,
           state,
           game.arcade_scores.accepted.count,
           game.play_url,
         )
  end
end
