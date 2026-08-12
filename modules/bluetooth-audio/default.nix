{ config, pkgs, ... }:
# Bluetooth オーディオ (A2DP / HFP) の挙動を home-manager 管理下に置くモジュール。
#
# 背景 (T2 MacBook + Bose QC Earbuds, 2026-08-12 の実機調査):
#
#  - 「接続がぷつぷつ切れる」の真因はイヤホン側のマルチポイントだった。iPhone と
#    同時接続していると A2DP スロットが埋まり、bluetoothd が
#    `a2dp-sink profile connect failed: Device or resource busy` (EBUSY) を返して
#    15 秒周期の再接続ループに入る。iPhone とのペアリング解除で EBUSY はゼロになり、
#    Link quality 255 / RSSI 0 で安定した。設定では直せない運用の問題なので、
#    本モジュールでは扱わない (再発時はまず他機器との同時接続を疑うこと)。
#
#  - それとは別に、WirePlumber の自動プロファイル切替が音質を落としていた。
#    Chrome のタブが一つでもマイクを掴むと A2DP → HFP (mSBC 16kHz モノラル) に
#    落ち、同じブラウザで再生している音楽まで巻き添えになる。本モジュールは
#    こちらを扱う。
#
# 方針: 常に A2DP ステレオで使う。自動切替を止めると、WirePlumber は優先度が
# 最大のプロファイル (a2dp-sink, prio 18) を選ぶようになる。会議のマイクは
# MacBook 内蔵マイク (Apple Audio Device BuiltinMic) を使う。
#
# Bluetooth Classic の仕様上、A2DP (ステレオ出力) と HFP (マイク) は排他で、
# 同時には使えない。このイヤホンは双方向 A2DP (faststream/aptx_ll_duplex) にも
# LE Audio (bap) にも非対応で、逃げ道がないことを pw-dump の EnumProfile で確認済み。
# → イヤホンのマイクがどうしても要る場面は pavucontrol の「設定」タブで
#   headset-head-unit-msbc へ手動切替する。
#
# 注意 1: WirePlumber は選択したプロファイルを ~/.local/state/wireplumber/default-profile
# に記憶して再接続時に復元する。過去に HFP を選んでいると自動切替を止めても HFP が
# 蘇るため、導入時に当該行を削除した (削除すると優先度による選択にフォールバックする)。
#
# 注意 2: WirePlumber 0.4 系の Lua 設定形式。0.5 以降は .conf ベースの新形式に
# なり本ファイルは無視されるため、Ubuntu 側の wireplumber を上げるときは要追従。
#
# 適用範囲: ユーザー空間のみ (sudo 不要)。ロールバックは flake.nix の modules から
# 本モジュールを外して home-manager switch するだけ。
{
  # WirePlumber は $XDG_CONFIG_HOME → /etc → /usr/share の順で *.lua.d を読み、
  # 同名ファイルは上位が下位を隠す。50 番の既定より後に読ませたいので 51 を付ける。
  xdg.configFile."wireplumber/policy.lua.d/51-disable-headset-autoswitch.lua".source =
    ./51-disable-headset-autoswitch.lua;

  # プロファイルを手動で切り替える GUI。GNOME Settings (46) にはプロファイル
  # 選択 UI がなく、A2DP 中はイヤホンのマイクがソース一覧にも出ないため、
  # HFP に戻す手段がこれしかない。「設定」タブで a2dp-sink /
  # headset-head-unit-msbc を直接選ぶ。
  home.packages = [ pkgs.pavucontrol ];

  # ランチャー (GNOME アプリ一覧 / Walker) 登録用の .desktop。
  #
  # nixpkgs の pavucontrol は org.pulseaudio.pavucontrol.desktop を
  # ~/.nix-profile/share/applications/ に置くが、GNOME セッションの
  # XDG_DATA_DIRS は /usr/local/share:/usr/share:/var/lib/snapd/desktop だけで
  # ~/.nix-profile/share を含まないため、そのままではランチャーに出てこない
  # (ログインシェルの XDG_DATA_DIRS には入っているので、端末からは起動できる)。
  # そこで XDG_DATA_HOME 配下に自前のエントリを置く。Ghostty (hosts/ubuntu.nix) と
  # 同じ回避策。
  #
  # 副作用として Exec / Icon も解決できないため、いずれも profileDirectory 経由の
  # フルパスで指定する (store パスを直書きすると更新のたびに切れる)。ここを
  # ~/.nix-profile と直書きしないのは、NixOS の nix.useUserPackages 等では
  # プロファイルが /etc/profiles/per-user/<user> になり解決に失敗するため。
  #
  # 根治するなら targets.genericLinux.enable = true で XDG_DATA_DIRS ごと直す手も
  # あるが、セッション全体に影響するため本モジュールでは踏み込まない。
  #
  # Categories から Settings を外している。上流の .desktop は AudioVideo と併記して
  # いるが、どちらもメインカテゴリのためメニューに二重登録されうる
  # (desktop-file-validate の hint)。Audio はメインカテゴリだが AudioVideo との
  # 併記が仕様上必須 (単独だと desktop-file-validate が error) なので残す。
  xdg.dataFile."applications/org.pulseaudio.pavucontrol.desktop".text = ''
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=Volume Control (pavucontrol)
    Name[ja]=音量調節 (pavucontrol)
    GenericName=Volume Control
    GenericName[ja]=音量調節
    Comment=Adjust volume and switch Bluetooth profiles (A2DP / HFP)
    Comment[ja]=音量調整と Bluetooth プロファイル切替 (A2DP / HFP)
    Exec=${config.home.profileDirectory}/bin/pavucontrol
    Icon=${config.home.profileDirectory}/share/icons/hicolor/scalable/apps/org.pulseaudio.pavucontrol.svg
    Terminal=false
    StartupNotify=true
    Categories=AudioVideo;Audio;Mixer;GTK;
    Keywords=pavucontrol;PulseAudio;PipeWire;Volume;Bluetooth;A2DP;HFP;音量;
  '';
}
