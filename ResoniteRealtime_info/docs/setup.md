# ResoniteRealtime セットアップ手順書

ResoniteRealtime は Mathematica (Wolfram Language) から VR プラットフォーム Resonite を制御するブリッジパッケージです。
純 Wolfram の WebSocket 層の上に、世界とのリアルタイム経路 (L1)、ResoniteLink による構造の読み書き (L2)、画像配信 (L3) を持ち、その上にワールド内の Chat ガジェット・ProtoFlux 生成・ClaudeEval タブレット・3D 生成・PDF ビューアを載せています。

macOS/Linux ではパス区切りやシェルコマンドを適宜読み替えてください (本書は Windows 11 を前提とします)。

## 1. 前提環境

- **Wolfram Language / Mathematica**: 14.x 以降を推奨します (`SocketListen` / `SocketConnect`、`ScheduledTask`、`Rasterize`、`Import[..., "PageImages"]` を多用します)。
- **OS**: Windows 11 を前提としています。
- **Resonite**: デスクトップクライアント。
  - L2 (ResoniteLink) を使う機能 (Chat ガジェット / タブレット / ProtoFlux 配置 / 板の生成) では、そのセッションの **ホスト** であり、Dashboard → Session → Settings で **Enable ResoniteLink** を押しておく必要があります (ResoniteLink 0.13 系で確認)。
  - L1 (リアルタイム経路) はホストでなくても動きますが、世界側に `WebsocketClient` を持つブリッジオブジェクトを 1 回作る必要があります ([in-world-bridge-setup.md](in-world-bridge-setup.md))。
- **外部ツール (任意)**:
  - **resoloop** + **.NET 10 SDK**: 3D 生成 (`ResoniteGraphics3D`、タブレットの「3D生成」ボタン) が、別パッケージ [ResoLoop](https://github.com/transreal/ResoLoop) を通して resoloop を呼びます。resoloop は AGPL-3.0 の別プロジェクトで **本リポジトリには含まれません**。導入は ResoLoop 側の setup.md に従ってください。
  - **Flux-SDK** (`Papaltine.FluxSDK` 1.9.0): ProtoGraph の build を使うときだけ。無くてもグラフ記述の生成・配置は動きます。
  - **dotnet fsi**: ProtoFlux ノードカタログを自分の Resonite から作り直すときだけ (5 節)。

## 2. 依存パッケージ (すべて任意)

WebSocket 層 (`ResoniteRealtime_ws.wl`) は依存ゼロで、L1 / L2 / 板の表示は本パッケージだけで動きます。

- **claudecode.wl + NBAccess.wl (+ ClaudeRuntime.wl)**: Chat ガジェット (`ResoniteChat`)、ProtoFlux 生成 (`ResoniteFluxGenerate`)、タブレット (`ResoniteTablet`。ClaudeEval の runtime 経路と承認ボタン `ClaudeRuntimeDecide` を使う) に必要です。無い場合は `Failure["NoClaudeCode"]` で止まります。
- **SourceVault.wl**: `sv://` URI や検索結果の行をワールドに出す `ResoniteShowObject` / `ResoniteListGadget`、Chat / タブレットの資料文脈に使います。無い場合、`sv://` 参照は `Failure["NoSourceVault"]` (fail-closed)。
- **ResoLoop.wl** (+ resoloop): 3D 生成。`ResoniteGraphics3D` は `$packageDirectory` の `ResoLoop.wl` を自動ロードします。無ければ `Failure["NoResoLoop"]`。
- **Claude Directives**: タブレットのプロンプトへの答え方の規則 `110-resonite-tablet.md` を `ResoniteRealtime_info/directives/` に同梱しています。`Claude Directives/rules/` にコピーしてください。

## 3. インストール手順

1. 本リポジトリをクローンし、`.wl` ファイル 7 本 (`ResoniteRealtime.wl` と `ResoniteRealtime_ws / _chat / _flux / _fluxlink / _tablet / _mesh.wl`) を `$packageDirectory` 直下に、`ResoniteRealtime_info/` フォルダをその隣に置きます (サブディレクトリに分けないこと。`ResoniteRealtime.wl` が同じディレクトリの補助モジュールを自動ロードし、`_flux.wl` は `ResoniteRealtime_info/references/` を参照します)。

   ```bash
   git clone https://github.com/transreal/ResoniteRealtime.git
   ```

2. (3D 生成を使う場合) ResoLoop パッケージと resoloop を導入します。

   ```bash
   git clone https://github.com/transreal/ResoLoop.git
   ```

   ```powershell
   winget install Microsoft.DotNet.SDK.10
   dotnet tool install --global ResoLoop --version 0.1.0-preview.13
   ```

   環境変数 `RESONITE_MANAGED_DATA_PATH` / `RESONITE_LOG_PATH` の設定と、プロジェクトの作成 (`ResoLoopProject["MyResoniteProject", "Create" -> True]`) は ResoLoop の setup.md を参照してください。3D 生成は `ResoLoop.wl` の既定プロジェクトの `content/g3d/` に mesh.json と apply.json を書きます。

3. (ProtoGraph の build を使う場合) Flux-SDK を導入します。

   ```powershell
   dotnet tool install --global Papaltine.FluxSDK --version 1.9.0
   ```

4. (ClaudeEval 連携を使う場合) `ResoniteRealtime_info/directives/110-resonite-tablet.md` を `Claude Directives/rules/` にコピーします。

## 4. Resonite 側の準備

### L2: ResoniteLink の有効化

1. 操作したいワールドのセッションを自分がホストします。
2. Dashboard → Session → Settings → **Enable ResoniteLink**。表示された **ポート番号** を控えます。
3. Mathematica から `ResoniteRealtimeLinkConnect[port]` で接続します。接続先は `localhost` です (`127.0.0.1` は http.sys が 400 で弾きます)。ポートは Resonite の起動毎に変わります。実機で分かった注意点は [resonitelink-notes.md](resonitelink-notes.md)。

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
ResoniteAccessLevel["Private", "Owner" -> True];     (* 自分のプライベートワールドなら表示上限 1.0 *)
ResoniteTablet[]                                     (* アバターの正面にタブレット。監視 tick も始まる *)
```

タブレットの入力欄にプロンプトを入れて Eval を押すと、専用ノートブック「Resonite Tablet」で ClaudeEval が走り、結果がタブレットとビューアに出ます。

作ったタブレットは Resonite のインベントリに保存しておけます。2 回目からは `Get["ResoniteRealtime.wl"]` だけで常駐監視 (`ResoniteTabletServe[]`) が
自動で始まるので、ResoniteLink を有効化し、インベントリからタブレットを出して「接続」を押すだけで使えます (ポートは自動検出)。

## 7. 主な設定 (抜粋)

| 変数 / 関数 | 意味 |
| --- | --- |
| `ResoniteAccessLevel["Private" \| "Contacts" \| "ContactsPlus" \| "Public", "Owner" -> True \| False]` | ワールドに出してよい情報の上限 (PL 1.0 / 0.5 / 0.25 / 0.25)。所有者/公開度は ResoniteLink から取れないので手で設定します。非オーナーの既定は一律 0.25 |
| `$ResoniteTabletCloudMaxLevel` (0.5) | タブレットの ClaudeEval に渡す AccessLevel の上限 (クラウド LLM に出す機密度の天井) |
| `$ResoniteTabletBuildMode` (Automatic) | 予約したガジェット組み立てを監視 tick の中で行う ("Tick") か専用ノートブックのセルで行う ("Notebook") か |
| `$ResoniteRealtimePublicBaseURL` | 聴衆がいる場での画像 URL (127.0.0.1 は自分にしか見えない) |
| `$ResoniteGraphics3DDirectory` | 3D 生成の作業フォルダ (既定 `%LOCALAPPDATA%\ResoLoop\g3d`。同期フォルダの外) |
| `$ResoniteFluxSDK` / `$ResoniteFluxProjects` | flux-sdk のパスと ProtoGraph プロジェクトの置き場 |
| `$ResoniteTabletShowCode` (False) | タブレットの出力欄に提案コード (Input セル) も出すか |

## 8. トラブルシューティング

| 症状 | 原因と対処 |
| --- | --- |
| `ResoniteRealtimeLinkConnect` が失敗する | ResoniteLink が無効、ホストでない、ポートが古い (起動毎に変わる)、または `"Host" -> "127.0.0.1"` にしている (`localhost` が正) |
| ScheduledTask / 提案コードの中で `Failure["Timeout"]` | ResoniteLink の応答待ちは非同期ハンドラが走れない文脈では必ずタイムアウトします。書き込みは待たずに送り (`"Wait" -> False`)、組み立ては予約 (`Deferred`) されます。設計どおりで、ガジェットは数秒後に tick が組み上げます |
| カーネル再起動後にワールドに残骸が残る | `ResoniteTabletCleanup[]` が Root 直下の "Mathematica Tablet" / "SourceVault List" / "PDF Viewer" 等を名前で消し、状態を空にします。その後 `ResoniteTablet[]` |
| 板やビューアが市松模様 | テクスチャ URL が無い/届いていない。`ResoniteRealtimeStart[]` (画像配信) が動いているか、`$ResoniteRealtimePublicBaseURL` が正しいかを確認。空の板は最初のページを出すまで非表示になります |
| 3D 生成が `APPLY_STATE_WRITE_FAILED` | resoloop の checkpoint を同期ソフト (Dropbox 等) が掴んだ。作業フォルダは既定で `%LOCALAPPDATA%\ResoLoop\g3d` (同期外) で、同じ apply を最大 3 回再実行します |
| 3D 生成が `Failure["NoResoLoop"]` | `ResoLoop.wl` が `$packageDirectory` に無い、または resoloop 未導入 (3 節 2.) |
| `sv://` の資料が `Failure["NoSourceVault"]` / `PrivacyExceeded` | SourceVault が無い、または行の機密度が表示上限を超えている (fail-closed。機密度が数値で取れない行も出しません) |
| ProtoFlux 生成でノードが見つからない | 5 節のカタログが無い。作り直すか、`ResoniteFluxCatalogSearch` で名前を確かめる |
