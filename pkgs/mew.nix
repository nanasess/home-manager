{ lib, stdenv, fetchFromGitHub, ruby, zlib }:

# Mew (Emacs のメーラ) が外部コマンドとして呼ぶ bin/ 配下を Nix でパッケージ化する。
#
# elisp 側は elpaca (modules/emacs/init.el の use-package mew) で管理し、ここでは
# ネイティブ依存だけを扱う (cmigemo と同じ扱い)。nixpkgs の `mew` は無関係な
# dmenu の Wayland 移植で、`emacsPackages.mew` は MELPA の elisp のみで bin/ を
# 含まないため自作する。
#
# 含まれるもの:
#   mewl / mewencode (mewdecode, mewcat) / incm -- C。Summary の走査と MIME エンコード
#   cmew / smew   -- Ruby + sqlite3。Message-ID: DB (スレッド追跡) の作成と検索
#   mew-pinentry  -- sh。gpg 用の簡易 pinentry
# 含めないもの:
#   mewest -- Hyper Estraier (estcmd) 前提だが nixpkgs に無い。全文検索は
#             mew-summary-pick (grep) で代替する
#
# elisp と同じコミットに固定する (modules/emacs/elpaca.lock の mew の :ref)。
# 更新時は両方を揃えて上げること。
let
  rubyWithSqlite = ruby.withPackages (ps: [ ps.sqlite3 ]);
in
stdenv.mkDerivation rec {
  pname = "mew-bin";
  version = "6.11-unstable-2026-10-24";

  src = fetchFromGitHub {
    owner = "kazu-yamamoto";
    repo = "Mew";
    rev = "a9a82848cd125ef8aa1404b05f2ce15cfc8dddf1";
    hash = "sha256-nna2CQOScoy4eG3Om40WqTz5IEl+jRjVuhJlEp8IaQc=";
  };

  # bin/ は独立した configure (autoconf 生成済み) を持つのでそこだけビルドする。
  sourceRoot = "${src.name}/bin";

  # zlib: mewencode の gzip64 エンコードが使う (configure の AC_CHECK_LIB(z))。
  # ruby: cmew / smew の `#!/usr/bin/env ruby` を sqlite3 gem 入りの ruby に
  #       差し替えるため。fixupPhase の patchShebangs は $out 配下を --host で
  #       処理し、interpreter を HOST_PATH (= buildInputs) から解決するので
  #       nativeBuildInputs では見つからない。実行時依存でもあるのでここが正しい。
  buildInputs = [ zlib rubyWithSqlite ];

  postInstall = ''
    rm $out/bin/mewest
    rm -f $out/share/man/man1/mewest.1
  '';

  meta = with lib; {
    description = "Mew (Emacs mail reader) の外部コマンド群 (mewl, mewencode, incm, cmew, smew)";
    homepage = "https://www.mew.org/";
    license = licenses.bsd3;
    platforms = platforms.unix;
  };
}
