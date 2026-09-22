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

## できないこと / 注意

- **ホストである必要がある** (公式明記)。
- リアルタイム制御には向かない (公式明記)。連続的な駆動は in-world の
  WebSocket/OSC 経路を使う。実測の目安: L1 の往復が 32.5 ms。
- **beta。破壊的変更があり得る。** WL 側はメッセージ組立を `iRLMessage` / `iRLValue`
  相当 (`ResoniteRealtimeValue` / `ResoniteRealtimeLink`) に閉じ込めてある。

## 2026-09-22: 1 接続 100 メッセージ目で必ずタイムアウトしていた (修正済)

受信バッファ `$iLinkMessages` は `$iLinkLimit` (100) 件で切り詰められるのに、`ResoniteRealtimeLink` の待ちは「送信前の件数より後ろ」だけを見ていたため、接続内 101 件目以降の応答が永遠に見えず `Failure["Timeout"]` になった (タブレットの組み立て ~100 メッセージで実測。chat ガジェットは ~60 で気付かなかった)。送信時刻以降に受けたメッセージから `sourceMessageId` で照合する形に直した。
同日実測: enum は `<|"$type"->"enum","value"->"MinSize"|>` だけ通る (int / 型名指定は ResoniteLinkError)、`updateSlot` の `isActive` でスロットの有効/無効を切り替えられる、複数カーネルからの同時接続は可。

