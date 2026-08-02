# frozen_string_literal: true

# The stamp only works if it changes exactly when the files do. Too sticky and
# a deploy leaves phones running old code (the Debris grey screen on iOS); too
# jumpy and every player redownloads games that did not change.

require "rails_helper"
require "tmpdir"
require "fileutils"

RSpec.describe ArcadeAssetsVersion do
  it "is a short hex stamp, safe to drop into a URL" do
    expect(ArcadeAssetsVersion.current).to match(/\A[0-9a-f]{12}\z/)
  end

  it "computes once and reuses it, since the files cannot change mid-process" do
    expect(ArcadeAssetsVersion.current).to equal(ArcadeAssetsVersion.current)
  end

  describe ".compute" do
    def tree(dir)
      games = File.join(dir, "games/demo")
      FileUtils.mkdir_p(games)
      File.write(File.join(games, "game.js"), "let a = 1;")
      File.write(File.join(games, "index.html"), "<html></html>")
    end

    it "is stable while nothing changes" do
      Dir.mktmpdir do |dir|
        tree(dir)
        expect(described_class.compute(root: dir)).to eq(described_class.compute(root: dir))
      end
    end

    it "changes when a file's content changes" do
      Dir.mktmpdir do |dir|
        tree(dir)
        before = described_class.compute(root: dir)

        File.write(File.join(dir, "games/demo/game.js"), "let a = 2;")

        expect(described_class.compute(root: dir)).not_to eq(before)
      end
    end

    it "changes when a file moves, even with the same content" do
      Dir.mktmpdir do |dir|
        tree(dir)
        before = described_class.compute(root: dir)

        FileUtils.mv(File.join(dir, "games/demo/game.js"), File.join(dir, "games/demo/main.js"))

        expect(described_class.compute(root: dir)).not_to eq(before)
      end
    end

    it "ignores timestamps, so a rebuild that rewrites mtimes busts nothing" do
      Dir.mktmpdir do |dir|
        tree(dir)
        before = described_class.compute(root: dir)

        FileUtils.touch(File.join(dir, "games/demo/game.js"), mtime: Time.now + 3600)

        expect(described_class.compute(root: dir)).to eq(before)
      end
    end
  end
end
