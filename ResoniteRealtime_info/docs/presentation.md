# 発表 — SlideWorkflow のプレゼンを Resonite のワールド内で自動実行する

`ResoniteRealtime_present.wl` (ResoniteRealtime.wl が自動ロード。chat / tablet の UIX 部品の上に載る)。2026-11-23 起草。

VRChat では VRCRealtime が**別アカウントのアバター**で Sliden を操作して発表します。Resonite では
**オーナーのアカウントでログインしたまま、ResoniteLink だけで**同じ発表 (SourceVault の発表登録簿 = SlideWorkflow パレットの「登録」) を実行します。
専用アカウントも、ワールド側のノード作業も、既存の発表ガジェットも要りません。スクリーンはその場で作ります。

## すぐ使う

```wolfram
ResoniteRealtimeLinkConnect[]                 (* Resonite でホストして Enable ResoniteLink。ポートは自動検出 *)
ResonitePresentationList[]                    (* 始められる発表の題名 *)
ResonitePresentationSetVoice["ほのか"]         (* 声を選ぶ (名前の一部でよい)。既定は "realtime:harema" *)
ResonitePresentationStart["計算と自然31"]       (* アバターの正面にスクリーンを作り、最初の枚を映して開始待ちで止まる *)
ResonitePresentationControl["Start"]          (* 読み始める (操作パネルの「開始」と同じ) *)

ResonitePresentationControl["Pause"]          (* "Resume" | "Toggle" | "Stop" | "Next" | "Previous" | "First" | "Last" | 番号 *)
ResonitePresentationStatus[]
ResonitePresenterResize["Larger"]             (* スクリーンを 1 段大きく ("Smaller" | "Reset" | 段の番号) *)
ResonitePresenterRemove[]                     (* スクリーンと操作パネルを片付ける *)

ResonitePresentationPanel[]                   (* ノートブックに置く操作パネル *)
ResonitePresentationVoiceControl[True]        (* 声での操作と質問への応答 (音声ブリッジ) を始める *)
```

`ResonitePresentationStart` はすぐ戻ります。組み立てと進行は監視タスク (0.4 秒ごと) が進めます。
スクリーンだけ先に置きたいときは `ResonitePresenter[]`。

### 開始待ち

`ResonitePresentationStart` は、既定では**読み始めません**。スクリーンを置いて最初の枚を映し、「開始待ち」で止まります
(スクリーンをつかんで良い位置へ動かしたり、大きさを決めたりする時間)。読み始めるのは次のどれかです。

- 操作パネルの「開始」(ワールドのパネルでも、ノートブックのパネルでも)
- `ResonitePresentationControl["Start"]`
- 声で「発表を始めて」

待っている間も「前へ」「次へ」で枚は送れ (映すだけ)、「開始」はそのとき映っている枚から読み始めます。
ローカルの声の音声は、待っている間に先に作っておきます。

- すぐ読み始めたいときは `ResonitePresentationStart[title, "AutoStart" -> True]`。
- 止めたあと・終わったあとにワールドのパネルの「開始」を押したときは、選んである発表をすぐ読み始めます (スクリーンはもう置いてある)。
- 声で「〜の発表を始めて」と頼んだときは、スクリーンがもう置いてあればすぐ読み始め、これから置くときは開始待ちで止まります。

## ワールドに出来るもの

`ResonitePresenter[]` が 1 つの slot (既定の名前 "Mathematica Presenter"、つかんで動かせる) の下に次を作ります。

| 部品 | 中身 |
| --- | --- |
| スクリーン | `QuadMesh` + `UnlitMaterial` + `StaticTexture2D` 2 枚 (表と控え)。幅 2.4 m の 16:9。裏に薄い箱 |
| スピーカー | `StaticAudioClip` 2 本 (再生中と控え) + `AudioClipPlayer` + `AudioOutput` (マルチメディアの音量、3 m まで等音量) |
| 操作パネル | UIX。発表の選択 `<` `>`、開始、一時停止/再開、停止、前へ、次へ、声を替える、音声応答、縮小、拡大、状態行 |

### 「前へ」「次へ」

| いまの状態 | 押すと |
| --- | --- |
| 発表中 | 移った枚を頭から読み始めます |
| 開始待ち | 枚を送るだけで、読みません。「開始」で、そのとき映っている枚から読み始めます |
| 一時停止中 | **枚を送るだけ**で、読みません。「一時停止/再開」で、そのとき映っている枚を頭から読み始めます |
| 停止したあと、発表が終わったあと | 枚を送るだけで、読みません。「開始」は選んである発表を 1 枚目から始め直します |

声での「次のスライド」や `ResonitePresentationControl["Next"]` も同じ扱いです。
(2026-11-23 までは、一時停止中に押すと再生が始まり、停止中は何も起きませんでした。)

### スクリーンの大きさ

パネルの「縮小」「拡大」(ノートブックでは `ResonitePresenterResize["Smaller" | "Larger" | "Reset" | 段の番号]`) で、
組み立てたときの大きさを等倍として 0.5 / 0.75 / 1 / 1.5 / 2 / 3 倍の 6 段を上下します (幅 2.4 m なら 1.2〜7.2 m)。
スクリーンの下の辺の高さは変わらず、操作パネルは同じ大きさのままスクリーンの右端についていきます。
段階は `$ResonitePresenterScales` で変えられます。全体を手でつかんで拡大縮小することもできます (こちらはパネルも一緒に変わる)。

- 既定ではアバターの正面 3 m、足元から 0.9 m の高さに置きます (`"Distance"`、`"Height"`、`"Width"`)。
  アバターは「名前が `User ` で始まり、子に `Head` を持つ slot」で見つけます (名前だけで選ぶと ProtoFlux の
  `User In VR Flux` のような別物を採ってしまう。2026-11-23 実機)。座標で置くなら
  `ResonitePresenter["Placement" -> "World", "Position" -> {x, y, z}]`。
- スライドは Sliden 用 mp4 (登録簿の SlideURL) を取ってきて 1 枚ずつ PNG にし、`importTexture2DFile` で
  **Resonite の資産 (`local://`)** に取り込みます。公開 URL も画像配信サーバも要らず、セッションの全員に見えます。
  次の枚は控えのテクスチャに読み込んでおき、マテリアルの参照を切り替えるだけなので、切り替えは一瞬です。
- 音声も `importAudioClipFile` で資産に取り込み、`AudioClipPlayer` の `playback` (`play` / `position`) を書いて鳴らします。

## 声

`$ResonitePresentationVoice` (既定 `"realtime:harema"`)。候補は `ResonitePresentationVoices[]`。
切り替えは `ResonitePresentationSetVoice[name]` / `ResonitePresentationCycleVoice[]` / パネルの「声を替える」/ 声で「声をほのかに変えて」。
発表の途中で替えると、次のスライドから効きます。

| 声 | どこから鳴るか | 作り方 |
| --- | --- | --- |
| ローカルの声 (SourceVault の声: ほのか・まお・コハク・tsukuyomi …) | **スクリーンのスピーカー** (ワールドの全員に聞こえる) | AivisSpeech へ `URLSubmit` で頼む (カーネルを塞がない)。今の枚と次の 2 枚まで先に作る。Piper の声は同期 (速い)。音声もテキストも機械の外へ出ません |
| クラウドの声 (`realtime:harema` など。モデルは `$ResonitePresentationVoiceModel`、既定 `gpt-live-1.1`) で、**録音がある枚** | スクリーンのスピーカー | 前に読んだときの録音をそのまま鳴らす (API を呼ばない) |
| クラウドの声で、**録音が無い枚** | **音声ブリッジ** (SourceVault の音声会話。Windows の既定の出力デバイス) | その場で読み上げ、鳴った音を 1 枚ずつ録って置き場に取っておく |

つまり Harema の声は、**最初の 1 回だけ**音声ブリッジが実時間で読み (GPT-Live は実時間でしか話せません)、2 回目からはスクリーンから全員に聞こえます。
本番の前に 1 度、一人で通しておくのが簡単です。最初の回から聴衆に聞かせるには、音声ブリッジの出力を仮想ケーブルにします:

```wolfram
$ResonitePresentationOutputDevice = "CABLE Input";   (* Resonite のマイクを CABLE Output にする *)
```

- `$ResonitePresentationAudioRoute`: `Automatic` (上の表のとおり) / `"World"` (録音の無いクラウドの声は読まずに 3 秒見せて進む) / `"Live"` (クラウドの声はいつも音声ブリッジ)。
- 途中で切れた録音 (原稿を毎秒 7 文字で読んだ長さの 55% に満たない) は取っておきません。
- 置き場は `$ResonitePresentationCacheDirectory` (既定 `$UserBaseDirectory/ApplicationData/ResoniteRealtime/present/<発表ごとの鍵>/`)。
  `slides/s001.png …`、`audio/<声>/a001-<原稿のハッシュ>.wav …`。原稿を直すとその枚だけ作り直します。
- 先に全部作っておくなら `ResonitePresentationPrepare["計算と自然31"]` (ローカルの声だけ)。
- 「はるか」という名前の声はこの環境に無く、いちばん近いのは「ほのか」です。声の名前は `ResonitePresentationVoices[]` で確かめてください。

### ローカルの声のエンジン (AivisSpeech) が止まっているとき

ほのか・まお・コハクは AivisSpeech の声で、**AivisSpeech Engine が動いているときしか `ResonitePresentationVoices[]` に並びません**
(止まっていると tsukuyomi とクラウドの声だけ)。エンジンは Mathematica のカーネルが起こした子プロセスなので、カーネルを起動し直すと止まっています。
止まっていても、声を頼めば起こします:

| どこから | 動き |
| --- | --- |
| ノートブックで `ResonitePresentationSetVoice["ほのか"]` / `ResonitePresentationStart[…, "Voice" -> "ほのか"]` / `ResonitePresentationCycleVoice[]` | エンジンを起こして、応答するまで**待ちます** (この機械で 15〜30 秒、初回は 1〜2 分)。そのあと声が選ばれます |
| ノートブックのパネルの「声を選ぶ」 | AivisSpeech の声が並んでいなければ「ローカルの声を起動 (AivisSpeech)」が出ます。起動が済むと一覧が増えます |
| ワールドのパネルの「声を替える」、声で「声をほのかに変えて」 | **待たずに**起こします (進行を止めない)。状態行に「ローカルの声 (AivisSpeech) を起動しています」と出て、「使えるようになりました」に変わったら、もう一度押す (言う) と選べます |

- `ResonitePresentationVoices[]` そのものはエンジンを起こしません (いま選べる声を返すだけ)。
- 発表の途中でエンジンが落ちたときも、待たずに起こし直して、その枚は音声ができるまで待ちます (240 秒たっても来なければ黙って見せて進む)。
- 自動で起こしたくなければ `SourceVault`$SourceVaultVoiceAivisAutoStart = False` (SourceVault の設定をそのまま見ます)。

## 声で操作する / 質問に答える

`ResonitePresentationVoiceControl[True]` (パネルの「音声応答」) が SourceVault の音声ブリッジ (`SourceVaultRealtimeStart`、既定 `gpt-live-1.1`・声は Harema) を起こします。
読み上げの声がローカルでも、応答は Harema が話します。止めるのは `ResonitePresentationVoiceControl[False]`。

| 言い方 | 動き |
| --- | --- |
| 「計算と自然31の発表を始めて」「三蔵祭のプレゼンをお願い」 | 登録簿から探して開始 (スクリーンが無ければ作る) |
| 「一時停止して」「発表を再開して」「発表を終了して」 | 進行の操作 |
| 「次のスライド」「前のスライド」「3 枚目」「〇〇のスライド」 | スライドの移動 (`show_slide`) |
| 「声をほのかに変えて」「ナレーションをハレマにして」 | 声の切り替え |
| 「発表の一覧を教えて」 | 題名を読み上げる |
| それ以外の質問 | 元の受け口 (`SourceVaultTalkQAHandler` = SourceVault の資料) で答える |

- 仕組み: `$SourceVaultRealtimeSlideHandler` / `$SourceVaultRealtimeAskHandler` を一時的にこのモジュールの受け口に差し替え、
  操作の依頼だけ先に拾って、残りは元の受け口へ回します。止めると元に戻します。
- 質問を操作と取り違えないよう、**頼む形の言い方だけ**を拾います (「この発表について説明して」「発表はいつ終わりますか」は質問として扱う)。
- 応答している間は、スクリーンの読み上げを止めて待ち、静かになって 2 秒したら続きから再開します。
- 1 枚読み終えるごとに `$ResonitePresentationQuestionSeconds` (既定 3 秒) の質問の時間を置きます。やり取りが始まったら、終わるまで次へ送りません (上限 60 秒)。
- クラウドの声が読んでいる間はマイクを閉じます。スクリーンから読んでいる間は既定でマイクを開けたままです。
  ヘッドセットを使わず、スピーカーの音をマイクが拾う環境では `$ResonitePresentationListenWhileNarrating = False` にしてください。
- マイクは Windows の既定の入力 (`$ResonitePresentationInputDevice` で変更)。**オーナー本人の声**で操作する想定です。
  同じワールドの他の人の声を聞かせるには、Resonite の音声出力を録れるデバイス (ループバック) を入力に指定します。

### プライバシー

- 音声ブリッジはクラウド経路です (マイクの音声と会話が OpenAI へ送られる)。`SourceVaultRealtimeStart` の確認をそのまま通ります:
  評価したノートブックの有料 API 許可、Private 宣言のノートでは始めない、NBAccess のプロバイダ方針。
  どのノートブックの許可を使うかは、`ResonitePresenter` / `ResonitePresentationStart` / `ResonitePresentationVoiceControl` を**評価したノートブック**です。
  パネルや声から音声応答を始めるには、先にノートブックで 1 度どれかを評価しておきます。
- 発表は登録簿の公開上限 (`$SourceVaultSlideDeckReleaseCeiling`、既定 0.5) を通ったものだけです。
- ワールドに出してよいかは、発表の機密度と `ResoniteAccessLevel[]` (ワールドの表示上限) で決めます。上限**以上**は出しません (tablet と同じ規則)。
- ローカルの声の合成は機械の外へ出ませんが、鳴らした音はワールドの全員に聞こえます (スライドと同じ扱い)。

## 設定

| 変数 | 既定 | 意味 |
| --- | --- | --- |
| `$ResonitePresentationVoice` | `"realtime:harema"` | 読み上げの声 |
| `$ResonitePresentationVoiceModel` | `"gpt-live-1.1"` | クラウドの声と音声応答のモデル |
| `$ResonitePresentationCloudVoices` | `{"harema", "shida", "marin", "cedar"}` | 一覧に並べるクラウドの声 (harema / shida は GPT-Live 専用) |
| `$ResonitePresentationAudioRoute` | `Automatic` | 音の出し方 |
| `$ResonitePresentationOutputDevice` / `InputDevice` | `Automatic` | 音声ブリッジのデバイス (名前の一部) |
| `$ResonitePresentationQuestionSeconds` | `3.` | 1 枚ごとの質問の時間 |
| `$ResonitePresentationListenWhileNarrating` | `True` | スクリーンから読んでいる間もマイクを聞くか |
| `$ResonitePresentationVolume` | `1.` | スピーカーの音量 (スクリーンを作るときに効く) |
| `$ResonitePresenterScales` | `{0.5, 0.75, 1, 1.5, 2, 3}` | スクリーンの大きさの段階 (組み立てたときの大きさに対する倍率) |
| `$ResonitePresentationCacheDirectory` | `Automatic` | 画像と音声の置き場 |
| `$ResonitePresentationRequirePaidAPIApproval` | `True` | 音声ブリッジの開始に有料 API 許可を求める |

## 設計上の約束

- 進行は `ScheduledTask` 1 本。tick の中では ResoniteLink の応答を**待ちません** (送りっぱなし → 次の tick で `sourceMessageId` を照合)。
  スクリーンもパネルも tick で組むので、ノートブックからでも、パネルのボタンからでも、声からでも同じ道を通ります。
- パネルのボタンは chat / tablet と同じ `Button` + `ValueField<bool>` + `ButtonToggle`。組み立ての 1.5 秒後に `getSlot` でメンバ ID を拾って結線します
  (組み立ての応答 100 件余りが流れ切るのを待つ。受信の控えは 100 件なので、重ねると応答を取りこぼす)。
- 控えの画像・音声は「今の枚が表に出てから」次の枚を読み込みます。今の枚がまだ控えにいる間に次の枚を読み込むと、
  同じ控えを奪い合って永久に始まりません (2026-11-23 実機: 音声が取ってあるときだけ起きた)。
- 控えに読み込ませてから表に出すまで 0.35 秒置きます (同じ tick で切り替えると、読み込みの間だけ空になる)。
- 常駐 Dynamic でポーリングしません。ノートブックのパネルは、状態行の文字列と声の一覧の変数を `TrackedSymbols` で追うだけです。
- tick の中では AivisSpeech にも同期で問い合わせません。止まっているエンジンへの問い合わせは、断られるまで 2.2 秒かかります (実測)。
  以前は tick の中から 30 秒ごとに声の一覧を聞き直していたので、エンジンが止まっているとそのたびに進行が止まる作りでした。
  声の一覧は覚えておき、エンジンが動いているかは `URLSubmit` で 15 秒ごとに確かめ、動き出したときだけ一覧を聞き直します。
  合成が繋がらなかったときも、同期の `SourceVaultVoiceSpeak` (エンジンの起動を待ってカーネルを 1〜2 分塞ぐ) には回しません。
- スライドの枚数は mp4 のフレーム数から決めます (先頭 29 + 1 枚 30 + 末尾 30 または 8。VRCRealtime と同じ規則)。
- 成否は**返ってきた結果の形**で決めます (メッセージが出たかどうかでは決めない)。`Quiet @ Check[expr, $Failed]` は、
  正しい結果が返っていてもメッセージが 1 つ出ただけで `$Failed` にします。カーネルを起動して最初の `Video[…]` は、
  内部で `LibraryFunction::libload` と `Set::shape` を出します (ふつうはシステムが内側で静かにしている)。
  mp4 は開けなければ 0.7 秒置いて 3 回まで試し、出たメッセージの名前を記録 (`VideoOpen` / `VideoFrames`) と Failure に残します。

## 確かめ方

```
wolframscript -file "test codes/ResoniteRealtime_present_test.wls"          (Resonite 無し。音は出ない)
wolframscript -file "test codes/ResoniteRealtime_present_test.wls" live     (実機。ワールドで 1 分ほど音が鳴り、最後に片付ける)
```

`live` はクラウドの声の経路を**偽の音声ブリッジ**で確かめます (本物の `SourceVaultRealtime*` の定義を消してから置くので OpenAI は呼ばれません)。

本物の GPT-Live では 2026-11-23 に 1 度だけ通しました (利用者の承認のもと、gpt-live-1.1 / harema、「計算と自然 31」の 2 枚):
169 字を 29.7 秒、317 字を 56.2 秒で読み、どちらも録音が残り、2 回目はブリッジを起こさずスクリーンのスピーカーから鳴りました。
音声応答 (マイクを開けての質問・声での操作) は本物の GPT-Live ではまだ確かめていません。

- 読み上げだけのとき (音声応答 off)、ブリッジはマイクを閉じたまま起こします (`"StartMuted" -> True`)。
- 読み上げのためだけに起こしたブリッジは、発表が終わると `EndTalk` を挟まずに止めます
  (挟むと、文脈を閉じる指示が届き切る前にセッションが終わり、ワーカーが `context_injection_incomplete` のエラーを残す)。

止まっている AivisSpeech の声は、2026-11-23 に本物のエンジンで確かめました (Resonite には触れずに): ノートブックからの名指しは 14 秒で選べ、
SourceVault が起動を断る場合 (同じカーネルで一度起こしたエンジンが落ちている) は自前で起こして 30 秒、
待たずに起こす経路は 0.02 秒で戻って 30 秒後に一覧へ並び、そのまま 1 文を合成できました
(30 秒かかるのは、直前に一覧を聞いていて SourceVault が「声なし」を 30 秒覚えていた場合。そうでなければエンジンが応答し次第)。
そのあと `live` も流して 88 件通っています (止まっているエンジンを起こすところから。ローカルの声の音声は前の回のものが
置き場に残っていたので、この回はワールドの中での合成は通っていません)。

「スライドの mp4 を開けませんでした」(2026-11-23、「VRとメタバース発表会」) は**再現できていません**。利用者のノートブックのカーネルで、
取ってきた直後の正しい mp4 (97 フレーム = 3 枚) がそうなりました。同じファイルは別のカーネルでは、フロントエンド付きでも、日本語設定でも、
裏でメッセージを出すタスクを回していても開けます。置き場の記録では、失敗は 2 回ともカーネルを起動して最初に mp4 を開いたときで、
その次の発表は開けています。上の「結果の形で決める」に直してあるので、同じことが起きても進むはずですが、利用者のカーネルでは未確認です。
まだ失敗するなら、Failure の `"Messages"` と `ResonitePresentationLog[]` の `VideoOpen` に理由が残ります。
この直しのあと、単体 66 件と `live` (合わせて 98 件) は通っています。その後、利用者のカーネルでも発表が始まりました。

「前へ」「次へ」の扱いとスクリーンの拡大縮小 (2026-11-23) は、単体テスト 88 件で確かめてあります。
`live` でも、パネルの「次へ」「前へ」「拡大」を押して読み戻して確かめました (合わせて 130 件): 一時停止中・停止中は枚だけ送られて
スピーカーは鳴らず、「拡大」で Screen Holder の倍率が 1.5、下の辺の高さはそのまま、操作パネルは右端へ動き、`"Reset"` で元に戻ります。
slot を読み戻すときは応答の `"data"` を直接引くこと (`"children"` の下にも `position` / `scale` があり、木を探すと子の値を拾う)。

開始待ち (2026-11-23) は単体テスト 101 件と `live` (合わせて 145 件) で確かめてあります: 既定の開始では読み始めずに最初の枚が映り、
スピーカーは鳴らず、パネルの「開始」を押すと 1 枚目を読み始めます。

進行の記録は `ResonitePresentationLog[]`。「準備中」のまま進まないときは、ここに `Import` / `Imported` / `Synth` / `Halt` が並びます。
ローカルの声のエンジンを起こしたときは `AivisStart`、声が並んだときは `LocalVoicesReady` が残ります。

## まだやっていないこと

- 読みの辞書 (SlideWorkflow の「読み」) はローカルの声の合成に反映していません (登録簿の原稿をそのまま読む)。
- ポスター発表、字幕、多言語の段重ね mp4 は未対応です (スライド発表だけ)。
- Zyzyl's Presentation System など既存ガジェットへの流し込みはしていません (自前のスクリーンを作る方式)。
