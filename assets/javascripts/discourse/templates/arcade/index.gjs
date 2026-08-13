import { LinkTo } from "@ember/routing";

export default <template>
  <div class="arcade-index">
    <div class="arcade-head">
      {{! A real emoji rather than a sprite icon, to match Bookie's heading. }}
      <h1><span class="arcade-head-emoji">🎮</span> Arcade</h1>
      <p class="arcade-intro">
        Beat the high score. Every score is tied to your account.
      </p>
    </div>

    {{#if @controller.hasGames}}
      <div class="arcade-grid">
        {{#each @controller.games as |game|}}
          <LinkTo @route="arcade.game" @model={{game.slug}} class="arcade-card">
            <div class="arcade-card-art">
              {{#if game.thumbnail_url}}
                <img src={{game.thumbnail_url}} alt="" />
              {{else}}
                <span class="arcade-card-art-fallback">{{game.name}}</span>
              {{/if}}
            </div>

            <div class="arcade-card-body">
              <h3 class="arcade-card-title">{{game.name}}</h3>
              {{#if game.tagline}}
                <p class="arcade-card-tagline">{{game.tagline}}</p>
              {{/if}}

              <div class="arcade-card-meta">
                <span class="arcade-chip">
                  Your best
                  <strong>{{if game.your_best game.your_best "-"}}</strong>
                </span>

                {{#if game.record}}
                  <span class="arcade-chip arcade-chip-record">
                    {{#if game.record.avatar_url}}
                      <img
                        class="arcade-avatar"
                        src={{game.record.avatar_url}}
                        alt=""
                        width="20"
                        height="20"
                      />
                    {{/if}}
                    {{game.record.username}}
                    <strong>{{game.record.score}}</strong>
                  </span>
                {{/if}}
              </div>
            </div>
          </LinkTo>
        {{/each}}
      </div>
    {{else}}
      <p class="arcade-empty">No games have been added yet.</p>
    {{/if}}
  </div>
</template>
