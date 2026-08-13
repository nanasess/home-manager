# Bluetooth オーディオ (T2 Mac + Bose QC Earbuds)

設定: `modules/bluetooth-audio/`（`nanasess@ubuntu` のみ）。2026-08-12 / 08-13 の実機調査に基づく。

接続不安定の原因は実際に 3 種類あった。いずれも「電波が弱い」「混線」ではなく、**単一コントローラ（Bluetooth / WiFi ワンチップ・アンテナ共用）の奪い合い**である。切り分けは下記 3 節の順で行う。

## 「接続がぷつぷつ切れる」はマルチポイントを最初に疑う

断続的な切断の真因は **イヤホン側のマルチポイント（iPhone との同時接続）** だった。他機器が A2DP スロットを掴んでいると `bluetoothd` が EBUSY を返し、15 秒周期の再接続ループに入る。

```text
a2dp-sink profile connect failed for <addr>: Device or resource busy
plugins/policy.c:reconnect_timeout() Reconnecting services failed: Device or resource busy (16)
```

iPhone とのペアリング解除で EBUSY はゼロになり、Link quality 255 / RSSI 0 で安定した。**設定では直せない運用上の問題**なので、再発時は WirePlumber や bluez をいじる前に他機器との同時接続を確認する。電波干渉や WiFi との coexistence を疑うのはその後。

## GNOME の Bluetooth 設定パネルを開きっぱなしにしない

このパネルは**開いている間ずっと inquiry + LE スキャンを回し続ける**。discovery 中はコントローラが取られ、音声リンクのスケジューリングが押しのけられる。2026-08-13 には**ペアリング情報ごと消し飛んだ**。

引き金は「パスキーのクロスデバイス認証」との組み合わせだった。FIDO2 の hybrid transport（caBLE）は iPhone を探すのに BLE を使うため、iPhone が RPA（Resolvable Private Address）でアドバタイズする。それを開きっぱなしのパネルが新規デバイスと見なして接続を試み、無線時間の奪い合いが決定的になった。

```text
gnome-control-c: Setting up /org/bluez/hci0/dev_5A_52_D5_CA_44_98 failed: ConnectionAttemptFailed: Page Timeout
bluetoothd: Wrong size of start discovery return parameters          ← スキャン開始
gnome-control-c: Setting up /org/bluez/hci0/dev_60_AB_D2_EE_4E_84 failed: InProgress   ← イヤホンが割り込めない
bluetoothd: Add Device complete for unknown device 60:AB:D2:EE:4E:84  ← ペアリング喪失
bluetoothd: avdtp.c:cancel_request() Open: Connection timed out (110)
```

アドレス先頭 2 ビットが `01` なら RPA（`0x5A` = `01`011010）。BLE のプライバシー用ランダムアドレスで、iPhone のアドバタイズと整合する。

スキャン状態の確認:

```bash
bluetoothctl show | grep -iE 'Discovering|Discoverable'
```

パスキー認証は BLE を使う仕様上、音切れを完全には避けられない。会議中に走らせない運用が無難。なお **`ControllerMode = bredr`（LE 無効化）でスキャン負荷を消す案は採用しないこと** — パスキーのクロスデバイス認証が使えなくなる。

デバイスを `trust` しておけば再接続にスキャンが不要になるので、パネルを開く機会自体を減らせる。

## ペアリングが壊れたら GUI で復旧する

`bluetoothctl` の**非対話モードの `pair` はボンドが確定しないこと**がある。実際 `Pairing successful` / `Paired: yes` の直後に `Paired: no` へ戻り、A2DP が `br-connection-unknown` で張れなかった。ペアリングエージェントの応答が絡むため、GNOME の設定パネル（開いたらすぐ閉じる）のほうが確実。

成否は `hcitool con` の**リンクモードで判定する**。`Paired: yes` の表示だけでは不十分:

```text
< ACL ... lm PERIPHERAL                    ← 失敗（未認証・未暗号化。A2DP を張れない）
> ACL ... lm CENTRAL AUTH ENCRYPT          ← 成功
```

BR/EDR 側で検出されているかは名前でも分かる。`LE-Bose QC Earbuds` は BLE アドバタイズ由来の名前で、この状態でペアリングしても A2DP に必要な BR/EDR のリンクキーは得られない。BR/EDR の inquiry は LE スキャンより時間がかかるため、**スキャン開始から 20 秒程度待って `Bose QC Earbuds`（`LE-` なし）になってから**操作する。

なお `btmgmt` は bluetoothd を迂回してカーネルの mgmt ソケットを直接叩くため、bluetoothd 稼働中のペアリングには使わない。

## 音が途切れるだけなら WiFi が 2.4GHz に落ちていないか見る

**リンク品質が最良値のまま音だけ途切れる**場合はこれ。切断もプロファイル切替も起きず、再生だけがぷつぷつする症状で現れる。

Bluetooth は 2.4GHz 固定なので、WiFi が同じ帯域に来ると直接干渉に加えてチップ内部の時分割も発生する。自宅 AP は同一 SSID で 3 バンド（ch 11 / ch 36 / ch 149）を出しており、バンドステアリングで 2.4GHz に寄せられることがある。

```bash
iwconfig wlp229s0 | grep -E 'Frequency|Bit Rate'
```

実測（2026-08-13、Chrome で Spotify を A2DP 再生中）:

```text
Frequency:2.462 GHz   Bit Rate=216.6 Mb/s   ← 音が途切れる（ch 11 = Bluetooth と同帯域）
Frequency:5.745 GHz   Bit Rate=1.17 Gb/s    ← WiFi 再接続後、5 分間 30/30 サンプル正常
```

**`hcitool lq` / `rssi` を見ても分からない**のが厄介な点。これらは BR/EDR リンクの受信品質を示す指標で、同一チップ内での WiFi との時分割は反映しない。実際、途切れている最中も `Link quality: 255`（最大）/ `RSSI: 0`（ゴールデンレンジ）のままだった。**電波が良好なのに音が飛ぶときは、リンク品質ではなく WiFi の周波数を見る。**

対処は WiFi を 5GHz に再接続するだけ。**`nmcli connection modify <conn> 802-11-wireless.band a` による 5GHz 固定は採用しない** — 会議で使う個室には 5GHz が届かず、フォールバックしないため圏外になる。

会議時の影響は相対的に小さい。HFP（mSBC 16kHz モノラル、約 60〜90kbps）は A2DP ステレオ（SBC、約 200〜320kbps）の 1/3 以下しか帯域を使わないため、同じ 2.4GHz 環境でも競合の圧力が低い。つまり「個室でステレオ再生」が最も厳しい条件になる。

次の候補は WiFi の省電力無効化（現在 `/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf` で `wifi.powersave = 3`）。省電力のスリープ/復帰のたびに共存の調停がリセットされるため。**未検証**（5GHz では競合しないため検証機会がない）。2.4GHz の個室で乱れたときに `sudo iw dev wlp229s0 set power_save off` で一時的に試すこと。バッテリー消費と引き換えになる。

## A2DP（ステレオ）と HFP（マイク）は排他

Bluetooth Classic の仕様上、両立できない。

| プロファイル | 出力 | マイク |
|---|---|---|
| `a2dp-sink` | ステレオ SBC | なし |
| `headset-head-unit-msbc` | モノラル 16kHz | あり |

A2DP は片方向でマイクの戻りチャンネルを持たず、マイクには SCO/eSCO を使う HFP が必要で、SCO は狭帯域モノラルしか通せない。回避技術（双方向 A2DP の `faststream_duplex` / `aptx_ll_duplex`、LE Audio の `bap-*`）は PipeWire 側が対応していても **Bose QC Earbuds が非対応**で、`pw-dump` の `EnumProfile` に現れないことを確認済み。これは OS 非依存で Windows でも同じ。

## 自動プロファイル切替を無効化している

WirePlumber の既定では、`/usr/share/wireplumber/policy.lua.d/10-default-policy.lua` の `media-role.applications` に載ったアプリが**実際にマイクを掴んだ**時点で A2DP → HFP へ自動切替する。`"Google Chrome input"` が含まれるため、Chrome のどこか 1 タブがマイク権限を使っているだけで、同じブラウザで再生している音楽まで mSBC 16kHz モノラルに巻き添えになる。

`51-disable-headset-autoswitch.lua` でこれを無効化し、**運用は pavucontrol での手動切替**（音楽 = `a2dp-sink` / 会議 = `headset-head-unit-msbc`）に統一した。

現在のプロファイルの確認（`select` を `Device` 型に絞らないと、同じ `device.api` を持つ
Node オブジェクト 2 件を拾って `null` 行が混ざる）:

```bash
pw-dump | jq -r '.[]
  | select(.type == "PipeWire:Interface:Device" and .info.props."device.api" == "bluez5")
  | "\(.info.props."device.description"): \(.info.params.Profile[0].description)"'
```

実機での出力:

```text
Bose QC Earbuds: High Fidelity Playback (A2DP Sink, codec SBC)   ← ステレオ
Bose QC Earbuds: Headset Head Unit (HSP/HFP, codec mSBC)         ← HFP（モノラル）
```

## プロファイルの記憶は home-manager 管理外

WirePlumber は選択したプロファイルを `~/.local/state/wireplumber/default-profile` に記憶し、再接続時に復元する。ランタイム状態なので宣言的管理の対象外。

- 記憶が HFP のままだと、自動切替を無効化しても再接続時に HFP で繋がる
- 当該行を削除すると優先度による選択（`a2dp-sink` が prio 18 で最大）にフォールバックする
- `wpctl set-profile` では**この記憶が更新されない**。pavucontrol など UI 経由の選択なら保存される

## GNOME にはプロファイル選択 UI がない

GNOME Settings (46) にプロファイルのドロップダウンはない。A2DP 中はイヤホンのマイクがソース一覧に出ないため、GUI から HFP に戻す手段が pavucontrol しかない。`modules/bluetooth-audio/` が pavucontrol を同梱しているのはこのため。

## WirePlumber 0.4 の Lua 設定形式

`51-disable-headset-autoswitch.lua` は WirePlumber 0.4 系の Lua 形式。**0.5 以降は `.conf` ベースの新形式になり本ファイルは無視される**ため、Ubuntu 側の wireplumber を上げるときは要追従。
