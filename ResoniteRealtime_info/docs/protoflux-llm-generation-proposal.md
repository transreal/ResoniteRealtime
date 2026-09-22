# ProtoFlux を LLM に書かせる方法 — サーベイと提案 (2026-09-06)

対象: `README-external-control-survey.md` の P5「ProtoFlux 生成」。
結論を先に書く。

> **LLM には ResoniteLink の JSON を書かせない。ProtoGraph (Flux SDK) を中間言語にして、
> 「生成 → `flux-sdk build` で型検査 → ResoniteLink でホットデプロイ → WL を正解器にした実行テスト → 修正」
> のループを回す。** 生の `addComponent` は、世界の実オブジェクトへの結線と小さなパッチにだけ使う。

---

## 1. サーベイ

### 1-A. Resonite 側で今あるもの

| もの | 何か | 状態 | LLM 生成に使えるか |
| --- | --- | --- | --- |
| **ResoniteLink** (公式) | WS+JSON でデータモデルを読み書き。`addComponent` で ProtoFlux ノード (`[ProtoFluxBindings]…`) も置ける | 0.13.1、beta。2 月に reflection・batch、3 月に sync メソッド呼出・辞書・セッション発見 | 置く手段としては本命。**書かせる対象としては不適** (下記) |
| **esnya/FluxMcp** | MOD で ProtoFlux を MCP 経由で AI に触らせる | **2026-03-10 アーカイブ**。「公式 ResoniteLink で代替」と明記 | 方向性の裏付けのみ |
| **rassi0429/resolink-mcp** | ResoniteLink の MCP ラッパ。`search_components`/`get_component_info`/`grep_source` (逆コンパイル済ソース検索) | 稼働中 | ノード型名の規約と落とし穴の一次情報 (1-B) |
| **sandraschi/resonite-mcp** | 「ProtoFlux スクリプト実行」を謳う | 中身は `[A] → [B] → [C]` の擬似図。実行可能表現ではない | 不採用 |
| **ProtoGraph / Flux SDK** (Papaltine, Kittysquirrel) | ProtoFlux 1:1 のテキスト言語 `.pg` + コンパイラ `flux-sdk` | **v1.7.0 stable (semver 保証)**、Core 1.9.0、AGPL-3.0、.NET 9 | **本命** (1-C) |
| wiki `Module:ProtoFlux` | 全ノードの入出力名と型が JSON でテンプレートに埋まっている | 保守中 | カタログの副次ソース |
| CytraX `Resonite-Component-List-Generator` | FrooxEngine DLL を reflection してコンポーネント/ノード一覧を生成 | 動くが作者自身「garbage setup」 | 不要 (`flux-sdk froox-docs` が同じ事をする) |

### 1-B. ResoniteLink で直接ノードを置く場合に判っていること (resolink-mcp の知見)

- 型名は `[ProtoFluxBindings]FrooxEngine.FrooxEngine.ProtoFlux.CoreNodes.<Node><T>` /
  `[ProtoFluxBindings]FrooxEngine.ProtoFlux.Runtimes.Execution.Nodes.<Category>.<Node>`。
  `FrooxEngine` が 2 回出る。**間違えると無応答でタイムアウト**する。
- ジェネリクスは `<int>` `<float>` `<floatQ>` `<colorX>` の C# 別名、複合型は `<[FrooxEngine]FrooxEngine.Slot>`。
- 入力は `{"$type":"reference","targetId":…}`。**接続先はコンポーネント ID ではなく出力メンバ自身の id**
  (出力は `{"$type":"empty","id":"…"}` として返る)。
- list は「要素追加 → 返った要素 id で targetId を更新」の 2 段。`enum` は小文字。
- 型検査は一切ない。繋がらない結線は**黙って**失敗する (in-world の手作業と同じ)。
- ResoniteLink はセッションホストでないと使えない。

つまり「ノード名・ジェネリクス・出力 id・2 段 list」を LLM に毎回正しく書かせるのは、
ComfyUI 研究で「JSON を直接書かせると壊れる」と結論された状況そのものになる。

### 1-C. ProtoGraph / Flux SDK で判っていること (公式ドキュメントより)

言語:

```
module CrossProduct
in A: float3
in B: float3
out this: float3
where {
    Ax, Ay, Az = A->unpack;
    Bx, By, Bz = B->unpack;
    Cx = (Ay * Bz) - (Az * By);
    Cy = (Az * Bx) - (Ax * Bz);
    Cz = (Ax * By) - (Ay * Bx);
    pack<float3>(Cx, Cy, Cz);
}
```

```
module Counter
out this: int
out Increment: Impulse
out Decrement: Impulse
where {
    sync CounterVar: int;
    Increment = CounterVar <- ValueInc(CounterVar);
    Decrement = CounterVar <- ValueDec(CounterVar);
    CounterVar;
}
```

- 純粋・遅延・強い静的型の **dataflow が核**。impulse は `impulse { bind x = GET_String(url).OnResponse; … }`、
  `switch node | OnTrue |> … | OnFalse |> …`、`if … then impulse {…} else impulse {…}`、`while`/`for` (+Async 版)。
  ProtoFlux の「impulse の外で出力を読むと既定値」等の癖まで型 (context color) で弾く。
- 動的変数は `~input<T>("name")` / `Slot->~read<T>("tag")` / `Slot->~write("path", Value=…)`、
  動的インパルスは `Slot->~trigger<int>("name", v)`。
- **ノード名は FrooxEngine の実名**が prelude として全モジュールに入っている (`If`, `GET_String`, `ValueWrite<_>`,
  `RangeForLoopInt`, `DelaySecondsInt`, …)。型解決は .NET reflection でジェネリクスまで解く。
- `in` は Source、`out` は Drive になり、in-world の **Flux SDK UI (I/O Assigner)** で世界のフィールドに結線する。
  再インポート時は名前一致で付け替え (`Replace Flux`)。
- **穴 `_`**: 置くとコンパイラが「ここに要る型は X」と言う。エラー箇所は bottom になり**エラーがあってもビルドが通る**
  (Hazel 由来)。生成ノードの Tag にソース位置 (module, 行, 列) が入る。
- CLI: `init` / `new` / `build` (→ `build/dev/<Mod>.pg.brson`) / `pack` / `parse-record` (**.brson → JSON**) /
  **`froox-docs` (全 ProtoFlux ノードの reflection メタデータを JSON/YAML にダンプ)** / `lsp` (言語サーバ)。
- **ResoniteLink 連携**: `Papaltine.FluxSDK.Core` + `YellowDogMan.ResoniteLink` を dotnet から使い、
  `Loader.replace config modulePath target` で**セッションへ直接デプロイ・ホットリロード** (brson 手動インポート不要)。
  標準レシピ `Recipes.hotReloadModuleAndWait` は Source/Drive 結線を扱わない (custom target で拡張可)。
- 要件: .NET 9、**Resonite の managed DLL** (`RESONITE_MANAGED_DATA_PATH` か `-L`)。この PC は Steam 版があるので可。
- 作者の設計方針: 「C#/F# の制限サブセット (UdonSharp 式) や EDSL は semantic dissonance で捨てた。
  ProtoGraph は ProtoFlux を IR として**在世界で読める・共同編集できる**グラフを出すことを優先」。
  LLM 生成物を人が VR 内で直せる、という点で我々の用途にも合う。

### 1-D. 他分野の先行研究 (ノードグラフを LLM に作らせる)

- **ComfyBench** (Xue et al., CVPR 2025): ComfyUI ワークフロー生成の 200 タスク・3,205 ノード注釈のベンチ。
  最良エージェントでも複雑タスクは低成功率。提案の ComfyAgent は **「グラフ JSON ではなく、可逆変換できるコード表現で
  書かせ、インタプリタで実行して検証」**。
- **ComfyGPT** (2025): Reformat / Flow / Refine / Execute の 4 エージェント。Flow はリンク単位のコードを書き、
  Refine が**ノードドキュメントの検索 (RAG)** で存在しないノードを潰し、Execute が実行して失敗を戻す。
  13,571 対の FlowDataset で微調整。
- Unreal Blueprint 系 (ue-llm-toolkit, UnrealGenAISupport 等) は MCP でノード API を直接叩く方式。
  Blueprint は Editor にコンパイラがあるので「置いてコンパイルしてエラーを返す」が成立している。
  ProtoFlux には in-world コンパイラの診断がないので、**外部で型検査できる ProtoGraph がその役を担う**。

共通の教訓は 3 つ: (1) 生成対象は**コンパイル可能なテキスト**、(2) **実在ノードのカタログで接地**、(3) **実行して検証し修正ループ**。

---

## 2. 方式比較

| 方式 | 接地 (幻覚耐性) | 型検査 | 世界への投入 | 実装コスト | 判定 |
| --- | --- | --- | --- | --- | --- |
| A. LLM が ResoniteLink JSON を直書き (resolink-mcp 流) | 低 (型名・出力 id を毎回当てる) | なし。黙って失敗 | 即時 | 小 | **小パッチ・結線専用** |
| B. 自前ミニ DSL (WL 式など) → 自前で ResoniteLink に展開 | 中 | 自前で .NET 型解決・ジェネリクス・impulse 色を再実装する必要 | 即時 | **大** (ProtoGraph の resolver を作り直す) | 不採用 |
| **C. ProtoGraph → `flux-sdk build` → ResoniteLink デプロイ** | 高 (`froox-docs` の実名カタログ + 型解決) | **あり**。穴・bottom・LSP | ホットリロード | 中 (dotnet 側は既製) | **採用** |
| D. MCP 製品 (sandraschi) | — | — | — | — | 実行可能表現ではない |
| E. ロジックは WL/Python で外部実行、ProtoFlux は WebSocket の受け口だけ | 高 | — | 既存 L1/L2 | 済 | **既存方針。C はこれを置き換えず、「在世界で完結すべきもの」にだけ使う** |

C の弱点と対処:

| 弱点 | 対処 |
| --- | --- |
| LLM は ProtoGraph を事前学習でほぼ知らない | 公式 docs は 20 ページ弱で小さい。**skill として全文注入** + ProtoGraph world の対訳例を few-shot。`froox-docs` の JSON を SourceVault に索引して RAG |
| ResoniteLink デプロイは beta、ホスト必須 | メッセージ組立は Flux SDK 側に任せ、WL からは 1 本の `dotnet fsi` スクリプトを叩くだけにして影響範囲を閉じる。ホストでない時は `.brson` を出して手動インポート |
| AGPL-3.0 | ツールとして使うだけ。生成物 (.brson / 世界内ノード) はユーザのもの。Flux SDK を改変配布しない限り問題なし |
| 言語がまだ動く | 1.7 で semver 保証。バージョンを固定し、docs スナップショットを skill に同梱 |

---

## 3. 提案アーキテクチャ

```
 spec (自然言語 / WL 式)
   │
   ▼  [G] 生成: claudecode ($ClaudeModel) + skill "protograph" + froox-docs RAG
 Main/<Name>.pg  (+ 補助モジュール)
   │
   ▼  [V1] 静的検証: flux-sdk build --profile Dev
 診断 (穴の期待型 / bottom / 型不一致 / 未知ノード)  ──失敗→ [R] 修正プロンプトへ (最大 N 回)
   │ 成功
   ▼  [D] デプロイ: dotnet fsi deploy.fsx  (Loader.replace → ResoniteLink)   ※ホストでなければ .brson
 /ResoniteRealtime/Flux/<Name>  (ノード群。Tag にソース位置)
   │
   ▼  [B] 結線: Source/Drive の reference を WL が updateComponent で書く  (または in-world I/O Assigner)
   │         ※ 動的変数・WebSocket 経由の I/O にしておけば結線不要
   ▼  [V2] 実行検証: L1 行プロトコル / Mailbox で入力を流し、出力を getSlot・~read で回収
 WL の同じ計算 (正解器) と比較  ──不一致→ [R]
   │ 一致
   ▼
 AI_GeneratedContent タグ付与、.brson を成果物として保存 (SourceVault に版管理)
```

設計の要点:

1. **LLM に書かせるのは `.pg` だけ。** ノード名は `froox-docs` で生成した一覧に存在するものだけを許可し、
   WL 側で生成物を正規表現走査して未知識別子を弾く (LLM の自己申告に頼らない)。
2. **I/O 規約を固定して結線問題を消す。** 生成モジュールの入出力は次のどれかに限定する:
   - 動的変数: `/ResoniteRealtime/Mailbox` の `Cmd`/`Arg`/`Seq`/`Ret`/`RetSeq` を `~read`/`~write` で読む (既存設計と同じ)
   - WebSocket: `WebsocketTextMessageReceiver` / `Sender` (既存 L1 と同じ TAB 行プロトコル)
   - どうしても世界のフィールドを駆動する時だけ `in`/`out` を使い、WL が Source/Drive の参照を書く
   これで「LLM が世界の何かを探して繋ぐ」工程が無くなる。
3. **WL を正解器にする。** CA・PDE・幾何は WL で同じ入力に対する期待出力が計算できる。
   V2 は「WL の答えと世界の答えの差」で機械判定する。見た目の検証は ResoniteLink ロードマップの
   screenshot API 待ち。それまでは既存の evidence カメラ経路。
4. **修正ループは spec-impl の流儀。** 実装器 `$ClaudeModel`、検証器 `$ClaudeAdvisaryModel`。
   ラウンド打切りは壁時計秒 (tick 数判定の失敗を繰り返さない)。診断はモデル非依存のテキストで渡す。
5. **既存資産を触らない。** `ResoniteRealtime.wl` (L1/L2) はそのまま使い、新規は `ResoniteFlux.wl` に閉じる。

---

## 4. 実装計画

| 段階 | 内容 | 目安 |
| --- | --- | --- |
| **F0** 環境 | `dotnet tool install --global Papaltine.FluxSDK`、`flux-sdk new HelloUser` → `build` → 手動インポートで動作確認。`froox-docs` を JSON で出し、件数と主要ノード (If, ValueWrite, Websocket 系, DynamicVariable 系) を確認 | 半日 |
| **F1** 知識 | skill `protograph` を作る: docs スナップショット (Basic Syntax / Expressions / Types / Impulse / Dynamics / Modules / Style) + 禁止事項 + 我々の I/O 規約 + 対訳例 5 本。`froox-docs` JSON を SourceVault に索引 | 1 日 |
| **F2** WL ラッパ `ResoniteFlux.wl` | `ResoniteFluxBuild[dir]` (RunProcess で `flux-sdk build`、診断を Association に構造化)、`ResoniteFluxCatalogQ[src]` (未知ノード検出)、`ResoniteFluxDeploy[dir, module, parentSlot]` (`deploy.fsx` を `dotnet fsi` で起動。引数は UTF-8 ファイル経由。`$Language=Japanese` の StartProcess 罠に注意)、`ResoniteFluxDiscard[name]` | 1 日 |
| **F3** 生成ループ | `ResoniteFluxGenerate[spec, opts]`: G → V1 → R を最大 N 回。spec-impl の起動関数として登録し、パレットから呼べるようにする | 1 日 |
| **F4** 実行検証 | Mailbox/WebSocket 規約でテストベクトルを流し、WL の期待値と比較する `ResoniteFluxVerify`。最初の題材は (a) `CrossProduct` 相当、(b) TAB 行を受けて slot の色を変える、(c) 1 次元 CA 1 ステップ (WL のルールテーブルと突合) | 1〜2 日 |
| **F5** 仕上げ | `AI_GeneratedContent` 付与、`.brson` の SourceVault 版管理、`parse-record` で既存の手作りノード群を `.pg` 対訳例に逆変換 (few-shot 増強) | 随時 |

最初の実験 (F0〜F2 の通し) は「WL から TAB 行 `color<TAB>#ff8800` を送ると板の色が変わる」で良い。
既存 L1 の受信ノード群を、LLM が書いた `.pg` で置き換えられれば方式の証明になる。

---

## 5. 未確認事項 (実測で潰す)

- ResoniteLink の reflection メッセージの正確な名前 (パッチノートは 2026.2.11 で「dynamic reflection」追加と言うが、
  README のロードマップには「planned」のまま)。**`froox-docs` があれば不要**なので優先度低。
- `Loader.replace` が我々のホスト構成 (Windows クライアントでホスト) でそのまま動くか。ダメなら `.brson` 手動インポートで F4 まで進める。
- `flux-sdk` のノード網羅率。`froox-docs` の件数を wiki `Category:ProtoFlux` と突き合わせる。
- 生成ノードの `Tag` に入るソース位置を、V2 失敗時の「どのノードが悪いか」の特定に使えるか。

---

## 6. 参照

- ResoniteLink: https://github.com/Yellow-Dog-Man/ResoniteLink (README ロードマップに type reflection / type validation / screenshot API / 変更監視)
- ResoniteLink 更新履歴: https://github.com/Yellow-Dog-Man/ResoniteLink/releases (0.13.1 = 2026-03-11)
- 2026.2.11.1336 パッチノート (reflection & batching): https://store.steampowered.com/news/app/2519830/view/502849918049714241
- FluxMcp (アーカイブ): https://github.com/esnya/FluxMcp
- resolink-mcp: https://github.com/rassi0429/resolink-mcp
- sandraschi/resonite-mcp: https://github.com/sandraschi/resonite-mcp
- ProtoGraph (wiki): https://wiki.resonite.com/ProtoGraph
- Flux SDK docs: https://flux-sdk.samsmucny.com/ (Expressions / Impulse-Control-Flow / Dynamics / Modules-and-Packages / CLI-Reference / Compiler-Tool-Chain / Test-and-Debug / Other/ResoniteLink-Getting-Started / Other/Why-ProtoGraph / UI/Flux-SDK-UI)  ※ 直接 curl は 403。ブラウザ UA を付ければ取れる
- Flux SDK ソース: https://git.samsmucny.com/ssmucny/Flux-SDK 、NuGet: https://www.nuget.org/packages/Papaltine.FluxSDK
- wiki Module:ProtoFlux: https://wiki.resonite.com/Module:ProtoFlux/doc
- CytraX 一覧生成器: https://github.com/CytraX-Team/Resonite-Component-List-Generator
- ComfyBench (CVPR 2025): https://arxiv.org/abs/2409.01392 、ComfyGPT: https://arxiv.org/abs/2503.17671
- UE Blueprint 系: https://github.com/ColtonWilley/ue-llm-toolkit 、https://github.com/prajwalshettydev/UnrealGenAISupport

---

## 7. 実装状況 (2026-09-06)

- **実装済**: `ResoniteRealtime_flux.wl` (F1〜F3 相当)。生成 → カタログ突合 → (flux-sdk があれば) build → 修正ループ。
  カタログは flux-sdk の `froox-docs` を待たず、Resonite の DLL を直接反射して作った
  (`resources/tools/protoflux-nodes-dump.fsx` + `protoflux-catalog-build.wl`、3,317 ノード)。
  言語リファレンスは公式 docs の抜粋 (`references/protograph/`)。
- **実装済**: `ResoniteRealtime_chat.wl` (Chat セルをワールド内で実現するガジェット。ProtoFlux 生成の表示先にもなる)。
- **未**: flux-sdk の導入 (ユーザ判断待ち)、F4 の実行検証 (WL を正解器にした比較)、ResoniteLink 経由の
  ホットデプロイ (`resources/tools/flux-deploy.fsx` は未検証)。
