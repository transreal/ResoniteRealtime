# ResoniteRealtime ユーザーマニュアル

ResoniteRealtime は Mathematica から Resonite を制御するブリッジです。3 つの経路 (L1 リアルタイム / L2 ResoniteLink / L3 画像配信) と、その上のガジェット群 (Chat / ProtoFlux / タブレット / 3D / PDF ビューア / サムネイル一覧 / 曲面) を扱います。
オプション付きの API 一覧は [api.md](api.md)、導入は [setup.md](setup.md) を参照してください。

## 目次

- 3 つの経路
- L1: リアルタイムブリッジ
- WebSocket 層 (RRWS)
- L2: ResoniteLink で構造を読み書きする
- 板と画像 (L3)
- 表示上限 (アクセスレベル)
- Chat ガジェット
- ProtoFlux ガジェット
- タブレット (ClaudeEval をワールド内で)
- 資料をワールドに出す (ShowObject / ビューア / 一覧 / PDF ビューア)
- 文書ビューアとサムネイル一覧 (インベントリ保存)
- サムネイル一覧を曲面に貼る
- フレンド向け PDF キャッシュ
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

## WebSocket 層 (RRWS)

`ResoniteRealtime_ws.wl` は純 Wolfram の WebSocket 層 (RFC 6455、サーバ + クライアント) で、L1 (サーバ側) と L2 (ResoniteLink へ繋ぐクライアント側) の下回りです。依存はなく、`SocketOpen` / `SocketListen` / `SocketConnect` だけで動きます。通常は直接使いませんが、公開されています。

```wolfram
id = RRWSServe[17301, Print]                          (* サーバ起動。"BindAddress" -> "127.0.0.1" (既定) | "0.0.0.0" *)
c  = RRWSConnect["ws://127.0.0.1:17301/path", Print]  (* クライアント接続 (ハンドシェイクは同期、"Timeout" -> 10) *)
RRWSSend[c, "hello"] ; RRWSPing[c] ; RRWSClose[c]
RRWSStatus[] ; RRWSConnections[]
RRWSStopServe[id]                                     (* RRWSStopServe[] は全サーバ *)
```

- ハンドラが受け取る Association は `<|"Event" -> "Open" | "Message" | "Close" | "Error", "Connection", "Role" -> "server" | "client", "Data", "Opcode", "Time"|>` です。
- `RRWSSweep[]` は閉じ待ちのソケットを回収します。公開 API から自動で呼ばれ、`SocketListen` のコールバック内では何もしません。`$RRWSLastError` は握りつぶされたハンドラ例外の記録です。
- 書き込みは `SocketWriteMessage[..., "Blocking" -> True]` を 64 KB ずつ送ります。ハンドラ内で `Pause` しないでください。

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

聴衆がいる場では `$ResoniteRealtimePublicBaseURL` に公開 URL を設定してください (127.0.0.1 は自分にしか見えません)。日本語や空白を含むファイル名は URL 側でパーセントエンコードされ、配信側で UTF-8 として戻されます。

## 表示上限 (アクセスレベル)

ワールドに出してよい情報の上限 (PrivacyLevel、PL) です。既定では、タブレットの監視がワールドの公開度と所有者を読んで自動で決めます。ワールドの Root 直下の `Mathematica World Info` (SessionInfoSource + ProtoFlux の WorldSessionID) から公開度・ホスト・ワールド記録の所有者を読み、ホスト = 所有者ならオーナーとみなします。自分がホストで所有するプライベートワールドなら 1.0、フレンド限定なら 0.5、それ以外や他人のワールドなら 0.25 です。読めないあいだは 0.25 です。手で決めたいときは次のように呼びます (手動になります)。

```wolfram
ResoniteAccessLevel["Private", "Owner" -> True]     (* 1.0: 自分のプライベートワールド *)
ResoniteAccessLevel["Contacts"]                     (* 0.5 *)
ResoniteAccessLevel["Public"]                       (* 0.25 *)
ResoniteAccessLevel[]                               (* 現在値。非オーナー ($ResoniteWorldOwner = False) は一律 0.25 *)
ResoniteAccessLevel[Automatic]                      (* 自動 (ワールドから読む) に戻す *)
```

- `$ResoniteWorldAccessMode` は `Automatic` (既定) か `"Manual"` (`ResoniteAccessLevel[access, "Owner" -> ...]` で手で決めた) です。
- `$ResoniteOwnerUserId` に `"U-..."` を置くと、自動判定でオーナーとみなすのはホストがその ID のときだけになります (既定 `Automatic`)。
- `$ResoniteWorldAccess` は現在の公開度 (既定 `"Public"`)、`$ResoniteWorldAccessLevels` は公開度 → 表示上限の表です。

PL がこの上限**以上**の資料・セルは出しません (上限と等しいものも出しません)。機密度が数値で取れないものも出しません (fail-closed)。LLM に渡す AccessLevel はさらに `$ResoniteTabletCloudMaxLevel` (0.5) で頭打ちになります。

## Chat ガジェット

ノートブックの Chat セル (ClaudeEval の ClaudeInput) をワールド内で実現します ([chat-gadget.md](chat-gadget.md))。

```wolfram
ResoniteChatGadget[]           (* アバターの正面 1.5 m に UIX パネル (入力欄 / 送信 / 状態 / 答え) と板 *)
ResoniteChatStart[]            (* 送信チェックを ScheduledTask 1 本で監視 *)
ResoniteChat["フィボナッチ数列の最初の 10 項は?"]   (* 関数からも。答えはノートブックとパネルの両方へ *)
ResoniteChatCell[]             (* ノートブックに ResoniteInput セルを挿入 (Shift+Enter で ResoniteChat) *)
ResoniteChatShow[text | expr]  ; ResoniteChatLog[n] ; ResoniteChatStatus[]
ResoniteChatAttach[ids]        (* 別カーネルが作ったパネル (ResoniteChatGadget の戻り値) を引き継ぐ *)
ResoniteChatStop[] ; ResoniteChatRemoveGadget[]
```

主なオプション:

- `ResoniteChat`: `"Notebook" -> Automatic`、`"World" -> True`、`"SourceVault" -> Automatic`、`"Evaluate" -> False`、`"Model" -> Automatic`、`"Timeout" -> 180`、`"Origin" -> "Notebook" | "World" | "Bridge"`。戻り値は `<|"Answer", "PrivacyLevel", "AccessLevel", "Context", "Shown"|>` か Failure。
- `ResoniteChatGadget`: 既定ではアバターの頭の正面に置きます。`"Placement" -> "User" | "World"`、`"Distance" -> 1.5` (m)、`"Height" -> Automatic` (目の高さ − 0.25 m。数値なら足元からの高さ)、`"User" -> Automatic` (名前の一部で選ぶ)。`"Placement" -> "World"` のときは `"Position" -> {0, 1.4, 1.5}`、`"Parent" -> "Root"`。ほかに `"Name" -> "Mathematica Chat"`、`"CanvasSize" -> {1200, 800}`、`"PanelScale" -> 0.001`、`"FontSize" -> 28`、`"Board" -> True` (図を出す板も作る)。
- `ResoniteChatStart`: `"PollInterval" -> 1.5` (秒)、`"Evaluate" -> False`。

答えに ```` ```mathematica ```` ブロックが含まれ `"Evaluate" -> True` のときは評価し、図なら板に出します (既定は評価しない)。PrivacyLevel = Max[プロンプトの機密度, 文脈の機密度] が 0.5 を超えるとローカル LLM に回り、プロンプトの機密度が表示上限を超えると `Failure["WorldAccessDenied"]`。世界の ProtoFlux から L1 で `ask<TAB>質問` が来た場合も同じ処理が走ります。

## ProtoFlux ガジェット

プロンプトから、ワールド内で実行できる ProtoFlux を作ります ([protoflux-gadget.md](protoflux-gadget.md))。既定はグラフ記述 (JSON) → ResoniteLink でノードを直接配置・結線 → probes (動的変数) を読み戻して検証、の修正ループです。

```wolfram
ResoniteFluxGenerate["0.5 秒ごとに 1 ずつ増えるカウンタ"]     (* <|"Graph","Placed","Probes","Rounds",...|> *)
ResoniteFluxChat["..."]                                      (* ノートブックとパネルにも出す *)
ResoniteFluxCell[]                                           (* ResoniteFluxInput セル *)
ResoniteFluxCatalog[]                                        (* ノードカタログ (Type / Name / Category / Inputs / Outputs / Impulses / Result) *)
ResoniteFluxCatalogSearch["ValueAdd", 10]                    (* ノードカタログ (setup.md 5 節で作る) *)
ResoniteFluxUnknownNodes[source]
ResoniteFluxGenerate[spec, "Format" -> "ProtoGraph"]         (* Flux SDK のテキスト言語で書かせ、静的検査 → build *)
ResoniteFluxBuild[pgFile] ; ResoniteFluxDeploy[result]
```

- ProtoGraph 経路のオプション: `"MaxRounds" -> 3`、`"Module" -> Automatic`、`"Model" -> Automatic`、`"Timeout" -> 300`、`"Build" -> Automatic`、`"SourceVault" -> False`、`"Origin" -> "Notebook"`。戻り値は `<|"Source","Module","File","Project","Unknown","Build","Rounds","Answer","PrivacyLevel"|>`。
- `flux-sdk` (dotnet tool `Papaltine.FluxSDK`) が無くても生成と静的検査までは動きます。build と `.brson` 出力は flux-sdk があるときだけで、無ければ `ResoniteFluxBuild` は `Failure["NoFluxSDK"]` を返します。
- `ResoniteFluxDeploy[result, "Method" -> "ResoniteLink"]` は Flux SDK のホットデプロイ (実験的) を試します。`.brson` があれば Resonite へドラッグ&ドロップです。

リンカ (`ResoniteRealtime_fluxlink.wl`) は直接も使えます。

```wolfram
ResoniteFluxBindingType["ValueAdd<float>"]     (* カタログから ProtoFluxBindings のコンポーネント型名。未知なら None *)
ResoniteFluxValidateGraph[graph]                (* <|"OK","Errors","Warnings","Nodes"|> *)
placed = ResoniteFluxPlace[graph]               (* "Parent","Position","Name","Spacing" -> {0.35, 0.25}。<|"Root","Nodes","Slots","Errors","Probes"|> *)
ResoniteFluxProbe[placed]                       (* probes の動的変数を読み戻す *)
ResoniteFluxDisplay[placed, "wl/sum"]           (* probe を 3D テキストに。"Position","Scale","Color" *)
ResoniteFluxDrive[placed, var, targetMemberId, type]   (* 動的変数で世界のフィールドを駆動 (DynamicValueVariableDriver) *)
ResoniteFluxRemove[placed]
```

## タブレット (ClaudeEval をワールド内で)

ワールド内の UIX タブレット (入力欄 / Eval / Clear / Cancel / 3D生成 / 承認・拒否 / スクロールする出力欄 / 板ビューア + ページ送り) から ClaudeEval を走らせます ([tablet.md](tablet.md))。

```wolfram
ResoniteTablet[]                          (* アバターの正面。監視 tick (既定 1 秒) も始まる *)
ResoniteTabletEval["Plot3D[Sin[x y], {x,0,3}, {y,0,3}]"]   (* Eval ボタンと同じ *)
ResoniteTabletApprove[] ; ResoniteTabletDeny[] ; ResoniteTabletCancel[]
ResoniteTabletShow[text | expr] ; ResoniteTabletStatus[] ; ResoniteTabletLog[n]
ResoniteTabletMake3D[]                    (* 直前のターンの Graphics3D を 3D オブジェクトに *)
ResoniteTabletNotebook[]                  (* 専用ノートブック (無ければ作る) *)
ResoniteTabletAttach[ids]                 (* 別カーネルが作ったタブレットを引き継ぐ *)
ResoniteTabletStart[] ; ResoniteTabletTick[]    (* 監視の起動 / 手動で 1 回分 (テスト用) *)
ResoniteTabletStop[] ; ResoniteTabletRemove[] ; ResoniteTabletCleanup[]
```

`ResoniteTablet` の主なオプション: `"Placement" -> "User" | "World"`、`"Distance" -> 1.2`、`"Height" -> Automatic`、`"User" -> Automatic`、`"Position" -> {0, 1.3, 1.2}`、`"Parent" -> "Root"`、`"Name" -> "Mathematica Tablet"`、`"CanvasSize" -> {1000, 1500}`、`"PanelScale" -> 0.0006`、`"FontSize" -> 26`、`"Viewer" -> True`、`"ViewerSize" -> 1.2`、`"Notebook" -> Automatic | NotebookObject`、`"NotebookVisible" -> True`、`"Model" -> Automatic`、`"Start" -> True`。`ResoniteTabletStart` は `"PollInterval" -> 1.0` (秒) を取ります。

- Eval は専用ノートブック「Resonite Tablet」に `ResoniteTabletTurn["..."]` の Input セルを書いて評価します (= ClaudeInput と同じ処理)。中身は ClaudeEval の runtime 経路で、tick が `ClaudeRuntimeState` を見張り、承認待ちなら承認行を有効にし、完了したら結果セルを表示上限でふるって平文と画像 (ページ) に描きます。
- 承認・拒否・中止は claudecode の `ClaudeRuntimeDecide` を通ります (ノートブックの承認ボタンと同じ処理)。実行がタイムアウトして延長を申告してきたときも承認行で応答できます。
- タブレットには提案コード (Input セル) や診断 Code セルは出しません (`$ResoniteTabletShowCode = True` で出す)。
- LLM への指示 (表示上限、`ResoniteShowObject` / `ResoniteListGadget` の使い方、検索語を core 関数に渡す等) はプロンプトに前置きされ、規則は `ResoniteRealtime_info/directives/110-resonite-tablet.md`。
- LLM に渡す AccessLevel は `Min[表示上限, 0.5]` です。`"Model"` にローカルモデルを指定したときだけ表示上限と同じになります。
- **予約 (Deferred)**: 提案コードが呼ぶガジェットの組み立て (一覧 / PDF ビューア / 動画 / ビューア) は、runtime のジョブや tick の中では ResoniteLink の応答を待てないので `<|"Deferred" -> True, "Id" -> ...|>` を即返して予約し、監視 tick が待たずに組み立てます (送りっぱなし → getSlot → ボタン結線。失敗したら組みかけを消す)。台帳は `ResoniteTabletDeferred[]`、進行中は `ResoniteTabletStatus[]["Builds"]`。
- **3D生成ボタン** (`ResoniteTabletMake3D[]`): 直前のターンの Graphics3D をワールド内のメッシュにします (`ResoniteGraphics3D` 経由、オプションも同じ)。表示上限を超える結果は作りません。
- **非同期ジョブ**: ターンが ClaudeOrchestrator の非同期ジョブ (`<|"OrchJobId" -> ...|>`) に回ったときは、`ResoniteTabletNoteTurnResult[res]` が監視対象にして完了を待ちます (戻り値は jobId か `None`)。
- **許可ヘッド**: `ResoniteTabletRegisterHeads[]` がタブレットの表示 API (`ResoniteShowObject` / `ResoniteListGadget` 等) を NBAccess の許可ヘッドに登録します (ロード時に自動で呼ばれます)。
- **作業用カーネル**: サムネイルの帯・Eagle フォルダの一覧・大きな PDF のページ数は、監視の tick から外して常駐サブカーネルで作ります (`$ResoniteTabletWorker`、既定 True。tick が長く塞ぐと FE に「動的評価の放棄」ダイアログが出るため)。状態は `ResoniteTabletWorkerStatus[]` (`<|"Phase","Alive","Queue","Job","SlowTicks"|>`)、止めるのは `ResoniteTabletWorkerStop[]` (次の仕事で立ち上げ直し)。`$ResoniteTabletWorker = False` で従来どおりこのカーネルで作ります。
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
ResonitePDFViewer[file]                             (* Resonite 標準のドキュメントビューアで開く (雛形が要る。無ければ Resonite 自身の文書表示 / 自前パネル)。呼ぶたびに増える *)
ResonitePDFViewer[file2, "Reuse" -> True]           (* 最新のビューアへ読み込む (増やさない) *)
ResonitePDFViewerPage["Next"] ; ResonitePDFViewerRemove[] ; ResonitePDFViewerRemove[All]
ResoniteViewerShow[pages] ; ResoniteViewerPage["Next"]   (* 板ビューア (ターンの図用) *)
ResoniteVideoBoard[urlOrFile]                       (* 動画の板 (再生制御は未実装) *)
```

PDF は Resonite 標準のドキュメントビューアで開きます (`$ResonitePDFMode = "Native"`)。ワールドに標準の PDF ビューアを 1 つ置いておいてください
(PDF を一度インポートした物。名前を `PDF Template` にしておくと確実)。それを ProtoFlux で複製して配信 URL を差し替えます。雛形が無い、または複製に失敗したときは、`$ResonitePDFLite` (既定 True) により次節の `ResoniteDocViewer` (Resonite 自身の文書表示) で開きます。`$ResonitePDFLite = False` なら従来どおり自前のページ画像パネルに落ちます。
画像 / ノートブックはページ画像にして自前パネルへ、文字列や Markdown は出力欄へ、`sv://` は SourceVault で解決します。行の PrivacyLevel が表示上限以上、または無い行は出しません (fail-closed。`Failure["PrivacyExceeded"]`)。

## 文書ビューアとサムネイル一覧 (インベントリ保存)

### 雛形なしの文書ビューア

```wolfram
ResoniteDocViewer["C:\\docs\\paper.pdf"]       (* Resonite 自身の文書表示 (StaticDocument + DocumentPageTexture) で開く *)
ResoniteDocViewer[file, "Title" -> "論文", "Position" -> Automatic, "Parent" -> "Root"]
ResoniteDocViewerRemove[root] ; ResoniteDocViewerRemove[]    (* 1 つ / 全部消す *)
```

標準ビューアの雛形が要らず、ページ送り (`<<` `<` `>` `>>`) と閉じるボタンはワールドの中だけで動きます (ProtoFlux の `ButtonValueShift` / `ButtonValueSet` が `PageIndex` と表示用の `Page` を同時に動かし、端で止まります)。Wolfram がページを画像にしないので速く、描くのは Resonite 側です。ワールドに雛形が無くても (開き直したあとでも) 使えます。`$ResonitePDFMode = "Native"` のとき、`ResoniteShowObject` や一覧の PDF は雛形が無ければ自動でこれを使います。

### サムネイル一覧のインベントリ保存と「接続」

構成したサムネイル一覧 (`ResoniteThumbnailGadget[rows, ...]`) は、そのままインベントリに保存して使い回せます。タブレットと同様に「接続」ボタンが付き、ResoniteRealtime がロードされていればタブレットが無くても PDF を開けます。

- 帯の画像は Resonite の資産 (`local://`) に取り込まれるので、保存するとクラウドに上がり、Wolfram が居なくても帯が出ます。
- 行 (題名 / ファイル / URI / 機密度) と配置は JSON として一覧の子 `Data` に入り、**署名つき** (HMAC-SHA256、鍵は `$ResoniteBoardKeyFile`) です。ワールドの誰かがファイルのパスや機密度を書き換えると署名が合わず、接続を断ります。署名は常にこの PC の自分の鍵で付けます。鍵は既定で `$UserBaseDirectory/ApplicationData/ResoniteRealtime/board.key` (32 バイト、無ければ作る) です。
- 自分の PC 同士で鍵を共有する「鍵束」があり、別の PC で作った一覧も確かめられます (次項)。
- インベントリから出した / 複製した一覧は、Wolfram が確かめるまで升目 (画像と題名) を隠し、「接続を押すと表示」だけを見せます。
- 「接続」を押すと、常駐監視が見つけて引き継ぎます。署名を確かめ、ワールド情報 (公開度・ホスト・所有者) を読み直してから、表示上限未満の行だけを見せます (上限以上の升目は覆いで隠し、開こうとしても断ります。公開度があとで変わっても覆いを付け直します)。ワールドの情報がまだ読めていないときは「ワールドの情報待ち」と出るので、数秒後に押し直してください。
- 標準ビューアの雛形が分かっていれば、複製を一覧の子に非表示で保管します (保存すると一緒に入ります)。一覧から開いた PDF は一覧の升目の前に出ます。

#### 鍵束と別の PC で作った一覧

鍵は PC ごとに別なので、以前は別の PC で作った一覧の「接続」が「行データの署名が合いません」で断られていました。現在は次のように扱います。

- **鍵束**: 各 PC が自分の鍵を `<SourceVault の PrivateVault>/keys/resonite-board/<PC 名>-<指紋>.key` に置きます (Dropbox で自分の PC 同士だけに同期されます。クラウド LLM / MCP の許可外で、`.key` は MCP も拒否します)。SourceVault が無ければ鍵束は使いません (`None` でも使わない設定にできます)。署名の検証は、自分の鍵 → 鍵束の鍵の順に試します。署名は今までどおり自分の鍵なので、前に作った一覧もそのまま通ります。
- **鍵束にまだ鍵が無い PC の一覧** (その PC で新しい版を一度も読んでいない一覧) は、行を信用せず、Eagle の項目だけをこの PC の SourceVault から引き直します。
  - URI が `sv://object/eagle-<Id>` の行だけを採り、ファイルのパスは捨てます (開くときに SourceVault がこの PC の Eagle から解決します)。
  - 機密度は、この PC の SourceVault の値と一覧に書いてある値の大きい方です (SourceVault が無ければ 1.0)。
  - それ以外の行は開けない升目 (機密度 1.0) にします。`sv://file/` は機密度 0.0 で任意のファイルを指せるので採りません。行の順は変えません (升目の番号 = 行の番号)。
  - 採れる行が 1 つも無ければ、今までどおり接続を断ります。
- 接続した状態欄には、別の PC の一覧なら「接続済み (別PCの一覧)」と出ます。詳しい説明 (鍵束にその PC の鍵がまだ無いこと、引き直す件数) はタブレット / ノートブックの状態に出ます。
- **機密度の引き直しは小分け**で行います。以前は接続の 1 tick で全行を引き直していたため、468 件で約 1 分塞いでいました。現在は作業用カーネルへ小分けに投げ、終わるまでの機密度は、署名の通った一覧なら署名の値 (引き直しは上げるだけ)、別の PC の一覧なら 1.0 です。
- 引き直しが終わる前でも、押した升目はその行だけ先に引き直して開きます。引き直しに失敗したら控えの行 (別の PC の一覧なら機密度 1.0 = 開けない側) を使います。
- 開示の方針: 升目は全部見せ、中身を開けない件数を状態欄で知らせます。

状態欄は幅 (全角 1、半角 0.55) で切れるので、経過・結果を先に、題名は最後に出します。たとえば「開いています… 3 秒 (ビューアを組み立てています)」「開きました (2 秒) 題名」「開けませんでした: …」の形です。文字数ではなく幅で切るので、半角の多い `[PL<1.00 Private]` のような表示でも枠を使い切りません。機密度が表示上限以上で断ったときは「中身は開けません: 機密度 … >= 表示上限 …」と出し、理由は記録 (BoardLog の `OpenRefused`) にも残ります。

```wolfram
ResoniteBoardAdopt[root]          (* 「接続」ボタンと同じ。ワールドの一覧を引き継ぐ (監視 tick が要る) *)
ResoniteBoardDiagnose[root]       (* 「接続」が効かないときの診断 (ノートブックから。getSlot を待つ) *)
ResoniteBoardDiagnose[]           (* Root 直下と入れ物の中の一覧を探して全部診断 *)
```

`ResoniteBoardDiagnose` は、ワールドでの名前・親・State の `ValueField<int>` の値 (接続を押すと -3)、監視の候補 / 引き継ぎ中 / 接続済みか、直近の記録 (BoardLog) を返します。記録には引き継ぎ (`Adopted`: 件数と署名の出所)、引き直しの完了 (`Rechecked`)、開くのを断った理由 (`OpenRefused`: 升目の番号・機密度・上限) が入ります。引き直しが済んだか途中か、ワールドの情報を読めているかも状態に出ます。読めなかったときは `"Reply"` に応答そのものが入ります。

## サムネイル一覧を曲面に貼る

`ResoniteRealtime_surface.wl` は、平面のサムネイル一覧をアバターを中心にした曲面 (円筒 / 球の内側 / メビウスの帯 / 任意の面) に貼り替えます。一覧の見出しの「形を変更」ボタンで形を巡回できます。

```wolfram
ResoniteThumbnailGadget[rows, "Shape" -> "Cylinder"]     (* 最初から曲面で組む *)
ResoniteThumbnailShape[root, "SphereInside"]            (* 既存の一覧を別の形で組み直す *)
ResoniteThumbnailShape[root]                            (* 次の形へ ($ResoniteThumbnailShapes の順。「形を変更」ボタンと同じ) *)
ResoniteThumbnailSurface["Mobius"]                      (* 面の定義 (Association) を返す *)
```

- 組み込みの形: `"Plane"` (平面)、`"Cylinder"` (円筒)、`"SphereInside"` (球の内側)、`"Mobius"` (メビウスの帯)、`"TorusOutside"` (トーラスの外側。切り替えの巡回には入れていません)。巡回の順は `$ResoniteThumbnailShapes` (既定 `{"Plane", "Cylinder", "SphereInside", "Mobius"}`) で変えられます。
- 曲面の中心はアバターの目の位置です。監視の tick の中では待たずに読みます。アバターが見つからない / 8 秒で読めないときは、今のパネルの 1.3 m 手前を中心にします。平面に戻すときは直前の中心の正面 1.4 m に置きます。
- 升目ごとに小さな Canvas を接平面に置き、帯のテクスチャから升目の矩形だけを切り出して貼ります。クリックはその升目のコライダーに当たり、平面と同じ監視で番号を読みます。

### 任意の面を設計する

面は「平面座標 → 3D 点」の写像 S(x, y) です。x, y は平面の一覧の座標 (m、升目の範囲の中心が原点、x 右 / y 上)、g は寸法 `<|"W", "H", "Y0", "R", ...|>`、戻り値は中心 (アバターの目、y 上、+z = 正面) から見た点です。UIX の表は −z を向くので、(∂S/∂x) × (∂S/∂y) が中心から外へ向くように書くと表が中心を向きます (`"Flip" -> True` で反転)。

```wolfram
spec = ResoniteThumbnailSurface[
  Function[{x, y, g}, {g["R"] Sin[x/g["R"]], y + g["Y0"], g["R"] Cos[x/g["R"]]}],
  "Name" -> "MyCyl", "Label" -> "円筒", "Radius" -> 1.5, "Y0" -> 0,
  "Fit" -> Function[g, <|"R" -> g["W"]/(2 Pi)|>], "Flip" -> False];
$ResoniteThumbnailSurfaces["MyCyl"] = spec;             (* 名前で使えるように登録 *)
ResoniteThumbnailShape[root, spec]
```

`$ResoniteThumbnailSurfaces` は名前 → 面の定義の登録簿で、組み込みの形はロードのたびに入れ直し、利用者が足した名前は残ります。

### 確認とテスト

```wolfram
ResoniteThumbnailSurfaceFrames[spec, g, {{0, 0}, {0.2, 0.1}}]   (* 点ごとの <|"Position","Rotation","X","Y","Z"|> (接平面) *)
ResoniteThumbnailSurfaceFrames[root]                             (* 組んだ一覧の升目ごとのフレーム *)
ResoniteThumbnailSurfaceHit[root, {origin, dir}]                 (* 光線が面と交わる升目の番号。当たらなければ None *)
ResoniteThumbnailSurfaceHit[root, {origin, dir}, "Detail"]       (* <|"Cell","XY","Point","T"|> *)
```

`ResoniteThumbnailSurfaceHit` は Newton 法で S(x, y) = o + t·d を解き、(x, y) を含む升目の番号を返します。ワールドでのクリックは Resonite が升目のコライダーで同じことをしますが、これは面の設計を確かめるためのものです。

## フレンド向け PDF キャッシュ

標準ビューアの URL (`http://127.0.0.1:<port>/a/...`) は各クライアントが自分で取りに行くため、フレンドの PC では中身が見えません。`ResoniteRealtime_pdfcache.wl` は、ワールドが Private か Contacts で**自分がオーナー**のときだけ、PDF を初めて出すときに設定した web サーバへ sftp で一時的な写しを置き、`<$ResonitePDFCacheBaseURL>/<SHA-256>.pdf` を `StaticDocument` の URL にします。

- 名前は中身の SHA-256 です。同じ PDF は何度開いても同じ URL で、送るのは 1 回です。送る前に HEAD で確かめ、同じ大きさで置いてあればそのまま使い、消されていれば送り直します (60 秒以内に確かめた物は省きます)。
- 送っている間は 127.0.0.1 で開き (オーナーはすぐ見える)、終わったら URL を差し替えます。送り先には `<hash>.pdf.part` に送ってから rename します。
- 機密度が `$ResonitePDFCacheMaxLevel` (既定 0.5) を超える PDF、機密度が数値で取れない PDF は送りません (オーナーだけに見えます)。
- 通信は Git for Windows 同梱の sftp 対応 curl を使い、tick で終わりを拾います (待ちません)。パスワードはコマンドラインに出しません。
- `$ResonitePDFCache = False` で写しを置かなくなります。

### 設定

ソースにはサーバ名もアカウントもパスワードも書きません。設定は PC ごとの設定ファイル (`$UserBaseDirectory/ApplicationData/ResoniteRealtime/pdfcache_server.json`) です。設定が無ければ写しは置かず、状態欄と `ResonitePDFCacheStatus[]` が設定の仕方を案内します。

```wolfram
ResonitePDFCacheSetup["sftp://user@host/path/to/www/cache", "https://host/cache"]   (* 書き込み先 (sftp) と読む URL (https) *)
ResonitePDFCacheCredential[]            (* パスワードをダイアログで尋ね、NBAccess 経由で SystemCredential に保存 *)
ResonitePDFCacheSetup[]                 (* 今の設定と案内 *)
ResonitePDFCacheSetup[None]             (* 設定を消す (写しを置かなくなる) *)
```

- `$ResonitePDFCacheUploadURL` / `$ResonitePDFCacheBaseURL` の既定は設定ファイルの値で、無ければ `None` です。
- パスワードの保存名は既定で `sftp://user@host` (アカウント名) です。同じアカウントを使う他のパッケージ (SlideWorkflow 等) と同じ保存場所を共有します。パッケージごとに分けたいときは `ResonitePDFCacheSetup[..., "Credential" -> "名前"]` で専用の名前にします。サーバ設定自体は他のパッケージと独立です。
- `ResonitePDFCacheCredential[password]` で直接保存、`ResonitePDFCacheCredential[None]` で削除します。既定の名前のまま削除すると同じアカウントを使う他のパッケージのパスワードも消えるため、戻り値の `"Shared"` で知らせます。

### 状態と後始末

```wolfram
ResonitePDFCacheStatus[]                 (* <|hash -> <|"Status","Title","URL","Bytes","Error"|>|> *)
ResonitePDFCacheStatus["Skipped"]        (* 機密度が上限を超えて置かなかった PDF (直近 20) *)
ResonitePDFCacheRetry[]                  (* 失敗した写し (パスワード違い・通信失敗など) を確かめ直して送り直す *)
ResonitePDFCacheList[]                   (* サーバに置いてある写しの名前 (sftp で一覧。待つ) *)
ResonitePDFCacheClear[]                  (* この PC が置いた写し (台帳にある物) を消す *)
ResonitePDFCacheClear[All]               (* cache の *.pdf をすべて消す *)
ResonitePDFCacheClear["OlderThan" -> 7]  (* 台帳で 7 日より前に置いた物だけ *)
ResonitePDFCacheClear[{hash, ...}]       (* 指定した物 *)
```

パスワード未保存で止まった物は、`ResonitePDFCacheCredential[]` で保存すれば 10 秒以内に自動で送り直すので `Retry` は不要です。サムネイル一覧の見出しの「キャッシュ削除」ボタンは、どのフォルダの物かに関係なく cache の写し (`<SHA-256>.pdf`) をすべて消し、置いたビューアは 127.0.0.1 の URL に戻します。URL 自体はインスペクタ等で見え、ブラウザで直接取れるので、使い終わったら消してください。

## 3D オブジェクト (Graphics3D をメッシュに)

`Plot3D` / `ArrayPlot3D` / `SphericalPlot3D` / `Graphics3D` をワールド内の掴めるメッシュにします。ResoLoop パッケージと resoloop が必要です。

```wolfram
mesh = ResoniteGraphics3DMesh[Plot3D[Sin[x y], {x, 0, 3}, {y, 0, 3}]]   (* 頂点 / 三角形 / 頂点色 / 法線 *)
ResoniteMeshJSON[mesh]                                                  (* ResoniteLink の ImportMeshJSON 形式 *)
r = ResoniteGraphics3D[Plot3D[Sin[x y], {x, 0, 3}, {y, 0, 3}], "Size" -> 0.6]  (* ResoLoop_Graphics3D_<stamp> をアバターの正面に *)
ResoniteGraphics3DRemove[r]
```

- 座標は Mathematica (右手, z 上) から Resonite (左手, y 上) へ (x,y,z) → (x,z,y) にし、三角形の向きを裏返して外向き法線を保ちます。BoxRatios を反映し最長辺を `"Size"` (m) にします。
- `ResoniteGraphics3DMesh` の戻り値は `<|"Points","Triangles","Colors","Normals","Ignored","Bounds","Source"|>` です。面が無ければ `Failure["NoSurface"]`。Line / Point / Text / Arrow は落とし、`"Ignored"` に数を残します。オプション: `"Size" -> 0.6`、`"BoxRatios" -> Automatic`、`"MaxTriangles" -> 300000`、`"MaxCellMeasure" -> Automatic`、`"Color" -> GrayLevel[0.75]`。
- `ResoniteGraphics3D` のオプション: `"Size" -> 0.6`、`"Placement" -> "User" | "World"`、`"Distance" -> 1.2`、`"Position" -> {0, 1.2, -1.5}`、`"Rotation" -> None`、`"Offset" -> {0,0,0}`、`"Name" -> Automatic`、`"Project" -> Automatic`、`"Metallic" -> 0.05`、`"Smoothness" -> 0.35`、`"Collider" -> True`、`"Grabbable" -> True`、`"Timeout" -> 240`、`"Apply" -> True`。戻り値は `<|"Root","Key","Files","Vertices","Triangles","Ignored","Apply"|>` か Failure。
- 生成物は Grabbable + StaticMesh (`$asset:mesh`) + PBS_VertexColorMetallic (Culling Off) + MeshRenderer + MeshCollider (DualSided)。`"Apply" -> False` なら mesh.json / apply.json を書くだけです。
- 作業フォルダは `$ResoniteGraphics3DDirectory` (既定 `%LOCALAPPDATA%\ResoLoop\g3d`、同期フォルダの外)。使う resoloop プロジェクトは `$ResoniteGraphics3DProject` (既定 `Automatic` = ResoLoop の既定)。checkpoint の書き込み失敗は同じ apply の再実行で収束します。

## 設計上の約束

- 常駐 Dynamic でポーリングしない (パレット常駐 UpdateInterval は FrontEnd を殺す)。監視は ScheduledTask 1 本、Monitor は手動更新ボタン式。
- SocketListen のコールバックからは FrontEnd を触らない。コールバック内で Close / Pause しない。
- ScheduledTask / SessionSubmit / runtime のジョブの中では ResoniteLink の応答を待たない (`"Wait" -> False` + `sourceMessageId` 照合)。重い仕事は作業用カーネルへ回す (サムネイル一覧の機密度の引き直しも小分けにして回す)。
- 機密度は fail-closed。上限以上のもの、数値で取れないものは出さない。外のサーバに置く写しにも別の上限 (`$ResonitePDFCacheMaxLevel`) がある。
- インベントリから出した一覧は、署名と公開度を確かめるまで中身を隠す。署名が確かめられない一覧 (別の PC で作った一覧) は行を信用せず、Eagle の項目だけをこの PC の SourceVault から引き直し、それ以外は開けない升目にする。
- ResoniteLink は beta。メッセージ組み立ては 1 箇所 (`ResoniteRealtimeValue` / `ResoniteRealtimeLink`) に閉じ込め、スキーマ変更に追随しやすくする。

## 変数

| 変数 | 意味 |
| --- | --- |
| `$ResoniteRealtimeVersion` | パッケージの版 |
| `$ResoniteRealtimePublicBaseURL` | 画像配信の公開 URL |
| `$ResoniteWorldAccess` / `$ResoniteWorldAccessLevels` / `$ResoniteWorldOwner` | 現在の公開度、公開度 → 表示上限の表 (Private 1.0 / Contacts 0.5 / ContactsPlus 0.25 / Public 0.25)、所有者フラグ |
| `$ResoniteWorldAccessMode` / `$ResoniteOwnerUserId` | アクセスレベルの決め方 (`Automatic` / `"Manual"`)、オーナー判定に使うユーザー ID |
| `$ResoniteTabletCloudMaxLevel` (0.5) / `$ResoniteTabletMaxChars` (6000) / `$ResoniteTabletShowCode` / `$ResoniteTabletBuildMode` / `$ResoniteTabletDeferMode` | タブレットの設定 |
| `$ResoniteTabletWorker` (True) | サムネイルの帯・フォルダ一覧・PDF ページ数を作業用カーネルで作る |
| `$ResoniteTabletPagePoints` (480) / `$ResoniteTabletPageResolution` (192) | ビューアのページ幅 (pt) と解像度 (dpi) |
| `$ResonitePDFMode` / `$ResonitePDFLite` (True) | PDF の開き方 (`"Native"`)、雛形が無いとき `ResoniteDocViewer` を使うか |
| `$ResoniteBoardKeyFile` | サムネイル一覧の署名鍵ファイル (既定はこの PC だけの `board.key`。各 PC の鍵は SourceVault の PrivateVault の鍵束にも置かれ、別の PC の一覧の検証に使う) |
| `$ResoniteThumbnailShapes` / `$ResoniteThumbnailSurfaces` | 「形を変更」の巡回順、名前 → 面の定義の登録簿 |
| `$ResonitePDFCache` (True) / `$ResonitePDFCacheBaseURL` / `$ResonitePDFCacheUploadURL` / `$ResonitePDFCacheMaxLevel` (0.5) | フレンド向け PDF キャッシュの有効化、読む URL、書き込み先 (sftp)、置いてよい機密度の上限 |
| `$ResoniteGraphics3DDirectory` / `$ResoniteGraphics3DProject` | 3D 生成の作業フォルダと resoloop プロジェクト |
| `$ResoniteFluxSDK` / `$ResoniteFluxProjects` / `$ResoniteFluxGraphSpec` | ProtoFlux の設定と LLM に渡すグラフ記述の仕様文 |
| `$RRWSLastError` | WebSocket 層で最後に握りつぶされたハンドラ例外 |