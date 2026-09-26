# Chat ガジェット — ノートブックの Chat セルを Resonite ワールド内で実現する

`ResoniteRealtime_chat.wl` (ResoniteRealtime.wl が自動ロード)。2026-09-06 作成。

## できること

| 入口 | 何が起きるか |
| --- | --- |
| ノートブックの **ResoniteInput セル** (`ResoniteChatCell[]` で挿入、Shift+Enter) | `ResoniteChat[text]` が走り、答えがノートブックとワールド内パネルの両方に出る |
| `ResoniteChat["質問"]` | 同上 (関数呼び出し) |
| ワールド内パネルの入力欄 + 「送信」チェック | `ResoniteChatStart[]` の監視タスクが拾い、答えをパネルへ返す |
| 世界の ProtoFlux から L1 で `ask<TAB>質問` | 同上 (既存の WebsocketClient 経路) |

答えに ```` ```mathematica ```` ブロックが含まれ、`"Evaluate" -> True` のときは評価して、
図なら板 (Chat Board) に画像として出す。既定は評価しない。

## 手順

1. Resonite で Dashboard → Session → Settings → **Enable ResoniteLink** (ホストであること)。
2. Mathematica:

```mathematica
Block[{$CharacterEncoding = "UTF-8"}, Get["ResoniteRealtime.wl"]];
ResoniteRealtimeLinkConnect[41234];           (* Dashboard に出た port *)
ResoniteAccessLevel["Public"];                (* ワールドの公開度。既定 Public *)
ResoniteChatGadget[];                         (* パネル + 板をワールドに出す *)
ResoniteChatStart[];                          (* 世界側入力の監視 (1.5 s ポーリング) *)
ResoniteChatCell[];                           (* ノートブックに ResoniteInput セルを挿入 *)
```

3. 終わるとき: `ResoniteChatStop[]` → `ResoniteChatRemoveGadget[]`。

## 置き場所 (既定: アバターの正面)

`"Placement" -> "User"` (既定) では、ユーザの根 slot (`User ...` という名前で `UserRoot` コンポーネントを持つ slot) と
その子 `Head` を読み、**頭の向き (ヨーだけ) の正面 `"Distance"` (1.5 m)、高さは `"Height"` (Automatic = 目の高さ − 0.25 m、
数値なら足元からの高さ)** に、直立してユーザを向く形で置く。親は根と同じ slot (Spawn holder) にするので、
holder が回転しているワールドでも座標合成が要らない。複数ユーザがいるときは `"User" -> "名前の一部"` で選ぶ。
`"Placement" -> "World"` にすると従来どおり `"Parent"` / `"Position"` に置く。

- デスクトップモードでは根 (UserRoot) の回転は視線と一致しない (2026-09-06 実機: 根は無回転で Head がヨー 90°)。
  必ず Head の回転を根の回転と合成して使う。
- 板 (図の出力先) は `ResoniteRealtimeStart[]` の画像配信が無いと真っ黒になる。無いときは `Failure["NoServer"]` で知らせる。
## パネルの構成 (すべて ResoniteLink で組み立て。世界側のノード作業ゼロ)

```
Mathematica Chat            Grabbable, AI_GeneratedContent
├─ Panel                    Canvas 1.2 m × 0.8 m (触れる)
│  │  (UI_UnlitMaterial / UI_TextUnlitMaterial をここに置いて全 Image / Text で共有)
│  └─ VLayout               VerticalLayout
│     ├─ Title              Text
│     ├─ Input              Image + Button + TextField + TextEditor
│     │  └─ Text            Text  ← 打った文字の置き場 (Content)
│     ├─ SendRow            HorizontalLayout: Send (Image + Button + ValueField<bool> + ButtonToggle) + ラベル
│     ├─ Status             Text  (ready / 考え中 / done)
│     └─ Answer             Text  (答え)
└─ Chat Board               ResoniteRealtimeBoard (図の出力先)
```

送信は **Button + ValueField<bool> + ButtonToggle**。ButtonToggle の TargetValue には ValueField の `Value`
メンバの ID (getSlot の応答に入っている) を参照で入れる。WL は Value を読んで処理し、False に戻す。

## アクセスレベル (2026-09-22 に 4 段化。正本は tablet.md)

> 2026-09-22: `$ResoniteWorldAccessLevels` は Private 1.0 / Contacts 0.5 / ContactsPlus 0.25 / Public 0.25、非オーナー (`$ResoniteWorldOwner = False`、既定) は一律 0.25。`ResoniteAccessLevel[kind, "Owner" -> True]` で設定。以下は 2 段だった頃の記述。


| ワールド | `$ResoniteWorldAccess` | アクセスレベル | SourceVault release context |
| --- | --- | --- | --- |
| 公開 | `"Public"` (既定) | **0.25** | `resonite-public` (MaxPrivacyLevel 0.25) |
| 非公開 | `"Private"` | **1.0** | `resonite-private` (MaxPrivacyLevel 1.0) |

- 表は `$ResoniteWorldAccessLevels` で変えられる (再ロードで既定に戻る)。
- 不明な値は Public 扱い (厳しい側)。
- **LLM への PrivacyLevel** = Max[プロンプトの機密度, SourceVault 文脈の機密度]。
  - プロンプトの機密度: ノートブック起点は NBAccess の宣言 (Private ノート = 1.0) とセルの機密マーク。
    世界起点は、Private ワールドなら 1.0 (その世界で打たれた文字はその世界の水準)、Public なら 0。
  - 0.5 を越えると claudecode が `$ClaudePrivateModel` (ローカル LLM) へ回す。未設定なら送らない。
- **プロンプトの機密度 > ワールドのアクセスレベル** (Private ノートの内容を Public ワールドへ) は
  LLM を呼ばずに `Failure["WorldAccessDenied"]`。
- SourceVault 文脈は `SourceVaultKBAnswer` (LLM を呼ばない根拠文の組み立て) を release context 付きで呼ぶ。
  KB が無ければ黙って文脈なしで進む。release context は初回に登録する (登録簿は永続化される)。

## 設計上の約束

- 監視は ScheduledTask **1 本** (`ResoniteChatStart` が前の分を必ず止めてから作る)。
- **ScheduledTask の中では ResoniteLink の応答を待たない。** タスク実行中は応答を受ける非同期ハンドラが走れず、待つ getSlot は必ずタイムアウトし、5 秒 x 毎 tick でカーネルが塞がって FE が固まる (2026-09-06 実機)。tick は「getSlot を送るだけ → 次の tick で `sourceMessageId` が一致する応答を探す」の二段階、書き込みは `Block[{$iLinkWaitDefault = False}, ...]` で送りっぱなし。LLM (ClaudeQueryBg) だけは同期で、その数秒〜数十秒はカーネルが塞がる。
- ScheduledTask / SocketListen の中では FrontEnd を触らない。LLM は `ClaudeQueryBg`、
  ノートブック起点だけ `ClaudeQuerySync` (進捗表示つき)。画像化は `UsingFrontEnd` で最小限。
- L1 の `ask` ハンドラは SocketListen のコールバック内なので、処理を 0.1 秒後の単発タスクへ逃がす。
- ResoniteLink の `$type` はこのファイルに書かない (本体の AddSlot / AddComponent / UpdateComponent / GetSlot を通す)。

## 未検証

- Private ワールドの判定は 2026-09-25 から自動 (タブレットの監視が SessionInfoSource + WorldSessionID で読む。tablet.md)。
  手動の `ResoniteAccessLevel["Private"]` も使え、呼ぶと手動になる。
- Text の整列 (enum) は既定のまま (書式は `<|"$type"->"enum","value"->...|>` で通るはず)。
- 背景を不透明にする方法 (下の表を参照)。

## テスト

```bash
wolframscript -file ResoniteRealtime_info/references/tests/test_chat.wl
```

Resonite も LLM も要らない (アクセスレベル・応答パーサ・ガードだけ)。

## 実機で分かったこと (2026-09-06、Resonite 2026.9 / ResoniteLink 0.13、port 37591)

通しで動いた: パネルの入力欄に「1から100までの和」→ 白い四角をクリック → 8 秒で「5050 です。…」がパネルに出た。
図の板 (Sin のグラフ) も出た。以下は、そこに辿り着くまでに踏んだ罠。**組み立てコードには全部反映済み**。

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| パネルが何も描かれない | UIX の Image / Text に**マテリアルが無い** (in-game の UIBuilder は必ず付ける) | `UI_UnlitMaterial` / `UI_TextUnlitMaterial` をパネルごとに 1 つずつ作り、Image.Material と Text.Materials (list) に参照を入れる。Font は自動で既定が付く |
| 文字も行も見えない | Canvas の `Size` は**メートル**。文字サイズ 28 = 28 m、行の高さ 112 = 112 m で外へ飛ぶ | Canvas を 1200×800 単位にして Panel スロットを 0.001 倍にする (`"CanvasSize"`, `"PanelScale"`) |
| 真っ黒で文字が消える | UI マテリアルの `BlendMode` を Opaque にすると、同じ平面の文字と Z ファイト | UI マテリアルは Alpha のまま。見た目は半透明で我慢 (背景板 `"Backdrop"` は前後どちらに置いても覆うので既定 off) |
| 四角をクリックしても反応しない | `Checkbox` は **Button ではない** (UIComponent)。しかも同じスロットに Button を足すと、`ButtonToggle` が先にある Checkbox を IButton として掴んでしまう | 送信は Button + `ValueField<bool>` + `ButtonToggle` (TargetValue → **メンバ ID**)。Checkbox は置かない |
| 監視が途中で黙る | 別のカーネルから ResoniteLink に繋ぐと、先に繋いでいた接続の応答が止まる (実質 **同時 1 接続**)。それ以外でも回答の約 1 分後から getSlot がタイムアウトし続けた例あり | 監視中は別の接続で触らない。`ResoniteChatStatus[]` の `PollFailures` が増え続けたら `ResoniteRealtimeLinkConnect[port]` で繋ぎ直す |
| 答え欄が文字化け | `wolframscript -file` は非 ASCII リテラルをバイト列で読む (既知の罠) | パッケージ経由の文字列は正しい。テストスクリプトに日本語リテラルを書かない |
| slot の有効/無効が効かない | キー名は応答と同じ **`isActive`** (`active` は無視される) | AddSlot / UpdateSlot とも `isActive` |

判明した仕様:

- 子スロットの `RectTransform` は ResoniteLink 経由でも自動で付く。Canvas の `BoxCollider` (Size = Canvas Size) も自動。
- getSlot の応答のメンバは `<|"$type", "value", "id"|>` で **メンバ ID を持つ** (`Reso_…`)。`ButtonToggle.TargetValue` のような
  フィールド参照はこの ID を `reference` の targetId に入れる。
- `removeComponent` は `<|"$type" -> "removeComponent", "componentId" -> id|>` で通る。
- enum は `<|"$type" -> "enum", "value" -> "Alpha"|>` で書ける (`ZWrite` も enum: Auto/On/Off。bool は弾かれる)。
- `Checkbox.CheckVisual` は slot 参照も Image 参照も弾かれた (型未確認)。
- 2 つ目の ResoniteLink 接続は張れるが、上の表のとおり先の接続が黙る。
| 監視が `listening` のまま、FE が固まる | ScheduledTask の中では ResoniteLink の応答が受け取れず、待つ getSlot が毎 tick 5 秒タイムアウト | tick では待たない二段階方式 (`icPoll` / `icPollHandle`)。書き込みは `$iLinkWaitDefault = False` で送りっぱなし。復旧は「評価を中止」→ `ResoniteChatStop[]` |
