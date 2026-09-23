# タブレット — ClaudeEval を Resonite ワールド内で走らせる

`ResoniteRealtime_tablet.wl` (ResoniteRealtime.wl が自動ロード。chat ガジェットのヘルパの上に載る)。
2026-09-22 起草。ワールド内のタブレットに打ったプロンプトを、ノートブックの ClaudeInput セルを評価したのと
**同じ処理** (ClaudeEval の runtime 経路: 提案コードの実行、承認、結果セル) で走らせ、結果をワールドへ出す。

## できること

- タブレット (UIX パネル): 入力欄 / **Eval** / Clear / Cancel / 状態行 / **承認・拒否** (承認待ちのときだけ有効) /
  **スクロールする出力欄** (Mask + ScrollRect + ContentSizeFitter) / 画像ビューア (板) と ◀ n/N ▶ 閉じる。
- Eval → 専用ノートブック「Resonite Tablet」に `ResoniteTabletTurn["..."]` の Input セルを書いて評価
  (中身は `ClaudeEval`。`$UseClaudeRuntime` を Block で True にして runtime 経路。あわせて `$ClaudeEvalMode = "Single"`、
  PromptRouter / natural dispatch を False にして ClaudeOrchestrator へ回らないようにする。2026-09-22: Eagle の PDF 一覧が
  オーケストレーションに回り、runtime が無いままタブレットが Pending の連想だけ描いた)。それでも `OrchJobId` が返ったときは
  `ResoniteTabletNoteTurnResult` が控えて `ClaudeOrchestrationStatus` の完了まで見張り、ノートブックに書かれた結果を描く。
- 承認待ち → タブレットに理由と式を出し、承認/拒否ボタン。押すと claudecode の `ClaudeRuntimeDecide` が
  ノートブックの承認ボタンと同じ処理 (runtime 再開 → 結果セル表示)。タイムアウト延長 (`TimeoutExtension`) は
  LLM が見積もった秒数で延長承認。
- 完了 → ターン開始後に増えたセルを機密度でふるい、平文を出力欄へ、ラスタライズしたページ画像をビューアへ。
  Dynamic/Button 入りのセル (承認 UI 等) は落とす。ページは幅 1000 px (`ImageResolution -> 144` + `PageWidth` で
  折り返し。Notebook の Rasterize は画面 DPI で膨らみ `ImageSize` は上限にならない。2026-09-22 実機)、
  高さ 1000 px で割り、分割した最後のページは白で埋めて高さを揃える (板の大きさがページ送りで変わらない)。
- `ResoniteShowObject[x]`: SourceVault オブジェクト (sv:// URI / 共通スキーマ行 / ファイル / 画像 / 式 / 行リスト) を
  ワールドへ。PDF はページ送り、動画は `ResoniteVideoBoard`、本文は出力欄、行リストは `ResoniteListGadget`。
- `ResoniteListGadget[rows]`: core 関数 (`SourceVaultArXiv` 等) の行リストをボタン付き一覧に。▶ でビューアへ。

## 手順

### Resonite 側から使う (インベントリのタブレット + 「接続」ボタン) — 2026-09-22

一度 `ResoniteTablet[]` で作ったタブレットは Resonite のインベントリに保存しておける。以後は

1. Mathematica で `Get["ResoniteRealtime.wl"]` (claudecode / SourceVault / NBAccess はロード済みの前提)。ノートブックのセッションでは
   ロード時に **常駐監視 `ResoniteTabletServe[]` が自動で始まる** (`$ResoniteTabletAutoServe`)。
2. Resonite で ResoniteLink を有効化 (ホストであること)。ポートは **自動検出** (`ResoniteRealtimeDiscover[]` = Windows の http.sys
   登録一覧 `netsh http show servicestate` から Resonite / Renderite.Host が登録した `HTTP://LOCALHOST:<port>/` を拾う。即時。
   無ければ resoloop discover、環境変数 RESONITE_LINK_URL)。常駐監視が 15 秒ごとに探して繋ぐ。
3. インベントリからタブレットを出して **「接続」** を押す。常駐監視が Root 直下の "Mathematica Tablet" を 5 秒ごとに見ていて、
   「接続」の ValueField が True のものをスロット名とコンポーネント型で読み取り (`itParseTabletTree`。ID はインベントリ経由で
   付け直されているので名前だけが頼り)、このカーネルのタブレットとして引き継ぐ (`ResoniteTabletAdopt`)。状態欄が
   「接続しました (PL<=…)」になれば使える。

ノートブックから明示的にやるなら `ResoniteRealtimeLinkConnect[]` → `ResoniteTabletFind[]` → `ResoniteTabletAdopt[root]`。
常駐監視は ResoniteLink の応答が 5 回続けて途絶えたら切断して再探索に戻り、ワールドから消えたタブレット (getSlot が 3 回失敗) は
台帳から外す。`ResoniteTabletServe[False]` で止める。

### ノートブックから作る

```mathematica
Get["ResoniteRealtime.wl"];                     (* claudecode / SourceVault / NBAccess はロード済みの前提 *)
ResoniteRealtimeLinkConnect[];                  (* ResoniteLink (常時オン)。ポートは自動検出。明示なら [port] *)
ResoniteAccessLevel["Private", "Owner" -> True];  (* 自分のプライベートワールド → 表示上限 1.0 *)
ResoniteTablet[]                                (* 正面 1.2 m にタブレット + 板。監視も始まる *)
```

ワールド側: 入力欄に打って **Eval**。承認が要るときはタブレットの **承認 / 拒否**。図はビューアに映る。
ノートブック側でも同じことができる: `ResoniteTabletEval["..."]`, `ResoniteTabletApprove[]`, `ResoniteTabletDeny[]`,
`ResoniteTabletCancel[]`, `ResoniteTabletShow[text | expr]`, `ResoniteTabletStatus[]`, `ResoniteTabletLog[]`。
片付け: `ResoniteTabletRemove[]` (`ResoniteListGadgetRemove[]`, `ResoniteViewerRemove[]`)。

## 表示上限 (アクセスレベル)

| ワールド | オーナー | 表示上限 PL |
|---|---|---|
| Private | ○ | 1.0 |
| Contacts | ○ | 0.5 |
| ContactsPlus / Public | ○ | 0.25 |
| どれでも | × (既定) | 0.25 |

- 所有者と公開度は ResoniteLink から取れないので **手で設定する**: `ResoniteAccessLevel[kind, "Owner" -> True]`。
  既定は非オーナー (0.25)。
- 表示: セルは `NBCellExprPrivacyLevel`、行は `PrivacyLevel` キー、sv:// は `SourceVaultObjectPrivacyLevel`。
  **数値が取れないものは出さない (fail-closed)**。上限を超えたセルは「[非表示: 機密度 …]」の注記に置き換わる。
- LLM に渡す `PrivacySpec -> <|"AccessLevel" -> …|>` は `Min[表示上限, $ResoniteTabletCloudMaxLevel (0.5)]`。
  `ResoniteTablet["Model" -> ローカルモデル]` のときだけ表示上限と同じ。
- ワールドで打った文字の機密度 (chat と共通 `icPromptPrivacy`) は Private 1.0 / Contacts 0.5 / それ以外 0。

## パネルの構成 (すべて ResoniteLink で組み立て)

```
<Name>                 Grabbable, AI_GeneratedContent
├─ Panel               Canvas 1000x1500 (単位) を PanelScale 0.0006 で縮小 = 0.6 m x 0.9 m
│  └─ VLayout          VerticalLayout
│     ├─ Title         Text (名前 + [PL<=x.xx kind])
│     ├─ Input         Image + Button + TextEditor + TextField / Text
│     ├─ ButtonRow     [Eval] [Clear] [Cancel] [3D生成] [接続]   ← Button + ValueField<bool> + ButtonToggle
│     ├─ Status        Text
│     ├─ ApprovalRow   [承認] [拒否] + ラベル         ← isActive=False。承認待ちのときだけ有効
│     ├─ Output        Image + Mask
│     │  └─ Content    RectTransform (上端固定) + VerticalLayout + ContentSizeFitter(VerticalFit=MinSize) + ScrollRect
│     │     └─ Text    LayoutElement (MinHeight = 文字数から見積り) + Text
│     └─ ViewerBar     [<] [n/N] [>] [閉じる]
└─ Tablet Viewer       ResoniteRealtimeBoard (パネルの右隣。ページ画像を映す)
```

- enum は `<|"$type" -> "enum", "value" -> "MinSize"|>` で書ける (2026-09-22 実測。数値や型名指定は弾かれる)。
- スロットの有効/無効は `updateSlot` の `isActive`。
- ボタンは chat と同じ「Button + ValueField<bool> + ButtonToggle (メンバ ID 結線)」。WL が Value を読んで False に戻す。

## 図が板に出ないとき (2026-09-22)

runtime の表示セル (実行結果の図) は LLM の応答セルより後に書かれることがあり、タブレットが「セル数が 2 tick 安定」で描いた時点では
無いことがあった (実機: ガンマ関数の Plot が板に出ず、テキストだけ)。対策は 2 段:

1. **表示 stash**: 実行時に `$ClaudeRuntimeDisplayHook` で拾った生の結果のうち図 (Graphics / Graphics3D / Legended / Image) を runtime ごとに
   `StashDisplay` に取っておき、結果セルに図が無いターンではそこからページを描く (`itStashDisplayCells`。機密度は同じ上限で判定)。
2. **遅れて来たセル**: Done の後 `$itLateCellSeconds` (180 s) の間に結果セルが増えたら Finishing に戻して描き直す (ログは同じ記録を置き換える)。

## 監視 (ScheduledTask 1 本、既定 1 秒)

- tick では待たない: `getSlot` を `"Wait" -> False` で送り、次の tick で `sourceMessageId` を照合 (chat と同じ 2 相)。
  対象はタブレットの根と一覧ガジェットの根を交互に。
- 同じ tick で runtime を見張る (`ClaudeRuntimeState`): Starting (`$ClaudeLastRuntimeId` が変わるのを待つ) →
  Running → AwaitingApproval (承認 UI) → Done/Failed → Finishing (セル数が 2 tick 安定するまで待つ) → 描画。
  終端の後に承認待ちへ戻ることがある (実行タイムアウト → 失敗 → 修復ターンが延長申告で再提案。2026-09-22 実機) ので、
  Finishing の間と Done の後 600 秒 (`$itDoneWatchSeconds`) は状態を見張り、AwaitingApproval / Running に戻ったらターンを再開する。
  タブレットの出力には診断用 Code セルとノートブック側の承認 UI ブロック (CellTags `claudecode-approval-*`) を出さない。
- FrontEnd を触るのはターン開始のセル書き込み/評価と完了時のラスタライズだけ。
- 承認/拒否/中止は別の ScheduledTask に投げる (`ClaudeRuntimeDecide` は実行を伴う)。
  runtime が `AwaitingApproval` でなければ送らない (押し直し / 古い読み取りで、後から来た別の提案を勝手に承認しない。2026-09-23)。
  承認したら出力欄の「承認が必要です」は「承認しました。実行しています ...」に置き換える。
- 「実行中」には内訳を付ける (`itRunPhaseLabel`): runtime の DAG にまだノードがあれば「LLM 応答待ち」、CurrentPhase が
  Execute なら「式を実行」。2026-09-23 実機: 承認後、続きの LLM 応答 (claude CLI) に 10 分かかり、何をしているか分からなかった。

## 承認 UI がノートブックに残る問題 (2026-09-23、修正済み)

タブレットで承認しても、ノートブック側の承認 UI (❓ 通知 / NeedsApproval セル / 承認・中止ボタン、CellTags
`claudecode-approval-<rid>`) はそのまま残っていた。しかも承認後の結果セル (提案コード / 出力 / ContinueEval 行) はジョブの
アンカー直後 = 承認 UI より**上**に挿入されるので、ノートブックの末尾に押せる承認ボタンが残り「2 度目の承認要求」に見えた。
押すと `ClaudeApproveProposal` は `NotAwaitingApproval` を返して無言 (runtime は Running で続きの LLM 応答待ち)。
対策 (claudecode.wl): `ClaudeRuntimeDecide` が承認 / 拒否 / 中止のときにそのタグのセルを消し、アンカー直後に
「✅ ワールド内タブレットで承認しました」を書く。ノートブックの承認ボタンも、処理済みなら案内 (`iRuntimeNotAwaitingNotice`) だけ書いて
`iRuntimeDisplayResult` を呼ばない (結果セルの二重書き防止)。

## LLM への指示

プロンプト先頭に `[Resonite tablet]` と表示上限、`ResoniteShowObject` / `ResoniteListGadget` の使い方を付ける
(`itPromptWithContext`)。規則 `Claude Directives/rules/110-resonite-tablet.md` も同じ内容。
表示 API は NBAccess の許可ヘッドに 2 層登録 (`ResoniteTabletRegisterHeads[]`、ロード時自動) するので、
LLM の提案コードが `ResoniteListGadget[SourceVaultArXiv["LLM"]]` を呼んでも承認は要らない。
削除系 (`ResoniteTabletRemove` 等) は承認ヘッド。
2026-09-23: 「クリックしたら赤と青の色が変わる Box」は `ResoniteColorToggleBox[{Red, Blue}]` 1 つで作るよう指示する
(状態確認 `ResoniteRealtimeStatus` / `ResoniteFluxCatalogSearch` は許可ヘッドにしたが「不要」と伝える。
実機では LLM がまず状態確認を提案 → 承認 → 続きの応答に 10 分 → 本題に進めなかった)。

## 未検証 (2026-09-22)

- 実機: ScrollRect のドラッグスクロール、`NormalizedPosition -> {0,1}` が「上端」か、Text の折り返しと
  MinHeight の見積り (ASCII 0.55 em / それ以外 1.0 em)、Mask のクリップ、ボタンのラベル配置。
- `ResoniteVideoBoard` の再生開始 (VideoTextureProvider の Playback は未操作)。
- `SelectionEvaluate` を ScheduledTask の中から呼んで FE がセルを評価するか (ノートブックの kernel で確認する)。
- 承認後の結果セル表示 (`ClaudeRuntimeDecide` → `iRuntimeDisplayResult`) は 2026-09-23 に実機で通った
  (結果セルは書かれる。残った承認 UI は上記のとおり修正)。
- `ResoniteColorToggleBox` (2026-09-23): 初版は箱は出たが押しても変わらなかった (BooleanValueDriver.State に参照を書いていた。
  State は bool 値。FrooxEngine.dll の反射 `resources/tools/frooxengine-reflect.fsx` で確認)。2 版 = TouchButton →
  ButtonToggle (→ driver.State) → BooleanValueDriver (TargetField → TintColor)。**ノートブックのトップレベル
  `ResoniteColorToggleBox[]` は実機で押すと赤⇔青が切り替わった (2026-09-23)**。タブレット経由 (tick の 2 巡結線) は
  ヘッドレステストのみで、実機は未確認。

## テスト

`test codes/ResoniteRealtime_tablet_test.wls` (ヘッドレス、ResoniteLink をモック、claudecode / ClaudeRuntime /
NBAccess は公開名のスタブ)。組み立て・出力欄の高さ・Eval → ターン開始・承認 UI と決定・完了時の PL ふるい分け・
ResoniteShowObject の分岐 (PDF / 画像 / 文字列 / 行の PL 拒否) ・一覧ガジェットのページ送りと ▶・中止・削除。

## 非同期文脈からの組み立ては予約する (2026-09-22)

ResoniteLink の応答待ちは ScheduledTask / SessionSubmit / runtime の実行ジョブの中では必ずタイムアウトする (受信ハンドラが走れない)。
LLM の提案コードが呼ぶ `ResoniteListGadget` (ButtonToggle の結線にメンバ ID の応答が要る) は runtime のジョブの中で実行されるので、
そのままでは「ResoniteLink 無応答」になった。`$CurrentTask` が TaskObject のとき (`$ResoniteTabletDeferMode` Automatic) は
組み立てを専用ノートブックの Input セル `ResoniteTabletRunDeferred["id"]` として評価を予約し、即座に
`<|"Deferred" -> True, "Id" -> id|>` を返す (セルはトップレベル評価なので応答を受けられる)。対象: `ResoniteListGadget` /
`ResoniteVideoBoard` / `ResoniteViewer`。台帳は `ResoniteTabletDeferred[]`。ビューアへの表示や板のテクスチャ更新は待たない送信なので予約不要。
タブレットの出力欄には提案コード (Input セル) を出さない (`$ResoniteTabletShowCode = True` で出す)。

2026-09-22 追記 (現行): **予約した組み立ては監視 tick の中で「待たずに」組む** (`$ResoniteTabletBuildMode` Automatic = tick が動いていれば "Tick")。
ノートブックのセルに予約する方式は、セルの応答待ちループの最中に runtime の非同期タスク (LLM 問い合わせ・セル書き込み) が割り込むと
FrontEnd とカーネルが待ち合って固まった (実機 2 回: 3 行組んだところで `In[•]` のまま停止、ボタンが空)。tick 方式は
1. Send: ビルダーを `$iLinkWaitDefault = False` で走らせ、スロット/コンポーネントを送りっぱなし。ボタンの `ButtonToggle` だけ後回し (`$itWireLater` に積む)。
   置き場所 "User" はアバター位置の問い合わせ (待ち) が要るので、タブレットがあればその子 (`{0,0,0}` + 各ガジェットの Offset) にする。
2. Wire: 根の `getSlot` (Depth -1, 待たない) を送り、次の tick で応答から `ValueField<bool>.Value` のメンバ ID を拾って `ButtonToggle` を結線。
   10 秒来なければ再送 (3 回まで)。それでも来なければ失敗にして**組みかけの根を消す** (結線されていない一覧は使えない)。
台帳は `ResoniteTabletDeferred[]` (`"Via" -> "Tick"`)、進行中は `ResoniteTabletStatus[]["Builds"]`。tick が無いときだけ従来のセル予約に落ちる (`"Notebook"`)。
`ResoniteTabletRunDeferred` は tick 予約の id には何もしない。

旧 (2026-09-22 前半): 予約の判定は `$CurrentTask` だけでは足りない。runtime は提案コードを `TimeConstrained[..., 30]` で主カーネルで直接実行する経路もあり (`$CurrentTask` は None)、22 行の一覧を直接組み始めて 30 秒で中断され、待ちループ内の Abort でカーネルが固着した (ボタン 4 個だけの一覧が残った)。そこで **タブレットのターンが進行中なら常に予約** する (`itTurnActiveQ`)。予約セルの中 (`$itInDeferredRun`) では直接組む。固着したら「評価 > 評価の中止」かカーネル再起動 → 再ロード → `ResoniteTabletCleanup[]` (Root 直下の名前で残骸を消し状態を空にする) → `ResoniteTablet[]`。

## 一覧の ▶ が開かないときの診断

▶ は監視 tick の中で `ResoniteShowObject[row]` を呼ぶ。結果は `ResoniteTabletStatus[]["LastShow"]`
(行の Kind/URI/File、Result、所要秒、LastError) に残る。PDF は `Import[file, {"PDF", "PageImages", {n}}]` (FrontEnd 不要) で
描き、駄目なら `"Pages"` + Rasterize。行に `File` が無ければ sv:// URI から `SourceVaultObjectProperties` → `SourceVaultResolveReference`
→ `SourceVaultObjectData` の順に解決する。HTML スナップショット (arXiv の abs ページ) は平文にして出力欄へ。
実測 (2026-09-22 ヘッドレス): arXiv の raw PDF (5 ページ) は tick の中でも約 6 秒で開いた。

## 3D生成 (2026-09-22)

タブレットの **3D生成** ボタン (`ResoniteTabletMake3D[]`) は直前のターンの結果にある Graphics3D (Plot3D / ArrayPlot3D 等) を
`ResoniteGraphics3D` でワールド内の実体メッシュにする (アバター正面 1.2 m、最長辺 0.6 m、頂点色、Grabbable)。
生の結果は claudecode の `$ClaudeRuntimeDisplayHook` (表示ストアに記録されるたびに呼ばれる seam) で拾う。
無ければ runtime の `LastExecutionResult["RawResult"]`、それも無ければ結果セルの Graphics3DBox から取る。機密度が表示上限を超える結果は作らない。
プロンプトで「ワールドに 3D で出して」と言えば LLM が `ResoniteGraphics3D[Plot3D[...]]` を直接呼ぶ (規則 110)。
仕組み: `ResoniteRealtime_mesh.wl` → ImportMeshJSON (vertices/submeshes) → resoloop apply の `kind: mesh` 資産 → `StaticMesh` + `PBS_VertexColorMetallic` (Culling Off) + `MeshRenderer` + `MeshCollider`。
罠: プロジェクト配下の `.resoloop/state` は Dropbox が新規 checkpoint を掴んで `APPLY_STATE_WRITE_FAILED` になる
(フォルダの `com.dropbox.ignored` は新規ファイルに効かなかった。タブレットの 3D生成で実機再現)。そのため mesh/apply/checkpoint は
`%LOCALAPPDATA%\ResoLoop\g3d` (Dropbox の外) に書き、それでも checkpoint 失敗なら同じ apply を最大 3 回再実行して収束させる。

## PDF ビューア (2026-09-22)

`ResonitePDFViewer[file | pages]`: Resonite のドキュメントビューア風の掴めるパネル (Canvas 1000x1400、0.6 m x 0.84 m)。
ヘッダ `[<<] [<] n/N [>] [>>] [閉じる]`、タイトル、ページ画像 (`StaticTexture2D` → `SpriteProvider` → `UIX.Image` PreserveAspect)。
ページ送りは StaticTexture2D の URL 差し替え (待たない送信) なので tick の中でも動く。一覧の ▶ と `ResoniteShowObject` の
PDF / 画像 / .nb はここに出る (タブレットの板はターンの図用)。▶ を押すたびに**新しいビューアが増え、前のは残る** (2026-09-22 ユーザー指示。
2 つ目以降は右下手前へ `$itPDFCascade` = {0.12, -0.05, -0.06} m ずつずらして並べる。掴んで並べ替えられる)。同じパネルへ読み込みたいときは
`"Reuse" -> True` (最新) か `"Reuse" -> root`。各ビューアの 閉じる はそのビューアだけ消す。`ResonitePDFViewerRemove[All]` で全部。
無いときの組み立ては応答待ちが要るので、非同期文脈では予約 (`Deferred`)。既定はアバターの正面 1.0 m、右へ 0.65 m (`"Offset"`)。
ボタンは監視 tick が `itHandlePDF` で読む。`ResonitePDFViewerPage["Next" | "+10" | n]` / `ResonitePDFViewerRemove[]`。

置き場所の注意 (2026-09-22 実機): 予約を tick が組むときはアバターの位置を問い合わせられない (待ちが要る) ので、タブレットの子として
置く。このとき同じ平面 (z = 0) に置くと、右隣の板 (Tablet Viewer、幅 1.2 m、x = 0.98) と重なって**板の裏に隠れ、押しても
何も出ないように見えた**。tick で組むガジェットは利用者側 (-z) に `$itFrontOffset` (0.35 m) だけ前に出す (PDF ビューアは
`{0.65, 0, -0.35}`)。また、ワールドから消えたビューア/一覧 (getSlot が 2 回続けて失敗) は台帳から外す (`GadgetGone`)。
残したままだと次の ▶ が `Reuse` で存在しないビューアに書き込み、何も出ない。組み立ての失敗は `ResoniteTabletStatus[]["LastError"]`
(`<|"Build", "Label", "Result"|>`) と `ResoniteTabletDeferred[]` の `Result` に残る。
