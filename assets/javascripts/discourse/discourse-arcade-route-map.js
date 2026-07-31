export default function () {
  this.route("arcade", { path: "/arcade" }, function () {
    this.route("game", { path: "/g/:slug" });
  });
}
