---
tier: procedure
paths:
  - "**/ResoniteRealtime*.wl"
---

# 110 — Resonite タブレット (ワールド内 ClaudeEval) のプロンプトへの答え方

## 背景

`ResoniteRealtime_tablet.wl` は Resonite ワールド内のタブレットから送られたプロンプトを、専用ノートブック
「Resonite Tablet」の ClaudeEval (runtime 経路) として走らせる。プロンプトの先頭に `[Resonite tablet]` と表示上限
(PL) が付く。答えはノートブックのセルに書かれたあと、**機密度が表示上限を超えるセルを除いて**ワールド内の
タブレット (幅の狭いスクロールするテキスト欄 + 画像ビューア) に出る。

## 必須ルール

1. **表示上限を超えるデータは出ない**: プロンプト冒頭の `表示上限 PL x.xx` を超える機密度のセル・オブジェクト・行は
   タブレットに表示されない (機密度が数値で取れないものも非表示)。上限を超えるデータで答えを組み立てない。
   必要なら「表示上限 0.25 のため出せません」と一言で伝える。
2. **SourceVault のオブジェクトは `ResoniteShowObject`**: 画像・PDF・動画・本文をワールドに出すときは
   `ResoniteShowObject[uri]` / `ResoniteShowObject[row]` / `ResoniteShowObject[filePath]` を呼ぶ。
   PDF はビューアでページ送りされる。`SystemOpen` や FE のノートブック窓を開く関数は使わない (ワールドからは見えない)。
3. **一覧は `ResoniteListGadget[rows]`**: 「arXiv の LLM 関連の論文のリスト」「Eagle の写真の一覧」「今週のメール」のような
   一覧の依頼は、**core 関数** (`SourceVaultArXiv[query]`, `SourceVaultEagleSummaries[query]`,
   `SourceVaultSummaries[query]`, `SourceVaultMailSearchIndex[query]` 等、行リストを返すもの) の戻り値を
   `ResoniteListGadget[rows, "Title" -> "..."]` に渡す。行の ▶ でその PDF / 画像 / 本文がビューアに出る。
   **提案コードとして実行する** (コードを本文に書いて見せるだけではガジェットは作られない)。
   戻り値が `<|"Deferred" -> True, "Id" -> ...|>` なら作成を予約できた = 成功 (組み立てはタブレットの監視 tick が数秒後に行う)。
   失敗扱いにしたり、`TimeConstrained` で包んだり、再試行したりしない。
   core 関数には検索語を渡す (`SourceVaultEagleSummaries["自然計算"]`)。`""` で全件取得して自分で絞らない
   (数分かかり実行上限 30 秒でタイムアウトする。延長を申告しても長い走査は避ける)。
   行を自分で組む (MCP の `sourcevault_search` の結果から等) ときのキーは `Title` / `URI` (`sv://...`) / `Kind` /
   `Date` / `PrivacyLevel` (数値。無い行は表示上限超え扱いで落ちる)。
   `...View` 関数 (Dataset/Grid の UI) はワールドでは使えないので使わない。
4. **図はそのまま出力**: `Plot` 等の Graphics / Image はそのまま結果にすればビューアに映る。
   数式も TeX のまま書けばセルがラスタライズされて映る。
   「ワールドに 3D で出して」「3D オブジェクトにして」と言われたときだけ `ResoniteGraphics3D[Plot3D[...]]` のように
   Graphics3D (Plot3D / ArrayPlot3D / SphericalPlot3D / Graphics3D[...]) を `ResoniteGraphics3D` に渡す
   (頂点色つきメッシュとしてアバターの正面に実体化。`"Size" -> 0.6` m)。言われなければ普通に出力する
   (タブレットの「3D生成」ボタンで後から作れる)。Line / Point だけの図は面が無いので作れない。
5. **短く**: テキスト欄は狭い。見出し・箇条書きは最小限、Markdown 装飾は使わない。長い説明はしない。
6. **承認**: 承認が必要な式はタブレットの承認/拒否ボタン (ノートブックの承認ボタンと同じ) で処理される。
   承認待ちのまま Pause で待たない。

## ノートブックの形 (LLM が書くコード)

```mathematica
ResoniteListGadget[SourceVaultArXiv["LLM", "Limit" -> 40], "Title" -> "arXiv: LLM"]
ResoniteShowObject["sv://snapshot/sha256/..."]
ResoniteShowObject[First[SourceVaultEagleSummaries["猫"]]]
Plot[Sin[x], {x, 0, 2 Pi}]
```
