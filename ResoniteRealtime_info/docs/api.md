# ResoniteRealtime API

Mathematica から Resonite (VR) を制御するブリッジ。ロード: `Block[{$CharacterEncoding = "UTF-8"}, Get["ResoniteRealtime.wl"]]`。
補助モジュール `ResoniteRealtime_ws.wl` (WebSocket 層)、`ResoniteRealtime_chat.wl` (Chat ガジェット)、`ResoniteRealtime_flux.wl` (ProtoFlux ガジェット) は自動ロードされる。
経路: L1 = WL が WebSocket サーバで世界の `WebsocketClient` (ProtoFlux) が繋ぐ (TAB 区切り行、速い、ホスト不要)。
L2 = WL が ResoniteLink (公式 WS+JSON) のクライアントで slot / component を読み書き (ホスト必須、リアルタイム制御には使わない)。
L3 = 同じポートで静的ファイル (画像) を配る。オプションはすべて文字列名。

## L1 ブリッジ (行プロトコル)
### ResoniteRealtimeStart[] → Association (Status)
Options: "Port" -> 17300, "Heartbeat" -> 25, "LinkPort" -> None, "BindAddress" -> "127.0.0.1", "HeartbeatMode" -> "Ping" | "Text"
WebSocket サーバを ws://127.0.0.1:17300/bridge に立てる。世界側は WebsocketClient の URL にこれを入れる。
### ResoniteRealtimeStop[] → Association
### ResoniteRealtimeStatus[] → <|"Running","Port","BridgeConnections","Link","LinkConnected","Events",...|>
### ResoniteRealtimeMonitor[] → DynamicModule (手動更新ボタン式。常駐ポーリングしない)
### ResoniteRealtimeSend[verb, args...] → Association (connId -> result) | Failure["NoBridgeConnection"]
世界へ `verb<TAB>arg...` を送る。ProtoFlux は JSON を扱えないので WL→世界は 2 フィールドまでにする。
### ResoniteRealtimeSendTo[connId, verb, args...]
### ResoniteRealtimeOn[verb, f] / ResoniteRealtimeOn[verb, None] / ResoniteRealtimeOn[]
世界からの行 (`<|"Verb","Args","Line","Connection","Time"|>`) にハンドラを登録する。verb に All で catch-all。合成 verb "$open" / "$close"。
ハンドラは SocketListen のコールバック内で走るので FrontEnd を触らない。
### ResoniteRealtimeEvents[n] → 直近 n 件の受信レコード

## L2 ResoniteLink
### ResoniteRealtimeLinkConnect[port] / ResoniteRealtimeLinkConnect[] → connId | Failure
引数無しは `ResoniteRealtimeDiscover[]` の最初の候補に繋ぐ (無ければ Failure["NoResoniteLink"])。Options: "Host" -> "localhost", "Quiet" -> False。
### ResoniteRealtimeDiscover[] → {<|"Port", "URL", "Process", "Source"|> ...}
有効化されている ResoniteLink のポート。(1) http.sys 登録一覧 (`netsh http show servicestate view=requestq` で Resonite / Renderite.Host のプロセスが
登録した `HTTP://LOCALHOST:<port>/`。即時)、(2) ResoLoop.wl があれば resoloop discover (約 12 秒)、(3) 環境変数 RESONITE_LINK_URL。
Options: "Host" -> "localhost" (127.0.0.1 は http.sys が 400 で弾く)
Dashboard → Session → Settings → Enable ResoniteLink で表示された port。
### ResoniteRealtimeLinkDisconnect[]
### ResoniteRealtimeLink[msg] → 応答 Association | Failure["ResoniteLinkError"|"Timeout"|"NotConnected"|"BadMessage"]
Options: "Timeout" -> 10, "Wait" -> Automatic ($iLinkWaitDefault、既定 True。ScheduledTask 内では Block で False にして送りっぱなしにする), "Match" -> Automatic, "Raw" -> False
生メッセージ送信。messageId を自動付与し sourceMessageId で照合する。
### ResoniteRealtimeGetSlot[slotId] → slotData
Options: "Depth" -> 0 (-1 で全階層), "IncludeComponentData" -> False, "Timeout" -> 10, "Wait" -> Automatic (False なら <|"Sent","MessageId"|> を返し、応答は ResoniteRealtimeLinkMessages から sourceMessageId で拾う)
### ResoniteRealtimeAddSlot["Name" -> ..., "Parent" -> "Root", "Position" -> {x,y,z}, "Rotation" -> {x,y,z,w}, "Scale" -> {..}, "Active" -> True, "Id" -> ...] → <|"Id", "Response"|>
### ResoniteRealtimeUpdateSlot[slotId, members] / ResoniteRealtimeRemoveSlot[slotId]
### ResoniteRealtimeAddComponent[slotId, componentType, members, componentId] → <|"Id", "Response"|>
componentType は `[FrooxEngine]FrooxEngine.Grabbable` のような Resonite の型名。members は名前 -> WL 値 (自動で型付け)。
### ResoniteRealtimeUpdateComponent[componentId, members]
### ResoniteRealtimeRef[id] → <|"$type"->"reference","targetId"->id|>
### ResoniteRealtimeValue[value] / ResoniteRealtimeValue[type, value]
String/Bool/Integer/Real/{x,y}/{x,y,z}/{x,y,z,w}/RGBColor を ResoniteLink の型付き値にする。Uri は ResoniteRealtimeValue["Uri", url]。
### ResoniteRealtimeNewId[prefix] → "WL<kernelTag>_<prefix>_<n>" (ID はセッション中解放されないのでカーネルごとのタグ入り)

## 表示 (板)
### ResoniteRealtimeBoard[] → ids Association
Options: "Position" -> {0,1.5,1.2}, "Rotation" -> None, "Size" -> 0.6, "Name" -> "Mathematica Board", "Parent" -> "Root", "Image" -> None
L2 だけで板 (StaticTexture2D + QuadMesh + UnlitMaterial + MeshRenderer) を作る。
### ResoniteRealtimeShowImage[expr] → url
Options: "Size" -> 800, "Verb" -> "img", "Send" -> True, "Target" -> Automatic | "Board" | "Bridge" | None
式を PNG にして配信し、板があれば板の URL を差し替え、無ければ L1 で `img<TAB>url` を送る。
### ResoniteRealtimeRemoveBoard[] / ResoniteRealtimeAsset[file]
### $ResoniteRealtimePublicBaseURL — 聴衆がいる場では公開 URL (127.0.0.1 は自分にしか見えない)

## Chat ガジェット (ResoniteRealtime_chat.wl)
ノートブックの Chat セル (ClaudeEval の ClaudeInput) をワールド内で実現する。docs/chat-gadget.md 参照。
### ResoniteAccessLevel[] → 0.25 | 1.0 / ResoniteAccessLevel["Public" | "Private"]
ワールドの公開度からアクセスレベルを決める (表は $ResoniteWorldAccessLevels、既定 Public 0.25 / Private 1.0。暫定)。
### ResoniteChat[prompt] → <|"Answer","PrivacyLevel","AccessLevel","Context","Shown","Evaluated"|> | Failure
Options: "Notebook" -> Automatic, "World" -> True, "SourceVault" -> Automatic, "Evaluate" -> False, "Model" -> Automatic, "Timeout" -> 180, "Origin" -> "Notebook"
LLM に投げて答えをノートブックとワールド内パネルへ出す。SourceVault KB の文脈は release context "resonite-public" / "resonite-private" で絞る。
PrivacyLevel = Max[プロンプトの機密度, 文脈の機密度] が 0.5 を越えるとローカル LLM。プロンプトの機密度 > アクセスレベルなら Failure["WorldAccessDenied"]。
### ResoniteChatCell[] → nb (ResoniteInput セルを挿入。Shift+Enter で ResoniteChat)
### ResoniteChatGadget[] → ids | Failure["NotConnected"]
Options: "Placement" -> "User" | "World", "Distance" -> 1.5, "Height" -> Automatic, "User" -> Automatic, "Position" -> {0,1.4,1.5}, "Parent" -> "Root", "Name" -> "Mathematica Chat", "CanvasSize" -> {1200, 800}, "PanelScale" -> 0.001, "FontSize" -> 28, "Board" -> True, "Backdrop" -> False
UIX パネル (入力欄 / 送信ボタン / 状態 / 答え) と板を L2 で組み立てる。既定でアバターの頭の正面 1.5 m に置く。世界側のノード作業は不要。
### ResoniteChatStart[] / ResoniteChatStop[]
Options: "PollInterval" -> 1.5, "Evaluate" -> False
送信チェックを ScheduledTask 1 本で監視し、世界側からの質問を処理する。L1 の `ask<TAB>質問` も受ける。
### ResoniteChatShow[text | expr] — 答え欄に文字列 / 板に画像
### ResoniteChatRemoveGadget[] / ResoniteChatLog[n] / ResoniteChatStatus[]

## 使用例
```mathematica
ResoniteRealtimeLinkConnect[41234];
ResoniteAccessLevel["Public"];
ResoniteChatGadget[]; ResoniteChatStart[];
ResoniteChat["フィボナッチ数列の最初の 10 項は?"]
ResoniteRealtimeShowImage[Plot[Sin[x], {x, 0, 2 Pi}]]
```

## ProtoFlux ガジェット (ResoniteRealtime_flux.wl)
プロンプトから ProtoFlux を ProtoGraph (Flux SDK のテキスト言語) として生成する。docs/protoflux-gadget.md 参照。
### ResoniteFluxGenerate[spec] → <|"Source","Module","File","Project","Unknown","Build","Rounds","Diagnostics","Answer","PrivacyLevel"|> | Failure
Options: "Format" -> "Graph" | "ProtoGraph", "Place" -> Automatic, "MaxRounds" -> 3, "Module" -> Automatic, "Model" -> Automatic, "Timeout" -> 300, "Build" -> Automatic, "SourceVault" -> False, "Origin" -> "Notebook", "Hints" -> 40
既定 (Graph): LLM にグラフ記述 JSON を書かせ、検証 → ResoniteLink で配置 → probes 読み戻し → 修正。戻り値に "Graph","Placed","Probes"。ProtoGraph: 静的検査 → (flux-sdk があれば) build。
### ResoniteFluxChat[prompt] → 同上 (ノートブックとワールド内パネルにも出す)。Options: ResoniteFluxGenerate + "Notebook", "World"
### ResoniteFluxCell[] → nb (ResoniteFluxInput セルを挿入)
### ResoniteFluxCatalog[] → {<|"Type","Name","Category","Inputs","Outputs","Impulses","Result"|>...} (3,317 ノード)
### ResoniteFluxCatalogSearch[query, n] → 上位 n 件
### ResoniteFluxUnknownNodes[source] → カタログにも予約語にも無いノード名のリスト
### ResoniteFluxBuild[pgFile] → <|"Success","ExitCode","Output","Diagnostics","Brson"|> | Failure["NoFluxSDK"]
### ResoniteFluxDeploy[result] → 手順 (Import: .brson をドラッグ&ドロップ) | "Method" -> "ResoniteLink" (実験的)
### $ResoniteFluxSDK (flux-sdk のパス、Automatic で探索) / $ResoniteFluxProjects (生成物の置き場)

## ProtoFlux リンカ (ResoniteRealtime_fluxlink.wl)
グラフ記述 (JSON/Association) を ResoniteLink でノードとして配置・結線する。ResoniteFluxGenerate の既定 "Format" -> "Graph" がこれを使う。
### ResoniteFluxValidateGraph[graph] → <|"OK","Errors","Warnings","Nodes"|>
### ResoniteFluxPlace[graph] → <|"Root","Nodes","Slots","Errors","ProbeNames","Probes"|> | Failure["NotConnected"|"InvalidGraph"]
Options: "Parent" -> Automatic (Chat パネルの根の左、無ければアバター正面), "Position" -> Automatic, "Name" -> Automatic, "Spacing" -> {0.35, 0.25}, "SpaceName" -> "wl"
### ResoniteFluxProbe[placed] → <|"wl/x" -> value ...|> / ResoniteFluxRemove[placed]
### ResoniteFluxBindingType["ValueAdd<float>"] → "[ProtoFluxBindings]FrooxEngine.ProtoFlux.Runtimes.Execution.Nodes.Operators.ValueAdd<float>"
### $ResoniteFluxGraphSpec — LLM に渡すグラフ記述の仕様文
### ResoniteFluxDisplay[placed, var] → <|"Slot","Text","Variable","Type","Converter"|>
Options: "Position" -> {0,0.4,0}, "Scale" -> 0.3, "Color" -> Yellow, "Type" -> Automatic
probe の動的変数を 3D テキストに出す (数値は ProtoFlux で文字列化)。ResoniteFluxGenerate は "Display" -> True (既定) で自動付与。
### ResoniteFluxDrive[placed, var, targetMemberId, type] → driver component id
DynamicValueVariableDriver<type> で世界のフィールド (メンバ ID) を動的変数で駆動する。

## タブレット (ResoniteRealtime_tablet.wl) — ClaudeEval をワールド内で走らせる
詳細は `tablet.md`。表示上限 (PL) を超えるもの・機密度が数値で取れないものは出さない (fail-closed)。
### ResoniteAccessLevel[] → 1.0 | 0.5 | 0.25 / ResoniteAccessLevel["Private" | "Contacts" | "ContactsPlus" | "Public", "Owner" -> True | False]
非オーナー (既定 `$ResoniteWorldOwner = False`) は一律 0.25。所有者/公開度は ResoniteLink から取れないので手で設定する。
### ResoniteTablet[] → ids | Failure["NotConnected"]
Options: "Placement" -> "User" | "World", "Distance" -> 1.2, "Height", "User", "Position", "Parent", "Name",
"CanvasSize" -> {1000, 1500}, "PanelScale" -> 0.0006, "FontSize" -> 26, "Viewer" -> True, "ViewerSize" -> 0.9,
"Notebook" -> Automatic | nb, "NotebookVisible" -> True, "Model" -> Automatic, "Start" -> True, "PollInterval" -> 1.0。
### ResoniteTabletServe[] / ResoniteTabletServe[False] → <|"Serve", "Linked", "Gadget", "Task"|>
常駐監視。ResoniteLink が無ければ 15 秒ごとに ResoniteRealtimeDiscover[] で探して繋ぎ、Root 直下の "Mathematica Tablet" (インベントリから出した物も)
を 5 秒 (引き継ぎ済みなら 15 秒) ごとに探して、「接続」ボタンが押されたものを ResoniteTabletAdopt で引き継ぐ。ノートブックのセッションでは
ロード時に自動で始まる (`$ResoniteTabletAutoServe`、既定 True)。Options: "PollInterval" -> 1.0, "Start" -> True。
### ResoniteTabletFind[] → {<|"Id", "Name", "Attached"|> ...} / ResoniteTabletAdopt[root | ] → ids | Failure["NotATablet" | "NoTablet"]
ワールドにあるタブレットを名前で探す / その構造 (スロット名 + コンポーネント型) から ids を復元して引き継ぎ、監視を始める。
### ResoniteTabletStart[] / ResoniteTabletStop[] / ResoniteTabletTick[]
`"Serve" -> True` でタブレット無しでも監視を始める (常駐監視用)。
監視 ScheduledTask (1 本)。Tick は 1 回分を手で回す (テスト用)。
### ResoniteTabletEval[prompt] / ResoniteTabletTurn[prompt]
Eval ボタンと同じ。Turn は専用ノートブックの Input セルとして評価される 1 ターン (ClaudeEval の runtime 経路。
PrivacySpec の AccessLevel = Min[表示上限, $ResoniteTabletCloudMaxLevel])。
### ResoniteTabletApprove[] / ResoniteTabletDeny[] / ResoniteTabletCancel[]
承認待ちへの応答 (claudecode の ClaudeRuntimeDecide 経由。ノートブックの承認ボタンと同じ処理)。
### ResoniteTabletShow[text | expr] / ResoniteTabletStatus[] / ResoniteTabletLog[n] / ResoniteTabletNotebook[]
### ResoniteTabletRemove[] / ResoniteTabletAttach[ids] / ResoniteTabletRegisterHeads[]
### ResoniteShowObject[x] → <|"Kind", "Title", "PrivacyLevel", "Pages", ...|> | Failure["PrivacyExceeded" | "NoSourceVault" | "Unsupported" | ...]
x: sv:// URI | 共通スキーマ行 | ファイルパス (pdf/png/jpg/mp4/txt/md/nb) | Image/Graphics | 行リスト | 文字列。
Options: "Title", "MaxPages" -> 200, "PageSize" -> 1200。
### ResoniteViewer[] / ResoniteViewerShow[pages] / ResoniteViewerPage[n | "Next" | "Prev" | "First" | "Last"] / ResoniteViewerRemove[]
ページ = Image | Graphics | {"PDF", file, n} | {"File", path}。PNG は URL 単位でキャッシュ。
### ResoniteListGadget[rows] → <|"Root", "Count", "Hidden", "Pages", "Title"|> / ResoniteListGadgetRemove[root | ]
Options: "Title", "RowsPerPage" -> 8, "Placement" -> Automatic (タブレットの左隣) | "User" | "World", "CanvasSize" -> {1400, 1000}, "FontSize" -> 30。
### ResoniteVideoBoard[urlOrFile] → ids (VideoTextureProvider + AudioOutput。再生開始は実機未確認)
### $ResoniteTabletMaxChars (6000) / $ResoniteTabletCloudMaxLevel (0.5) / $ResoniteTabletTurnRunner (テスト用フック)
### $ResoniteTabletBuildMode (Automatic | "Tick" | "Notebook") / ResoniteTabletDeferred[] / ResoniteTabletRunDeferred[id]
非同期文脈 (runtime の提案コード・Task 内・ターン進行中) で頼まれた ListGadget / PDFViewer / VideoBoard / Viewer の組み立ては
`<|"Deferred" -> True, "Id", "Via" -> "Tick" | "Notebook", ...|>` を即返して予約する。Automatic = 監視 tick が動いていれば tick の中で
待たずに組む (Send → getSlot → ButtonToggle 結線。失敗時は組みかけを消す)、無ければ専用ノートブックのセル `ResoniteTabletRunDeferred["id"]`。
台帳 `ResoniteTabletDeferred[]`、進行中 `ResoniteTabletStatus[]["Builds"]`。
### ResoniteTabletCleanup[] → 消した {<|"Id","Name"|>..} — Root 直下の "Mathematica Tablet" / "SourceVault List" / "PDF Viewer" 等を名前で消し、状態と予約を空にする (カーネル再起動後の残骸掃除)

## 3D オブジェクト (ResoniteRealtime_mesh.wl) — Graphics3D をワールド内のメッシュに
### ResoniteGraphics3DMesh[g] → <|"Points", "Triangles", "Colors", "Normals", "Ignored", "Bounds", "Source"|> | Failure["NotGraphics3D" | "NoSurface" | "TooManyTriangles"]
Plot3D / ArrayPlot3D / SphericalPlot3D / Graphics3D / Legended。GraphicsComplex の VertexColors を頂点色に、Polygon / Cuboid は直接、
Sphere / Cylinder / Cone / 多面体は DiscretizeGraphics、Translate / Rotate / Scale / GeometricTransformation は座標に畳む。
Line / Point / Text は落とす。BoxRatios を反映し最長辺を "Size" (0.6 m) に。座標は (x,y,z) → (x,z,y) (Resonite は y 上)。
Options: "Size", "BoxRatios" -> Automatic, "MaxTriangles" -> 300000, "MaxCellMeasure", "Color" -> GrayLevel[0.75]。
### ResoniteMeshJSON[mesh] → String (ResoniteLink 0.13.1 ImportMeshJSON: vertices position/normal/color/uvs, submeshes trianglesFlat)
### ResoniteGraphics3D[g] → <|"Root", "Key", "Files", "Vertices", "Triangles", "Ignored", "Placement", "Apply", "Seconds"|> | Failure
resoloop プロジェクトの content/g3d/ に mesh.json + apply.json を書き、ResoLoopValidate (strict) → ResoLoopApply。
ResoLoop_Graphics3D_<stamp> = Grabbable + AI_GeneratedContent / _Assets (StaticMesh "$asset:mesh", PBS_VertexColorMetallic Culling Off) /
Model (MeshRenderer, MeshCollider DualSided)。Options: "Placement" -> "User" | "World", "Distance" -> 1.2, "Position", "Rotation",
"Offset", "Name", "Project" -> Automatic, "Metallic" -> 0.05, "Smoothness" -> 0.35, "Collider", "Grabbable", "Timeout" -> 240,
"Apply" -> True (False で書くだけ) + ResoniteGraphics3DMesh のオプション。
### ResoniteGraphics3DRemove[result | rootName] (ResoLoopSlotDelete。承認ヘッド)
### ResoniteTabletMake3D[] — タブレットの「3D生成」ボタン。直前のターンの Graphics3D (claudecode の $ClaudeRuntimeDisplayHook で拾う) を ResoniteGraphics3D へ
### ResonitePDFViewer[file | pages] → <|"Root", "Pages", "Page", "Title"|> | <|"Deferred" -> True, ...|> | Failure
掴める PDF ビューアパネル (ページ画像 + ページ送り)。呼ぶたびに新しいビューアを増やし、前のは残る (2 つ目以降は右下手前へ {0.12,-0.05,-0.06} m ずつずらす)。
Options: "Placement", "Distance" -> 1.0, "Offset" -> {0.65,0,0}, "Position", "Parent", "CanvasSize" -> {1000,1400}, "PanelScale", "FontSize", "Title",
"PageSize" -> 1200, "MaxPages" -> 400, "Reuse" -> False (True = 最新のビューアへ読み込む、root 文字列 = そのビューアへ)。
### ResonitePDFViewerPage[[root,] n | "Next" | "Prev" | "First" | "Last" | "+10" | "-10"] / ResonitePDFViewerRemove[[root | All]]
root 省略は最新のビューア。`ResoniteTabletStatus[]["PDFViewers"]` に root -> <|"Pages","Page","Title"|> の一覧、`["PDFViewer"]` は最新。
### ResoniteColorToggleBox[{c1, c2}] → <|"Root", "Mesh", "Material", "Driver", "Colors", "Shape", "Size", "Parent"|> | <|"Deferred" -> True, ...|> | Failure (2026-09-23)
クリック (レーザー / タッチ) するたびに色が c1 <-> c2 と切り替わる箱 (球)。`ResoniteColorToggleBox[]` は {Red, Blue}。ProtoFlux 不要:
BoxMesh|SphereMesh + UnlitMaterial (TintColor = c1) + MeshRenderer + BoxCollider|SphereCollider + TouchButton (AcceptRemoteTouch/PhysicalTouch) +
BooleanValueDriver<colorX> (State: bool 値 = False, TargetField -> UnlitMaterial.TintColor, True = c2, False = c1) + ButtonToggle (TargetValue -> driver の State)。
**BooleanValueDriver.State は参照ではなく bool 値** (FrooxEngine.dll 反射で確認。初版は ValueField への参照を書いて動かなかった)。
参照 2 つ (driver.TargetField、toggle.TargetValue) はメンバ ID が要るので、非同期文脈 (LLM の提案コードの実行中 / tick) では監視 tick の
Send → getSlot → 1 巡目 (driver) → getSlot → 2 巡目 (toggle) で結線する (`$itWireRounds` / `itBuildWire` の "Rounds")。
Options: "Shape" -> "Box" | "Sphere", "Size" -> 0.2 (m), "Placement" -> "User" | "World", "Distance" -> 1.0, "Height", "Position", "Parent",
"Offset" -> {-0.55,-0.1,-0.2} (tick 内の組み立てでタブレットの子になるときの位置), "Name", "Grabbable" -> True, "ButtonComponent" -> "TouchButton"。
LLM の提案コードから呼べる許可ヘッド (承認不要)。`ResoniteRealtimeStatus` / `ResoniteFluxCatalogSearch` / `ResoniteFluxCatalog` /
`ResoniteRealtimeLinkMessages` / `ResoniteTabletDeferred` (読むだけ) も同日から許可ヘッド。

