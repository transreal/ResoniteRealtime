# ResoniteRealtime_present API リファレンス

## 概要
ResoniteRealtime_present は SlideWorkflow の発表 (SourceVault の発表登録簿 = SlideWorkflow パレットの「登録」) を、Resonite のワールド内でオーナーのアカウントのまま ResoniteLink (L2) だけで自動実行するパッケージだ。専用アカウントもワールド側のノード作業も不要。
ResoniteRealtime.wl が自動ロードする (同じ ResoniteRealtime` コンテキスト。chat の UIX ヘルパ icSlot / icComp / icPollReply と tablet の部品 itButton / itText / itBacking の上に載る)。UTF-8 エンコード。
GitHub: https://github.com/transreal/ResoniteRealtime_present
依存: ResoniteRealtime, ResoniteRealtime_chat, ResoniteRealtime_tablet, SourceVault (SourceVault_slidedeck / SourceVault_voice / SourceVault_realtime / SourceVault_talkqa), SlideWorkflow

## 動作の流れ
1. ResonitePresenter[] がアバター正面にスクリーン + スピーカー + 操作パネルを組む。
2. ResonitePresentationStart["題名"] が登録簿からスライド (Sliden 用 mp4) と原稿を引き、スライド画像を Resonite 資産 (local://) に取り込んでスクリーンに映し、原稿を読み上げて自動で送る。スクリーンが無ければその場で作る。
3. 声は $ResonitePresentationVoice で切替 (既定 "realtime:harema" = gpt-live-1.1 の Harema)。
 - ローカルの声 (ほのか等): 合成 wav を資産に取り込み、スクリーンのスピーカーから鳴らす (全員に聞こえる。仮想ケーブル不要、音声は機械の外へ出ない)。
 - クラウドの声 (realtime:...): SourceVault の音声ブリッジがその場で話す (既定の出力デバイス。聴衆に聞かせるには仮想ケーブルを Resonite のマイクにする)。話した音は 1 枚ずつ録って保存し、次回同じ原稿ならスクリーンから鳴らす。
4. ResonitePresentationVoiceControl[True] で音声ブリッジ (GPT-Live) を起こすと声で操作できる: 「計算と自然31の発表を始めて」「一時停止」「再開」「発表を終了」「次のスライド」「3 枚目」「声をほのかに変えて」「発表の一覧」。それ以外の質問は SourceVault (TalkQA) が答える。
5. ワールド内の操作パネルと ResonitePresentationPanel[] (ノートブック) で同じ切替ができる。

## 設計上の約束
- 進行は ScheduledTask 1 本 (irpTick)。tick 内で ResoniteLink の応答を待たない (送りっぱなし → 次の tick で sourceMessageId を照合)。スクリーンもパネルも tick で組む。ノートブック・パネルボタン・声のどれからでも同じ道を通る。
- 重い仕事 (ローカル音声合成) は AivisSpeech へ URLSubmit で頼み、カーネルを塞がない。AivisSpeech 以外 (Piper 等) は同期で 1 枚ずつ。
- 常駐 Dynamic でポーリングしない。ノートブックのパネルは文字列変数 1 つを TrackedSymbols で追うだけ。
- 表示可否は発表の PrivacyLevel と ResoniteAccessLevel[] で決める (上限以上は出さない)。クラウドの声は発表登録簿の公開上限 (0.5) を通った発表だけ。
- スライドは Sliden 用 mp4 から PNG 化 (先頭 29 フレーム + 1 枚 30 フレーム + 末尾 30 または 8 フレーム。Sliden でない mp4 は 1 秒 1 枚)。画像は表と控えの 2 枚で切替える。
- 原稿: Opening は先頭の枚、Closing は末尾の枚へつなぐ (SlidePlay と同じ)。
- 失敗は Failure を返す (例: NotConnected, PresentationNotRegistered, PresentationWithheld, PresentationNoSlides, PresentationDownloadFailed, PresentationVideoFailed, PresentationCacheFailed, WorldAccessDenied, VoiceBridgeUnavailable, VoiceBridgeStartFailed, InvalidPresentationControl, PresenterBuildFailed, PresentationRegistryUnavailable)。
- ResoniteLink 未接続のとき、ノートブックからの呼び出しは ResoniteRealtimeLinkConnect[Automatic, "Quiet" -> True] を試みる。

## スクリーン組み立て

### ResonitePresenter[opts]
ResoniteLink だけでスクリーン・スピーカー・操作パネルを組む (専用アカウント不要)。組み立ては監視タスクが進める。ノートブックからは Ready まで最大 25 秒待つ。
→ ResonitePresenterStatus[] と同じ Association、または Failure
Options: "Placement" -> "User" ("User" | "World"。User はアバター正面), "Distance" -> 3.0 (m), "Height" -> 0.9 (足元からスクリーン下端付近までの高さ), "User" -> Automatic (名前の一部でアバターを選ぶ), "Position" -> {0, 1.0, 2.5} (Placement が World のときの位置), "Parent" -> "Root" (Placement が World のときの親 slot), "Width" -> 2.4 (スクリーン幅 m。高さは 16:9), "Panel" -> True (操作パネルも作る), "Name" -> "Mathematica Presenter", "Rebuild" -> False (True で作り直し), "Wait" -> Automatic (True で Ready まで待つ。Automatic はタスク外なら待つ)
例: ResonitePresenter["Distance" -> 3.5, "Width" -> 3.0]

### ResonitePresenterRemove[] → Association | None
発表を止めてスクリーン・操作パネルをワールドから消す。

### ResonitePresenterStatus[] → Association
スクリーン・操作パネルの状態 (Phase / Root / Screen / Speaker / PanelRoot / Size / Buttons / Unwired / Task) を返す。未構築は <|"Phase" -> None|>。

## 発表の実行

### ResonitePresentationStart[title, opts]
登録簿の発表を Resonite ワールド内で始める。スライドを画像にしてスクリーンに映し、原稿を読み上げながら自動で送る。スクリーンが無ければ作る。title に mp4 の URL (http/https) を直接渡すと原稿なしで再生。ResonitePresentationStart[opts] は操作パネルで選んだ発表。
→ <|"Status" -> "Starting", "Title", "Slides", "First", "Last", "Scripted", "Voice"|> | Failure
Options: "Voice" -> Automatic ($ResonitePresentationVoice), "StartSlide" -> Automatic (登録簿の startSlide、無ければ 1), "EndSlide" -> Automatic (登録簿の endSlide、無ければ最終枚), "Presenter" -> {} (ResonitePresenter のオプションのリスト)
例: ResonitePresentationStart["計算と自然31", "Voice" -> "ほのか", "StartSlide" -> 3]

### ResonitePresentationPrepare[title, opts]
スライド画像とローカルの声の音声を先に作る (発表途中で合成を待たない)。クラウドの声は事前に作れない (最初の発表で録る)。
→ <|"Title", "Slides", "Scripted", "Voice", "AudioReady", "Synthesized", "Failed", "Directory", "Note"|> | Failure
Options: "Voice" -> Automatic, "StartSlide" -> Automatic, "EndSlide" -> Automatic (発表のときと同じ範囲にする。範囲が違うと文が変わり音声も別になる)

### ResonitePresentationControl[action] → Association
実行中の発表を操作する。action: "Pause" | "Resume" | "Toggle" | "Stop" | "Next" | "Previous" | "First" | "Last" | 整数 (スライド番号)。不正な action は Failure["InvalidPresentationControl"]。操作は tick が処理し、ノートブックからは最大 1.5 秒待って ResonitePresentationStatus[] を返す。

### ResonitePresentationStop[] → Association
発表を止める (スクリーンは残る)。ResonitePresentationControl["Stop"] と同じ。

### ResonitePresentationStatus[] → Association
発表の状態を返す。キー: Status ("Starting" | "Playing" | "Paused" | "Finished" ほか), Title, Slide, First, Last, Count, Phase ("WaitAssets" | "Narrating" | "Question" ほか), Route ("Silent" | "World" | "Live" ほか), Voice, VoiceModel, Answering, Presenter, Synthesizing, Message ほか。

### ResonitePresentationList[] → {String...}
登録簿のうち、スライド発表ができる (Sliden 用 mp4 の URL がある) ものの題名の一覧。60 秒キャッシュ。

## 声

### ResonitePresentationVoices[] → {String...}
選べる声の一覧 (ローカルの声の名前と "realtime:<声>")。

### ResonitePresentationSetVoice[name]
読み上げの声を選ぶ (名前の一部でよい。例 "ほのか", "harema")。発表中は次のスライドから効く。

### ResonitePresentationCycleVoice[]
声を一覧の次へ切り替える (操作パネルの「声」ボタン)。

### ResonitePresentationVoiceControl[flag]
音声ブリッジ (SourceVault の音声会話、既定 gpt-live-1.1) を起こし、声での操作と質問応答を始める。
ResonitePresentationVoiceControl[True] で起動、[False] で停止、引数なし [] は切替。
クラウド経路 (マイク音声と会話が OpenAI へ送られる) なので、評価したノートブックの有料 API 許可を使う ($ResonitePresentationRequirePaidAPIApproval)。
→ <|"Answering" -> True, "Bridge" -> ...|> (True) | <|"Answering" -> False|> (False) | Failure
False のとき、クラウドの声で読み上げ中ならブリッジは止めずマイクだけ閉じる。
声からのスライド移動は show_slide ハンドラ、発表操作・質問は ask ハンドラ (SourceVault`$SourceVaultRealtimeSlideHandler / AskHandler を一時的に差し替える)。

## ノートブック UI・記録

### ResonitePresentationPanel[] → Panel
ノートブックに置く操作パネルを返す (発表の選択・開始・一時停止・声の切替・音声応答)。

### ResonitePresentationLog[n] → {...}
直近 n 件の進行記録を返す。

## 変数

### $ResonitePresentationVoice
型: String, 初期値: "realtime:harema"
読み上げの声。ローカルの声の名前 (SourceVaultVoices[]) か "realtime:<声>"。

### $ResonitePresentationVoiceModel
型: String, 初期値: "gpt-live-1.1"
クラウドの声と音声応答に使うモデル。

### $ResonitePresentationCloudVoices
型: {String...}, 初期値: {"harema", "shida", "marin", "cedar"}
声の一覧に並べるクラウドの声。

### $ResonitePresentationAudioRoute
型: Automatic | "World" | "Live", 初期値: Automatic
音の出し方。Automatic = 音声ファイルがあればスクリーンのスピーカー、無いクラウドの声は音声ブリッジ。"World" = スクリーンのスピーカーだけ (録音の無いクラウドの声は読まない)。"Live" = クラウドの声はいつも音声ブリッジ。

### $ResonitePresentationOutputDevice
型: Automatic | String, 初期値: Automatic
音声ブリッジの出力デバイス (名前の一部)。Automatic = Windows の既定。聴衆に聞かせるには仮想ケーブル (例 "CABLE Input") にし、Resonite のマイクを反対側 (CABLE Output) にする。

### $ResonitePresentationInputDevice
型: Automatic | String, 初期値: Automatic
音声ブリッジの入力デバイス。Automatic = Windows の既定のマイク。

### $ResonitePresentationQuestionSeconds
型: Number, 初期値: 3
音声応答が on のとき、1 枚読み終えてから次へ送るまで質問を待つ秒数。

### $ResonitePresentationListenWhileNarrating
型: True | False, 初期値: True
音声応答が on のとき、スクリーンのスピーカーで読み上げ中もマイクを聞くか。True なら読み上げ途中でも声で操作・質問できる (応じている間は読み上げを止めて待つ)。ヘッドセットを使わずスピーカーの音をマイクが拾う環境では False にする (読み上げ中はマイクを閉じ、1 枚読み終えるごとの質問時間だけ開く)。クラウドの声が読んでいる間は、どちらでもマイクを閉じる。

### $ResonitePresentationVolume
型: Number, 初期値: 1.0
スクリーンのスピーカーの音量。

### $ResonitePresentationCacheDirectory
型: Automatic | String, 初期値: Automatic
スライド画像 (slides/s001.png ...) と音声の置き場。Automatic = $UserBaseDirectory/ApplicationData/ResoniteRealtime/present。発表ごとに id・url・更新日時のハッシュのサブフォルダを作り、deck.mp4 / deck.json を置く。

### $ResonitePresentationRequirePaidAPIApproval
型: True | False, 初期値: True
音声ブリッジの開始にノートブックの有料 API 許可を求めるか。

## 内部の注意
- 資産取り込みは importTexture2DFile / importAudioClipFile を待たずに送り、tick が応答を照合する (最大同時 6 件、40 秒でタイムアウト、失敗は 15 秒再試行を控える)。
- アバター位置は Root の getSlot 応答から "User <名前> (ID...)" の slot を候補にし、子に "Head" があるものを採る ("User In VR Flux" 等の誤検出を避ける)。
- 次の枚の音声の取り込みはいつでもよいが、控えテクスチャへの読み込みは今の枚が鳴り始めてから (控えの奪い合いで永久に始まらなくなるのを避ける)。
- 音声ブリッジはマイクを閉じたまま ("StartMuted" -> True) 起動し、音声応答を on にする側が起動後に開ける。