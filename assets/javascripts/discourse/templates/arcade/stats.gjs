import { LinkTo } from "@ember/routing";
import icon from "discourse/ui-kit/helpers/d-icon";

export default <template>
  <div class="arcade-stats-page">
    <div class="arcade-head">
      <h1><span class="arcade-head-emoji">📊</span> Statistics</h1>
      {{! One sentence on one line on purpose: broken across lines, the closing
      full stop picks up the indentation as a space and reads as "Amsterdam) ."
      The server always resolves a timezone, so there is nothing to guard. }}
      <p class="arcade-intro">Admin only. Days are counted in your own timezone
        ({{@controller.timezone}}).</p>
    </div>

    {{#if @controller.hasPlays}}
      <div class="arcade-stat-tiles">
        <div class="arcade-stat-tile">
          <span
            class="arcade-tile-value"
          >{{@controller.totals.plays_today}}</span>
          <span class="arcade-tile-label">played today</span>
        </div>
        <div class="arcade-stat-tile">
          <span
            class="arcade-tile-value"
          >{{@controller.totals.plays_week}}</span>
          <span class="arcade-tile-label">this week</span>
        </div>
        <div class="arcade-stat-tile">
          <span
            class="arcade-tile-value"
          >{{@controller.totals.plays_total}}</span>
          <span class="arcade-tile-label">all time</span>
        </div>
        <div class="arcade-stat-tile">
          <span
            class="arcade-tile-value"
          >{{@controller.totals.players_week}}</span>
          <span class="arcade-tile-label">players this week</span>
        </div>
      </div>

      <section class="arcade-stat-block">
        <h2>Per game</h2>
        <div class="arcade-stat-scroll">
          <table class="arcade-stat-table">
            <thead>
              <tr>
                <th>Game</th>
                <th class="is-num">Week</th>
                <th class="is-num">Total</th>
                <th class="is-num">Players</th>
                <th class="is-num">Typical run</th>
                <th class="is-num">Best</th>
                <th>Last played</th>
              </tr>
            </thead>
            <tbody>
              {{#each @controller.games as |game|}}
                <tr class={{unless game.enabled "is-off"}}>
                  <td>
                    {{game.name}}
                    {{#unless game.enabled}}
                      <span class="arcade-stat-off">off</span>
                    {{/unless}}
                  </td>
                  <td class="is-num">{{game.plays_week}}</td>
                  <td class="is-num">{{game.plays_total}}</td>
                  <td class="is-num">{{game.players_total}}</td>
                  <td class="is-num">{{game.medianLabel}}</td>
                  <td class="is-num">
                    {{#if game.best_score}}
                      {{game.best_score}}
                    {{else}}
                      -
                    {{/if}}
                  </td>
                  <td class="arcade-stat-quiet">{{game.lastPlayedLabel}}</td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
      </section>

      {{#if @controller.trophies}}
        <section class="arcade-stat-block">
          <h2>Most records held</h2>
          <ol class="arcade-trophy-list">
            {{#each @controller.trophies as |holder|}}
              <li class="arcade-trophy-row">
                <img
                  class="arcade-avatar"
                  src={{holder.avatar_url}}
                  alt=""
                  width="24"
                  height="24"
                />
                <span class="arcade-trophy-name">{{holder.username}}</span>
                <span class="arcade-trophy-games">{{holder.gamesLabel}}</span>
                <span class="arcade-trophy-count">
                  {{icon "trophy"}}
                  {{holder.count}}
                </span>
              </li>
            {{/each}}
          </ol>
        </section>
      {{/if}}

      <section class="arcade-stat-block">
        <h2>Last two weeks</h2>
        <div class="arcade-bars">
          {{#each @controller.byDay as |day|}}
            <div class="arcade-bar-col" title="{{day.date}}: {{day.count}}">
              <div class="arcade-bar-track">
                <div
                  class="arcade-bar {{if day.isPeak 'is-peak'}}"
                  style={{day.style}}
                ></div>
              </div>
              <span class="arcade-bar-value">{{day.count}}</span>
              <span class="arcade-bar-label">{{day.label}}</span>
            </div>
          {{/each}}
        </div>
      </section>

      <section class="arcade-stat-block">
        <h2>By day of the week</h2>
        {{#if @controller.busiestWeekday}}
          <p class="arcade-stat-note">
            Busiest so far:
            <strong>{{@controller.busiestWeekday}}</strong>.
          </p>
        {{/if}}
        <div class="arcade-bars">
          {{#each @controller.byWeekday as |day|}}
            <div class="arcade-bar-col" title="{{day.name}}: {{day.count}}">
              <div class="arcade-bar-track">
                <div
                  class="arcade-bar {{if day.isPeak 'is-peak'}}"
                  style={{day.style}}
                ></div>
              </div>
              <span class="arcade-bar-value">{{day.count}}</span>
              <span class="arcade-bar-label">{{day.short}}</span>
            </div>
          {{/each}}
        </div>
      </section>
    {{else}}
      <p class="arcade-empty">Nothing has been played yet.</p>
    {{/if}}

    <LinkTo @route="arcade.index" class="arcade-stats-back">
      Back to the arcade
    </LinkTo>
  </div>
</template>
