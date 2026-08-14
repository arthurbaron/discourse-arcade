export default function () {
  this.route("arcade", function () {
    this.route("game", { path: "/g/:slug" });
    // Admin only. The route itself turns a non-admin away, and the API it reads
    // is behind Discourse's own admin check, so the guard does not rest on the
    // link being hidden.
    this.route("stats");
  });
}
