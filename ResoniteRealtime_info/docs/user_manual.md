# ResoniteRealtime ユーザーマニュアル

ResoniteRealtime は Mathematica から Resonite を制御するブリッジです。3 つの経路 (L1 リアルタイム / L2 ResoniteLink / L3 画像配信) と、その上のガジェット群 (Chat / ProtoFlux / タブレット / 3D / PDF ビューア / 一覧) を扱います。
オプション付きの API 一覧は [api.md](api.md)、導入は [setup.md](setup.md) を参照してください。

## 目次

- 3 つの経路
- L1: リアルタイムブリッジ
- L2: ResoniteLink で構造を読み書きする
- 板と画像 (L3)
- 表示上限 (アクセスレベル)
- Chat ガジェット
- ProtoFlux ガジェット
- タブレット (ClaudeEval をワールド内で)
- 資料をワールドに出す (ShowObject / ビューア / 一覧 / PDF ビューア)
- 3D オブジェクト (Graphics3D をメッシュに)
- 設計上の約束
- 変数

## 3 つの経路

| 経路 | 役割 | 必要なもの |
| --- | --- | --- |
| **L1** リアルタイム | WL が WebSocket サーバ。世界の `WebsocketClient` が繋いでくる。TAB 区切りの行 (`evt<TAB>...` / `cmd<TAB>...`)。往復が速く、ホスト不要 | 世界側のブリッジオブジェクト (1 回作る) |
| **L2** ResoniteLink | WL が公式 ResoniteLink (WS + JSON) のクライアント。Slot / Component を読み書き | セッションのホスト + Enable ResoniteLink |
| **L3** 画像配信 | 同じポートで PNG などを HTTP 配信。板 (`StaticTexture2D`) の URL に使う | `ResoniteRealtimeStart[]` |

## L1: リアルタイムブリッジ

```wolfram
ResoniteRealtimeStart[]                                (* ws://127.0.0.1:17300/bridge *)
ResoniteRealtimeOn["evt", Print]                       (* 世界からの行にハンドラ *)
ResoniteRealtimeOn[All, f]                             (* catch-all。合成 verb "$open" / "$close" も来る *)
ResoniteRealtimeSend["cmd", "show", url]               (* 世界へ cmd<TAB>show<TAB>url *)
ResoniteRealtimeEvents[20]                             (* 直近の受信レコード *)
ResoniteRealtimeStatus[] ; ResoniteRealtimeMonitor[] ; ResoniteRealtimeStop[]
```

- ProtoFlux は JSON を扱えないので、WL → 世界は 2 フィールドまでに抑えます。
- ハンドラは `SocketListen` のコールバック内で走ります。**FrontEnd を触らない**でください。
- `ResoniteRealtimeMonitor[]` は手動更新ボタン式です (常駐 Dynamic でポーリングしない方針)。

## L2: ResoniteLink で構造を読み書きする

```wolfram
ResoniteRealtimeLinkConnect[]                          (* ポートは自動検出 (ResoniteRealtimeDiscover[])。明示なら [port]。接続先は localhost *)
ResoniteRealtimeGetSlot["Root", "Depth" -> 1]
ResoniteRealtimeGetSlot[slotId, "Depth" -> -1, "IncludeComponentData" -> True]
r = ResoniteRealtimeAddSlot["Name" -> "Hello", "Parent" -> "Root", "Position" -> {0, 1.5, 2}];
ResoniteRealtimeAddComponent[r["Id"], "[FrooxEngine]FrooxEngine.Grabbable", <|"Scalable" -> True|>]
ResoniteRealtimeUpdateSlot[r["Id"], <|"isActive" -> False|>]
ResoniteRealtimeUpdateComponent[componentId, <|"Value" -> True|>]
ResoniteRealtimeRemoveSlot[r["Id"]]
ResoniteRealtimeLinkDisconnect[]
```

- 値は `ResoniteRealtimeValue` が自動で型付けします (String / Bool / Integer / Real / {x,y} / {x,y,z} / {x,y,z,w} / RGBColor)。URI は `ResoniteRealtimeValue["Uri", url]`、参照は `ResoniteRealtimeRef[id]`、列挙は `<|"$type" -> "enum", "value" -> "MinSize"|>`。
- 応答は `messageId` / `sourceMessageId` で照合します。**ScheduledTask や SocketListen の中では応答を待てない** ので、そこからは `"Wait" -> False` で送りっぱなしにし、応答は `ResoniteRealtimeLinkMessages[n]` から `sourceMessageId` で拾います (本パッケージのガジェットはすべてこの流儀です)。
- ID は `ResoniteRealtimeNewId[prefix]` (`WL<kernelTag>_<prefix>_<n>`)。セッション中は解放されないのでカーネルごとのタグが入ります。

## 板と画像 (L3)

```wolfram
ResoniteRealtimeBoard["Size" -> 0.6, "Position" -> {0, 1.5, 1.2}]     (* StaticTexture2D + QuadMesh + UnlitMaterial + MeshRenderer *)
ResoniteRealtimeShowImage[Plot[Sin[x], {x, 0, 2 Pi}]]                  (* PNG にして配信し、板の URL を差し替える *)
ResoniteRealtimeAsset["C:\\path\\to\\image.png"]                       (* 任意のファイルを配信 URL に *)
ResoniteRealtimeRemoveBoard[]
```

聴衆がいる場では `$ResoniteRealtimePublicBaseURL` に公開 URL を設定してください (127.0.0.1 は自分にしか見えません)。

## 表示上限 (アクセスレベル)

ワールドに出してよい情報の上限 (PrivacyLevel、PL) です。既定では、タブレットの監視がワールドの公開度と所有者を読んで自動で決めます。自分がホストで所有するプライベートワールドなら 1.0、フレンド限定なら 0.5、それ以外や他人のワールドなら 0.25 です。読めないあいだは 0.25 です。手で決めたいときは次のように呼びます (手動になります)。

```wolfram
ResoniteAccessLevel["Private", "Owner" -> True]     (* 1.0: 自分のプライベートワールド *)
ResoniteAccessLevel["Contacts"]                     (* 0.5 *)
ResoniteAccessLevel["Public"]                       (* 0.25 *)
ResoniteAccessLevel[]                               (* 現在値。非オーナー ($ResoniteWorldOwner = False) は一律 0.25 *)
ResoniteAccessLevel[Automatic]                      (* 自動 (ワールドから読む) に戻す *)
```

PL がこの上限を超える資料・セルは出しません。機密度が数値で取れないものも出しません (fail-closed)。LLM に渡す AccessLevel はさらに `$ResoniteTabletCloudMaxLevel` (0.5) で頭打ちになります。

## Chat ガジェット

ノートブックの Chat セル (ClaudeEval の ClaudeInput) をワールド内で実現します ([chat-gadget.md](chat-gadget.md))。

```wolfram
ResoniteChatGadget[]           (* アバターの正面 1.5 m に UIX パネル (入力欄 / 送信 / 状態 / 答え) と板 *)
ResoniteChatStart[]            (* 送信チェックを ScheduledTask 1 本で監視 *)
ResoniteChat["フィボナッチ数列の最初の 10 項は?"]   (* 関数からも。答えはノートブックとパネルの両方へ *)
ResoniteChatCell[]             (* ノートブックに ResoniteInput セルを挿入 (Shift+Enter で ResoniteChat) *)
ResoniteChatShow[text | expr]  ; ResoniteChatLog[n] ; ResoniteChatStatus[]
ResoniteChatStop[] ; ResoniteChatRemoveGadget[]
```

答えに ```` ```mathematica ```` ブロックが含まれ `"Evaluate" -> True` のときは評価し、図なら板に出します (既定は評価しない)。PrivacyLevel = Max[プロンプトの機密度, 文脈の機密度] が 0.5 を超えるとローカル LLM に回り、プロンプトの機密度が表示上限を超えると `Failure["WorldAccessDenied"]`。

## ProtoFlux ガジェット

プロンプトから、ワールド内で実行できる ProtoFlux を作ります ([protoflux-gadget.md](protoflux-gadget.md))。既定はグラフ記述 (JSON) → ResoniteLink でノードを直接配置・結線 → probes (動的変数) を読み戻して検証、の修正ループです。

```wolfram
ResoniteFluxGenerate["0.5 秒ごとに 1 ずつ増えるカウンタ"]     (* <|"Graph","Placed","Probes","Rounds",...|> *)
ResoniteFluxChat["..."]                                      (* ノートブックとパネルにも出す *)
ResoniteFluxCell[]                                           (* ResoniteFluxInput セル *)
ResoniteFluxCatalogSearch["ValueAdd", 10]                    (* ノードカタログ (setup.md 5 節で作る) *)
ResoniteFluxUnknownNodes[source]
ResoniteFluxGenerate[spec, "Format" -> "ProtoGraph"]         (* Flux SDK のテキスト言語で書かせ、静的検査 → build *)
ResoniteFluxBuild[pgFile] ; ResoniteFluxDeploy[result]
```

リンカ (`ResoniteRealtime_fluxlink.wl`) は直接も使えます: `ResoniteFluxValidateGraph` / `ResoniteFluxPlace` / `ResoniteFluxProbe` / `ResoniteFluxRemove` / `ResoniteFluxDisplay` (probe を 3D テキストに) / `ResoniteFluxDrive` (動的変数で世界のフィールドを駆動)。

## タブレット (ClaudeEval をワールド内で)

ワールド内の UIX タブレット (入力欄 / Eval / Clear / Cancel / 3D生成 / 承認・拒否 / スクロールする出力欄 / 板ビューア + ページ送り) から ClaudeEval を走らせます ([tablet.md](tablet.md))。

```wolfram
ResoniteTablet[]                          (* アバターの正面。監視 tick (既定 1 秒) も始まる *)
ResoniteTabletEval["Plot3D[Sin[x y], {x,0,3}, {y,0,3}]"]   (* Eval ボタンと同じ *)
ResoniteTabletApprove[] ; ResoniteTabletDeny[] ; ResoniteTabletCancel[]
ResoniteTabletShow[text | expr] ; ResoniteTabletStatus[] ; ResoniteTabletLog[n]
ResoniteTabletStop[] ; ResoniteTabletRemove[] ; ResoniteTabletCleanup[]
```

- Eval は専用ノートブック「Resonite Tablet」に `ResoniteTabletTurn["..."]` の Input セルを書いて評価します (= ClaudeInput と同じ処理)。中身は ClaudeEval の runtime 経路で、tick が `ClaudeRuntimeState` を見張り、承認待ちなら承認行を有効にし、完了したら結果セルを表示上限でふるって平文と画像 (ページ) に描きます。
- 承認・拒否・中止は claudecode の `ClaudeRuntimeDecide` を通ります (ノートブックの承認ボタンと同じ処理)。実行がタイムアウトして延長を申告してきたときも承認行で応答できます。
- タブレットには提案コード (Input セル) や診断 Code セルは出しません (`$ResoniteTabletShowCode = True` で出す)。
- LLM への指示 (表示上限、`ResoniteShowObject` / `ResoniteListGadget` の使い方、検索語を core 関数に渡す等) はプロンプトに前置きされ、規則は `ResoniteRealtime_info/directives/110-resonite-tablet.md`。
- **予約 (Deferred)**: 提案コードが呼ぶガジェットの組み立て (一覧 / PDF ビューア / 動画 / ビューア) は、runtime のジョブや tick の中では ResoniteLink の応答を待てないので `<|"Deferred" -> True, "Id" -> ...|>` を即返して予約し、監視 tick が待たずに組み立てます (送りっぱなし → getSlot → ボタン結線。失敗したら組みかけを消す)。台帳は `ResoniteTabletDeferred[]`、進行中は `ResoniteTabletStatus[]["Builds"]`。
- **3D生成ボタン** (`ResoniteTabletMake3D[]`): 直前のターンの Graphics3D をワールド内のメッシュにします (次節)。
- カーネルを再起動して台帳を失ったら `ResoniteTabletCleanup[]` → `ResoniteTablet[]`。
- **Resonite 側から呼び出す**: 作ったタブレットをインベントリに保存しておき、次回は `Get["ResoniteRealtime.wl"]` (常駐監視
  `ResoniteTabletServe[]` が自動で始まる) → ResoniteLink 有効化 → インベントリから出して「接続」を押す。常駐監視がポートを自動検出して繋ぎ、
  そのタブレットを名前で読み取って引き継ぐ (`ResoniteTabletFind[]` / `ResoniteTabletAdopt[root]` で手動も可)。

## 資料をワールドに出す (ShowObject / ビューア / 一覧 / PDF ビューア)

```wolfram
ResoniteShowObject["sv://object/eagle-XXXX"]         (* SourceVault の URI *)
ResoniteShowObject[row]                             (* 共通スキーマ行 (Title / URI / Kind / Date / PrivacyLevel) *)
ResoniteShowObject["C:\\docs\\paper.pdf"]            (* pdf / png / jpg / mp4 / txt / md / nb *)
ResoniteShowObject[Plot[Sin[x], {x, 0, 5}]]
ResoniteListGadget[rows, "Title" -> "arXiv"]        (* 行ごとに ▶ のある一覧パネル (タブレットの左隣)。▶ で開く *)
ResonitePDFViewer[file]                             (* Resonite 標準のドキュメントビューアで開く (雛形が要る。無ければ自前パネル)。呼ぶたびに増える *)
ResonitePDFViewer[file2, "Reuse" -> True]           (* 最新のビューアへ読み込む (増やさない) *)
ResonitePDFViewerPage["Next"] ; ResonitePDFViewerRemove[] ; ResonitePDFViewerRemove[All]
ResoniteViewerShow[pages] ; ResoniteViewerPage["Next"]   (* 板ビューア (ターンの図用) *)
ResoniteVideoBoard[urlOrFile]                       (* 動画の板 (再生制御は未実装) *)
```

PDF は Resonite 標準のドキュメントビューアで開きます (`$ResonitePDFMode = "Native"`)。ワールドに標準の PDF ビューアを 1 つ置いておいてください
(PDF を一度インポートした物。名前を `PDF Template` にしておくと確実)。それを ProtoFlux で複製して配信 URL を差し替えます。無ければ自前のページ画像パネルに落ちます。
画像 / ノートブックはページ画像にして自前パネルへ、文字列や Markdown は出力欄へ、`sv://` は SourceVault で解決します。行の PrivacyLevel が表示上限を超える、または無い行は出しません (fail-closed)。

## 3D オブジェクト (Graphics3D をメッシュに)

`Plot3D` / `ArrayPlot3D` / `SphericalPlot3D` / `Graphics3D` をワールド内の掴めるメッシュにします。ResoLoop パッケージと resoloop が必要です。

```wolfram
mesh = ResoniteGraphics3DMesh[Plot3D[Sin[x y], {x, 0, 3}, {y, 0, 3}]]   (* 頂点 / 三角形 / 頂点色 / 法線 *)
ResoniteMeshJSON[mesh]                                                  (* ResoniteLink の ImportMeshJSON 形式 *)
r = ResoniteGraphics3D[Plot3D[Sin[x y], {x, 0, 3}, {y, 0, 3}], "Size" -> 0.6]  (* ResoLoop_Graphics3D_<stamp> をアバターの正面に *)
ResoniteGraphics3DRemove[r]
```

- 座標は Mathematica (右手, z 上) から Resonite (左手, y 上) へ (x,y,z) → (x,z,y) にし、三角形の向きを裏返して外向き法線を保ちます。BoxRatios を反映し最長辺を `"Size"` (m) にします。
- 生成物は Grabbable + StaticMesh (`$asset:mesh`) + PBS_VertexColorMetallic (Culling Off) + MeshRenderer + MeshCollider (DualSided)。`"Apply" -> False` なら mesh.json / apply.json を書くだけです。
- 作業フォルダは `%LOCALAPPDATA%\ResoLoop\g3d` (同期フォルダの外)。checkpoint の書き込み失敗は同じ apply の再実行で収束します。

## 設計上の約束

- 常駐 Dynamic でポーリングしない (パレット常駐 UpdateInterval は FrontEnd を殺す)。監視は ScheduledTask 1 本、Monitor は手動更新ボタン式。
- SocketListen のコールバックからは FrontEnd を触らない。コールバック内で Close / Pause しない。
- ScheduledTask / SessionSubmit / runtime のジョブの中では ResoniteLink の応答を待たない (`"Wait" -> False` + `sourceMessageId` 照合)。
- 機密度は fail-closed。上限を超えるもの、数値で取れないものは出さない。
- ResoniteLink は beta。メッセージ組み立ては 1 箇所 (`ResoniteRealtimeValue` / `ResoniteRealtimeLink`) に閉じ込め、スキーマ変更に追随しやすくする。

## 変数

| 変数 | 意味 |
| --- | --- |
| `$ResoniteRealtimeVersion` | パッケージの版 |
| `$ResoniteRealtimePublicBaseURL` | 画像配信の公開 URL |
| `$ResoniteWorldAccessLevels` / `$ResoniteWorldOwner` | 公開度 → 表示上限の表 (Private 1.0 / Contacts 0.5 / ContactsPlus 0.25 / Public 0.25) と所有者フラグ |
| `$ResoniteTabletCloudMaxLevel` (0.5) / `$ResoniteTabletMaxChars` (6000) / `$ResoniteTabletShowCode` / `$ResoniteTabletBuildMode` / `$ResoniteTabletDeferMode` | タブレットの設定 |
| `$ResoniteTabletPagePoints` (480) / `$ResoniteTabletPageResolution` (192) | ビューアのページ幅 (pt) と解像度 (dpi) |
| `$ResoniteGraphics3DDirectory` | 3D 生成の作業フォルダ |
| `$ResoniteFluxSDK` / `$ResoniteFluxProjects` / `$ResoniteFluxGraphSpec` | ProtoFlux の設定と LLM に渡すグラフ記述の仕様文 |
