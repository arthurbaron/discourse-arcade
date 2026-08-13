export default function () {
  this.route("arcade", function () {
    this.route("game", { path: "/g/:slug" });
  });
}
