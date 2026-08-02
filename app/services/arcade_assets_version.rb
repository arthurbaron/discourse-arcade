# frozen_string_literal: true

# Everything under /plugins/ is served with "cache for a year and never ask
# again" (nginx marks it immutable). That is right for Discourse's own bundles,
# which get a digest in their filename on every build, but our game files keep
# the same URL forever, so a phone holds whatever copy it saw first. That is
# how Debris broke on iOS: a cached pre-Debris copy of the shared helper next
# to fresh game code.
#
# So every game asset URL carries a stamp of the games tree's content. A deploy
# that changes any game file changes the stamp, which changes the URL, which
# makes every browser fetch fresh. A deploy that changes nothing leaves every
# cache warm.
class ArcadeAssetsVersion
  def self.current
    @current ||= compute
  end

  # Content, not mtimes: a rebuild rewrites timestamps on files that did not
  # change, and those caches should stay warm.
  def self.compute(root: File.expand_path("../../public", __dir__))
    digest = Digest::SHA1.new

    Dir
      .glob(File.join(root, "{games,images}/**/*"))
      .sort
      .each do |path|
        next unless File.file?(path)
        digest << path.delete_prefix(root)
        digest << File.binread(path)
      end

    digest.hexdigest[0, 12]
  end
end
