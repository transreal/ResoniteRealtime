# in-world ブリッジの作り方 (L1) と ResoniteLink の有効化 (L2)

`ResoniteRealtime.wl` を使うために **Resonite 側で 1 回だけやること**をまとめる。
WL 側の実装と検証は済んでいる (`ResoniteRealtime_info/references/tests/`)。ここは実機作業。

---

## L1: ブリッジオブジェクト (世界 ⇄ Mathematica のリアルタイム経路)

WL 側が WebSocket サーバなので、**世界側がクライアントとして繋ぎに行く**。
ホストである必要はない。他人のセッションでも自分のアバターに付けて動く。

### 手順

1. **空の Slot を作る。**
   Create New → Empty Object。名前は `ResoniteRealtime Bridge` など。
   ワールドに置いてもよいし、アバターに付けてもよい (どこでも繋がる)。

2. **`WebsocketClient` コンポーネントを付ける。**

   | フィールド | 値 |
   | --- | --- |
   | `URL` | `ws://127.0.0.1:17300/bridge` |
   | `HandlingUser` | **自分**(Mathematica が動いているマシンのユーザ) |
   | `AccessReason` | `Mathematica bridge (ResoniteRealtime)` |
   | `ConnectRetryInterval` | 5 |

   - `HandlingUser` を間違えると、その人のマシンの localhost に繋ごうとして失敗する。
   - Mathematica が**別 PC**で動いているなら、WL 側を
     `ResoniteRealtimeStart["BindAddress" -> "0.0.0.0"]` で起動し、
     URL をその PC の LAN IP (`ws://192.168.x.y:17300/bridge`) にする。

   ### 実機で通した構成 (2026-09-04、L1 開通・RTT 32.5 ms)

実際に動いたノード構成は次のとおり。**`HandlingUser` フィールドには何も書かない**
(`WebsocketConnect` ノードの入力で渡す)。

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

操作面の落とし穴 (全部踏んだ):

- **ノードは「床など当たり判定のある面」を狙ってダブルクリックしないと置けない。**
  空を狙っても何も起きない。ノードブラウザは「項目をダブルクリックで選択 (名前がツールの
  上に出る) → 置き場所をダブルクリックで生成」の 2 段構え。
- **`Receiver.OnReceived` (Call) は `Sender.*` (IAsyncOperation) に直結できない。**
  間に `Flow > Async > StartAsyncTask` を挟む。型が違うと線がつながらないだけで
  エラーも出ないので気付きにくい。
- ノードの `Client` 入力に参照ノードを落とすと **Drive / Write** を聞かれる。
  常時つないでおきたいので **Drive** を選ぶ (`Reference Drive<Websocket Client>` が生える)。
- デスクトップのキー: 左クリック=使う/つなぐ、**T**=コンテキストメニュー、右クリック=掴む、
  **R**=ノード選択、**Ctrl+左クリック**=ワイヤを切る。ダイアログのボタンが押せないときは
  **ESC** でマウスカーソルを解放する。
- 実測: WL → 世界 → WL の往復 **32.5 ms**。ProtoFlux はフレーム同期なので
  60 fps だと 1〜2 フレームが下限。毎フレームの数値ストリームには向かない (OSC を使う)。
- エコー構成にすると **heartbeat も返ってくる**。害はないが Events に溜まる。

### `HandlingUser` の落とし穴 (2026-09-04 実機で踏んだ)

   `HandlingUser` は生の User 参照ではなく **`UserRef`** という入れ子型で、
   `User` / `_machineId` / `_userId` の 3 つを持つ。再入室しても同じ人を指し直せるように
   ID を覚えておく仕組みで、**実際に効くのは解決済みの `User` フィールド**。

   - **`_userId` はユーザ名ではない。** Resonite の User ID は必ず `U-` で始まり、
     ユーザ名と一致する保証はない (移行アカウントは似ていることが多いが、
     新規アカウントはランダム)。`_userId` に `nconc` と入れても解決しない。
     自分の ID はアカウントサイトか `UserUserID` ノードで確認する。
   - **`User: null` のままだと誰も接続を張らない。**

   代入の仕方は 2 通り。**ProtoFlux (下の最小構成) を勧める**。

   - **ProtoFlux**: `LocalUser` を `Write` で `HandlingUser.User` に書く。
     ID も掴み操作も要らず、誰がスポーンしても自分が HandlingUser になる。
   - **インスペクタだけ**: 参照の代入は「行の左端のフィールドハンドルを掴む →
     代入先の行のハンドル (フィールド名側) に落とす」。ただし User 参照を持っている
     場所を先に探す必要があり遠回り。`_userId` を手で入れる手もあるが、
     正しい `U-` 付き ID と `_machineId` が絡むので立ち上げ時には勧めない。

   (`Parent:` / `User:` の横にある 2 つの小さいボタンの機能は公式 wiki に記載が無い。
    参照の代入は上の 2 通りで確実にできる。)

3. **ProtoFlux を置く** (ProtoFlux ツールで `Websocket` / `Users` カテゴリから):

   - `Websocket Connect` — **接続開始。これを impulse しない限り永久に繋がらない。**
     コンポーネントを付けただけでは `IsConnected` は false のまま。
   - `Websocket Connection Events` — 接続/切断イベント。状態表示や再接続に使う。
   - `Websocket Text Message Receiver` — 受信文字列が出る。
   - `Websocket Text Message Sender` — 送信。

   いずれも `WebsocketClient` コンポーネントへの参照を入れる。

   **最小構成**:

   ```
   ValueField<bool>.Value ─▶ FireOnLocalTrue ──*──▶ WebsocketConnect ──Next──▶ …
                                                     Client       ← WebsocketClient の参照
                                                     URL          ← URL フィールドの Source
                                                     HandlingUser ← LocalUser
   ```

   **`WebsocketConnect` の入力は `Client` / `URL` / `HandlingUser` の 3 つ**で、
   すべてノード側から渡せる。つまり:

   - **コンポーネントの `HandlingUser.User` に書き込む必要はない。**
     `LocalUser` を Connect ノードの `HandlingUser` 入力へ直接挿せばよい
     (`Write` ノードも UserRef の代入も不要)。`LocalUser` は「そのノードを見ている
     ユーザ」なので、誰がスポーンしても自分が HandlingUser になり、User ID も要らない。
   - `URL` は Uri 型。インスペクタの `URL:` 行を ProtoFlux ツールで掴んで **Source** を
     選び、その出力を挿すのが早い (URL を二度書かずに済む)。文字列から作るなら
     `String to Absolute URI` を挟む。
   - `ValueField<bool>` をスロットに付け、インスペクタでチェックを入れると
     `FireOnLocalTrue` が**そのクライアントだけで** impulse を出す。
     外す→入れるで何度でも再接続できるので、立ち上げ期のトリガとして扱いやすい。

   送受信のノードも同じ `Client` を使う:

   - `WebsocketTextMessageSender` — 入力 `*`(Call) / `Client` / `Data`(String)、
     出力 `OnSendStart` / `OnSent` / `OnSendError`
   - `WebsocketTextMessageReceiver` — 受信文字列を出す

4. **初回はホストアクセスの同意ダイアログが出る。許可する。**
   誤って拒否した場合: Dash → 右下の Debug → "Web Hosts" タブ → 該当アドレス →
   Remove Setting → もう一度接続して許可。

5. **動作確認**: Mathematica 側で

   ```
   ResoniteRealtimeStart[]
   ResoniteRealtimeEvents[]        (* $open が入っていれば接続成功 *)
   ResoniteRealtimeSend["cmd", "hello"]
   ```

   世界側の Receiver に `cmd<TAB>hello` が出れば往復できている。

### 行プロトコルの設計上の注意

**ProtoFlux は JSON も配列 (Collection) も扱えない。** したがって世界側で
「TAB で分割してリストにする」ことはできない。世界へ送るメッセージは

```
verb<TAB>arg
```

の **2 フィールドまで**に抑え、分岐は「先頭が `cmd\tshow\t` で始まるか」のような
**前方一致 + 残りを Substring で取り出す**形にするのが実用的。

逆向き (世界 → WL) は WL 側でいくらでも分割できるので、フィールド数は自由:

```
evt<TAB>userJoined<TAB>nconc
req<TAB>17<TAB>plot<TAB>Sin[x]
```

WL 側は先頭語 (`evt` / `req` / …) でハンドラに振り分ける:

```
ResoniteRealtimeOn["req", Function[rec,
  Module[{seq = rec["Args"][[1]], what = rec["Args"][[2]]},
    ResoniteRealtimeSendTo[rec["Connection"], "res", seq <> ":" <> ToString[f[what]]]]]]
```

### heartbeat

Resonite の WebsocketClient は **サーバから 60 秒何も来ないと切断する**。
WL 側は既定 25 秒ごとに `hb<TAB><unixtime>` を送っている
(`ResoniteRealtimeStart["Heartbeat" -> 25]`)。**世界側は受け取るだけでよい**。
`hb` で分岐する必要はなく、無視して構わない。

---

## L2: ResoniteLink (Mathematica → データモデル)

### 有効化

1. Dashboard を開く
2. "Session" ページ → "Settings" タブ
3. 左下の **"Enable ResoniteLink"** を選ぶ
4. `ResoniteLink running on port: <port>` が表示される。この番号を使う。

```
ResoniteRealtimeLinkConnect[<port>]
ResoniteRealtimeGetSlot["Root", "Depth" -> 1]
```

### 制約 (公式ドキュメントに明記されているもの)

- **セッションのホストである必要がある。**
- **リアルタイム制御には使わない。** 読み書きは "eventually" 反映。
  連続的に動かすものは L1 (WebSocket) か OSC、または in-world の ProtoFlux でやる。
- ID はセッション内のみ有効。**ワールドを保存して開き直すと変わる**。
  永続化したいものは slot 名か DynamicVariable に逃がす。
- まだ **beta**。スキーマの破壊的変更があり得る。

### P0 で確かめること (未確認)

- [ ] port は毎回変わるのか。`forceResoniteLinkPort` は**通常クライアントでも**効くか
      (ドキュメントは headless の config でのみ言及している)。
      効かないなら起動のたびに Dashboard を見る運用になる。
- [ ] **応答エンベロープの形**。相関 ID があるか。
      現状 `ResoniteRealtimeLink` は「送信後に届いた、JSON として解釈できた最初のメッセージ」を
      応答とみなしている。相関 ID があると分かれば `"Match" -> 述語` を渡すだけで厳密化できる。
- [ ] `WebsocketClient` の同意ダイアログが毎回出るのか、一度許可すれば残るのか。
- [ ] L1 の実測 RTT (ResoniteIO の gRPC は 0.81–1.04 ms だった)。

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
  ノートブックで開発しながら何度も `Get` する使い方を守るためのもの。

Node は v22 以降であれば `WebSocket` が組み込みなので追加インストールは要らない
(検証時は v24.14.0)。

## 実装上の落とし穴 (実測で踏んだもの)

- **SocketListen のコールバックの中で `Close` / `DeleteObject` してはいけない。**
  その場では成功するが、以後に別のソケットを閉じた瞬間にカーネルごと落ちる。
  `ResoniteRealtime_ws.wl` は墓場 (`$iWSGraveyard`) に積んで、トップレベルの公開 API から
  `RRWSSweep[]` で回収する方式にしてある。
- 閉じる順序は「索引から外す → listener を DeleteObject → socket を Close」。逆順は落ちる。
- heartbeat の宛先は **role だけで選ばない**。同一カーネルに別の WebSocket サーバがいると
  その接続にまで送ってしまう (実際に L2 の応答待ちが heartbeat を拾う事故が起きた)。
  ブリッジサーバ ID で絞る。
