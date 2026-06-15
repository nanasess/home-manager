{ ... }:
{
  # Claude Code のユーザーレベル設定のうち、宣言的に管理したいものだけを
  # home-manager 経由で ~/.config/claude/ へ symlink する。
  #
  # 対象は CLAUDE.md (全プロジェクト共通指示) のみ。
  # settings.json はこのモジュールでは扱わない:
  #   - Claude Code は実行時 state (theme / feedbackSurveyState / verbose 等) を
  #     settings.json ではなく ~/.config/claude/.claude.json に書き込むため、
  #     read-only symlink でも実害は小さいが、/config・update-config による
  #     settings.json への明示的書き込みは失敗する。
  #   - その他の ~/.config/claude/ 配下 (.claude.json, projects/, sessions/ 等) は
  #     Claude Code が自由に書き込む runtime ディレクトリのため管理対象外。
  #
  # 注意: ~/.config/claude は別 git リポジトリ (nanasess/claude.git) でもあり、
  # symlink 化により当該リポジトリ側では CLAUDE.md が type-changed として見える。
  xdg.configFile."claude/CLAUDE.md".source = ./CLAUDE.md;
}
