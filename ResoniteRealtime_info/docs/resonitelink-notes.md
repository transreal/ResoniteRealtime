# ResoniteLink (L2) 実機メモ

2026-09-04〜05 に実機 (Resonite Beta 2026.9.2.1275) で確かめたことだけを書く。
公式ドキュメントに書かれていない、あるいは書かれていても踏み抜いた点が中心。

## 有効化

Dash → **セッション** → 設定タブ → 左下の **「Resoniteリンクを有効化」**。
押すと `Resoniteリンクがポート <番号> で動作中` に変わる。この番号を使う。
同じ画面に「ワールドを保存」もある。

## **接続先は localhost。127.0.0.1 では繋がらない**

```
ws://localhost:13116/     ← OK
ws://127.0.0.1:13116/     ← HTTP/1.1 400 Bad Request (Server: Microsoft-HTTPAPI/2.0)
```

ResoniteLink は .NET の HttpListener (http.sys) で待ち受けており、登録されている
プレフィックスが `localhost` なので、`127.0.0.1` で来た要求は **http.sys がアプリに渡す前に**
400 で弾く。Node の WebSocket クライアントでも同じなので、クライアント実装の問題ではない。

ポート番号が分からないときは `ResoniteRealtimeDiscover[]` が有効なポートを探す
(順に Windows の http.sys 登録一覧 `netsh http show servicestate`、ResoLoop.wl があれば `resoloop discover`、環境変数 `RESONITE_LINK_URL`)。
`ResoniteRealtimeLinkConnect[]` を引数なしで呼ぶとこの探索結果に接続する (候補が無ければ `Failure["NoResoniteLink"]`)。

## メッセージのエンベロープ

リクエストに `messageId` を入れると、応答の `sourceMessageId` に返ってくる。
**これが相関 ID。** フィールド名は `id` でも `sourceMessageId` でもなく `messageId`。

応答は成否によらず次を持つ:

| フィールド | 内容 |
| --- | --- |
| `$type` | `slotData` / `componentData` / `newEntityId` など。**要求の型とは対にならない** (`getSlot` → `slotData`) |
| `sourceMessageId` | 要求の `messageId`。付けなければ `null` |
| `success` | Bool |
| `errorInfo` | 失敗時の文字列 (例 `Slot with ID 'NoSuchSlot' not found.`) |

`$type` では要求と応答を対応付けられないので、**照合は `sourceMessageId` で行う**。

## 値の型名 (`$type`)

ResoniteLink のモデル定義 (`Models/DataModel/PrimitiveContainers.cs` ほか) の
`JsonDerivedType` に一致する名前でなければ
`Read unrecognized type discriminator id '...'` で弾かれる。

| 用途 | 書き方 |
| --- | --- |
| 文字列 | `{"$type":"string","value":"..."}` |
| 数値 | `"int"` / `"float"` / `"double"` / `"long"` (`"int?"` のような nullable 版もある) |
| 真偽 | `{"$type":"bool","value":true}` |
| ベクトル | `{"$type":"float3","value":{"x":..,"y":..,"z":..}}` (`float2` / `float4` も) |
| 色 | `"color"` / `"colorX"` |
| **URL** | `{"$type":"Uri","value":"http://..."}` — **大文字始まり。`"uri"` は弾かれる** |
| 参照 | `{"$type":"reference","targetId":"..."}` |
| **リスト (SyncList)** | `{"$type":"list","elements":[ ... ]}` — 配列を直接書くと `could not be converted to ResoniteLink.Member` |
| **enum** | `{"$type":"enum","value":"MinSize"}` — 名前だけ通る (int や型名指定は ResoniteLinkError) |
| 日時 / 時間 | `"DateTime"` / `"TimeSpan"` |

## ID の寿命

- クライアントが決めた ID は **Resonite のセッションが続く限り登録が残る**。
- **`removeSlot` しても ID は解放されない。** 同じ ID をもう一度使うと
  `ID 'X' is already in use`。
- したがって **連番だけの ID は危険**。カーネルを再起動して連番が 1 に戻ると、
  前のカーネルが使った ID と衝突する (実際に踏んだ)。
  `ResoniteRealtimeNewId` はカーネルごとのタグを混ぜて `WL<tag>_Board_7` の形にしてある。

## 「画像を映す板」のレシピ (実機で成功した最小構成)

1 つの Slot に 4 つのコンポーネントを載せるだけ。**世界側の操作は一切不要**。

| # | 操作 | 内容 |
| --- | --- | --- |
| 1 | `addSlot` | 位置・スケール・名前。親は `Root` |
| 2 | `addComponent` | `[FrooxEngine]FrooxEngine.StaticTexture2D`、`URL` に `{"$type":"Uri", ...}` |
| 3 | `addComponent` | `[FrooxEngine]FrooxEngine.QuadMesh` (members 不要) |
| 4 | `addComponent` | `[FrooxEngine]FrooxEngine.UnlitMaterial`、`Texture` に texture の `reference` |
| 5 | `addComponent` | `[FrooxEngine]FrooxEngine.MeshRenderer`、`Mesh` に quad の `reference`、`Materials` に `list`/`elements` |

`QuadMesh` は正方形なので、画像の縦横比は **slot の `scale`** で合わせる
(`ResoniteRealtimeBoard` / `ShowImage` が自動でやる)。

絵の差し替えは `updateComponent` で `StaticTexture2D` の `URL` を書くだけ。
**Resonite は URL 単位でアセットをキャッシュする**ので、毎回別のファイル名にすること
(`ShowImage` はミリ秒を名前に入れている)。

## 画像の配り方

`ResoniteRealtime` は **ブリッジと同じポート (既定 17300) で HTTP も受ける**。
`ShowImage` は PNG を配信ディレクトリに書き、`http://127.0.0.1:17300/a/<name>.png` を返す。
ws と同じ host:port なので、一度許可したホストアクセスがそのまま効く。

**HTTP の URL アセットは各クライアントが個別に取りに行く。**
`127.0.0.1` は自分にしか見えないので、聴衆がいるセッションでは
`$ResoniteRealtimePublicBaseURL` に公開 URL を設定し、配信ディレクトリの中身を
そこへ置くこと。

PDF については、ワールドが Private / Contacts で自分がオーナーのとき、初めてワールドに出す時点で
web サーバへ sftp で一時的な写し (`<SHA-256>.pdf`) を置き、`StaticDocument.URL` をその URL にできる
(`ResoniteRealtime_pdfcache.wl`、`$ResonitePDFCache` 既定 True)。サーバ設定は PC ごとの設定ファイル
(`$UserBaseDirectory/ApplicationData/ResoniteRealtime/pdfcache_server.json`) だけで、ソースには書かない。

- `ResonitePDFCacheSetup["sftp://user@host/path", "https://host/cache"]`: 置き先 (sftp) と読み出し URL (https) を設定。引数なしで現在の設定と案内、`None` で設定消去。オプション `"Credential"` でパスワード名を専用にできる。
- `ResonitePDFCacheCredential[]`: sftp パスワードを NBAccess 経由の SystemCredential に保存 (`[password]` で直接、`[None]` で削除)。
- `ResonitePDFCacheStatus[]` / `ResonitePDFCacheStatus["Skipped"]`: 写しの状態、機密度超過で置かなかった PDF。
- `ResonitePDFCacheRetry[]`: 失敗した写しの送り直し。
- `ResonitePDFCacheList[]` / `ResonitePDFCacheClear[]`: サーバ上の写しの一覧と削除 (`All`、`"OlderThan" -> days`、ハッシュのリストも指定可)。
- `$ResonitePDFCacheMaxLevel` (既定 0.5): これを超える機密度の PDF は置かない。`$ResonitePDFCacheBaseURL` / `$ResonitePDFCacheUploadURL`: 現在の読み出し URL と置き先。

## できないこと / 注意

- **ホストである必要がある** (公式明記)。
- リアルタイム制御には向かない (公式明記)。連続的な駆動は in-world の
  WebSocket/OSC 経路を使う。実測の目安: L1 の往復が 32.5 ms。
- **beta。破壊的変更があり得る。** WL 側はメッセージ組立を `iRLMessage` / `iRLValue`
  相当 (`ResoniteRealtimeValue` / `ResoniteRealtimeLink`) に閉じ込めてある。

## 2026-09-22: 1 接続 100 メッセージ目で必ずタイムアウトしていた (修正済)

受信バッファ `$iLinkMessages` は `$iLinkLimit` (100) 件で切り詰められるのに、`ResoniteRealtimeLink` の待ちは「送信前の件数より後ろ」だけを見ていたため、接続内 101 件目以降の応答が永遠に見えず `Failure["Timeout"]` になった (タブレットの組み立て ~100 メッセージで実測。chat ガジェットは ~60 で気付かなかった)。送信時刻以降に受けたメッセージから `sourceMessageId` で照合する形に直した。
同日実測: enum は `<|"$type"->"enum","value"->"MinSize"|>` だけ通る (int / 型名指定は ResoniteLinkError)、`updateSlot` の `isActive` でスロットの有効/無効を切り替えられる、複数カーネルからの同時接続は可。

## L2 の上に載るモジュール (補助ファイル)

`ResoniteRealtime.wl` が自動でロードする補助ファイルは、すべて本体の `ResoniteRealtimeAddSlot` / `AddComponent` / `UpdateComponent` / `UpdateSlot` / `GetSlot` を通して L2 を使う (補助ファイルに `$type` を直書きしない)。共通の約束は次のとおり。

- 常駐 Dynamic でポーリングしない。世界側入力の監視は `ScheduledTask` 1 本 (Start / Stop を必ず対にする)。
- `ScheduledTask` / `SocketListen` のコールバックの中では FrontEnd を触らない。
- 監視の tick の中では ResoniteLink の応答を**待たない**。`getSlot` は `"Wait" -> False` で送り、次の tick で `sourceMessageId` を照合する。書き込みは `Block[{$iLinkWaitDefault = False}, ...]` で送りっぱなしにする。

### WebSocket 層 (`ResoniteRealtime_ws.wl`)

純 Wolfram の RFC 6455 実装 (サーバ・クライアント両方、依存ゼロ)。ResoniteLink へ繋ぎに行くクライアント側と、世界の WebsocketClient を受けるサーバ側を同じフレーム codec で賄う。公開 API: `RRWSServe` / `RRWSStopServe` / `RRWSConnect` / `RRWSSend` / `RRWSPing` / `RRWSClose` / `RRWSStatus` / `RRWSConnections` / `RRWSSweep`、`$RRWSLastError`。

- 書き込みは `SocketWriteMessage[..., "Blocking" -> True]` を 64 KB ずつ (2026-09-24 に変更。旧: `BinaryWrite` 512 B ずつ)。タスクやコールバックの中の `BinaryWrite` は待たずに積むだけで、溢れると黙って捨てられるため。
- ハンドラ内で `Pause` しない。`SocketListen` のコールバック内で Close するとカーネルが落ちるので、閉じ待ちの回収は `RRWSSweep[]` に任せる。

### Chat とアクセスレベル (`ResoniteRealtime_chat.wl`)

L2 だけで UIX パネル (入力欄 / 送信 / 答え / 板) を組み立てる。世界側のノード作業はゼロ。

- `ResoniteChatGadget[]` / `ResoniteChatAttach[ids]` / `ResoniteChatRemoveGadget[]`: パネルの組み立て、別カーネルが作ったパネルの引き継ぎ、削除。既定ではアバターの頭の正面 (`"Placement" -> "User"`) に置く。
- `ResoniteChatStart[]` / `ResoniteChatStop[]`: 入力監視の `ScheduledTask`。
- `ResoniteChat[prompt]` / `ResoniteChatCell[]`: ノートブック側。`ResoniteChatShow` / `ResoniteChatLog` / `ResoniteChatStatus` で表示・記録・状態。
- 公開度とアクセスレベル: `$ResoniteWorldAccess` (Private / Contacts / ContactsPlus / Public)、`$ResoniteWorldAccessLevels` (既定 1.0 / 0.5 / 0.25 / 0.25)、`$ResoniteWorldOwner` (オーナーでなければ一律 0.25)、`$ResoniteWorldAccessMode` (Automatic か "Manual")、`$ResoniteOwnerUserId`。`ResoniteAccessLevel[]` で現在の表示上限を取得。`ResoniteAccessLevel[Automatic]` で自動判定に戻る。
- 自動判定は監視が Root 直下の `"Mathematica World Info"` スロット (SessionInfoSource + ProtoFlux の WorldSessionID) を読み、公開度・ホスト・ワールド記録の所有者から決める。ホスト = 所有者ならオーナー。

### タブレット (`ResoniteRealtime_tablet.wl`)

`ResoniteTablet[]` が入力欄 / Eval / 承認・拒否 / スクロール出力 / 画像ビューアを組み立てて監視も始める。Eval は専用ノートブック「Resonite Tablet」に `ResoniteTabletTurn[...]` の Input セルを書いて評価し、ノートブックの `ClaudeInput` 評価と同じ処理 (ClaudeEval の runtime 経路) を走らせる。

- 制御: `ResoniteTabletStart` / `Stop` / `Tick` / `Eval` / `Approve` / `Deny` / `Cancel` / `Show` / `Status` / `Remove` / `Attach` / `Notebook` / `Log` / `NoteTurnResult` / `RegisterHeads`。
- `ResoniteTabletMake3D[]`: 直前の結果の Graphics3D を 3D オブジェクトにする (「3D生成」ボタン)。
- `ResoniteShowObject[x]`: sv:// URI / SourceVault の行 / ファイル / 画像 / 式をワールド内に出す一般 API。`ResoniteListGadget[rows]` は行リストをボタン付き一覧にする。
- 表示上限: 機密度が上限**以上**のものは出さない (等しくても出さない)。数値が取れないものは fail-closed。LLM に渡す AccessLevel は `Min[表示上限, 0.5]`。

### 文書ビューアとサムネイル一覧 (`ResoniteRealtime_docboard.wl`)

- `ResoniteDocViewer[file]` / `ResoniteDocViewerRemove[]`: 標準ビューアの雛形が無くても、Resonite 自身の部品 (`StaticDocument` → `DocumentPageTexture` → `SpriteProvider`) で PDF を開く。ページ送り (`<<` `<` `>` `>>`) と閉じるはワールド内の `ButtonValueShift<int>` / `ButtonValueSet<int>` / `ButtonDestroy` だけで動く。`$ResonitePDFLite` (既定 True) が False なら従来どおり Wolfram でページを画像にする自前パネルに落ちる。
- サムネイル一覧はインベントリに保存して使い回せる。帯の画像は `importTexture2DFile` で Resonite の資産 (`local://`) に取り込む。行データと配置は HMAC-SHA256 署名つきの JSON として子 `"Data"` の `ValueField<string>` に入れ、鍵は `$ResoniteBoardKeyFile` (この PC だけ)。署名が合わなければ「接続」を断る。
- インベントリから出した一覧は、「接続」(State の `Selected = -3`) を押して監視が署名とワールド情報 (公開度・ホスト・所有者) を確かめるまで升目を隠す。`ResoniteBoardAdopt[root]` が同じ引き継ぎ、`ResoniteBoardDiagnose[]` が「接続」が効かないときの診断。
- 重い仕事 (帯の画像化・Eagle フォルダ一覧・大きな PDF のページ数) は作業用サブカーネルに回す (`$ResoniteTabletWorker`、既定 True)。tick を長く塞ぐと FE の Dynamic が待たされ「動的評価の放棄」ダイアログが出るため。`ResoniteTabletWorkerStatus[]` / `ResoniteTabletWorkerStop[]` で状態確認・停止。

### 曲面に貼る (`ResoniteRealtime_surface.wl`)

サムネイル一覧を平面座標 → 3D 点の写像 S(x, y) で曲面に貼る。升目ごとの接平面に小さな Canvas を置き、帯テクスチャの矩形を `SpriteProvider.Rect` で切り出す。クリックは Resonite が升目のコライダーで解決する。

- 面の定義: `ResoniteThumbnailSurface[name]` (組み込み `"Plane"` / `"Cylinder"` / `"SphereInside"` / `"Mobius"` / `"TorusOutside"`) または `ResoniteThumbnailSurface[Function[{x, y, g}, {X, Y, Z}], opts]`。登録簿は `$ResoniteThumbnailSurfaces`。
- `ResoniteThumbnailShape[root, shape]` と一覧の「形を変更」ボタン (`Selected = -4`) が `$ResoniteThumbnailShapes` の順に形を巡回する。
- `ResoniteThumbnailSurfaceFrames` (点ごとの位置・向き) と `ResoniteThumbnailSurfaceHit[root, {origin, dir}]` (光線と面の交点の升目。Newton 法) で面の設計を確かめられる。
- 実機メモ (2026-09-26): 帯全体を升目の外まで広げた Image を UIX Mask で切る作りは、Mask が切らず升目ごとに帯全体が出たので、`SpriteProvider.Rect` で切り出す方式にした。

### 3D オブジェクト (`ResoniteRealtime_mesh.wl`)

- `ResoniteGraphics3DMesh[g]` が Graphics3D (Plot3D / ArrayPlot3D / SphericalPlot3D など) を三角形メッシュにする。座標は Mathematica (右手・z 上) → Resonite (左手・y 上) で (x,y,z) → (x,z,y)。反転なので三角形の向きを裏返す。`ResoniteMeshJSON[mesh]` は ResoniteLink 0.13.1 の `ImportMeshJSON` 形式の JSON にする。
- `ResoniteGraphics3D[g]` は mesh.json + apply.json を書き、ResoLoop.wl の `ResoLoopValidate` (strict) → `ResoLoopApply` で `ResoLoop_Graphics3D_<stamp>` を作る。`ResoniteGraphics3DRemove` で消す。
- 作業ファイルの場所は `$ResoniteGraphics3DDirectory` (既定 `%LOCALAPPDATA%\ResoLoop\g3d`)。Dropbox 配下だと Dropbox が checkpoint を掴んで `APPLY_STATE_WRITE_FAILED` になる (2026-09-22 実機)。使うプロジェクトは `$ResoniteGraphics3DProject`。

### ProtoFlux (`ResoniteRealtime_fluxlink.wl` / `ResoniteRealtime_flux.wl`)

2026-09-06 に Resonite 2026.9 / ResoniteLink 0.13 で確かめた、ProtoFlux ノードを L2 で置くときの仕様:

- ノードは ProtoFluxBindings のコンポーネント。論理ノードは `[ProtoFluxBindings]FrooxEngine.ProtoFlux.Runtimes.Execution.Nodes.<Cat>.<Node><float>`、コアノードは `[ProtoFluxBindings]FrooxEngine.FrooxEngine.ProtoFlux.CoreNodes.<Node><[FrooxEngine]FrooxEngine.Slot>`。**型名を間違えると応答が来ない (タイムアウト)**。
- 入力 (`SyncRef<INodeValueOutput<T>>`) は出力元ノードのコンポーネント ID への reference。複数出力のノード (`Unpack_Float3` の X/Y/Z など) はそのメンバ ID。インパルス出力 (`OnUpdate` など) は行き先ノードのコンポーネント ID への reference。
- 定数は `ValueInput<T>` / `ValueObjectInput<string>` の `Value`。世界のスロット/コンポーネントは `GlobalReference<T>` + `ElementSource<T>`。
- 動的変数への書き込み先には `DynamicVariableSpace` が要る (無いと `OnNotFound` で何も起きない)。置いたノード群はそのまま実行される。

API:

- `ResoniteFluxBindingType` / `ResoniteFluxValidateGraph` / `ResoniteFluxPlace` / `ResoniteFluxProbe` / `ResoniteFluxRemove` / `ResoniteFluxDisplay` / `ResoniteFluxDrive`、仕様文 `$ResoniteFluxGraphSpec`。`ResoniteFluxDrive` は `DynamicValueVariableDriver<type>` で世界のフィールドを駆動する (ValueFieldDrive の駆動先は ResoniteLink で書けないが、この経路なら駆動できる)。
- ProtoGraph 経由の生成: `ResoniteFluxGenerate` (静的検査 → flux-sdk build → 修正ループ、`"MaxRounds"` など) / `ResoniteFluxChat` / `ResoniteFluxCell` / `ResoniteFluxDeploy`。カタログは `ResoniteFluxCatalog` / `ResoniteFluxCatalogSearch` / `ResoniteFluxUnknownNodes`、ビルドは `ResoniteFluxBuild`。`$ResoniteFluxSDK` / `$ResoniteFluxProjects` で flux-sdk のパスと置き場を指定する。flux-sdk が無くても生成と静的検査までは動く。カタログ (`references/protoflux-nodes.json`) は公開リポジトリに含まれないので、利用者が setup.md の手順で作る。

関連リポジトリ: [ResoniteRealtime](https://github.com/transreal/ResoniteRealtime)、補助モジュール [ResoniteRealtime_chat](https://github.com/transreal/ResoniteRealtime_chat) / [ResoniteRealtime_tablet](https://github.com/transreal/ResoniteRealtime_tablet) / [ResoniteRealtime_docboard](https://github.com/transreal/ResoniteRealtime_docboard) / [ResoniteRealtime_surface](https://github.com/transreal/ResoniteRealtime_surface) / [ResoniteRealtime_mesh](https://github.com/transreal/ResoniteRealtime_mesh) / [ResoniteRealtime_pdfcache](https://github.com/transreal/ResoniteRealtime_pdfcache) / [ResoniteRealtime_fluxlink](https://github.com/transreal/ResoniteRealtime_fluxlink) / [ResoniteRealtime_flux](https://github.com/transreal/ResoniteRealtime_flux) / [ResoniteRealtime_ws](https://github.com/transreal/ResoniteRealtime_ws)。