import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { LinkTo } from "@ember/routing";
import ArcadeFrame from "../../components/arcade-frame";

export default <template>
  <div class="arcade-game-page">
    <div class="arcade-game-head">
      <LinkTo @route="arcade.index" class="arcade-back">Back to the arcade</LinkTo>
      <h1>{{@controller.game.name}}</h1>
      {{#if @controller.game.tagline}}
        <p class="arcade-game-tagline">{{@controller.game.tagline}}</p>
      {{/if}}
    </div>

    <div class="arcade-game-layout">
      <div class="arcade-game-main">
        {{! The arcade-frame class now lives inside the component, since it is
            what positions the canvas and the overlay rather than anything this
            page chose. }}
        <ArcadeFrame
          @game={{@controller.game}}
          @onScore={{@controller.scoreSaved}}
        />

        <div class="arcade-stats">
          <div class="arcade-stat">
            <span class="arcade-stat-label">Your best</span>
            <span class="arcade-stat-value">
              {{if @controller.yourBest @controller.yourBest "-"}}
            </span>
          </div>
          <div class="arcade-stat">
            <span class="arcade-stat-label">Your rank</span>
            <span class="arcade-stat-value">
              {{if @controller.yourRank @controller.yourRank "-"}}
            </span>
          </div>
          <div class="arcade-stat">
            <span class="arcade-stat-label">Plays</span>
            <span
              class="arcade-stat-value"
            >{{@controller.game.plays_count}}</span>
          </div>
        </div>
      </div>

      <aside class="arcade-game-side">
        <h2 class="arcade-side-title">Leaderboard</h2>

        {{#if @controller.recordToBeat}}
          <p class="arcade-record-line">
            Record to beat
            <strong>{{@controller.recordToBeat.score}}</strong>
            by
            {{@controller.recordToBeat.username}}
          </p>
        {{/if}}

        {{#if @controller.hasScores}}
          <ol class="arcade-leaderboard">
            {{#each @controller.leaderboard as |entry|}}
              <li class="arcade-lb-row {{if entry.is_you 'is-you'}}">
                <span class="arcade-lb-rank">{{entry.rank}}</span>
                {{#if entry.avatar_url}}
                  <img
                    class="arcade-avatar"
                    src={{entry.avatar_url}}
                    alt=""
                    width="24"
                    height="24"
                  />
                {{/if}}
                <span class="arcade-lb-name">{{entry.username}}</span>
                <span class="arcade-lb-score">{{entry.score}}</span>
                {{#if @controller.canModerate}}
                  <button
                    type="button"
                    class="arcade-lb-remove"
                    title="Remove this score"
                    {{on "click" (fn @controller.removeScore entry)}}
                  >×</button>
                {{/if}}
              </li>
            {{/each}}
          </ol>
        {{else}}
          <p class="arcade-empty">No scores yet. Be the first.</p>
        {{/if}}
      </aside>
    </div>
  </div>
</template>
