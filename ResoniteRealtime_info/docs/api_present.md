## 概要
ResoniteRealtime_present は SlideWorkflow の発表 (SourceVault の発表登録簿 = SlideWorkflow パレットの「登録」) を、Resonite のワールド内でオーナーのアカウントのまま ResoniteLink (L2) だけで自動実行するパッケージだ。専用アカウントもワールド側のノード作業も不要。
ResoniteRealtime.wl が自動ロードする (同じ ResoniteRealtime` コンテキスト。chat の UIX ヘルパ icSlot / icComp / icPollReply と tablet の部品 itButton / itText / itBacking の上に載る)。UTF-8 エンコード。
GitHub: https://github.com/transreal/ResoniteRealtime_present
依存: ResoniteRealtime, ResoniteRealtime_chat, ResoniteRealtime_tablet, SourceVault (SourceVault_slidedeck / SourceVault_voice / SourceVault_realtime / SourceVault_talkqa), SlideWorkflow

## 動作の流れ
1. ResonitePresenter[] がアバター正面にスクリーン + スピーカー + 操作パネルを組む。
2. ResonitePresentationStart["題名"] が登録簿からスライド (Sliden 用 mp4) と原稿を引き、スライド画像を Resonite 資産 (local://) に取り込んでスクリーンに映す。スクリーンが無ければその場で作る。既定では最初の枚を映して開始待ち (Status "Ready") で止まる (スクリーンを良い位置へ動かす時間)。
3. 操作パネルの「開始」か ResonitePresentationControl["Start"] で原稿の読み上げと自動送りが始まる。すぐ読み始めるなら "AutoStart" -> True。
4. 声は $ResonitePresentationVoice で切替 (既定 "realtime:harema" = gpt-live-1.1 の Harema)。
 - ローカルの声 (ほのか等): 合成 wav を資産に取り込み、スクリーンのスピーカーから鳴らす (全員に聞こえる。仮想ケーブル不要、音声は機械の外へ出ない)。
 - クラウドの声 (realtime:...): SourceVault の音声ブリッジがその場で話す (既定の出力デバイス。聴衆に聞かせるには仮想ケーブルを Resonite のマイクにする)。話した音は 1 枚ずつ録って保存し、次回同じ原稿ならスクリーンから鳴らす。
5. ResonitePresentationVoiceControl[True] で音声ブリッジ (GPT-Live) を起こすと声で操作できる: 「計算と自然31の発表を始めて」「一時停止」「再開」「発表を終了」「次のスライド」「3 枚目」「声をほのかに変えて」「発表の一覧」。それ以外の質問は SourceVault (TalkQA) が答える。
6. ワールド内の操作パネルと ResonitePresentationPanel[] (ノートブック) で同じ切替ができる。

典型的な使い方:
ResonitePresentationStart["計算と自然31", "Voice" -> "ほのか"]
(スクリーン位置を調整)
ResonitePresentationControl["Start"]

## 設計上の約束
- 進行は ScheduledTask 1 本 (irpTick、0.4 秒間隔)。tick 内で ResoniteLink の応答を待たない (送りっぱなし → 次の tick で sourceMessageId を照合)。スクリーンもパネルも tick で組む。ノートブック・パネルボタン・声のどれからでも同じ道を通る。
- 発表の開始・操作は非同期だ。ResonitePresentationStart の戻り値は受付結果であり、進行は ResonitePresentationStatus[] で調べる。
- 重い仕事 (ローカル音声合成) は AivisSpeech へ URLSubmit で頼み、カーネルを塞がない。AivisSpeech 以外 (Piper 等) は同期で 1 枚ずつ。
- 常駐 Dynamic でポーリングしない。ノートブックのパネルは文字列変数と声の一覧の変数を TrackedSymbols で追うだけ。
- 表示可否は発表の PrivacyLevel と ResoniteAccessLevel[] で決める (上限以上は出さない。値が取れなければ 1.0 扱い。mp4 URL の直接指定は 0)。クラウドの声は発表登録簿の公開上限 (0.5) を通った発表だけ。
- スライドは Sliden 用 mp4 から PNG 化 (先頭 29 フレーム + 1 枚 30 フレーム + 末尾 30 または 8 フレーム。Sliden でない mp4 は登録簿の枚数、無ければ 1 秒 1 枚)。画像は表と控えの 2 枚で切替える。
- 原稿: Opening は範囲の先頭の枚、Closing は末尾の枚へつなぐ (SlidePlay と同じ)。
- 失敗は Failure を返す: NotConnected, PresentationRegistryUnavailable, PresentationNotRegistered ("Query" / "Available"), PresentationWithheld, PresentationNoSlides, PresentationDownloadFailed, PresentationVideoFailed ("File" / "Messages"), PresentationCacheFailed, WorldAccessDenied, VoiceUnavailable ("Available" / "LocalEngine"), VoiceLiveOnly, VoiceSynthesisFailed, VoiceBridgeUnavailable, VoiceBridgeStartFailed, InvalidPresentationControl, PresenterNotBuilt, InvalidPresenterSize, PresenterBuildFailed。説明文は "MessageTemplate"。
- ResoniteLink 未接続のとき、ノートブックからの ResonitePresenter / ResonitePresentationStart は ResoniteRealtimeLinkConnect[Automatic, "Quiet" -> True] を試みる (タスク内からは試みない)。
- パッケージを再ロードしても設定値 ($ResonitePresentation*) と実行状態は残る。

## スクリーン組み立て

### ResonitePresenter[opts]
ResoniteLink だけでスクリーン・スピーカー・操作パネルを組む (専用アカウント不要)。組み立ては監視タスクが進める。ノートブックからは Ready まで最大 25 秒待つ。スクリーンが既にある場合は "Rebuild" -> True でない限り他のオプションは反映されない。
→ ResonitePresenterStatus[] と同じ Association | Failure (NotConnected, PresenterBuildFailed)
Options: "Placement" -> "User" ("User" | "World"。User はアバター正面。アバターが見つからなければ "Position" に置く), "User" -> Automatic (名前の一部でアバターを選ぶ), "Distance" -> 3.0 (アバターからの距離 m), "Height" -> 0.9 (足元からスクリーン下端付近までの高さ), "Position" -> {0, 1.0, 2.5} (Placement が World のときの位置), "Parent" -> "Root" (Placement が World のときの親 slot), "Width" -> 2.4 (スクリーン幅 m。高さは 16:9), "Panel" -> True (操作パネルも作る), "Name" -> "Mathematica Presenter", "Rebuild" -> False (True で作り直し), "Wait" -> Automatic (True で Ready まで待つ。Automatic はタスク外なら待つ)
例: ResonitePresenter["Distance" -> 3.5, "Width" -> 3.0]

ワールド内の操作パネルのボタン: 発表の選択 "<" ">", 開始, 一時停止/再開, 停止, 前へ, 次へ, 声を替える, 音声応答, 縮小, 拡大。「開始」は、開始待ち・一時停止中なら映っている枚から読み、準備中なら組み上がり次第読み、停止後・終了後は選択中の発表を AutoStart で始める。

### ResonitePresenterRemove[] → Association | $Failed | None
発表を止めてスクリーン・操作パネルをワールドから消す (戻り値は slot 削除の結果。消すものが無い・未接続なら None)。音声応答が off なら監視タスクも止める。

### ResonitePresenterStatus[] → Association
未構築は <|"Phase" -> None|>。構築後のキー: Phase ("PoseRoot" | "PoseHead" | "Settle" | "Wire" | "Ready"), Root, Screen, Speaker, PanelRoot, Size ({幅, 高さ}。等倍の値), Step, Steps, Scale, Width (現在の幅 m), Buttons, Unwired (結線できていないボタン数), Task。組み立て途中は一部のキーが無い。

### ResonitePresenterResize[spec] → Association | Failure
スクリーンの大きさを段階 ($ResonitePresenterScales) で切替える。spec: "Larger" (1 段大きく) | "Smaller" (1 段小さく) | "Reset" (組み立てたときの大きさ) | 整数 n (n 段目。範囲外は端に丸める)。下の辺の高さは変えず、操作パネルは右端についていく (パネルの大きさは不変)。
戻り値: <|"Step", "Steps", "Scale", "Width"|>。スクリーン未構築は Failure["PresenterNotBuilt"]、不正な spec は Failure["InvalidPresenterSize"]。

## 発表の実行

### ResonitePresentationStart[title, opts]
登録簿の発表を Resonite ワールド内で始める。スライドを画像にしてスクリーンに映し、原稿を読み上げながら自動で送る。スクリーンが無ければ作る。既定では読み始めず開始待ち ("Ready") で止まる。title に mp4 の URL (http/https) を直接渡すと原稿なしで表示。ResonitePresentationStart[opts] は操作パネルで選んでいる発表。
→ <|"Status" -> "Starting", "Title", "Slides", "First", "Last", "Scripted", "Voice", "AutoStart"|> ("AutoStart" が False なら "Next" (次の操作の案内) も付く) | Failure
Options: "AutoStart" -> False (True で組み上がり次第読み始める), "Voice" -> Automatic ($ResonitePresentationVoice。指定すると $ResonitePresentationVoice も書き換わる), "StartSlide" -> Automatic (登録簿の startSlide、無ければ 1), "EndSlide" -> Automatic (登録簿の endSlide、無ければ最終枚), "Presenter" -> {} (ResonitePresenter のオプションのリスト。スクリーンを新規に作るときだけ有効)
AivisSpeech の声を使う場合、ノートブックからはエンジン起動を待つ (起動できなければ Failure["VoiceUnavailable"])。
例: ResonitePresentationStart["計算と自然31", "Voice" -> "ほのか", "StartSlide" -> 3, "AutoStart" -> True, "Presenter" -> {"Width" -> 3.0}]

### ResonitePresentationPrepare[title, opts]
スライド画像とローカルの声の音声を先に作る (発表途中で合成を待たない。同期実行)。title は mp4 の URL も可。クラウドの声は事前に作れない (最初の発表で録る)。
→ <|"Title", "Slides", "Scripted", "Voice", "AudioReady", "Synthesized", "Failed" (合成に失敗した枚番号), "Directory", "Note"|> | Failure
Options: "Voice" -> Automatic, "StartSlide" -> Automatic, "EndSlide" -> Automatic (発表のときと同じ範囲にする。範囲が違うと文が変わり音声も別になる)

### ResonitePresentationControl[action] → Association | Failure
実行中の発表を操作する。action: "Start" | "Resume" | "Pause" | "Toggle" | "Stop" | "Next" | "Previous" | "First" | "Last" | 整数 (スライド番号)。不正な action は Failure["InvalidPresentationControl"]。操作は tick が処理し、ノートブックからは最大 1.5 秒待って ResonitePresentationStatus[] を返す。
- "Start" と "Resume" は同じ: 開始待ち ("Ready")・一時停止中 ("Paused") の発表を映っている枚から読み始める。それ以外の状態では何もしない (停止後に最初から読むには ResonitePresentationStart を呼び直す)。
- "Toggle" は "Paused" なら再開、それ以外は一時停止 ("Ready" からの開始はできない)。
- スライド移動は First〜Last の範囲外なら無視。"Playing" 中 (または AutoStart の準備中) は移った枚を読み始め、開始待ち・一時停止中・停止後・終了後は映すだけで読まない。
- スピーカーで読んでいた枚の再開は続きから、クラウドの声と移動後の枚は頭から読む。

### ResonitePresentationStop[] → Association
発表を止める (スクリーンは残る)。ResonitePresentationControl["Stop"] と同じ。

### ResonitePresentationStatus[] → Association
キー: Status ("Idle" | "Starting" | "Ready" | "Playing" | "Paused" | "Finished"), Title, Slide, First, Last, Count, Phase (None | "WaitAssets" | "Narrating" | "Question" | "Moved"), Route (None | "Silent" | "World" | "Live"), Voice, VoiceModel, Answering, Presenter (スクリーンの Phase か None), Synthesizing (合成中の枚番号か None), Message, Line (表示用の状態行), AccessLevel, Task。

### ResonitePresentationList[] → {String...}
登録簿のうち、スライド発表ができる (Sliden 用 mp4 の URL がある) ものの題名の一覧。呼ぶたびに読み直す。

## 声

### ResonitePresentationVoices[] → {String...}
いま選べる声の一覧 (ローカルの声の名前と "realtime:<声>")。呼ぶたびにローカルの声を聞き直す。AivisSpeech の声はエンジンが動いているときだけ並ぶ (この関数はエンジンを起こさない)。

### ResonitePresentationSetVoice[name] → String | Failure
読み上げの声を選び、選んだ声の名前を返す。ローカルの声は名前の一部でよい (例 "ほのか")。クラウドの声は一覧の名前と一致する指定 (例 "harema") か "realtime:<声>"。発表中は次のスライドから効く。
一覧に無い名前なら止まっている AivisSpeech を起こして探し直す (ノートブックからは起動を待つ。20 秒〜2 分。SourceVault`$SourceVaultVoiceAivisAutoStart = False なら起こさない)。失敗は Failure["VoiceUnavailable"]、GPT-Live 専用の声を Live でないモデルで選ぶと Failure["VoiceLiveOnly"]。
エンジン関連の設定 (SourceVault` 側): $SourceVaultVoiceAivisEndpoint (無指定は "http://127.0.0.1:10101"), $SourceVaultVoiceAivisStartTimeout (無指定は 180 秒)。

### ResonitePresentationCycleVoice[] → String | Failure
声を一覧の次へ切り替える (操作パネルの「声を替える」ボタン)。AivisSpeech が止まっていれば起こす: ノートブックからは起動を待って一覧に加え、ワールドのパネルからは待たずに起こす (動き出してから押すと選べる)。

### ResonitePresentationVoiceControl[flag] → Association | Failure
音声ブリッジ (SourceVault の音声会話、既定 gpt-live-1.1) を起こし、声での操作と質問応答を始める。
ResonitePresentationVoiceControl[True] で起動、[False] で停止、引数なし [] は切替。
クラウド経路 (マイク音声と会話が OpenAI へ送られる) なので、評価したノートブックの有料 API 許可を使う ($ResonitePresentationRequirePaidAPIApproval)。
戻り値: <|"Answering" -> True, "Bridge" -> ...|> (True。起動済みのブリッジなら "Bridge" は <|"Status" -> "AlreadyRunning"|>) | <|"Answering" -> False|> (False) | Failure
False のとき、クラウドの声で読み上げ中ならブリッジは止めずマイクだけ閉じる。
声からのスライド移動は show_slide ハンドラ、発表操作・質問は ask ハンドラ (SourceVault`$SourceVaultRealtimeSlideHandler / $SourceVaultRealtimeAskHandler を一時的に差し替え、停止時に戻す)。発表停止後もスクリーンがあれば声でスライドを送れる。声の「始めて」は開始待ち・一時停止中の発表なら再開し、新規開始はスクリーンが既にあればすぐ読み、無ければ開始待ちで止まる。

## ノートブック UI・記録

### ResonitePresentationPanel[] → Panel
ノートブックに置く操作パネルを返す: 発表を選ぶ (開始待ちで準備), 開始, 一時停止/再開, 停止, 前へ, 次へ, 声を選ぶ (AivisSpeech の起動項目を含む), 音声応答 on/off, スクリーンを置く, 縮小, 拡大, 片付ける。

### ResonitePresentationLog[n] → {<|"Time", "Tag", "Data"|>...}
直近 n 件 (省略時 30、保持は最大 200 件) の進行記録を返す。

## 変数

### $ResonitePresentationVoice
型: String, 初期値: "realtime:harema"
読み上げの声。ローカルの声の名前 (SourceVaultVoices[]) か "realtime:<声>"。

### $ResonitePresentationVoiceModel
型: String, 初期値: "gpt-live-1.1"
クラウドの声と音声応答に使うモデル。

### $ResonitePresentationCloudVoices
型: {String...}, 初期値: {"harema", "shida", "marin", "cedar"}
声の一覧に並べるクラウドの声。モデルが GPT-Live でなければ Live 専用の声 (harema, shida 等) は除かれる。

### $ResonitePresentationAudioRoute
型: Automatic | "World" | "Live", 初期値: Automatic
音の出し方。Automatic = 音声ファイルがあればスクリーンのスピーカー、無いクラウドの声は音声ブリッジ。"World" = スクリーンのスピーカーだけ (録音の無いクラウドの声は読まない)。"Live" = クラウドの声はいつも音声ブリッジ。ローカルの声は常にスクリーンのスピーカー。

### $ResonitePresentationOutputDevice
型: Automatic | String, 初期値: Automatic
音声ブリッジの出力デバイス (名前の一部)。Automatic = Windows の既定。聴衆に聞かせるには仮想ケーブル (例 "CABLE Input") にし、Resonite のマイクを反対側 (CABLE Output) にする。

### $ResonitePresentationInputDevice
型: Automatic | String, 初期値: Automatic
音声ブリッジの入力デバイス。Automatic = Windows の既定のマイク。

### $ResonitePresentationQuestionSeconds
型: Number, 初期値: 3.
音声応答が on のとき、1 枚読み終えてから次へ送るまで質問を待つ秒数 (最小 0.8 秒)。

### $ResonitePresentationListenWhileNarrating
型: True | False, 初期値: True
音声応答が on のとき、スクリーンのスピーカーで読み上げ中もマイクを聞くか。True なら読み上げ途中でも声で操作・質問できる (応じている間は読み上げを止めて待つ)。ヘッドセットを使わずスピーカーの音をマイクが拾う環境では False にする (読み上げ中はマイクを閉じ、1 枚読み終えるごとの質問時間だけ開く)。クラウドの声が読んでいる間は、どちらでもマイクを閉じる。

### $ResonitePresentationVolume
型: Number, 初期値: 1.
スクリーンのスピーカーの音量。スクリーンを組み立てるときに適用される。

### $ResonitePresenterScales
型: {Number...}, 初期値: {0.5, 0.75, 1, 1.5, 2, 3}
スクリーンの大きさの段階 (組み立てたときの大きさに対する倍率)。「拡大」「縮小」と ResonitePresenterResize がこの段を上下する。1 は無くても補われる。各値は 0.05〜20 (不正なら既定の段を使う)。

### $ResonitePresentationCacheDirectory
型: Automatic | String, 初期値: Automatic
スライド画像と音声の置き場。Automatic = $UserBaseDirectory/ApplicationData/ResoniteRealtime/present。発表ごとに id・url・更新日時のハッシュのサブフォルダを作り、deck.mp4 / deck.json / slides/s001.png ... / audio/<声ごと>/*.wav を置く。2 回目以降は画像を再利用する。

### $ResonitePresentationRequirePaidAPIApproval
型: True | False, 初期値: True
音声ブリッジの開始にノートブックの有料 API 許可を求めるか。

## 内部の注意
- 資産取り込みは importTexture2DFile / importAudioClipFile を待たずに送り、tick が応答を照合する (最大同時 6 件、40 秒でタイムアウト、失敗は 15 秒再試行を控える)。
- アバター位置は Root の getSlot 応答から "User <名前> (ID...)" の slot を候補にし、子に "Head" があるものを採る ("User In VR Flux" 等の誤検出を避ける)。
- 次の枚の音声の取り込みはいつでもよいが、控えのクリップへの読み込みは今の枚が鳴り始めてから (控えの奪い合いで永久に始まらなくなるのを避ける)。
- 音声ブリッジはマイクを閉じたまま ("StartMuted" -> True) 起動し、音声応答を on にする側が起動後に開ける。
- 監視タスク内では AivisSpeech の起動を待たない (待たずに起こし、動き出してから合成を頼み直す)。
- タイムアウト: スクリーン準備 40 秒、スライド画像 45 秒、音声取り込み 60 秒、音声ブリッジ接続 40 秒 (超えると発表を中止)。音声合成待ちは 240 秒で黙って次へ。原稿の無い枚は 3 秒表示。