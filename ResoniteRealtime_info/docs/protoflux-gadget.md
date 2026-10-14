# ProtoFlux ガジェット — プロンプトからワールド内で実行可能な ProtoFlux を作る

`ResoniteRealtime_flux.wl` (生成ループ) + `ResoniteRealtime_fluxlink.wl` (リンカ)。ResoniteRealtime.wl が自動ロードします。
2026-09-06 作成、同日実機で通し確認 (LLM が書いたカウンタのグラフが 0.5 秒ごとに動的変数を増やした)。
Chat ガジェット (`chat-gadget.md`) の上に載ります。LLM 呼び出し・アクセスレベル・パネル表示は `ResoniteRealtime_chat.wl` のものをそのまま使います。

## 方式 (既定: グラフ記述 → 直接配置)

flux-sdk を待たずに **ワールド内で実行できる形**にするため、LLM には ProtoGraph ではなく
小さな **グラフ記述 (JSON)** を書かせ、Mathematica がそれを ResoniteLink で **ノードのコンポーネントとして
配置・結線**します。置いたノード群はそのまま実行されます (実機確認済み)。

もう一つの経路として、LLM に **ProtoGraph** (Flux SDK のテキスト言語、ProtoFlux 1:1) を書かせる方式もあります
(`ResoniteRealtime_flux.wl`、"Format" -> "ProtoGraph")。生成 → 静的検査 (実在ノードのカタログと突合) → flux-sdk build (あれば) → 修正ループ、という流れで、
flux-sdk (dotnet tool `Papaltine.FluxSDK`) が無くても生成と静的検査までは動きます。build と `.brson` 出力は flux-sdk があるときだけです。

```
仕様 ──▶ プロンプト = グラフ記述の仕様 ($ResoniteFluxGraphSpec) + 例 + ノードカタログの手掛かり + 仕様
          ▼  LLM (claudecode 経由。アクセスレベルと機密度は Chat と同じ)
       ```json {"name", "nodes": [...], "probes": [...]} ```
          ▼  ResoniteFluxValidateGraph — ノード型・入力名・インパルス名・参照先をカタログと突合
          ▼  ResoniteFluxPlace — ルート slot (DynamicVariableSpace "wl") + ノードごとの子 slot、pass1 本体/定数/参照、pass2 結線
          ▼  ResoniteFluxProbe — probes の動的変数を読み戻す (実行の証拠)
          └─ 問題があれば「前回の JSON + 問題点」を付けて次 round (既定 3 回まで)
```

グラフ記述の書式と約束は `ResoniteRealtime_fluxlink.wl` 冒頭と `$ResoniteFluxGraphSpec` にあります。要点:

- 定数は `ValueInput<T>` / `ValueObjectInput<string>` ノード。入力は `inputs: {入力名: ノード id}` (複数出力は `"id.出力名"`)。
- インパルスは `impulses: {出力名: 行き先 id}`。起点は `LocalUpdate` / `SecondsTimer` / `FireOnTrue` / `DynamicImpulseReceiver`。
- 世界の参照は `ElementSource<Slot>` の `ref` (`$root` / `$panel` / `$user` / 世界の ID)。
- 結果は `WriteOrCreateDynamicValueVariable<T>` で `wl/<名前>` に書き、`probes` に入れます。

## 公開関数

### リンカ (`ResoniteRealtime_fluxlink.wl`)

| 関数 | 説明 |
| --- | --- |
| `ResoniteFluxBindingType["ValueAdd<float>"]` | カタログから ProtoFluxBindings のコンポーネント型名を作る。未知なら `None` |
| `ResoniteFluxValidateGraph[graph]` | グラフ記述 (Association) を検査し `<|"OK","Errors","Warnings","Nodes"|>` を返す |
| `ResoniteFluxPlace[graph]` | グラフ記述を ResoniteLink で配置・結線する。オプション: `"Parent" -> Automatic` (Chat パネルの根か Root), `"Position" -> Automatic`, `"Name" -> Automatic`, `"Spacing" -> {0.35, 0.25}`。戻り値: `<|"Root","Nodes","Slots","Errors","Probes"|>` |
| `ResoniteFluxProbe[placed]` | 配置したグラフの probes (動的変数) を読み戻す |
| `ResoniteFluxRemove[placed]` | 配置したグラフのルートスロットを消す |
| `ResoniteFluxDisplay[placed, var]` | 動的変数 `var` をワールド内の 3D テキストに出す。オプション: `"Position" -> {0, 0.4, 0}`, `"Scale" -> 0.3`, `"Color" -> Yellow`。戻り値: `<|"Slot","Text","Converter"|>` |
| `ResoniteFluxDrive[placed, var, targetMemberId, type]` | 動的変数 `var` で世界のフィールド (メンバ ID) を駆動する `DynamicValueVariableDriver<type>` を付ける |
| `$ResoniteFluxGraphSpec` | LLM に渡すグラフ記述の仕様文 (日本語) |

### 生成ループ (`ResoniteRealtime_flux.wl`)

| 関数 / 変数 | 説明 |
| --- | --- |
| `$ResoniteFluxSDK` | flux-sdk 実行ファイルのパス。`Automatic` なら PATH と `~/.dotnet/tools` を探す |
| `$ResoniteFluxProjects` | 生成した ProtoGraph プロジェクトの置き場 (既定 `$packageDirectory/ResoniteFlux_projects`) |
| `ResoniteFluxCatalog[]` | ProtoFlux ノードのカタログ (Association のリスト)。各要素 `<|"Type","Name","Category","Inputs","Outputs","Impulses","Result"|>` |
| `ResoniteFluxCatalogSearch[query, n]` | カタログを語で検索して上位 n 件 (既定 30) を返す |
| `ResoniteFluxUnknownNodes[source]` | ProtoGraph ソース中の、カタログにも予約語にも無いノード名を返す |
| `ResoniteFluxBuild[pgFile]` | flux-sdk build を走らせ `<|"Success","Output","Diagnostics","Brson"|>` を返す。flux-sdk が無ければ `Failure["NoFluxSDK"]` |
| `ResoniteFluxGenerate[spec]` | 仕様 (自然言語) から LLM に生成させ、静的検査 → (flux-sdk があれば) build → 修正を最大 `"MaxRounds"` 回まわす |
| `ResoniteFluxChat[prompt]` | `ResoniteChat` の ProtoFlux 版。生成した ProtoGraph をノートブックとワールド内パネルに出し、`.pg` をプロジェクトに保存する。オプションは `ResoniteFluxGenerate` と同じ |
| `ResoniteFluxCell[]` | `ResoniteFluxInput` セル (Shift+Enter で `ResoniteFluxChat`) を挿入する |
| `ResoniteFluxDeploy[result]` | 生成結果を世界へ入れる手順を返す。`.brson` があれば Resonite へドラッグ&ドロップ。`"Method" -> "ResoniteLink"` で Flux SDK のホットデプロイ (`resources/tools/flux-deploy.fsx`、実験的) を試す |

`ResoniteFluxGenerate` のオプション (ソースの usage より): `"MaxRounds" -> 3`, `"Module" -> Automatic`, `"Model" -> Automatic`, `"Timeout" -> 300`, `"Build" -> Automatic`, `"SourceVault" -> False`, `"Origin" -> "Notebook"`。
ProtoGraph 経路の戻り値は `<|"Source","Module","File","Project","Unknown","Build","Rounds","Answer","PrivacyLevel"|>` です。
グラフ記述経路 (既定) では下の「使い方」にある `"Placed"` / `"Probes"` が返り、`"Display"` で読み出し表示を止められます。

## 実機で分かった配置の規則 (2026-09-06)

| 項目 | 事実 |
| --- | --- |
| 型名 | 論理ノード `ProtoFlux.Runtimes.Execution.Nodes.<Cat>.<Node>` → `[ProtoFluxBindings]FrooxEngine.` + それ。コアノード `FrooxEngine.ProtoFlux.CoreNodes.<Node>` → `[ProtoFluxBindings]FrooxEngine.FrooxEngine.ProtoFlux.CoreNodes.<Node>`。型引数は `<float>` / `<[FrooxEngine]FrooxEngine.Slot>`。間違えると**無応答** |
| 入力 | `SyncRef<INodeValueOutput<T>>` に **出力元ノードのコンポーネント ID** を reference。複数出力ノードはメンバ ID |
| インパルス | 出力側 (`OnUpdate` 等) に **行き先ノードのコンポーネント ID** を reference |
| 定数 | `ValueInput<T>.Value` / `ValueObjectInput<string>.Value` (これらは ProtoFluxBindings 側だけにあるのでカタログに合流させた) |
| 世界参照 | `GlobalReference<T>` (Reference → 対象) + `ElementSource<T>` (Source → GlobalReference)。`ReferenceSource` は型が合わない |
| 動的変数 | 書き込み先に `DynamicVariableSpace` が要る (無いと OnNotFound で黙る) |
| 実行 | 置いただけで動く。NodeGroup はデータモデルに無い (実行時のみ) |
| ドライブ | `ValueFieldDrive` の駆動先 (Proxy) は ResoniteLink で書けない。結果は動的変数で受ける |

## 使い方

```mathematica
ResoniteRealtimeLinkConnect[<port>];
g = ResoniteFluxGenerate["0.5 秒ごとにカウンタを 1 増やして wl/count に書く"];
g["Probes"]                    (* <|"wl/count" -> 9|> など *)
g["Placed"]["Root"]            (* 配置した slot。ResoniteFluxRemove[g["Placed"]] で消す *)
ResoniteFluxPlace[graph]       (* 手書きのグラフ記述を置く *)
ResoniteFluxGenerate[spec, "Format" -> "ProtoGraph"]   (* 旧: ProtoGraph 文字列を返す (flux-sdk 用) *)
ResoniteFluxChat["..."]        (* ProtoGraph を生成してノートブックとパネルに出す *)
```

パネルでは `flux: ...` で始めると同じ経路に入ります。ただしパネル経路は ScheduledTask 内なので ResoniteLink の応答を
待てず、**複数出力の参照 (`id.出力名`) と probes の読み戻しはノートブック経路でだけ機能します**。

## ワールド内での観測

- **既定で読み出し表示が付く**: `ResoniteFluxGenerate` は配置後、最初の probe を黄色の 3D テキスト (TextRenderer) で
  グラフのルート slot の上 (0.4 m) に出します (`"Display" -> False` で止める)。仕組みは `ResoniteFluxDisplay[placed, var]`:
  数値なら ProtoFlux の変換グラフ (ReadDynamicValueVariable → ToString_* → WriteOrCreateDynamicObjectVariable<string> "<var>_text") を足し、
  `DynamicValueVariableDriver<string>` で TextRenderer.Text を駆動します。
- **インスペクタ**: slot `Flux <name>` の `DynamicValueVariable<T>` (VariableName `wl/<名前>`) の Value が変わります。
- **Mathematica から**: `ResoniteFluxProbe[g["Placed"]]`。
- **フィールドを動かす**: `ResoniteFluxDrive[placed, "wl/x", <メンバ ID>, "float"]` が `DynamicValueVariableDriver<T>` を付けます。
  `DynamicValueVariableDriver.Target` (FieldDrive) は **メンバ ID への reference で書けます** (ValueFieldDrive ノードの Proxy は書けない)。
- **value 型と object 型**: string / Uri / Slot / User は object 型です。`WriteOrCreateDynamicValueVariable<string>` は
  "Failed to resolve type" になります。Object 系 (`ValueObjectInput`, `WriteOrCreateDynamicObjectVariable`, `ReadDynamicObjectVariable`,
  `ObjectValueSource`) を使います。検証がこの取り違えを指摘します。

## アクセスレベルと他モジュールとの関係

生成のプロンプトの機密度・アクセスレベルの扱いは Chat ガジェット (`ResoniteRealtime_chat.wl`) と同じです。

- `ResoniteAccessLevel[]` がワールドの表示上限 (1.0 / 0.5 / 0.25) を返します。`$ResoniteWorldAccess` (公開度)、`$ResoniteWorldAccessLevels` (公開度 → 上限の表)、
  `$ResoniteWorldOwner` / `$ResoniteWorldAccessMode` / `$ResoniteOwnerUserId` (オーナー判定。既定はタブレットの監視がワールドから自動で読む。
  `ResoniteAccessLevel["Private", "Owner" -> True]` で手動、`ResoniteAccessLevel[Automatic]` で自動に戻る) が関わります。
- 生成結果を出すパネルは `ResoniteChatGadget[]` / `ResoniteChatStart[]` (監視は ScheduledTask 1 本) です。`ResoniteFluxPlace` の `"Parent" -> Automatic` はこの Chat パネルの根を使います。
- タブレット (`ResoniteTablet`)・サムネイル一覧・PDF ビューア・3D 生成 (`ResoniteGraphics3D`) など他のガジェットは、この ProtoFlux 生成とは独立しています
  (それぞれ `api_tablet.md` / `api_docboard.md` / `api_mesh.md` などを参照)。

## flux-sdk の導入 (任意。"Format" -> "ProtoGraph" のときだけ使う)

- .NET SDK 9 以上。`dotnet tool install --global --version 1.9.0 Papaltine.FluxSDK`
  (1.10.0-rc.2 は tool 用の設定ファイルが無くインストールできない。2026-09-06 時点)。
- Resonite の DLL の場所は `-L` で渡します (`$ResoniteFluxSDK` が Automatic なら
  `C:\Program Files (x86)\Steam\steamapps\common\Resonite` を既定にする)。
  `RESONITE_MANAGED_DATA_PATH` があればそちらを使います。
  環境変数を StartProcess に渡さないのは `$Language=Japanese` で落ちるためです。
- `flux-sdk` が無くても生成と静的検査は動きます (`"Build" -> Automatic` は SDK 未検出なら自動で off)。

## カタログと言語リファレンスの作り方

- `references/protoflux-nodes.json` (3,325 ノード): Resonite の DLL
  (ProtoFlux.Core / ProtoFlux.Nodes.Core / ProtoFlux.Nodes.FrooxEngine / FrooxEngine) を
  `resources/tools/protoflux-nodes-dump.fsx` で反射して raw JSON にし、
  `resources/tools/protoflux-catalog-build.wl` で圧縮したもの (`references/` は GitHub に公開しないので、利用者が自分の Resonite から作る。setup.md 5 節)。ProtoFluxBindings.dll だけにあるノード (ValueInput 等) は
  `protoflux-bindings-dump.fsx` で別に出して合流させます。
  各要素 `<|"Type","Name","Category","Inputs","Outputs","Impulses","Result"|>`。
  Resonite 更新後は 2 つを順に走らせて作り直します (flux-sdk の `froox-docs` でも同等の物が出せる)。
- `references/protograph/*.txt` は Flux SDK 公式 docs (flux-sdk.samsmucny.com) のテキスト抜粋、
  `protograph-skill.md` はその中からプロンプトに入れる 7 ページ (約 63 KB。言語仕様) です。
  サイトは curl 直叩きだと 403 になるのでブラウザの User-Agent を付けて取ります。

## 制約と未検証

- グラフ記述モードの検証は「カタログとの突合 + 配置の成否 + probes の読み戻し」です。型の互換 (float に int を繋ぐ等) は
  配置は通っても動かないことがあり、probes が Missing になって修正 round に回ります。
- ドライブ (ValueFieldDrive の駆動先) は ResoniteLink で書けないので、世界のフィールドを直接動かすグラフは作れません。
  結果は動的変数で受け、必要なら WL 側か既存の in-world ProtoFlux が読みます。
- パネル経路 (`flux:`) は ScheduledTask 内のため ResoniteLink の応答を待てません。複数出力の参照と probes はノートブック経路でだけ機能します。
- 置いたノードにビジュアルは付きません (in-game の ProtoFlux ツールで unpack すれば見える)。
- ProtoGraph モード ("Format" -> "ProtoGraph") は静的検査がノード名だけで、flux-sdk 未導入なら build できません。
  `resources/tools/flux-deploy.fsx` (`ResoniteFluxDeploy` の `"Method" -> "ResoniteLink"`) は未検証・実験的です。

## テスト

```bash
wolframscript -file ResoniteRealtime_info/references/tests/test_flux.wl       # 生成ループ (LLM はスタブ)
wolframscript -file ResoniteRealtime_info/references/tests/test_fluxlink.wl   # 型名解決・検証・レイアウト
```

Resonite / LLM / flux-sdk 不要です。実機の通しは `ResoniteFluxGenerate` を ResoniteLink 接続下で呼びます。