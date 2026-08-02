import { withPluginApi } from "discourse/lib/plugin-api";

const PLUGIN_ID = "discourse-arcade";

export default {
  name: "arcade-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "gamepad");
      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "arcade.admin.games.title",
          route: "adminPlugins.show.discourse-arcade-games",
          description: "arcade.admin.games.nav_description",
        },
      ]);
    });
  },
};
