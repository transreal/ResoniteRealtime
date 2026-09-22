# タブレット仕様 v0.1 — ClaudeEval をワールド内で再現する (2026-09-22)

`ResoLoop_info/design/resoloop_integration_spec_v0_1.md` の続き。ユーザー指示 (2026-09-22):
「音声の前に ClaudeEval をワールド内で実行できる実装を優先。タブレットのようなガジェット (ChatInput / Eval / 出力) と、
それを支える仕組みを ResoniteRealtime に追加。SourceVault にアクセスする一般のプロンプトを実行。アクセスレベルは
オーナーのプライベート 1.0 / フレンド 0.5 / フレンド+・パブリック 0.25、オーナー以外は一律 0.25、それ以上の PL は表示しない。
承認・キャンセルのボタン。スクロールテキスト。数式・グラフはスクリーンショット画像。SourceVault オブジェクトを
ワールド内に表示する一般 API。View 関数のリスティングガジェット (ボタンで PDF ビューア)。できる限りノートブック上の動作を
Resonite に適したやり方で再現する。これを支えるのが ResoniteRealtime の最大の目的。」

## 1. 方針

- **ノートブックを本当に使う**。タブレットの Eval は専用ノートブック「Resonite Tablet」に Input セルを書いて評価する
  (= ユーザーが Shift+Enter したのと同じ)。ClaudeEval の全機能 (提案コードの実行、NBAccess の検証・承認、
  結果セル、継続、記録) をそのまま使い、タブレットは**鏡**に徹する。
- runtime 経路 (`$UseClaudeRuntime = True` を Block) を使う理由: 承認が非ブロックの状態 (`AwaitingApproval`) と
  プログラム API (`ClaudeApproveProposal` 等) を持つ。旧経路の承認はモーダルダイアログでワールドから押せない。
- 表示は**鏡の出口で漉す**: 増えたセルを `NBCellExprPrivacyLevel` で見て表示上限を超えるものを注記に置き換える。
  数値が取れないものは出さない (fail-closed)。LLM に渡す AccessLevel は別途 `Min[表示上限, 0.5]`。
- 世界側の作業ゼロ (chat と同じ): UIX は ResoniteLink だけで組む。ボタンは Button + ValueField<bool> + ButtonToggle。

## 2. 構成要素

| 層 | もの | 置き場 |
|---|---|---|
| ワールド | タブレット / ビューア (板) / 一覧ガジェット / 動画の板 | `ResoniteRealtime_tablet.wl` |
| ノートブック | 「Resonite Tablet」(SourceVault default.nb スタイル) に `ResoniteTabletTurn["..."]` セル | 同上 |
| claudecode | `ClaudeRuntimeDecide[rid, "Approve" \| "Deny" \| {"ApproveTimeout", s} \| "Cancel"]` (承認セルのボタンと同じ処理をダイアログ無しで) | `claudecode.wl` |
| chat | 表示上限 4 段 + `$ResoniteWorldOwner`、release context 4 つ、世界起点の文字の機密度 | `ResoniteRealtime_chat.wl` |
| 規則 | `110-resonite-tablet.md` (ShowObject / ListGadget / View 不使用 / 短く) | `Claude Directives/rules/` |
| NBAccess | 表示 API を許可ヘッド 2 層登録、削除系は承認ヘッド | `ResoniteTabletRegisterHeads[]` |

## 3. ターンの状態機械 (tick 毎)

```
Eval 押下 ─→ Starting ($ClaudeLastRuntimeId が変わるのを待つ。90 s で Finishing)
Starting ─→ Running (ClaudeRuntimeState[rid]["Status"])
Running ─→ AwaitingApproval: 承認行を有効化 + 説明/式を出力欄へ (同じ pending は 1 回だけ)
        ─→ Done / Failed / Cancelled: Finishing
Finishing ─→ セル数が 2 tick 安定 → 描画 (平文 + ページ画像) → Done
承認/拒否/中止 ─→ ClaudeRuntimeDecide を別 ScheduledTask で (tick は待たない)
```

## 4. 一般表示 API `ResoniteShowObject`

| 入力 | 判定 | 出口 |
|---|---|---|
| sv:// URI | `SourceVaultObjectPrivacyLevel` ≤ 上限 | Properties.FilePath → ResolveReference.File → ObjectData の順に解決し、ファイル/画像/文字へ |
| 共通スキーマ行 | `PrivacyLevel` キー (無ければ URI、それも無ければ 1.0) | mail → `SourceVaultMailGetBody`、他 → File → URI |
| ファイル | 拡張子 | pdf=ページ、画像、動画=`ResoniteVideoBoard`、nb=ラスタライズ、テキスト |
| Image / Graphics / 式 | — | ページ画像 (縦長は 1200 px ごとに分割) |
| 行リスト | 行ごとに PL | `ResoniteListGadget` (上限超は落として件数を表示) |

## 5. 実装記録

- (a) 2026-09-22 `ResoniteRealtime_tablet.wl` 新規 (タブレット / ビューア / ShowObject / ListGadget / VideoBoard)、
  `ResoniteRealtime_chat.wl` の表示上限 4 段化、`claudecode.wl` に `ClaudeRuntimeDecide`、規則 110、
  `test codes/ResoniteRealtime_tablet_test.wls` (ResoniteLink モック、claudecode / ClaudeRuntime / NBAccess は公開名のスタブ)。
- 実測: ResoniteLink の enum は `<|"$type"->"enum","value"->"MinSize"|>`、`updateSlot` の `isActive` で有効/無効、
  ヘッドレス kernel でも `UsingFrontEnd` で Rasterize / PDF ページ import / Notebook の Rasterize が動く。
- (b) 2026-09-22 予約した組み立てを tick 駆動の非同期ビルド (Send → getSlot → 結線、失敗時は残骸削除) に変更
  (`$ResoniteTabletBuildMode`)。ノートブックのセル予約は runtime の非同期タスクと待ち合って 2 回固着したため tick 無しの fallback のみ。
  空の板は最初のページまで isActive False (市松模様対策)。テスト 117 件。
- 未実機: §tablet.md「未検証」。次 = ユーザーのノートブック kernel で `ResoniteTablet[]` → Eval → 承認 → 結果、
  `ResoniteListGadget[SourceVaultArXiv["LLM"]]` → ▶ → PDF。

## 6. 後続

- 世界の所有者/公開度の自動検出 (ResoniteLink 0.13 には無い。resoloop `discover` も sessionName のみ)。
- ScrollRect の位置制御 (NormalizedPosition の向き) と Text の折り返し実測 → MinHeight 見積りの係数調整。
- 動画の再生制御 (Playback)。
- 音声 (F4–F6) はこのタブレットの上に載せる (音声入力 = 入力欄への書き込み + Eval)。
