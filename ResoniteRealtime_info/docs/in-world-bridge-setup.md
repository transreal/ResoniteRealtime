# in-world ブリッジの作り方 (L1) と ResoniteLink の有効化 (L2)

`ResoniteRealtime.wl` を使うために **Resonite 側で 1 回だけやること**をまとめます。
WL 側の実装と検証は済んでいます (`ResoniteRealtime_info/references/tests/`)。ここは実機作業です。

`ResoniteRealtime.wl` は補助モジュール (`_ws` / `_chat` / `_tablet` / `_docboard` / `_surface` / `_pdfcache` / `_mesh` / `_flux` / `_fluxlink`) を自動でロードします。L1 / L2 の経路を作ったあとにそれらの上に載るガジェットを使う場合は、末尾の「L2 の上に載るガジェット」を参照してください。

---

## L1: ブリッジオブジェクト (世界 ⇄ Mathematica のリアルタイム経路)

WL 側が WebSocket サーバなので、**世界側がクライアントとして繋ぎに行きます**。
ホストである必要はありません。他人のセッションでも自分のアバターに付けて動きます。

### 手順

1. **空の Slot を作る。**
   Create New → Empty Object。名前は `ResoniteRealtime Bridge` などにします。
   ワールドに置いてもよいし、アバターに付けてもよいです (どこでも繋がります)。

2. **`WebsocketClient` コンポーネントを付ける。**

   | フィールド | 値 |
   | --- | --- |
   | `URL` | `ws://127.0.0.1:17300/bridge` |
   | `HandlingUser` | **自分**(Mathematica が動いているマシンのユーザ) |
   | `AccessReason` | `Mathematica bridge (ResoniteRealtime)` |
   | `ConnectRetryInterval` | 5 |

   - `HandlingUser` を間違えると、その人のマシンの localhost に繋ごうとして失敗します。
   - Mathematica が**別 PC**で動いているなら、WL 側を
     `ResoniteRealtimeStart["BindAddress" -> "0.0.0.0"]` で起動し、
     URL をその PC の LAN IP (`ws://192.168.x.y:17300/bridge`) にします。

   ### 実機で通した構成 (2026-09-04、L1 開通・RTT 32.5 ms)

実際に動いたノード構成は次のとおりです。**`HandlingUser` フィールドには何も書きません**
(`WebsocketConnect` ノードの入力で渡します)。

```
Source(ValueField<bool>.Value) ─▶ FireOnLocalTrue.Condition
FireOnLocalTrue.OnChange ─▶ WebsocketConnect.*
ChangeableSource(WebsocketClient) ─▶ WebsocketConnect.Client
Source(WebsocketClient.URL) ─▶ WebsocketConnect.URL
LocalUser ─▶ WebsocketConnect.HandlingUser

(エコー試験用)
WebsocketTextMessageReceiver.OnReceived ─▶ StartAsyncTask.*
StartAsyncTask.TaskStart ─▶ WebsocketTextMessageSender.*
WebsocketTextMessageReceiver.Data ─▶ WebsocketTextMessageSender.Data
ChangeableSource(WebsocketClient) ─▶ Receiver.Client / Sender.Client (Drive)
```

操作面の落とし穴 (全部踏みました):

- **ノードは「床など当たり判定のある面」を狙ってダブルクリックしないと置けません。**
  空を狙っても何も起きません。ノードブラウザは「項目をダブルクリックで選択 (名前がツールの
  上に出る) → 置き場所をダブルクリックで生成」の 2 段構えです。
- **`Receiver.OnReceived` (Call) は `Sender.*` (IAsyncOperation) に直結できません。**
  間に `Flow > Async > StartAsyncTask` を挟みます。型が違うと線がつながらないだけで
  エラーも出ないので気付きにくいです。
- ノードの `Client` 入力に参照ノードを落とすと **Drive / Write** を聞かれます。
  常時つないでおきたいので **Drive** を選びます (`Reference Drive<Websocket Client>` が生えます)。
- デスクトップのキー: 左クリック=使う/つなぐ、**T**=コンテキストメニュー、右クリック=掴む、
  **R**=ノード選択、**Ctrl+左クリック**=ワイヤを切る。ダイアログのボタンが押せないときは
  **ESC** でマウスカーソルを解放します。
- 実測: WL → 世界 → WL の往復 **32.5 ms**。ProtoFlux はフレーム同期なので
  60 fps だと 1〜2 フレームが下限です。毎フレームの数値ストリームには向きません (OSC を使います)。
- エコー構成にすると **heartbeat も返ってきます**。害はありませんが Events に溜まります。

### `HandlingUser` の落とし穴 (2026-09-04 実機で踏んだ)

   `HandlingUser` は生の User 参照ではなく **`UserRef`** という入れ子型で、
   `User` / `_machineId` / `_userId` の 3 つを持ちます。再入室しても同じ人を指し直せるように
   ID を覚えておく仕組みで、**実際に効くのは解決済みの `User` フィールド**です。

   - **`_userId` はユーザ名ではありません。** Resonite の User ID は必ず `U-` で始まり、
     ユーザ名と一致する保証はありません (移行アカウントは似ていることが多いですが、
     新規アカウントはランダムです)。`_userId` に `nconc` と入れても解決しません。
     自分の ID はアカウントサイトか `UserUserID` ノードで確認します。
   - **`User: null` のままだと誰も接続を張りません。**

   代入の仕方は 2 通りあります。**ProtoFlux (下の最小構成) を勧めます**。

   - **ProtoFlux**: `LocalUser` を `Write` で `HandlingUser.User` に書きます。
     ID も掴み操作も要らず、誰がスポーンしても自分が HandlingUser になります。
   - **インスペクタだけ**: 参照の代入は「行の左端のフィールドハンドルを掴む →
     代入先の行のハンドル (フィールド名側) に落とす」です。ただし User 参照を持っている
     場所を先に探す必要があり遠回りです。`_userId` を手で入れる手もありますが、
     正しい `U-` 付き ID と `_machineId` が絡むので立ち上げ時には勧めません。

   (`Parent:` / `User:` の横にある 2 つの小さいボタンの機能は公式 wiki に記載がありません。
    参照の代入は上の 2 通りで確実にできます。)

3. **ProtoFlux を置く** (ProtoFlux ツールで `Websocket` / `Users` カテゴリから):

   - `Websocket Connect` — **接続開始。これを impulse しない限り永久に繋がりません。**
     コンポーネントを付けただけでは `IsConnected` は false のままです。
   - `Websocket Connection Events` — 接続/切断イベント。状態表示や再接続に使います。
   - `Websocket Text Message Receiver` — 受信文字列が出ます。
   - `Websocket Text Message Sender` — 送信します。

   いずれも `WebsocketClient` コンポーネントへの参照を入れます。

   **最小構成**:

   ```
   ValueField<bool>.Value ─▶ FireOnLocalTrue ──*──▶ WebsocketConnect ──Next──▶ …
                                                     Client       ← WebsocketClient の参照
                                                     URL          ← URL フィールドの Source
                                                     HandlingUser ← LocalUser
   ```

   **`WebsocketConnect` の入力は `Client` / `URL` / `HandlingUser` の 3 つ**で、
   すべてノード側から渡せます。つまり:

   - **コンポーネントの `HandlingUser.User` に書き込む必要はありません。**
     `LocalUser` を Connect ノードの `HandlingUser` 入力へ直接挿せばよいです
     (`Write` ノードも UserRef の代入も不要)。`LocalUser` は「そのノードを見ている
     ユーザ」なので、誰がスポーンしても自分が HandlingUser になり、User ID も要りません。
   - `URL` は Uri 型です。インスペクタの `URL:` 行を ProtoFlux ツールで掴んで **Source** を
     選び、その出力を挿すのが早いです (URL を二度書かずに済みます)。文字列から作るなら
     `String to Absolute URI` を挟みます。
   - `ValueField<bool>` をスロットに付け、インスペクタでチェックを入れると
     `FireOnLocalTrue` が**そのクライアントだけで** impulse を出します。
     外す→入れるで何度でも再接続できるので、立ち上げ期のトリガとして扱いやすいです。

   送受信のノードも同じ `Client` を使います:

   - `WebsocketTextMessageSender` — 入力 `*`(Call) / `Client` / `Data`(String)、
     出力 `OnSendStart` / `OnSent` / `OnSendError`
   - `WebsocketTextMessageReceiver` — 受信文字列を出します

4. **初回はホストアクセスの同意ダイアログが出ます。許可してください。**
   誤って拒否した場合: Dash → 右下の Debug → "Web Hosts" タブ → 該当アドレス →
   Remove Setting → もう一度接続して許可します。

5. **動作確認**: Mathematica 側で

   ```
   ResoniteRealtimeStart[]
   ResoniteRealtimeEvents[]        (* $open が入っていれば接続成功 *)
   ResoniteRealtimeSend["cmd", "hello"]
   ```

   世界側の Receiver に `cmd<TAB>hello` が出れば往復できています。

### 行プロトコルの設計上の注意

**ProtoFlux は JSON も配列 (Collection) も扱えません。** したがって世界側で
「TAB で分割してリストにする」ことはできません。世界へ送るメッセージは

```
verb<TAB>arg
```

の **2 フィールドまで**に抑え、分岐は「先頭が `cmd\tshow\t` で始まるか」のような
**前方一致 + 残りを Substring で取り出す**形にするのが実用的です。

逆向き (世界 → WL) は WL 側でいくらでも分割できるので、フィールド数は自由です:

```
evt<TAB>userJoined<TAB>nconc
req<TAB>17<TAB>plot<TAB>Sin[x]
```

WL 側は先頭語 (`evt` / `req` / …) でハンドラに振り分けます:

```
ResoniteRealtimeOn["req", Function[rec,
  Module[{seq = rec["Args"][[1]], what = rec["Args"][[2]]},
    ResoniteRealtimeSendTo[rec["Connection"], "res", seq <> ":" <> ToString[f[what]]]]]]
```

ワールドの ProtoFlux から `ask<TAB>質問` を送ると、Chat ガジェット (`ResoniteChat` と同じ処理) を L1 経由で走らせることもできます (後述)。

### heartbeat

Resonite の WebsocketClient は **サーバから 60 秒何も来ないと切断します**。
WL 側は既定 25 秒ごとに `hb<TAB><unixtime>` を送っています
(`ResoniteRealtimeStart["Heartbeat" -> 25]`)。**世界側は受け取るだけでよいです**。
`hb` で分岐する必要はなく、無視して構いません。

---

## L2: ResoniteLink (Mathematica → データモデル)

### 有効化

1. Dashboard を開く
2. "Session" ページ → "Settings" タブ
3. 左下の **"Enable ResoniteLink"** を選ぶ
4. `ResoniteLink running on port: <port>` が表示されます。この番号を使います。

```
ResoniteRealtimeLinkConnect[<port>]
ResoniteRealtimeGetSlot["Root", "Depth" -> 1]
```

ポート番号が分からないときは `ResoniteRealtimeDiscover[]` が有効な ResoniteLink のポートを探します。引数なしの `ResoniteRealtimeLinkConnect[]` はこれで見つけたポートに接続します (候補が無ければ `Failure["NoResoniteLink"]`)。探す順序は次のとおりです。

1. Windows の http.sys 登録一覧 (`netsh http show servicestate`。即時)
2. ResoLoop.wl があれば `resoloop discover` (約 12 秒)
3. 環境変数 `RESONITE_LINK_URL`

### 制約 (公式ドキュメントに明記されているもの)

- **セッションのホストである必要があります。**
- **リアルタイム制御には使いません。** 読み書きは "eventually" 反映されます。
  連続的に動かすものは L1 (WebSocket) か OSC、または in-world の ProtoFlux でやります。
- ID はセッション内のみ有効です。**ワールドを保存して開き直すと変わります**。
  永続化したいものは slot 名か DynamicVariable に逃がします。
- まだ **beta** です。スキーマの破壊的変更があり得ます。

### P0 で確かめること (未確認)

- [ ] port は毎回変わるのか。`forceResoniteLinkPort` は**通常クライアントでも**効くか
      (ドキュメントは headless の config でのみ言及しています)。
      効かないなら起動のたびに Dashboard を見る運用になります (`ResoniteRealtimeDiscover[]` で緩和できます)。
- [ ] **応答エンベロープの形**。相関 ID があるか。
      現状 `ResoniteRealtimeLink` は「送信後に届いた、JSON として解釈できた最初のメッセージ」を
      応答とみなしています。相関 ID があると分かれば `"Match" -> 述語` を渡すだけで厳密化できます。
- [ ] `WebsocketClient` の同意ダイアログが毎回出るのか、一度許可すれば残るのか。
- [ ] L1 の実測 RTT (ResoniteIO の gRPC は 0.81–1.04 ms でした)。

---

## L2 の上に載るガジェット

L1 / L2 が通れば、次のガジェットは **ResoniteLink だけでワールド内にパネルを組み立てます** (世界側のノード作業は不要)。いずれも `ResoniteRealtime.wl` が自動でロードします。claudecode / NBAccess / SourceVault / ResoLoop / Flux-SDK は任意の依存で、無くてもブリッジ本体は動きます。

### アクセスレベル (表示上限)

ワールドの公開度とオーナー判定から表示上限 (PL) を決めます。機密度が上限**以上**のものはワールドに出しません (数値が取れないものも fail-closed)。

- `ResoniteAccessLevel[]` — 現在の上限 (1.0 / 0.5 / 0.25)。`ResoniteAccessLevel["Private" | "Contacts" | "ContactsPlus" | "Public", "Owner" -> True | False]` で手動設定 (Manual)。`ResoniteAccessLevel[Automatic]` で自動に戻ります。
- `$ResoniteWorldAccess` (既定 `"Public"`)、`$ResoniteWorldAccessLevels` (既定 Private 1.0 / Contacts 0.5 / ContactsPlus 0.25 / Public 0.25)、`$ResoniteWorldOwner` (既定 False、オーナーでなければ一律 0.25)、`$ResoniteWorldAccessMode` (Automatic | `"Manual"`)、`$ResoniteOwnerUserId` (`"U-..."` を置くとホストがその ID のときだけオーナー)。
- 自動判定はタブレットの監視が Root 直下の `Mathematica World Info` スロットから公開度・ホスト・ワールド記録の所有者を読みます。ホスト = 所有者ならオーナーです。

### Chat パネル (`ResoniteRealtime_chat.wl`)

- `ResoniteChat[prompt]` — LLM に投げ、答えをノートブックとワールド内パネルの両方へ出します。オプション `"Notebook"`, `"World"`, `"SourceVault"`, `"Evaluate"`, `"Model"`, `"Timeout"`, `"Origin"` (`"Notebook" | "World" | "Bridge"`)。`ResoniteChatCell[]` で `ResoniteInput` セルを挿入します。
- `ResoniteChatGadget[]` — 入力欄 / 送信ボタン / 答え / 板のパネルを組み立てます (既定でアバターの頭の正面。`"Placement"`, `"Distance"`, `"Height"`, `"User"`, `"Position"`, `"Parent"`, `"Name"`, `"CanvasSize"`, `"PanelScale"`, `"FontSize"`, `"Board"`)。
- `ResoniteChatStart[]` / `ResoniteChatStop[]` — 世界側入力を監視する ScheduledTask を 1 本だけ起動 / 停止します (`"PollInterval"`, `"Evaluate"`)。必ず対にします。
- `ResoniteChatAttach[ids]`, `ResoniteChatRemoveGadget[]`, `ResoniteChatShow[x]`, `ResoniteChatLog[n]`, `ResoniteChatStatus[]`。
- L1 経由: 世界の ProtoFlux から `ask<TAB>質問` を送ると同じ処理が走ります。

### タブレット (`ResoniteRealtime_tablet.wl`)

- `ResoniteTablet[]` — ClaudeEval をワールド内で走らせるタブレット (入力欄 / Eval / 承認・拒否 / スクロール出力 / 画像ビューア) を組み立て、監視も始めます。専用ノートブック「Resonite Tablet」経由で ClaudeEval の runtime 経路が動きます。
- 監視・操作: `ResoniteTabletStart` / `Stop` / `Tick` / `Eval` / `Turn` / `Approve` / `Deny` / `Cancel` / `Show` / `Status` / `Log` / `Remove` / `Attach` / `Notebook` / `NoteTurnResult` / `RegisterHeads`。
- `ResoniteTabletMake3D[]` — 直前のターンの Graphics3D を 3D オブジェクトにします (「3D生成」ボタン)。
- `ResoniteShowObject[x]` — SourceVault オブジェクト (URI / 行 / ファイル / 画像 / 式) をワールドに出す一般 API です。`ResoniteListGadget[rows]` — 行リストをボタン付き一覧にします。
- 作業用カーネル: `ResoniteTabletWorkerStatus[]`, `ResoniteTabletWorkerStop[]`, `$ResoniteTabletWorker` (既定 True。重い仕事を監視の tick から外し、FE の「動的評価の放棄」を避けます)。

### 文書ビューアとサムネイル一覧 (`ResoniteRealtime_docboard.wl`)

- `ResoniteDocViewer[file]` — 標準ビューアの雛形が無くても、Resonite 自身の文書表示 (StaticDocument + DocumentPageTexture) で PDF を開きます。ページ送りと閉じるはワールド内だけで動きます。`ResoniteDocViewerRemove[root]` で消します。`$ResonitePDFLite` (既定 True) が雛形無し / 複製失敗時にこれへ落とすかを決めます。
- サムネイル一覧はインベントリに保存して再利用できます。行データは HMAC-SHA256 で署名され、書き換えられた一覧は接続を断ります。
- `ResoniteBoardAdopt[root]` — インベントリから出した一覧を引き継ぎます (「接続」ボタンと同じ)。署名の確認 → 公開範囲とオーナーの読み直し → 表示上限未満の升目だけ表示、の順です。`ResoniteBoardDiagnose[]` は「接続」が効かないときの診断です。

#### 署名の鍵と鍵束 (2026-10-11)

鍵は PC ごとなので、別の PC で作った一覧は以前は必ず署名が合わず、「行データの署名が合いません」と断られていました。これを次のように扱います。

- **自分の鍵**: `$ResoniteBoardKeyFile` (既定 `$UserBaseDirectory/ApplicationData/ResoniteRealtime/board.key`)。署名は今までどおり自分の鍵で行うので、前に作った一覧もそのまま通ります。
- **鍵束**: 各 PC が自分の鍵を `<SourceVault の PrivateVault>/keys/resonite-board/<PC 名>-<指紋>.key` に置きます (既定 Automatic。SourceVault が無ければ使いません。`None` で使わない)。Dropbox で自分の PC 同士だけに同期され、検証は「自分の鍵 → 鍵束の鍵」の順に試します。署名が通った一覧の `Signer` は `"Local"` (自分の鍵) か `"Ring"` (鍵束の鍵) になります。
- **鍵束にまだ鍵が無い PC の一覧** (その PC で新しい版を一度も読んでいない場合): 行を信用せず、Eagle の項目だけこの PC の SourceVault から引き直します (`Signer` は `"Foreign"`)。
  - URI が `sv://object/eagle-<Id>` の行だけ採り、ファイルのパスは捨てます (開くときに SourceVault がこの PC の Eagle から解決します)。
  - 機密度は、この PC の SourceVault の値と書いてある値の大きい方です (SourceVault が無ければ 1.0)。
  - それ以外の行は開けない升目 (機密度 1.0) にします。`sv://file/` は機密度 0.0 で任意のファイルを指せるので採りません。
  - 採れる行が 1 つも無ければ、今までどおり接続を断ります。
- 引き直しは小分けに進めます。以前は接続の 1 tick で全行を引き直しており、468 件で約 1 分塞いでいました。終わるまでの機密度は、署名が通った一覧なら署名の値 (引き直しは上げるだけ)、別の PC の一覧なら 1.0 です。押した升目だけは、その行を先に引き直してから開きます。
- 状態欄の表示は、経過と結果を先に、題名を最後に出します (状態欄は幅で切れるため)。幅は全角 1・半角 0.55 で数えます。接続後は「接続済み (別PCの一覧)」のように署名の種類も出ます。
- 開けない升目の理由は `ResoniteBoardDiagnose[]` で確かめられます (記録には `Adopted` / `Rechecked` / `OpenRefused` などが残ります)。ワールドの情報がまだ読めていないときは「ワールドの情報待ち。数秒後に押し直してください」と出ます。

### 曲面表示 (`ResoniteRealtime_surface.wl`)

- `ResoniteThumbnailSurface[name]` — 一覧を貼る面の定義 (`"Plane"`, `"Cylinder"`, `"SphereInside"`, `"Mobius"`, `"TorusOutside"`)。`ResoniteThumbnailSurface[Function[{x, y, g}, {X, Y, Z}], opts]` で任意の面を作れます。
- `ResoniteThumbnailShape[root, shape]` — 一覧を別の形で組み直します (「形を変更」ボタンと同じ)。`$ResoniteThumbnailShapes`, `$ResoniteThumbnailSurfaces`。
- `ResoniteThumbnailSurfaceFrames[...]`, `ResoniteThumbnailSurfaceHit[root, {origin, dir}]` — 面の設計の確認 (升目ごとの接平面 / 光線との交点の升目)。

### PDF の写し (`ResoniteRealtime_pdfcache.wl`)

標準ビューアの URL は `http://127.0.0.1:<port>/...` で、HTTP の URL 資産は各クライアントが自分で取りに行くため、フレンドには見えません。ワールドが Private / Contacts で自分がオーナーのときだけ、利用者が設定した web サーバへ sftp で `<SHA-256>.pdf` を置いて URL を差し替えます。

- 設定: `ResonitePDFCacheSetup["sftp://user@host/path", "https://host/cache"]` (PC ごとの設定ファイル `pdfcache_server.json`。ソースにはサーバ情報を書きません)。`ResonitePDFCacheCredential[]` でパスワードを NBAccess 経由で保存します。
- 変数: `$ResonitePDFCache` (既定 True), `$ResonitePDFCacheBaseURL`, `$ResonitePDFCacheUploadURL`, `$ResonitePDFCacheMaxLevel` (既定 0.5。超える PDF は送りません)。
- 運用: `ResonitePDFCacheStatus[]`, `ResonitePDFCacheRetry[]`, `ResonitePDFCacheList[]`, `ResonitePDFCacheClear[]` (使い終わったら消します)。

### 3D 生成 (`ResoniteRealtime_mesh.wl`)

- `ResoniteGraphics3DMesh[g]` — Graphics3D (Plot3D / ArrayPlot3D など) を三角形メッシュにします。`ResoniteMeshJSON[mesh]` は ResoniteLink の ImportMeshJSON 形式です。
- `ResoniteGraphics3D[g]` — ResoLoop 経由でワールド内の 3D オブジェクトにします (`ResoniteGraphics3DRemove` で削除)。`$ResoniteGraphics3DProject`, `$ResoniteGraphics3DDirectory`。ResoLoop と resoloop CLI が必要です。

### ProtoFlux 生成 (`ResoniteRealtime_flux.wl` / `ResoniteRealtime_fluxlink.wl`)

- `ResoniteFluxChat[prompt]` / `ResoniteFluxGenerate[spec]` / `ResoniteFluxCell[]` — LLM に ProtoGraph を書かせ、静的検査 (`ResoniteFluxCatalog`, `ResoniteFluxCatalogSearch`, `ResoniteFluxUnknownNodes`) と flux-sdk build (`ResoniteFluxBuild`、flux-sdk があるときのみ) を修正ループで回します。`ResoniteFluxDeploy[result]` で世界へ入れる手順を返します。`$ResoniteFluxSDK`, `$ResoniteFluxProjects`。
- `ResoniteFluxPlace[graph]` — グラフ記述 (JSON) を ResoniteLink で ProtoFlux ノードとして配置・結線します。`ResoniteFluxValidateGraph`, `ResoniteFluxBindingType`, `ResoniteFluxProbe`, `ResoniteFluxRemove`, `ResoniteFluxDisplay`, `ResoniteFluxDrive`, `$ResoniteFluxGraphSpec`。

### 設計上の約束

- 常駐 Dynamic でポーリングしません。監視は ScheduledTask 1 本です (Start / Stop を必ず対にします)。
- tick や SocketListen のコールバックの中では FrontEnd を触らず、ResoniteLink の応答も待ちません (`"Wait" -> False`)。

---

## テストの走らせ方 (Resonite 無しで動く)

```
wolframscript -file ResoniteRealtime_info/references/tests/test_ws.wl
wolframscript -file ResoniteRealtime_info/references/tests/test_rr.wl
wolframscript -file ResoniteRealtime_info/references/tests/test_reload.wl
```

- `test_ws.wl` (19) — RFC6455 codec 単体 + **Node の組み込み WebSocket クライアント**との結合
  (ハンドシェイク / マスク解除 / 200 KB / マルチバイト / 分割到着) + WL クライアント ⇄ WL サーバ。
- `test_rr.wl` (31) — 行プロトコル・ハンドラ (catch-all 含む)・heartbeat・イベントバッファと、
  **偽の ResoniteLink サーバ**を同一カーネルに立てての JSON 往復
  (getSlot / addSlot / updateSlot / addComponent / removeSlot / 型変換 / タイムアウト)。
- `test_reload.wl` (6) — 起動したままの再ロード・二重起動・ポート衝突・停止後の再開。
  ノートブックで開発しながら何度も `Get` する使い方を守るためのものです。

Node は v22 以降であれば `WebSocket` が組み込みなので追加インストールは要りません
(検証時は v24.14.0)。

## 実装上の落とし穴 (実測で踏んだもの)

- **SocketListen のコールバックの中で `Close` / `DeleteObject` してはいけません。**
  その場では成功しますが、以後に別のソケットを閉じた瞬間にカーネルごと落ちます。
  `ResoniteRealtime_ws.wl` は墓場 (`$iWSGraveyard`) に積んで、トップレベルの公開 API から
  `RRWSSweep[]` で回収する方式にしてあります。
- 閉じる順序は「索引から外す → listener を DeleteObject → socket を Close」です。逆順は落ちます。
- **タスク / コールバックの中の `BinaryWrite` は待たずに積むだけで、溢れると黙って捨てます。**
  そのため WebSocket 層の書き込みは `SocketWriteMessage[..., "Blocking" -> True]` を 64 KB ずつ送る方式にしてあります (2026-09-24 変更。旧: `BinaryWrite` を 512 B ずつ)。大きなメッセージ (画像の URL 配信や大きなメッシュなど) が途中で欠けるときは、この経路を疑ってください。
- ハンドラ内で `Pause` しません (SocketListen コンテキストで FE をブロックします)。
- heartbeat の宛先は **role だけで選びません**。同一カーネルに別の WebSocket サーバがいると
  その接続にまで送ってしまいます (実際に L2 の応答待ちが heartbeat を拾う事故が起きました)。
  ブリッジサーバ ID で絞ります。

### 低レベル WebSocket API (`ResoniteRealtime_ws.wl`)

L1 / L2 の下回りは依存ゼロの純 Wolfram 実装 (RFC 6455、サーバ + クライアント) で、直接も使えます。

- `RRWSServe[port, handler]` (`"BindAddress" -> "127.0.0.1" | "0.0.0.0"`) / `RRWSStopServe[serverId]`
- `RRWSConnect[url, handler]` (`"Timeout" -> 10`) / `RRWSSend[connId, text]` / `RRWSPing[connId]` / `RRWSClose[connId]`
- `RRWSStatus[]` / `RRWSConnections[]` / `RRWSSweep[]` (通常は自動) / `$RRWSLastError`

handler は `<|"Event" -> "Open" | "Message" | "Close" | "Error", "Connection", "Role", "Data", "Opcode", "Time"|>` を受けます。