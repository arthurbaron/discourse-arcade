# frozen_string_literal: true

# Turns a run token plus a claimed score into a stored score, or an error.
#
# A browser game cannot be trusted to report an honest score, so this is where
# the cheap defences live: the run must have been issued by us, to this user,
# unredeemed, unexpired, long enough to be physically possible, and inside the
# game's plausible range. That stops casual tampering. It is not proof, so
# moderators can still pull a score afterwards.
class ArcadeScoreSubmission
  Result = Struct.new(:success, :score, :error, keyword_init: true) do
    def ok?
      success
    end
  end

  def self.call(user:, token:, raw_score:)
    new(user: user, token: token, raw_score: raw_score).call
  end

  def initialize(user:, token:, raw_score:)
    @user = user
    @token = token
    @raw_score = raw_score
  end

  def call
    run = ArcadeRun.find_by(token: @token)
    return failure("Unknown run") if run.nil?
    return failure("That run belongs to someone else") if run.user_id != @user.id
    return failure("This run already has a score") if run.consumed?
    return failure("This run expired, start a new game") if run.expired?

    game = run.arcade_game
    score = Integer(@raw_score.to_s, exception: false)
    return failure("Score must be a whole number") if score.nil?

    if score.negative? || score > game.max_plausible_score
      return failure("Score outside the plausible range for this game")
    end

    elapsed = run.elapsed_seconds

    # A run that produced nothing needs no minimum. Losing in a second is
    # ordinary play in several of these games: Keepie Uppie is over in about a
    # second if you never touch the ball, and Dribble in two if you steer into
    # the first defender. Rejecting those threw away real runs and told the
    # player their score was fake, which is how this was reported.
    if score.positive? && elapsed < game.min_run_seconds
      return(
        failure(
          "That score arrived quicker than the game allows, so it was not saved.",
        )
      )
    end

    record = nil

    run.with_lock do
      run.reload
      return failure("This run already has a score") if run.consumed?

      run.consume!
      record =
        ArcadeScore.create!(
          user_id: @user.id,
          arcade_game_id: game.id,
          arcade_run_id: run.id,
          score: score,
          duration_seconds: elapsed,
        )
    end

    # A new score may have taken a first place, so the cached holders are stale.
    ArcadeRecordHolders.clear!

    Result.new(success: true, score: record)
  rescue ActiveRecord::RecordNotUnique
    failure("This run already has a score")
  end

  private

  def failure(message)
    Result.new(success: false, error: message)
  end
end
