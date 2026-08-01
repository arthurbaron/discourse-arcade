# frozen_string_literal: true

# The catalogue lives here rather than in an admin screen: adding a game means
# shipping its files, so it is a deploy anyway. Re-running this task updates
# metadata in place and never touches existing scores.
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
    min_run_seconds: 5,
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
    min_run_seconds: 3,
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
    min_run_seconds: 5,
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
    min_run_seconds: 3,
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
    min_run_seconds: 3,
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
    min_run_seconds: 3,
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
    min_run_seconds: 5,
    position: 7,
  },
].freeze

desc "Create or update the arcade game catalogue"
task "arcade:seed" => :environment do
  ARCADE_GAMES.each do |attrs|
    game = ArcadeGame.find_or_initialize_by(slug: attrs[:slug])
    game.assign_attributes(attrs.except(:slug))
    game.enabled = true if game.new_record?
    game.save!

    puts "#{game.persisted? ? "ok" : "failed"}  #{game.slug}  #{game.name}"
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
