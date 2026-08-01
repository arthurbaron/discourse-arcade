import Component from "@glimmer/component";
import getURL from "discourse/lib/get-url";
import icon from "discourse/ui-kit/helpers/d-icon";

// A trophy and a count next to the name of anyone currently holding first place
// on an arcade game. One glyph plus a number rather than one glyph per record:
// the post header is already a crowded line, and a fixed width keeps it from
// pushing the timestamp around on a phone.
//
// This renders on every post in every topic, so it is written to fail quiet.
// A missing field or an unexpected shape renders nothing rather than throwing
// and taking the topic view down with it.
export default class ArcadeRecordFlair extends Component {
  get records() {
    // PluginOutlet curries outlet args as named args and also passes them as
    // @outletArgs, so accept either.
    const post = this.args.post ?? this.args.outletArgs?.post;
    const records = post?.arcade_records;

    return Array.isArray(records) ? records : [];
  }

  get count() {
    return this.records.length;
  }

  get title() {
    return `Arcade record holder: ${this.records.join(", ")}`;
  }

  <template>
    {{#if this.count}}
      <a
        class="arcade-record-flair"
        href={{getURL "/arcade"}}
        title={{this.title}}
      >
        {{icon "trophy"}}
        <span class="arcade-record-flair-count">{{this.count}}</span>
      </a>
    {{/if}}
  </template>
}
