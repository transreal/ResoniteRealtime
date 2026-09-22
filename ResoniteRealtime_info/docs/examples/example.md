# ResoniteRealtime 使用例集

Mathematica から Resonite を制御するブリッジの、よく使う操作パターンをまとめます。各例は `Block[{$CharacterEncoding = "UTF-8"}, Get["ResoniteRealtime.wl"]]` の後にそのまま評価できます。L2 (ResoniteLink) を使う例では、Resonite の Dashboard → Session → Settings で ResoniteLink を有効化し、表示されたポートで接続しておきます (導入は [setup.md](setup.md))。

## 1. ResoniteLink に接続して階層を見る

```mathematica
ResoniteRealtimeLinkConnect[]            (* ポートは自動検出。明示なら ResoniteRealtimeLinkConnect[46378] *)
ResoniteRealtimeGetSlot["Root", "Depth" -> 1]
```
`"Depth" -> -1` で全階層、`"IncludeComponentData" -> True` でコンポーネントの中身も返ります。

## 2. Slot と Component を作る

```mathematica
r = ResoniteRealtimeAddSlot["Name" -> "Hello", "Parent" -> "Root", "Position" -> {0, 1.5, 2}];
ResoniteRealtimeAddComponent[r["Id"], "[FrooxEngine]FrooxEngine.Grabbable", <|"Scalable" -> True|>]
ResoniteRealtimeRemoveSlot[r["Id"]]
```

## 3. 図を板に出す

```mathematica
ResoniteRealtimeStart[];                       (* 画像配信 *)
ResoniteRealtimeBoard[];
ResoniteRealtimeShowImage[Plot[Sin[x], {x, 0, 2 Pi}]]
ResoniteRealtimeShowImage[Graphics3D[Sphere[]], "Size" -> 1000]
```

## 4. 世界のイベントを受け、世界へ送る (L1)

```mathematica
ResoniteRealtimeStart[];
ResoniteRealtimeOn["evt", Function[rec, Print[rec["Args"]]]];
ResoniteRealtimeSend["cmd", "show", ResoniteRealtimeShowImage[Plot[Cos[x], {x, 0, 5}], "Send" -> False]]
ResoniteRealtimeEvents[10]
```
世界側のブリッジオブジェクト (`WebsocketClient`) の作り方は [in-world-bridge-setup.md](in-world-bridge-setup.md)。

## 5. 表示上限を宣言する

```mathematica
ResoniteAccessLevel["Private", "Owner" -> True]    (* 1.0 *)
ResoniteAccessLevel["Public"]                      (* 0.25 *)
```
上限を超える機密度の資料・セルはワールドに出ません。

## 6. Chat ガジェット

```mathematica
ResoniteChatGadget[]; ResoniteChatStart[];
ResoniteChat["フィボナッチ数列の最初の 10 項は?"]
```
パネルの入力欄と送信チェックからも同じ処理が走ります。

## 7. タブレットで ClaudeEval

```mathematica
ResoniteTablet[]
ResoniteTabletEval["Plot3D[Sin[x y], {x, 0, 3}, {y, 0, 3}]"]
ResoniteTabletStatus[]["Turn"]
```
専用ノートブック「Resonite Tablet」で runtime 経路の ClaudeEval が走り、結果がタブレットの出力欄と板ビューアに出ます。承認待ちはタブレットの承認/拒否ボタンか `ResoniteTabletApprove[]` / `ResoniteTabletDeny[]`。

## 8. 直前の 3D プロットをワールド内のメッシュにする

```mathematica
ResoniteTabletMake3D[]        (* タブレットの「3D生成」ボタンと同じ *)
```
ノートブックから直接なら:

```mathematica
r = ResoniteGraphics3D[Plot3D[Sin[x y], {x, 0, 3}, {y, 0, 3}], "Size" -> 0.6];
ResoniteGraphics3DRemove[r]
```
ResoLoop パッケージと resoloop が必要です。

## 9. 資料の一覧をワールドに出し、▶ で開く

```mathematica
rows = SourceVaultArXiv["LLM"];                     (* SourceVault の core 関数 (行リスト) *)
ResoniteListGadget[rows, "Title" -> "arXiv: LLM"]
```
タブレットのプロンプトで「SourceVault の arXiv の論文のリスト」と頼んでも同じ結果になります (提案コードが `ResoniteListGadget` を呼び、tick が組み立てます)。

## 10. PDF を掴めるビューアで読む

```mathematica
ResonitePDFViewer["C:\\docs\\paper.pdf"]
ResonitePDFViewerPage["Next"]
ResonitePDFViewerPage["+10"]
ResonitePDFViewerRemove[]
```

## 11. ProtoFlux をプロンプトから作る

```mathematica
r = ResoniteFluxGenerate["0.5 秒ごとに 1 ずつ増えるカウンタを wl/count に書く"];
r["Probes"]
ResoniteFluxRemove[r["Placed"]]
```
ノードカタログ (`ResoniteRealtime_info/references/protoflux-nodes.json`) は setup.md 5 節の手順で作ります。

## 12. グラフ記述を直接配置する

```mathematica
g = <|"name" -> "SumDemo",
  "nodes" -> {
    <|"id" -> "a", "type" -> "ValueInput<float>", "value" -> 1.|>,
    <|"id" -> "b", "type" -> "ValueInput<float>", "value" -> 2.|>,
    <|"id" -> "sum", "type" -> "ValueAdd<float>", "inputs" -> <|"A" -> "a", "B" -> "b"|>|>,
    <|"id" -> "path", "type" -> "ValueObjectInput<string>", "value" -> "wl/sum"|>,
    <|"id" -> "here", "type" -> "ElementSource<Slot>", "ref" -> "$root"|>,
    <|"id" -> "w", "type" -> "WriteOrCreateDynamicValueVariable<float>",
      "inputs" -> <|"Value" -> "sum", "Path" -> "path", "Target" -> "here"|>|>,
    <|"id" -> "tick", "type" -> "LocalUpdate", "impulses" -> <|"OnUpdate" -> "w"|>|>},
  "probes" -> {"wl/sum"}|>;
ResoniteFluxValidateGraph[g]
placed = ResoniteFluxPlace[g];
ResoniteFluxProbe[placed]
```
書式の詳細は `$ResoniteFluxGraphSpec` と [protoflux-gadget.md](protoflux-gadget.md)。

## 13. インベントリに保存したタブレットを使う (Resonite 側から呼び出す)

```mathematica
Get["ResoniteRealtime.wl"]      (* ノートブックのセッションなら常駐監視 ResoniteTabletServe[] が自動で始まる *)
```
Resonite で ResoniteLink を有効化し、インベントリからタブレットを出して「接続」を押すだけです。手動なら:

```mathematica
ResoniteRealtimeLinkConnect[];  (* 自動検出 *)
ResoniteTabletFind[]            (* {<|"Id", "Name", "Attached"|> ...} *)
ResoniteTabletAdopt[]           (* 最後に見つかったものを引き継ぐ *)
```

## 14. カーネル再起動後の掃除

```mathematica
ResoniteRealtimeLinkConnect[port];
ResoniteTabletCleanup[]        (* Root 直下の残骸を名前で消す *)
ResoniteTablet[]
```

## 15. 状態と診断

```mathematica
ResoniteRealtimeStatus[]
ResoniteTabletStatus[]
ResoniteTabletStatus[]["LastShow"]      (* 一覧の ▶ で何が開かれたか *)
ResoniteTabletDeferred[]                (* 予約した組み立ての台帳 *)
```
