# ResoniteRealtime セットアップ手順書

ResoniteRealtime は Mathematica (Wolfram Language) から VR プラットフォーム Resonite を制御するブリッジパッケージです。
純 Wolfram の WebSocket 層の上に、世界とのリアルタイム経路 (L1)、ResoniteLink による構造の読み書き (L2)、画像配信 (L3) を持ち、その上にワールド内の Chat ガジェット・ProtoFlux 生成・ClaudeEval タブレット・3D 生成・PDF ビューア・サムネイル一覧 (平面 / 曲面) を載せています。

macOS/Linux ではパス区切りやシェルコマンドを適宜読み替えてください (本書は Windows 11 を前提とします)。

## 1. 前提環境

- **Wolfram Language / Mathematica**: 14.x 以降を推奨します (`SocketListen` / `SocketConnect`、`ScheduledTask`、`Rasterize`、`Import[..., "PageImages"]` を多用します)。
- **OS**: Windows 11 を前提としています。
- **Resonite**: デスクトップクライアント。
  - L2 (ResoniteLink) を使う機能 (Chat ガジェット / タブレット / ProtoFlux 配置 / 板の生成 / サムネイル一覧) では、そのセッションの **ホスト** であり、Dashboard → Session → Settings で **Enable ResoniteLink** を押しておく必要があります (ResoniteLink 0.13 系で確認)。
  - L1 (リアルタイム経路) はホストでなくても動きますが、世界側に `WebsocketClient` を持つブリッジオブジェクトを 1 回作る必要があります ([in-world-bridge-setup.md](in-world-bridge-setup.md))。
- **外部ツール (任意)**:
  - **resoloop** + **.NET 10 SDK**: 3D 生成 (`ResoniteGraphics3D`、タブレットの「3D生成」ボタン) が、別パッケージ [ResoLoop](https://github.com/transreal/ResoLoop) を通して resoloop を呼びます。resoloop は AGPL-3.0 の別プロジェクトで **本リポジトリには含まれません**。導入は ResoLoop 側の setup.md に従ってください。
  - **Flux-SDK** (`Papaltine.FluxSDK` 1.9.0): ProtoGraph の build を使うときだけ。無くてもグラフ記述の生成・配置は動きます。
  - **dotnet fsi**: ProtoFlux ノードカタログを自分の Resonite から作り直すときだけ (5 節)。
  - **sftp 対応の curl** (Git for Windows 同梱): フレンド用の PDF キャッシュサーバを使うときだけ (7 節)。

## 2. 前提パッケージ (先にセットアップしてください)

ResoniteRealtime は、同じ作者の次の 5 つのパッケージの上に作られています。**まずそれぞれのリポジトリの setup.md に従って、
この順に導入してください** (後のものほど前のものに依存します):

1. [NBAccess](https://github.com/transreal/NBAccess) — [セットアップ](https://github.com/transreal/NBAccess/blob/main/NBAccess_info/docs/setup.md)
2. [claudecode](https://github.com/transreal/claudecode) — [セットアップ](https://github.com/transreal/claudecode/blob/main/claudecode_info/docs/setup.md)
3. [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) — [セットアップ](https://github.com/transreal/ClaudeRuntime/blob/main/ClaudeRuntime_info/docs/setup.md)
4. [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) — [セットアップ](https://github.com/transreal/ClaudeOrchestrator/blob/main/ClaudeOrchestrator_info/docs/setup.md)
5. [SourceVault](https://github.com/transreal/SourceVault) — [セットアップ](https://github.com/transreal/SourceVault/blob/main/SourceVault_info/docs/setup.md)

| パッケージ | ResoniteRealtime での役割 | リポジトリ / セットアップ |
| --- | --- | --- |
| **NBAccess** | 機密度 (PrivacyLevel) の判定でワールドに出す物をふるう (fail-closed)、LLM の提案コードが呼べる表示 API の許可ヘッド登録、キャッシュサーバのパスワード (SystemCredential は NBAccess だけが扱う) | [NBAccess](https://github.com/transreal/NBAccess) / [setup.md](https://github.com/transreal/NBAccess/blob/main/NBAccess_info/docs/setup.md) |
| **claudecode** | タブレット・Chat ガジェットの ClaudeEval / LLM 呼び出し、ProtoFlux 生成、承認ボタン (`ClaudeRuntimeDecide`) | [claudecode](https://github.com/transreal/claudecode) / [setup.md](https://github.com/transreal/claudecode/blob/main/claudecode_info/docs/setup.md) |
| **ClaudeRuntime** | タブレットのターンの実行と状態 (承認待ち / 実行中 / 完了) の監視、承認・拒否・中止 | [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) / [setup.md](https://github.com/transreal/ClaudeRuntime/blob/main/ClaudeRuntime_info/docs/setup.md) |
| **ClaudeOrchestrator** | タブレットのターンがオーケストレーション (複数ステップのジョブ) に回ったときの進行の監視 | [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) / [setup.md](https://github.com/transreal/ClaudeOrchestrator/blob/main/ClaudeOrchestrator_info/docs/setup.md) |
| **SourceVault** | `sv://` 資料・検索結果の一覧、Eagle フォルダのサムネイル一覧と PDF、資料ごとの機密度、KB 応答 | [SourceVault](https://github.com/transreal/SourceVault) / [setup.md](https://github.com/transreal/SourceVault/blob/main/SourceVault_info/docs/setup.md) |

WebSocket 層 (`ResoniteRealtime_ws.wl`) は依存ゼロで、L1 / L2 / 板の表示だけなら本パッケージ単体でも動きます。ただしタブレット
(`ResoniteTablet`)、Chat ガジェット (`ResoniteChat`)、ProtoFlux 生成 (`ResoniteFluxGenerate`)、一覧 / サムネイル一覧 / Eagle フォルダ
(`ResoniteListGadget` / `ResoniteThumbnailGadget` / `ResoniteEagleFolderGadget`)、`sv://` 資料の表示 (`ResoniteShowObject`) は上の
パッケージが前提で、無ければ fail-closed で止まります (`Failure["NoClaudeCode"]` / `Failure["NoSourceVault"]`。機密度が取れない物は
ワールドに出しません)。

その他:

- **ResoLoop.wl** (+ resoloop): 3D 生成。`ResoniteGraphics3D` は `$packageDirectory` の `ResoLoop.wl` を自動ロードします。無ければ `Failure["NoResoLoop"]`。
- **Claude Directives**: タブレットのプロンプトへの答え方の規則 `110-resonite-tablet.md` を `ResoniteRealtime_info/directives/` に同梱しています。`Claude Directives/rules/` にコピーしてください。

## 3. インストール手順

0. 2 節の前提パッケージを、それぞれの setup.md に従って先に導入します。

1. 本リポジトリをクローンし、`.wl` ファイル 10 本 (`ResoniteRealtime.wl` と `ResoniteRealtime_ws / _chat / _flux / _fluxlink / _tablet / _mesh / _docboard / _surface / _pdfcache.wl`) を `$packageDirectory` 直下に、`ResoniteRealtime_info/` フォルダをその隣に置きます (サブディレクトリに分けないこと。`ResoniteRealtime.wl` が同じディレクトリの補助モジュールを自動ロードし、`_flux.wl` は `ResoniteRealtime_info/references/` を参照します)。

   ```bash
   git clone https://github.com/transreal/ResoniteRealtime.git
   ```

2. (3D 生成を使う場合) ResoLoop パッケージと resoloop を導入します。

   ```bash
   git clone https://github.com/transreal/ResoLoop.git
   ```

   ```powershell
   winget install Microsoft.DotNet.SDK.10
   dotnet tool install --global ResoLoop --version 0.1.0-preview.17
   ```

   環境変数 `RESONITE_MANAGED_DATA_PATH` / `RESONITE_LOG_PATH` の設定と、プロジェクトの作成 (`ResoLoopProject["MyResoniteProject", "Create" -> True]`) は ResoLoop の setup.md を参照してください。3D 生成は `ResoLoop.wl` の既定プロジェクトの `content/g3d/` に mesh.json と apply.json を書きます。

3. (ProtoGraph の build を使う場合) Flux-SDK を導入します。

   ```powershell
   dotnet tool install --global Papaltine.FluxSDK --version 1.9.0
   ```

4. (ClaudeEval 連携を使う場合) `ResoniteRealtime_info/directives/110-resonite-tablet.md` を `Claude Directives/rules/` にコピーします。

5. (任意) PDF を Resonite 標準のビューアで開きたい場合は、ワールドに標準の PDF ビューアを 1 つ置いておきます (任意の PDF を一度 Resonite にインポートした物。名前を `PDF Template` にしておくと確実です)。パッケージはこれを雛形として ProtoFlux で複製し、配信 URL を差し替えます。**雛形が無くても** `ResoniteDocViewer` が Resonite 自身の文書表示部品 (`StaticDocument` + `DocumentPageTexture`) でビューアを組むので、PDF は開けます (`$ResonitePDFLite` が既定 `True`)。ページ送りと閉じるはワールドの中だけで動きます。`$ResonitePDFLite = False` にすると、従来どおり Wolfram でページを画像にする自前パネルに落ちます。

## 4. Resonite 側の準備

### L2: ResoniteLink の有効化

1. 操作したいワールドのセッションを自分がホストします。
2. Dashboard → Session → Settings → **Enable ResoniteLink**。表示された **ポート番号** を控えます。
3. Mathematica から `ResoniteRealtimeLinkConnect[port]` で接続します。接続先は `localhost` です (`127.0.0.1` は http.sys が 400 で弾きます)。ポートは Resonite の起動毎に変わります (`ResoniteRealtimeLinkConnect[]` は `ResoniteRealtimeDiscover[]` でポートを自動検出します)。実機で分かった注意点は [resonitelink-notes.md](resonitelink-notes.md)。

### L1: ブリッジオブジェクト (任意)

世界の ProtoFlux からイベントを送ったり、世界へ `cmd<TAB>...` の行を送ったりするリアルタイム経路です。空の Slot に `WebsocketClient` を付け、URL を `ws://127.0.0.1:17300/bridge` にします。ノード構成と落とし穴は [in-world-bridge-setup.md](in-world-bridge-setup.md) にまとめてあります。Mathematica が別 PC なら `ResoniteRealtimeStart["BindAddress" -> "0.0.0.0"]` で起動し、URL をその PC の LAN IP にします。

## 5. リポジトリに含めていない参照データ (ProtoFlux 生成を使う場合のみ)

`ResoniteRealtime_flux.wl` は次の 2 つを `ResoniteRealtime_info/references/` から読みます。どちらも第三者のデータから作るため、リポジトリには含めていません (`references/` フォルダ自体を公開対象外にしています。作り直しの道具は `resources/tools/` にあります)。無ければ ProtoFlux 生成はカタログ無し (`ResoniteFluxCatalog[]` が `{}`) で動きますが、静的検査と LLM への手掛かりが弱くなります。

1. **`protoflux-nodes.json` (ノードカタログ)**: 自分の Resonite の DLL を反射して作ります。手順は [protoflux-gadget.md](protoflux-gadget.md) の「カタログと言語リファレンスの作り方」。

   ```powershell
   cd ResoniteRealtime_info
   mkdir references
   dotnet fsi resources/tools/protoflux-nodes-dump.fsx json references/protoflux-nodes-raw.json
   wolframscript -file resources/tools/protoflux-catalog-build.wl
   ```

   `protoflux-nodes-dump.fsx` は Resonite の既定パス (`C:\Program Files (x86)\Steam\steamapps\common\Resonite`) を見ます。別の場所なら先頭の `dir` を書き換えてください。

2. **`protograph/protograph-skill.md` (ProtoGraph 言語リファレンス)**: Flux SDK 公式ドキュメント (https://flux-sdk.samsmucny.com/ 、AGPL-3.0) の抜粋です。次の 7 ページをブラウザでテキスト保存し、`## <ページ名>` の見出しを付けて 1 つの Markdown に連結します: Basic-Syntax / Expressions-and-Operators / Types-and-Variables / Impulse-Control-Flow / Dynamics / Modules-and-Packages / Reference-Keywords。先頭行は `# ProtoGraph 言語リファレンス (Flux SDK 公式ドキュメントの抜粋スナップショット)` とし、出典と日付を書いておきます。ProtoGraph 形式 (`"Format" -> "ProtoGraph"`) を使わないなら不要です。

## 6. 読込と動作確認

```wolfram
Block[{$CharacterEncoding = "UTF-8"}, Get["ResoniteRealtime.wl"]];

ResoniteRealtimeLinkConnect[];                       (* ポートは自動検出。明示なら ResoniteRealtimeLinkConnect[port] *)
ResoniteRealtimeGetSlot["Root", "Depth" -> 1]        (* 階層が返れば L2 は OK *)

ResoniteRealtimeStart[];                             (* L1 サーバ + 画像配信 (ws://127.0.0.1:17300/bridge) *)
ResoniteRealtimeBoard[];                             (* ワールドに板を作る *)
ResoniteRealtimeShowImage[Plot[Sin[x], {x, 0, 2 Pi}]]  (* 板に図が出れば L3 も OK *)
ResoniteRealtimeStatus[]
```

タブレット (claudecode.wl / NBAccess.wl がある環境):

```wolfram
(* 表示上限はワールドの公開度と所有者から自動で決まる (自分がホストで所有するプライベートワールドなら 1.0) *)
ResoniteTablet[]                                     (* アバターの正面にタブレット。監視 tick も始まる *)
```

タブレットの入力欄にプロンプトを入れて Eval を押すと、専用ノートブック「Resonite Tablet」で ClaudeEval が走り、結果がタブレットとビューアに出ます。

作ったタブレットは Resonite のインベントリに保存しておけます。2 回目からは `Get["ResoniteRealtime.wl"]` だけで常駐監視 (`ResoniteTabletServe[]`) が
自動で始まるので、ResoniteLink を有効化し、インベントリからタブレットを出して「接続」を押すだけで使えます (ポートは自動検出)。

サムネイル一覧 (`ResoniteThumbnailGadget`) もインベントリに保存して使い回せます。インベントリから出した一覧は、Wolfram が確かめるまで升目を覆いで隠し、「接続」を押すと署名 (HMAC-SHA256。鍵は `$ResoniteBoardKeyFile`、既定 `$UserBaseDirectory/ApplicationData/ResoniteRealtime/board.key`、この PC だけ) とワールドの公開度・オーナーを確かめた上で、表示上限未満の升目だけを見せます。別の PC で作った一覧や、行データが書き換えられた一覧は接続を断ります。「接続」が効かないときは `ResoniteBoardDiagnose[]` で診断できます。一覧の「形を変更」ボタン (または `ResoniteThumbnailShape[root, shape]`) で、平面 → 円筒 → 球の内側 → メビウスの帯の順に曲面へ貼り替えられます (巡回の順は `$ResoniteThumbnailShapes`)。`ResoniteThumbnailSurface[Function[{x, y, g}, {X, Y, Z}]]` で任意の面も定義できます。

## 7. 主な設定 (抜粋)

| 変数 / 関数 | 意味 |
| --- | --- |
| `ResoniteAccessLevel["Private" \| "Contacts" \| "ContactsPlus" \| "Public", "Owner" -> True \| False]` | ワールドに出してよい情報の上限 (PL 1.0 / 0.5 / 0.25 / 0.25)。既定はワールドから自動で読みます (Root 直下の "Mathematica World Info")。明示で呼ぶと手動になり (`$ResoniteWorldAccessMode` が `"Manual"`)、`ResoniteAccessLevel[Automatic]` で自動に戻ります。非オーナーの既定は一律 0.25 |
| `$ResoniteOwnerUserId` (Automatic) | `"U-..."` を置くと、自動判定でオーナーとみなすのはホストがその ID のときだけになる。既定はホスト = ワールド記録の所有者ならオーナー |
| `$ResoniteTabletCloudMaxLevel` (0.5) | タブレットの ClaudeEval に渡す AccessLevel の上限 (クラウド LLM に出す機密度の天井) |
| `$ResoniteTabletBuildMode` (Automatic) | 予約したガジェット組み立てを監視 tick の中で行う ("Tick") か専用ノートブックのセルで行う ("Notebook") か |
| `$ResoniteTabletWorker` (True) | サムネイルの帯・Eagle フォルダの一覧・大きな PDF のページ数を作業用カーネル (常駐サブカーネル) で作る。tick の中で長く塞ぐと FE の「動的評価の放棄」ダイアログが出るため。`False` なら従来どおりこのカーネルで。状態は `ResoniteTabletWorkerStatus[]`、停止は `ResoniteTabletWorkerStop[]` |
| `$ResonitePDFLite` (True) | 標準ビューアの雛形が無い / 複製に失敗したとき、`ResoniteDocViewer` (Resonite の文書表示) で開く。`False` なら Wolfram でページを画像にする自前パネル |
| `$ResoniteBoardKeyFile` | サムネイル一覧の行データに付ける署名の鍵ファイル (32 バイト、無ければ作る) |
| `$ResoniteRealtimePublicBaseURL` | 聴衆がいる場での画像 URL (127.0.0.1 は自分にしか見えない) |
| `$ResoniteGraphics3DDirectory` | 3D 生成の作業フォルダ (既定 `%LOCALAPPDATA%\ResoLoop\g3d`。同期フォルダの外) |
| `$ResoniteFluxSDK` / `$ResoniteFluxProjects` | flux-sdk のパスと ProtoGraph プロジェクトの置き場 |
| `$ResoniteTabletShowCode` (False) | タブレットの出力欄に提案コード (Input セル) も出すか |
| `ResonitePDFCacheSetup["sftp://user@host/path/www/cache", "https://host/cache"]` | **フレンドにも PDF を見せるためのキャッシュサーバ** (任意)。Private / Contacts のワールドでは `http://127.0.0.1` の PDF は自分にしか見えないので、自分の web サーバ (sftp で書けて https で読めるディレクトリ) を設定します。設定はこの PC の `$UserBaseDirectory/ApplicationData/ResoniteRealtime/pdfcache_server.json` に保存され、リポジトリには含まれません。続けて `ResonitePDFCacheCredential[]` でパスワードを保存します (NBAccess 経由で SystemCredential に。NBAccess が必要)。この設定は他のパッケージ (SlideWorkflow 等) と独立で、別々のサーバも指定できます。同じアカウントのパスワードは既定で共有され、分けたいときは `"Credential" -> "専用の名前"` を付けます。未設定なら写しは置かず、PDF はオーナーにだけ見えます。sftp 対応の curl (Git for Windows 同梱) が必要です |
| `$ResonitePDFCache` (True) / `$ResonitePDFCacheMaxLevel` (0.5) | キャッシュを使うか / 機密度がこれを超える PDF は外のサーバに置かない (オーナーにだけ見える。機密度が数値で取れない物も置かない) |
| `ResonitePDFCacheStatus[]` / `ResonitePDFCacheRetry[]` / `ResonitePDFCacheList[]` / `ResonitePDFCacheClear[]` | 写しの状態の確認 (`"Skipped"` で置かなかった PDF) / 失敗した写しの送り直し / サーバ上の写しの一覧 / 写しの削除 (`All`、`"OlderThan" -> days`、名前のリストも可)。写しの名前は中身の SHA-256 です。使い終わったら `ResonitePDFCacheClear[]` で消してください |

## 8. トラブルシューティング

| 症状 | 原因と対処 |
| --- | --- |
| `ResoniteRealtimeLinkConnect` が失敗する | ResoniteLink が無効、ホストでない、ポートが古い (起動毎に変わる)、または `"Host" -> "127.0.0.1"` にしている (`localhost` が正)。`ResoniteRealtimeDiscover[]` で有効なポートの候補 (netsh / resoloop discover / 環境変数 `RESONITE_LINK_URL`) を確認できます |
| ScheduledTask / 提案コードの中で `Failure["Timeout"]` | ResoniteLink の応答待ちは非同期ハンドラが走れない文脈では必ずタイムアウトします。書き込みは待たずに送り (`"Wait" -> False`)、組み立ては予約 (`Deferred`) されます。設計どおりで、ガジェットは数秒後に tick が組み上げます |
| カーネル再起動後にワールドに残骸が残る | `ResoniteTabletCleanup[]` が Root 直下の "Mathematica Tablet" / "SourceVault List" / "PDF Viewer" 等を名前で消し、状態を空にします。その後 `ResoniteTablet[]` |
| 板やビューアが市松模様 | テクスチャ URL が無い/届いていない。`ResoniteRealtimeStart[]` (画像配信) が動いているか、`$ResoniteRealtimePublicBaseURL` が正しいかを確認。空の板は最初のページを出すまで非表示になります |
| ResoniteLink に繋ぐ瞬間にカーネルが落ちる | 新しいカーネルで最初のソケット操作が接続だと、Wolfram 15.0.1 がまれに落ちます (約 4 回に 1 回)。2026-09-24 版から読み込み時に下準備をしているので、パッケージを読み直してください |
| 標準 PDF ビューアが空で、ページ表示が「1/-1」 | 文書を受け取れていない。2026-09-24 より前の版には 2 つの原因がありました。約 1 MB を超えるファイルを配信の途中で切っていた (Resonite のログに `Failed gather`) ことと、日本語や空白を含むファイル名を 404 にしていたことです。パッケージを読み直してから開き直してください。空のビューアは `ResonitePDFViewerRemove[All]` か手で消せます。文書ビューア (`ResoniteDocViewer`) は `ResoniteDocViewerRemove[]` で消せます |
| 標準 PDF ビューアの雛形が無く、ワールドを開き直すと元に戻る | 雛形はワールドごとに必要です。雛形が無いときは `ResoniteDocViewer` が自動で使われます (`$ResonitePDFLite = True`)。標準ビューアにこだわるなら 3 節 5. の手順で雛形を置いてください |
| サムネイル一覧を出しても升目が隠れたまま / 「接続」が効かない | 接続が済むまで升目は覆いで隠れます。監視 (`ResoniteTabletServe[]`) が動いているか、署名鍵 (`$ResoniteBoardKeyFile`) がこの PC のものか、ワールドの公開度から決まる表示上限を確認し、`ResoniteBoardDiagnose[]` で状態 (State の値、候補 / 引き継ぎ中 / 接続済み、直近の記録) を見てください |
| フレンドに PDF が見えない | Private / Contacts のワールドで `http://127.0.0.1` の URL は本人にしか見えません。7 節の `ResonitePDFCacheSetup` と `ResonitePDFCacheCredential[]` を設定し、`ResonitePDFCacheStatus[]` で状態 (パスワード未保存・通信失敗・機密度超過での不送信) を確認してください |
| 3D 生成が `APPLY_STATE_WRITE_FAILED` | resoloop の checkpoint を同期ソフト (Dropbox 等) が掴んだ。作業フォルダは既定で `%LOCALAPPDATA%\ResoLoop\g3d` (同期外) で、同じ apply を最大 3 回再実行します |
| 3D 生成が `Failure["NoResoLoop"]` | `ResoLoop.wl` が `$packageDirectory` に無い、または resoloop 未導入 (3 節 2.) |
| `sv://` の資料が `Failure["NoSourceVault"]` / `PrivacyExceeded` | SourceVault が無い、または行の機密度が表示上限を超えている (fail-closed。機密度が数値で取れない行も出しません) |
| ProtoFlux 生成でノードが見つからない | 5 節のカタログが無い。作り直すか、`ResoniteFluxCatalogSearch` で名前を確かめる |
| FE が止まる / 「動的評価の放棄」ダイアログが出る | 監視 tick が重い仕事で塞がっている可能性があります。`ResoniteTabletWorkerStatus[]` の `"SlowTicks"` (1 秒を超えた tick の段) で原因を確かめ、`$ResoniteTabletWorker` が `True` であることを確認してください |