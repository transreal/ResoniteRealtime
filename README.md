# ResoniteRealtime

## 設計思想と実装の概要

**ResoniteRealtime** は、Mathematica (Wolfram Language) から VR プラットフォーム Resonite を制御するブリッジパッケージです。ノートブックで計算した図や資料をワールドの中に出し、ワールドの中から ClaudeEval (LLM 支援の計算) を走らせ、3D プロットを掴めるオブジェクトとして実体化する、といった「計算環境と VR 空間を往復する」使い方を狙っています。

土台は **純 Wolfram の WebSocket 層** (`ResoniteRealtime_ws.wl`、RFC 6455 のサーバとクライアント) で、Python ワーカーや J/Link に依存しません。その上に 3 つの経路があります。

- **L1 リアルタイム**: WL が WebSocket サーバになり、世界の `WebsocketClient` (ProtoFlux) が繋いできます。ProtoFlux は JSON を扱えないので TAB 区切りの行プロトコル (`evt<TAB>...` / `cmd<TAB>...`) にしました。往復が速く、セッションのホストである必要がありません。
- **L2 ResoniteLink**: WL が公式 ResoniteLink (WebSocket + JSON) のクライアントになり、Slot / Component を読み書きします。ホストである必要があり、リアルタイム制御には使いません。
- **L3 画像配信**: 同じポートで PNG などを HTTP 配信し、板 (`StaticTexture2D`) の URL に使います。

この経路の上に、ワールド内で完結するガジェット群を載せています。

- **Chat ガジェット**: ノートブックの Chat セルをワールド内の UIX パネルで実現します。
- **ProtoFlux ガジェット**: プロンプトからグラフ記述を LLM に書かせ、ResoniteLink でノードを直接配置・結線し、動的変数 (probes) を読み戻して検証する修正ループです。Flux SDK のテキスト言語 ProtoGraph での生成にも対応します。
- **タブレット**: ワールド内の UIX タブレットから ClaudeEval (runtime 経路) を走らせます。承認・拒否・中止はタブレットのボタンから行え、結果は表示上限でふるって平文とページ画像に描かれます。PDF は Resonite 標準のドキュメントビューア (ワールドにある雛形を ProtoFlux で複製し、配信 URL を差し替える) で開き、画像 / ノートブックは掴めるページパネルへ、検索結果の行リストは ▶ 付きの一覧パネルへ出ます。
- **3D 生成**: `Plot3D` / `ArrayPlot3D` / `Graphics3D` を三角形メッシュにし、ResoniteLink の ImportMeshJSON 形式で resoloop (別パッケージ ResoLoop 経由) に渡して、ワールド内の掴めるオブジェクトにします。

設計上の要点は 3 つです。第一に **プライバシーは fail-closed** です。ワールドに出してよい情報の上限 (アクセスレベル: 自分のプライベートワールドなら 1.0、公開ワールドなら 0.25) を宣言し、上限を超える資料やセル、機密度が数値で取れないものは出しません。クラウド LLM に渡す機密度もさらに天井 (0.5) を設けています。第二に **監視は待たない** ことです。ResoniteLink の応答待ちは ScheduledTask やコールバックの中では成立しないため、ガジェットの監視は 1 本の tick が「送るだけ」「次の tick で照合」の 2 相で回り、LLM の提案コードが頼むガジェットの組み立ても予約して tick が待たずに組みます。第三に **FrontEnd を守る** ことです。常駐 Dynamic でポーリングせず、SocketListen のコールバックからは FrontEnd を触りません。

**前提パッケージ**: ワールド内のタブレット・一覧 / サムネイル一覧・PDF ビューアなど本パッケージの主な機能は、同じ作者の
[NBAccess](https://github.com/transreal/NBAccess) / [claudecode](https://github.com/transreal/claudecode) / [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) /
[ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) / [SourceVault](https://github.com/transreal/SourceVault) の上に作られていて、これらのセットアップが済んでいることを
前提にしています (役割は下の「前提パッケージ」)。3D 生成には [ResoLoop](https://github.com/transreal/ResoLoop) を使います。

外部ツールのうち **resoloop** (orange3134 氏、AGPL-3.0) と **Flux SDK** (Papaltine、AGPL-3.0) はライセンスが異なるため本リポジトリには含めていません。3D 生成は [ResoLoop](https://github.com/transreal/ResoLoop) パッケージの setup.md に従って resoloop を導入すると使えます。ProtoFlux 生成に使うノードカタログと言語リファレンスも、利用者が自分の Resonite と公式ドキュメントから作ります ([setup.md](ResoniteRealtime_info/docs/setup.md) 5 節)。

## 詳細説明

### 動作環境

- **Wolfram Language / Mathematica**: 14.x 以降を推奨します (`SocketListen` / `SocketConnect`、`ScheduledTask`、`Rasterize`、PDF の `PageImages` import を多用します)。
- **OS**: Windows 11 を前提としています。
- **Resonite**: デスクトップクライアント。L2 を使う機能では、そのセッションのホストであり、Dashboard → Session → Settings で **Enable ResoniteLink** を押しておく必要があります (ResoniteLink 0.13 系で確認)。
- **外部ツール (任意)**: resoloop + .NET 10 SDK (3D 生成)、Flux-SDK 1.9.0 (ProtoGraph の build)、dotnet fsi (ノードカタログの再生成)。
- **前提パッケージ**: 下の表の 5 つ。先にそれぞれの setup.md に従って導入してください (NBAccess → claudecode → ClaudeRuntime →
  ClaudeOrchestrator → SourceVault の順)。3D 生成を使う場合は [ResoLoop](https://github.com/transreal/ResoLoop) も。WebSocket 層と L1 / L2 / 板の表示だけなら
  本パッケージ単体でも動きますが、タブレット・一覧・PDF 表示はこれらが無いと fail-closed で止まります (`Failure["NoClaudeCode"]` /
  `Failure["NoSourceVault"]`、機密度が取れない物は出さない)。

| パッケージ | ResoniteRealtime での役割 | リポジトリ / セットアップ |
| --- | --- | --- |
| **NBAccess** | 機密度 (PrivacyLevel) の判定でワールドに出す物をふるう (fail-closed)、LLM の提案コードが呼べる表示 API の許可ヘッド登録、キャッシュサーバのパスワード (SystemCredential は NBAccess だけが扱う) | [NBAccess](https://github.com/transreal/NBAccess) / [setup.md](https://github.com/transreal/NBAccess/blob/main/NBAccess_info/docs/setup.md) |
| **claudecode** | タブレット・Chat ガジェットの ClaudeEval / LLM 呼び出し、ProtoFlux 生成、承認ボタン (`ClaudeRuntimeDecide`) | [claudecode](https://github.com/transreal/claudecode) / [setup.md](https://github.com/transreal/claudecode/blob/main/claudecode_info/docs/setup.md) |
| **ClaudeRuntime** | タブレットのターンの実行と状態 (承認待ち / 実行中 / 完了) の監視、承認・拒否・中止 | [ClaudeRuntime](https://github.com/transreal/ClaudeRuntime) / [setup.md](https://github.com/transreal/ClaudeRuntime/blob/main/ClaudeRuntime_info/docs/setup.md) |
| **ClaudeOrchestrator** | タブレットのターンがオーケストレーション (複数ステップのジョブ) に回ったときの進行の監視 | [ClaudeOrchestrator](https://github.com/transreal/ClaudeOrchestrator) / [setup.md](https://github.com/transreal/ClaudeOrchestrator/blob/main/ClaudeOrchestrator_info/docs/setup.md) |
| **SourceVault** | `sv://` 資料・検索結果の一覧、Eagle フォルダのサムネイル一覧と PDF、資料ごとの機密度、KB 応答 | [SourceVault](https://github.com/transreal/SourceVault) / [setup.md](https://github.com/transreal/SourceVault/blob/main/SourceVault_info/docs/setup.md) |


### インストール

0. 前提パッケージ (NBAccess / claudecode / ClaudeRuntime / ClaudeOrchestrator / SourceVault) を、それぞれのリポジトリの setup.md に従って
   先に導入します (上の表)。

1. 本リポジトリをクローンし、`.wl` ファイル 10 本を `$packageDirectory` 直下に、`ResoniteRealtime_info/` をその隣に置きます。

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

3. (ClaudeEval 連携を使う場合) `ResoniteRealtime_info/directives/110-resonite-tablet.md` を `Claude Directives/rules/` にコピーします。

4. Resonite で ResoniteLink を有効化し、Mathematica で読み込みます。

   ```wolfram
   Block[{$CharacterEncoding = "UTF-8"}, Get["ResoniteRealtime.wl"]];
   ResoniteRealtimeLinkConnect[];            (* ポートは自動検出 (netsh の http.sys 登録一覧)。明示なら [port] *)
   ```

詳細 (L1 ブリッジオブジェクトの作り方、含めていない参照データの作り方、トラブルシューティング) は [setup.md](ResoniteRealtime_info/docs/setup.md) を参照してください。

### クイックスタート

```wolfram
ResoniteRealtimeStart[];                                (* L1 サーバ + 画像配信 *)
ResoniteRealtimeBoard[];                                (* 板 *)
ResoniteRealtimeShowImage[Plot[Sin[x], {x, 0, 2 Pi}]]   (* 板に図 *)

(* 表示上限はワールドの公開度と所有者から自動。手で決めるなら ResoniteAccessLevel["Private", "Owner" -> True] *)
ResoniteTablet[]                                        (* ワールド内タブレット。入力欄に書いて Eval *)
ResoniteGraphics3D[Plot3D[Sin[x y], {x, 0, 3}, {y, 0, 3}]]   (* 掴めるメッシュ (ResoLoop + resoloop) *)
```

### 主な機能

- **L1 / L2 / L3**: `ResoniteRealtimeStart` / `ResoniteRealtimeOn` / `ResoniteRealtimeSend`、`ResoniteRealtimeLinkConnect` / `ResoniteRealtimeGetSlot` / `ResoniteRealtimeAddSlot` / `ResoniteRealtimeAddComponent` / `ResoniteRealtimeUpdateSlot` / `ResoniteRealtimeUpdateComponent`、`ResoniteRealtimeBoard` / `ResoniteRealtimeShowImage` / `ResoniteRealtimeAsset`。
- **表示上限**: `ResoniteAccessLevel` (Private 1.0 / Contacts 0.5 / ContactsPlus 0.25 / Public 0.25、非オーナーは一律 0.25)。既定はワールドの公開度とホスト / 所有者から自動で決まる。
- **Chat**: `ResoniteChatGadget` / `ResoniteChatStart` / `ResoniteChat` / `ResoniteChatCell`。
- **ProtoFlux**: `ResoniteFluxGenerate` / `ResoniteFluxChat` / `ResoniteFluxCatalogSearch` / `ResoniteFluxPlace` / `ResoniteFluxProbe` / `ResoniteFluxBuild`。
- **タブレット**: `ResoniteTablet` / `ResoniteTabletEval` / `ResoniteTabletApprove` / `ResoniteTabletDeny` / `ResoniteTabletCancel` / `ResoniteTabletMake3D` / `ResoniteTabletCleanup`。
- **資料の表示**: `ResoniteShowObject` / `ResoniteListGadget` / `ResonitePDFViewer` / `ResoniteViewerShow` / `ResoniteVideoBoard`。
- **3D**: `ResoniteGraphics3DMesh` / `ResoniteMeshJSON` / `ResoniteGraphics3D` / `ResoniteGraphics3DRemove`。

### ドキュメント一覧

- [api.md](ResoniteRealtime_info/docs/api.md) — オプションを含む API リファレンス
- [setup.md](ResoniteRealtime_info/docs/setup.md) — セットアップ手順書 (外部ツールと参照データの用意を含む)
- [user_manual.md](ResoniteRealtime_info/docs/user_manual.md) — ユーザーマニュアル
- [example.md](ResoniteRealtime_info/docs/examples/example.md) — 使用例集
- [tablet.md](ResoniteRealtime_info/docs/tablet.md) — タブレット (ClaudeEval / 承認 / 予約した組み立て / 3D 生成 / PDF ビューア) の仕組みと実機メモ
- [chat-gadget.md](ResoniteRealtime_info/docs/chat-gadget.md) — Chat ガジェット
- [protoflux-gadget.md](ResoniteRealtime_info/docs/protoflux-gadget.md) — ProtoFlux ガジェット (グラフ記述の配置と検証、カタログの作り方)
- [protoflux-llm-generation-proposal.md](ResoniteRealtime_info/docs/protoflux-llm-generation-proposal.md) — ProtoFlux 生成の方式検討
- [in-world-bridge-setup.md](ResoniteRealtime_info/docs/in-world-bridge-setup.md) — L1 ブリッジオブジェクトの作り方と ResoniteLink の有効化
- [resonitelink-notes.md](ResoniteRealtime_info/docs/resonitelink-notes.md) — ResoniteLink の実機メモ
- [tablet_claudeeval_spec_v0_1.md](ResoniteRealtime_info/design/tablet_claudeeval_spec_v0_1.md) — タブレットの設計仕様と実装記録 (resoloop 統合仕様の続き。統合仕様の正本は [ResoLoop](https://github.com/transreal/ResoLoop) 側)
- [110-resonite-tablet.md](ResoniteRealtime_info/directives/110-resonite-tablet.md) — ClaudeEval 向けの規則 (Claude Directives 用の写し)

## 使用例・デモ

ワールド内のタブレットに「SourceVault の arXiv の論文のリスト」と入力して Eval を押すと、専用ノートブックで ClaudeEval が SourceVault を検索し、▶ 付きの一覧パネルがタブレットの左隣に組み上がります。▶ を押すと、その論文の PDF が掴めるビューアで開き、ページ送りできます。`Plot3D` を頼んだあとに「3D生成」を押すと、そのプロットがアバターの正面に掴めるメッシュとして現れます。

```wolfram
Block[{$CharacterEncoding = "UTF-8"}, Get["ResoniteRealtime.wl"]];
ResoniteRealtimeLinkConnect[];
ResoniteTablet[]                (* 表示上限はワールドの公開度と所有者から自動で決まる *)
```

一度作ったタブレットは Resonite のインベントリに保存できます。以後は `Get["ResoniteRealtime.wl"]` だけで常駐監視が始まり (ノートブックのセッション)、
ResoniteLink を有効化してインベントリからタブレットを出し、「接続」を押せば使えます (ポート指定も `ResoniteTablet[]` も不要)。

## 謝辞

- 3D 生成は ResoLoop.wl を介して resoloop (orange3134 氏、AGPL-3.0-or-later) を利用します。resoloop 本体は本リポジトリに含まれません。
- ProtoFlux 生成の言語リファレンスは Flux SDK (Papaltine、AGPL-3.0) 公式ドキュメントの抜粋を利用者側で用意します (本リポジトリには含まれません)。
- Resonite / ResoniteLink は Yellow Dog Man Studios の製品です。

---

## 免責事項

本ソフトウェアは "as is"（現状有姿）で提供されており、明示・黙示を問わずいかなる保証もありません。
本ソフトウェアの使用または使用不能から生じるいかなる損害についても責任を負いません。
今後の動作保証のための更新が行われるとは限りません。
本ソフトウェアとドキュメントはほぼすべてが生成AIによって生成されたものです。
Windows 11上での実行を想定しており、MacOS, LinuxのMathematicaでの動作検証は一切していません(生成AIの処理で対応可能と想定されます)。

---

## ライセンス

```
MIT License

Copyright (c) 2026 Katsunobu Imai

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

上記ライセンスは本リポジトリのコードとドキュメントに適用されます。外部ツールとして利用する resoloop と Flux SDK、およびそれらから作る参照データは本リポジトリに含まれていません。
