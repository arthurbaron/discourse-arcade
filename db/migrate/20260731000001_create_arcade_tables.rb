# frozen_string_literal: true

class CreateArcadeTables < ActiveRecord::Migration[7.0]
  def change
    create_table :arcade_games do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :tagline
      # Path inside public/games, e.g. "twentyfortyeight/index.html"
      t.string :entry_path, null: false
      # Filename inside public/images/thumbs, e.g. "twentyfortyeight.svg"
      t.string :thumbnail
      # "high" = higher score wins (points), "low" = lower wins (time trials)
      t.string :score_direction, null: false, default: "high"
      t.string :score_unit, null: false, default: "points"
      # Plausibility guard: scores beyond this are rejected outright.
      t.integer :max_plausible_score, null: false, default: 1_000_000
      # A run shorter than this cannot have produced a real score.
      t.integer :min_run_seconds, null: false, default: 5
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :arcade_games, :slug, unique: true

    # One row per started game. The token is what the browser redeems a score
    # with, so a score can never be posted without the server handing out a
    # run first.
    create_table :arcade_runs do |t|
      t.integer :user_id, null: false
      t.integer :arcade_game_id, null: false
      t.string :token, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :arcade_runs, :token, unique: true
    add_index :arcade_runs, %i[user_id arcade_game_id]

    create_table :arcade_scores do |t|
      t.integer :user_id, null: false
      t.integer :arcade_game_id, null: false
      t.integer :arcade_run_id, null: false
      t.integer :score, null: false
      # Measured server side, from run creation to score submission.
      t.integer :duration_seconds, null: false, default: 0
      # Soft delete so moderators can pull a score without losing the trail.
      t.boolean :rejected, null: false, default: false
      t.string :rejected_reason
      t.integer :rejected_by_id
      t.timestamps
    end
    add_index :arcade_scores, %i[arcade_game_id score]
    add_index :arcade_scores, %i[user_id arcade_game_id]
    add_index :arcade_scores, :arcade_run_id, unique: true
  end
end
