export default {
  resource: "admin.adminPlugins.show",

  path: "/plugins",

  map() {
    this.route("discourse-arcade-games", { path: "games" });
  },
};
