import { LinkTo } from "@ember/routing";

export default <template>
  <div class="arcade-season-page">
    <div class="arcade-game-head">
      <LinkTo @route="arcade.index" class="arcade-back">Back to the arcade</LinkTo>
      <h1>Season {{@controller.label}}</h1>
      <p class="arcade-game-tagline">
        Every month, the top
        {{@controller.topCount}}
        in each game score
        {{@controller.pointsLabel}}
        points. A game counts once
        {{@controller.minPlayers}}
        people have played it that month.
      </p>
      {{#if @controller.monthsLabel}}
        <p class="arcade-season-months">{{@controller.monthsLabel}}</p>
      {{/if}}
    </div>

    {{#if @controller.hasStandings}}
      <div class="arcade-season-table">
        <div class="arcade-season-row arcade-season-header" aria-hidden="true">
          <span class="arcade-lb-rank"></span>
          <span class="arcade-season-player">Player</span>
          <span class="arcade-season-num">Points</span>
          <span class="arcade-season-num">Wins</span>
          <span class="arcade-season-num">Podiums</span>
        </div>
        <ol class="arcade-leaderboard">
          {{#each @controller.standings as |row|}}
            <li
              class="arcade-lb-row arcade-season-row {{if row.is_you 'is-you'}}"
            >
              <span class="arcade-lb-rank">{{row.rank}}</span>
              <span class="arcade-season-player">
                <img
                  class="arcade-avatar"
                  src={{row.avatar_url}}
                  alt=""
                  width="24"
                  height="24"
                />
                <span class="arcade-lb-name">{{row.username}}</span>
              </span>
              <span class="arcade-season-num arcade-season-points">
                {{row.points}}
              </span>
              <span class="arcade-season-num">{{row.wins}}</span>
              <span class="arcade-season-num">{{row.podiums}}</span>
            </li>
          {{/each}}
        </ol>
      </div>
    {{else}}
      <p class="arcade-empty">
        No standings yet. A game starts counting once
        {{@controller.minPlayers}}
        people have played it in a month.
      </p>
    {{/if}}

    {{#if @controller.pastMonths}}
      <section class="arcade-month-tops">
        <h2 class="arcade-side-title">Top
          {{@controller.monthTop}}
          per month</h2>
        <div class="arcade-month-grid">
          {{#each @controller.pastMonths as |month|}}
            <div class="arcade-month-card">
              <h3 class="arcade-month-title">{{month.label}}</h3>
              {{#if month.hasTop}}
                <ol class="arcade-leaderboard">
                  {{#each month.top as |row|}}
                    <li class="arcade-lb-row {{if row.is_you 'is-you'}}">
                      <span class="arcade-lb-rank">{{row.rank}}</span>
                      <img
                        class="arcade-avatar"
                        src={{row.avatar_url}}
                        alt=""
                        width="24"
                        height="24"
                      />
                      <span class="arcade-lb-name">{{row.username}}</span>
                      <span class="arcade-lb-score">{{row.points}} pts</span>
                    </li>
                  {{/each}}
                </ol>
              {{else}}
                <p class="arcade-empty">
                  No game had
                  {{@controller.minPlayers}}
                  players this month.
                </p>
              {{/if}}
            </div>
          {{/each}}
        </div>
      </section>
    {{/if}}
  </div>
</template>
