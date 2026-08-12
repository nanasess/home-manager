-- Bluetooth ヘッドセット (HFP/HSP) への自動プロファイル切替を無効化する。
--
-- WirePlumber の既定では、録音ストリームを持つアプリが「マイクを実際に掴んだ」
-- 時点で A2DP → headset-head-unit へ自動的に切り替わる。対象アプリは
-- /usr/share/wireplumber/policy.lua.d/10-default-policy.lua の
-- bluetooth_policy.policy["media-role.applications"] に列挙されており、
-- "Google Chrome input" や "ZOOM VoiceEngine" が含まれる。
--
-- HFP に落ちるとそのデバイスの「全音声」が mSBC 16kHz モノラルになる。実機で
-- 確認した挙動 (2026-08-12):
--   * sink のポートが playback_FL/playback_FR → playback_MONO になる
--   * api.bluez5.codec = "msbc" / factory.name = "api.bluez5.sco.sink" (SCO 転送)
--   * hcitool con に eSCO リンクが現れる
-- Chrome のどこか一つのタブがマイク権限を使っているだけで発火するため、同じ
-- ブラウザで再生している音楽まで巻き添えでモノラルになっていた。
--
-- 注意: bluetooth_policy は 10-default-policy.lua が定義するグローバル。
-- 読み込み順が崩れて未定義だった場合に wireplumber の起動ごと落とさないよう、
-- 存在チェックを挟んでから代入する。
bluetooth_policy = bluetooth_policy or {}
bluetooth_policy.policy = bluetooth_policy.policy or {}
bluetooth_policy.policy["media-role.use-headset-profile"] = false
