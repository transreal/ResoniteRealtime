(* ::Package:: *)

(* ResoniteRealtime_present.wl -- SlideWorkflow の発表を Resonite のワールド内で自動実行する

   This file is encoded in UTF-8.
   ResoniteRealtime.wl が自動でロードする (同じ ResoniteRealtime` コンテキスト。
   chat の UIX ヘルパ (icSlot / icComp / icPollReply ...) と tablet の部品 (itButton / itText / itBacking) の上に載る)。

   ---- 何をするか ----

   VRChat では VRCRealtime が別アカウントのアバターで Sliden を操作して発表するが、Resonite では
   **オーナーのアカウントのまま、ResoniteLink (L2) だけで** 同じ発表 (SourceVault の発表登録簿 =
   SlideWorkflow パレットの「登録」) を実行する。専用アカウントも世界側のノード作業も要らない。

   1. ResonitePresenter[] がアバターの正面にスクリーン + スピーカー + 操作パネルを組み立てる。
   2. ResonitePresentationStart["計算と自然31"] が登録簿からスライド (Sliden 用 mp4) と原稿を引き、
      スライド画像を Resonite の資産 (local://) に取り込んでスクリーンに映し、原稿を読み上げて自動で送る。
      スクリーンが無ければその場で作る。
   3. 読み上げの声は切り替えられる ($ResonitePresentationVoice、既定 "realtime:harema" = gpt-live-1.1 の Harema)。
        ローカルの声 (ほのか など)  : 合成した wav を Resonite の資産に取り込み、**スクリーンのスピーカーから鳴らす**
                                      (ワールドの全員に聞こえる。仮想ケーブル不要、音声は機械の外へ出ない)。
        クラウドの声 (realtime:...) : SourceVault の音声ブリッジがその場で話す (既定の出力デバイス。
                                      聴衆に聞かせるには仮想ケーブルを Resonite のマイクにする)。話した音は
                                      1 枚ずつ録って取っておき、次に同じ原稿を読むときはスクリーンから鳴らす。
   4. ResonitePresentationVoiceControl[True] で音声ブリッジ (GPT-Live) を起こすと、声で操作できる:
        「計算と自然31の発表を始めて」「一時停止」「再開」「発表を終了」「次のスライド」「3 枚目」
        「声をほのかに変えて」「発表の一覧」、それ以外の質問は SourceVault (TalkQA) で答える。
   5. 操作パネル (ワールド内) と ResonitePresentationPanel[] (ノートブック) で同じ切り替えができる。

   ---- 設計上の約束 (chat / tablet と同じ) ----

   - 進行は ScheduledTask 1 本 (irpTick)。tick の中では ResoniteLink の応答を待たない
     (送りっぱなし → 次の tick で sourceMessageId を照合)。スクリーンもパネルも tick で組むので、
     ノートブックからでも、パネルのボタンからでも、声からでも同じ道を通る。
   - 重い仕事 (ローカル音声の合成) は AivisSpeech へ URLSubmit で頼み、カーネルを塞がない。
   - 常駐 Dynamic でポーリングしない。ノートブックのパネルは文字列変数 1 つを TrackedSymbols で追うだけ。
   - 表示してよいかは発表の PrivacyLevel と ResoniteAccessLevel[] で決める (上限以上は出さない)。
     クラウドの声は発表登録簿の公開上限 (0.5) を通った発表だけ。
*)

BeginPackage["ResoniteRealtime`"];

ResoniteRealtime`ResonitePresenter::usage =
  "ResonitePresenter[] は ResoniteLink だけでワールド内に発表用のスクリーン・スピーカー・操作パネルを組み立てる (専用アカウント不要)。\n" <>
  "既定ではアバターの正面に置く。オプション: \"Placement\" -> \"User\" | \"World\", \"Distance\" -> 3.0 (m), \"Height\" -> 0.9 (足元からスクリーン下端付近までの高さ),\n" <>
  "  \"User\" -> Automatic (名前の一部で選ぶ), \"Position\" -> {0, 1.0, 2.5}, \"Parent\" -> \"Root\" (Placement が World のとき),\n" <>
  "  \"Width\" -> 2.4 (スクリーンの幅 m)、\"Panel\" -> True (操作パネルも作る)、\"Name\"、\"Rebuild\" -> False、\"Wait\" -> Automatic。\n" <>
  "組み立ては監視タスクが進める。戻り値は ResonitePresenterStatus[] と同じ。";
ResoniteRealtime`ResonitePresenterRemove::usage =
  "ResonitePresenterRemove[] は発表を止めてスクリーン・操作パネルをワールドから消す。";
ResoniteRealtime`ResonitePresenterStatus::usage =
  "ResonitePresenterStatus[] はスクリーン・操作パネルの状態 (Phase / Root / Screen / Panel / Scale / Width ...) を返す。";
ResoniteRealtime`ResonitePresenterResize::usage =
  "ResonitePresenterResize[\"Larger\"] / ResonitePresenterResize[\"Smaller\"] はスクリーンを 1 段大きく / 小さくする (操作パネルの「拡大」「縮小」と同じ)。\n" <>
  "ResonitePresenterResize[n] は n 段目にする。ResonitePresenterResize[\"Reset\"] は組み立てたときの大きさに戻す。段階は $ResonitePresenterScales。\n" <>
  "スクリーンの下の辺の高さは変わらず、操作パネルは右端についていく。<|\"Step\", \"Steps\", \"Scale\", \"Width\"|> を返す。";
ResoniteRealtime`ResonitePresentationStart::usage =
  "ResonitePresentationStart[title] は SourceVault の発表登録簿 (SlideWorkflow の「登録」) の発表を Resonite のワールド内で始める。\n" <>
  "スライド (Sliden 用 mp4) を画像にしてスクリーンに映し、原稿を読み上げながら自動で送る。スクリーンが無ければその場で作る。\n" <>
  "ResonitePresentationStart[url] は mp4 の URL を直接指定する (原稿は付かない)。ResonitePresentationStart[] は操作パネルで選んだ発表。\n" <>
  "既定では読み始めない: スクリーンを置いて最初の枚を映し、開始待ちで止まる (スクリーンを良い位置へ動かす時間)。\n" <>
  "操作パネルの「開始」か ResonitePresentationControl[\"Start\"] で読み始める。すぐ読み始めるなら \"AutoStart\" -> True。\n" <>
  "オプション: \"AutoStart\" -> False、\"Voice\" -> Automatic ($ResonitePresentationVoice)、\"StartSlide\"、\"EndSlide\"、\"Presenter\" -> {} (ResonitePresenter のオプション)。\n" <>
  "声は ResonitePresentationVoices[] のどれか。ローカルの声はスクリーンのスピーカーから、クラウドの声 (realtime:...) は音声ブリッジから出る。";
ResoniteRealtime`ResonitePresentationPrepare::usage =
  "ResonitePresentationPrepare[title] は発表のスライド画像とローカルの声の音声を先に作っておく (発表の途中で合成を待たない)。\n" <>
  "オプション: \"Voice\" -> Automatic、\"StartSlide\" / \"EndSlide\" (発表のときと同じ範囲にする)。クラウドの声は事前に作れない (最初の発表のときに録る)。";
ResoniteRealtime`ResonitePresentationControl::usage =
  "ResonitePresentationControl[action] は発表を操作する。action: \"Start\" | \"Pause\" | \"Resume\" | \"Toggle\" | \"Stop\" | \"Next\" | \"Previous\" | \"First\" | \"Last\" | 番号。\n" <>
  "\"Start\" (\"Resume\" も同じ) は、開始待ち・一時停止中の発表を、映っている枚から読み始める。";
ResoniteRealtime`ResonitePresentationStop::usage =
  "ResonitePresentationStop[] は発表を止める (スクリーンは残る)。";
ResoniteRealtime`ResonitePresentationStatus::usage =
  "ResonitePresentationStatus[] は発表の状態 (Status / Title / Slide / Count / Phase / Voice / Route / Message ...) を返す。";
ResoniteRealtime`ResonitePresentationList::usage =
  "ResonitePresentationList[] は登録簿のうちスライド発表ができるものの題名の一覧を返す。";
ResoniteRealtime`ResonitePresentationVoices::usage =
  "ResonitePresentationVoices[] は、いま選べる声の一覧を返す (ローカルの声の名前と \"realtime:<声>\")。\n" <>
  "AivisSpeech の声 (ほのか など) は、AivisSpeech Engine が動いているときだけ並ぶ。止まっているエンジンは、\n" <>
  "ResonitePresentationSetVoice[name] で声を名指ししたときに自動で起こす。";
ResoniteRealtime`ResonitePresentationSetVoice::usage =
  "ResonitePresentationSetVoice[name] は読み上げの声を選ぶ (名前の一部でよい。例 \"ほのか\"、\"harema\")。発表中は次のスライドから効く。\n" <>
  "名指しの声が一覧に無いときは、止まっているローカルの声のエンジン (AivisSpeech) を起こして探し直す (起動に 20 秒〜2 分かかる。\n" <>
  "SourceVault`$SourceVaultVoiceAivisAutoStart = False なら起こさない)。";
ResoniteRealtime`ResonitePresentationCycleVoice::usage =
  "ResonitePresentationCycleVoice[] は読み上げの声を一覧の次の声へ切り替える (操作パネルの「声」ボタン)。\n" <>
  "ローカルの声のエンジン (AivisSpeech) が止まっていれば起こす: ノートブックからは起動を待って一覧に加え、ワールドのパネルからは待たずに起こす (動き出してから押すと選べる)。";
ResoniteRealtime`ResonitePresentationVoiceControl::usage =
  "ResonitePresentationVoiceControl[True] は音声ブリッジ (SourceVault の音声会話、既定 gpt-live-1.1) を起こし、声での操作と質問への応答を始める。\n" <>
  "ResonitePresentationVoiceControl[False] で止める。ResonitePresentationVoiceControl[] は切り替え。\n" <>
  "クラウド経路 (マイクの音声と会話が OpenAI へ送られる) なので、評価したノートブックの有料 API 許可を使う。";
ResoniteRealtime`ResonitePresentationPanel::usage =
  "ResonitePresentationPanel[] はノートブックに置く操作パネル (発表の選択・開始・一時停止・声の切り替え・音声応答) を返す。";
ResoniteRealtime`ResonitePresentationLog::usage =
  "ResonitePresentationLog[n] は直近 n 件の進行記録を返す。";

ResoniteRealtime`$ResonitePresentationVoice::usage =
  "$ResonitePresentationVoice は読み上げの声 (既定 \"realtime:harema\")。ローカルの声の名前 (SourceVaultVoices[]) か \"realtime:<声>\"。";
ResoniteRealtime`$ResonitePresentationVoiceModel::usage =
  "$ResonitePresentationVoiceModel はクラウドの声と音声応答に使うモデル (既定 \"gpt-live-1.1\")。";
ResoniteRealtime`$ResonitePresentationCloudVoices::usage =
  "$ResonitePresentationCloudVoices は声の一覧に並べるクラウドの声 (既定 {\"harema\", \"shida\", \"marin\", \"cedar\"})。";
ResoniteRealtime`$ResonitePresentationAudioRoute::usage =
  "$ResonitePresentationAudioRoute は音の出し方。Automatic (既定) = 音声ファイルがあればスクリーンのスピーカー、無いクラウドの声は音声ブリッジ。\n" <>
  "\"World\" = スクリーンのスピーカーだけ (録音の無いクラウドの声は読まない)、\"Live\" = クラウドの声はいつも音声ブリッジ。";
ResoniteRealtime`$ResonitePresentationOutputDevice::usage =
  "$ResonitePresentationOutputDevice は音声ブリッジの出力デバイス (名前の一部。既定 Automatic = Windows の既定)。\n" <>
  "聴衆に聞かせるには仮想ケーブル (例 \"CABLE Input\") にして、Resonite のマイクをその反対側 (CABLE Output) にする。";
ResoniteRealtime`$ResonitePresentationInputDevice::usage =
  "$ResonitePresentationInputDevice は音声ブリッジの入力デバイス (既定 Automatic = Windows の既定のマイク)。";
ResoniteRealtime`$ResonitePresentationQuestionSeconds::usage =
  "$ResonitePresentationQuestionSeconds は音声応答が on のとき、1 枚読み終えてから次へ送るまで質問を待つ秒数 (既定 3)。";
ResoniteRealtime`$ResonitePresentationListenWhileNarrating::usage =
  "$ResonitePresentationListenWhileNarrating (既定 True) は、音声応答が on のとき、スクリーンのスピーカーで読み上げている間もマイクを聞くか。\n" <>
  "True なら読み上げの途中でも声で操作・質問できる (応じている間は読み上げを止めて待つ)。ヘッドセットを使わず、スピーカーの音をマイクが拾う環境では False にする\n" <>
  "(読み上げ中はマイクを閉じ、1 枚読み終えるごとの質問の時間だけ開く)。クラウドの声が読んでいる間は、どちらでもマイクを閉じる。";
ResoniteRealtime`$ResonitePresentationVolume::usage =
  "$ResonitePresentationVolume はスクリーンのスピーカーの音量 (既定 1.0)。";
ResoniteRealtime`$ResonitePresenterScales::usage =
  "$ResonitePresenterScales はスクリーンの大きさの段階 (組み立てたときの大きさに対する倍率。既定 {0.5, 0.75, 1, 1.5, 2, 3})。\n" <>
  "「拡大」「縮小」のボタンと ResonitePresenterResize がこの段を上下する。等倍 (1) は無くても補われる。";
ResoniteRealtime`$ResonitePresentationCacheDirectory::usage =
  "$ResonitePresentationCacheDirectory はスライド画像と音声の置き場 (既定 Automatic = $UserBaseDirectory/ApplicationData/ResoniteRealtime/present)。";
ResoniteRealtime`$ResonitePresentationRequirePaidAPIApproval::usage =
  "$ResonitePresentationRequirePaidAPIApproval (既定 True) は音声ブリッジの開始にノートブックの有料 API 許可を求めるか。";

Begin["`Private`"];

(* 再ロード: 公開関数だけ落とす (設定値 $ResonitePresentation* と状態は残す)。tick は Busy の間なにもしない *)
If[AssociationQ[$irpState], $irpState["Busy"] = True];
Scan[Quiet[Clear[#]] &, Names["ResoniteRealtime`ResonitePresent*"]];

(* ---- 設定の既定 ---- *)
If[!ValueQ[ResoniteRealtime`$ResonitePresentationVoice], ResoniteRealtime`$ResonitePresentationVoice = "realtime:harema"];
If[!ValueQ[ResoniteRealtime`$ResonitePresentationVoiceModel], ResoniteRealtime`$ResonitePresentationVoiceModel = "gpt-live-1.1"];
If[!ValueQ[ResoniteRealtime`$ResonitePresentationCloudVoices],
  ResoniteRealtime`$ResonitePresentationCloudVoices = {"harema", "shida", "marin", "cedar"}];
If[!ValueQ[ResoniteRealtime`$ResonitePresentationAudioRoute], ResoniteRealtime`$ResonitePresentationAudioRoute = Automatic];
If[!ValueQ[ResoniteRealtime`$ResonitePresentationOutputDevice], ResoniteRealtime`$ResonitePresentationOutputDevice = Automatic];
If[!ValueQ[ResoniteRealtime`$ResonitePresentationInputDevice], ResoniteRealtime`$ResonitePresentationInputDevice = Automatic];
If[!ValueQ[ResoniteRealtime`$ResonitePresentationQuestionSeconds], ResoniteRealtime`$ResonitePresentationQuestionSeconds = 3.];
If[!ValueQ[ResoniteRealtime`$ResonitePresentationVolume], ResoniteRealtime`$ResonitePresentationVolume = 1.];
If[!ValueQ[ResoniteRealtime`$ResonitePresenterScales], ResoniteRealtime`$ResonitePresenterScales = {0.5, 0.75, 1, 1.5, 2, 3}];
If[!BooleanQ[ResoniteRealtime`$ResonitePresentationListenWhileNarrating],
  ResoniteRealtime`$ResonitePresentationListenWhileNarrating = True];
If[!ValueQ[ResoniteRealtime`$ResonitePresentationCacheDirectory], ResoniteRealtime`$ResonitePresentationCacheDirectory = Automatic];
If[!BooleanQ[ResoniteRealtime`$ResonitePresentationRequirePaidAPIApproval],
  ResoniteRealtime`$ResonitePresentationRequirePaidAPIApproval = True];

(* ---- 状態 (再ロードで壊さない) ---- *)
$irpIdlePlay = <|"Status" -> "Idle", "Title" -> "", "Slide" -> 0, "First" -> 1, "Last" -> 0, "Count" -> 0,
  "Phase" -> None, "Route" -> None, "Run" -> 0, "Message" -> ""|>;
If[!AssociationQ[$irpState], $irpState = <|"Busy" -> False, "Task" -> None, "Ticks" -> 0|>];
If[!AssociationQ[$irpPlay], $irpPlay = $irpIdlePlay];
If[!MatchQ[$irpRig, _Association | None], $irpRig = None];
If[!AssociationQ[$irpAssets], $irpAssets = <||>];
If[!ListQ[$irpQueue], $irpQueue = {}];
If[!ListQ[$irpLog], $irpLog = {}];
If[!MatchQ[$irpSynth, _Association | None], $irpSynth = None];
If[!AssociationQ[$irpTexts], $irpTexts = <||>];
If[!StringQ[$irpLabel], $irpLabel = "待機中"];
If[!IntegerQ[$irpDeckIndex], $irpDeckIndex = 1];
If[!ListQ[$irpVoiceMenu], $irpVoiceMenu = {}];
If[!BooleanQ[$irpHandlersInstalled], $irpHandlersInstalled = False];
If[!ValueQ[$irpPrevSlideHandler], $irpPrevSlideHandler = None];
If[!ValueQ[$irpPrevAskHandler], $irpPrevAskHandler = None];
If[!BooleanQ[$irpBridgeOwned], $irpBridgeOwned = False];
If[!BooleanQ[$irpAnswering], $irpAnswering = False];
$irpControlNotebook = If[ValueQ[$irpControlNotebook], $irpControlNotebook, None];

$irpTickSeconds = 0.4;
$irpPanelPollSeconds = 1.2;
$irpSilentSeconds = 3.;      (* 原稿の無い枚を見せておく秒数 *)
$irpGapSeconds = 0.8;        (* 読み終えてから次へ送るまでの間 *)
$irpQuestionMaxSeconds = 60.;
$irpLogLimit = 200;
(* GPT-Live にしか無い声 (Realtime API には無い)。SlideWorkflow の一覧と同じ *)
$irpLiveOnlyVoices = {"quartz", "ripple", "vesper", "willow", "stone", "gleam", "meridian", "bossa",
  "tempo", "beacon", "delta", "cinder", "nuri", "juni", "flitz", "brise", "sillage", "nira",
  "harema", "shida", "noeul"};
(* 声で頼まれたときの呼び名 (書き起こしは片仮名になることが多い) *)
$irpVoiceAliases = <|"harema" -> {"ハレマ", "はれま", "ハーレマ"}, "shida" -> {"シダ", "しだ"},
  "marin" -> {"マリン", "まりん"}, "cedar" -> {"シダー", "セダー", "シーダー"}|>;

(* ============================================================
   共通
   ============================================================ *)

irpNow[] := AbsoluteTime[];
irpLinkQ[] := StringQ[$iState["Link"]];

SetAttributes[irpNoWait, HoldFirst];
irpNoWait[expr_] := Block[{$iLinkWaitDefault = False}, expr];

irpNote[tag_String, data_ : None] := (
  $irpLog = Take[Append[$irpLog, <|"Time" -> irpNow[], "Tag" -> tag, "Data" -> data|>],
    -Min[Length[$irpLog] + 1, $irpLogLimit]]; Null);

irpFail[tag_String, msg_String, more_Association : <||>] :=
  Failure[tag, Join[<|"MessageTemplate" -> msg|>, more]];

irpFailText[f_Failure] := With[{m = Quiet @ Check[f["MessageTemplate"], None]},
  If[StringQ[m], m, ToString[First[f]]]];
irpFailText[x_] := ToString[x];

irpTaskContextQ[] := MatchQ[$CurrentTask, _TaskObject];

(* 式を静かに評価して {結果, その間に出たメッセージの名前} を返す。
   成否は結果の形で決める (メッセージが出たかどうかでは決めない)。Quiet @ Check[expr, $Failed] は、正しい結果が返っていても
   メッセージが 1 つ出ただけで $Failed にする。2026-11-23: 利用者のノートブックのカーネルで、正しい mp4 が
   「開けませんでした」になった (同じファイルは別のカーネルでは何度でも開け、再現できていない)。
   何が出たかを後で見られるように、名前は拾っておく *)
SetAttributes[irpQuietly, HoldFirst];
irpQuietly[expr_] :=
  Module[{held = {}, r},
    r = Internal`HandlerBlock[{"Message", (AppendTo[held, #] &)}, Quiet[expr]];
    (* 切ってあるメッセージ (General::newsym など、Off されているもの) は数えない。
       システムが内側で静かにしているもの (最初の Video で出る LibraryFunction::libload や Set::shape) は区別できないので残る *)
    {r, DeleteDuplicates @ Cases[held,
      Hold[Message[m_MessageName, ___], ___] /; !MatchQ[m, _$Off] :> ToString[Unevaluated[m]], Infinity]}];

irpEnqueue[a_Association] := ($irpQueue = Append[$irpQueue, a]; Null);

irpMessage[text_String] := ($irpPlay["Message"] = text; irpNote["Message", text]; Null);

irpCacheRoot[] :=
  Module[{d = ResoniteRealtime`$ResonitePresentationCacheDirectory},
    If[!StringQ[d], d = FileNameJoin[{$UserBaseDirectory, "ApplicationData", "ResoniteRealtime", "present"}]];
    If[!DirectoryQ[d], Quiet @ CreateDirectory[d, CreateIntermediateDirectories -> True]];
    d];

(* wav の長さ (秒)。ヘッダの byteRate から (音声を復号しない。60 秒を超える Quantity の罠も避ける) *)
irpWavSeconds[file_String] :=
  Module[{strm, hdr, rate, size},
    If[!FileExistsQ[file], Return[0.]];
    size = Quiet[FileByteCount[file]];
    If[!IntegerQ[size] || size < 64, Return[0.]];
    strm = Quiet[OpenRead[file, BinaryFormat -> True]];
    If[Head[strm] =!= InputStream, Return[0.]];
    hdr = Quiet[BinaryReadList[strm, "Byte", 44]];
    Quiet[Close[strm]];
    If[Length[hdr] < 44, Return[0.]];
    rate = FromDigits[Reverse[hdr[[29 ;; 32]]], 256];
    If[rate > 0, N[(size - 44)/rate], 0.]];

irpWriteBytes[file_String, bytes_ByteArray] :=
  Module[{strm = Quiet[OpenWrite[file, BinaryFormat -> True]]},
    If[Head[strm] =!= OutputStream, Return[False]];
    BinaryWrite[strm, bytes]; Close[strm]; True];

(* ============================================================
   発表の解決 (SourceVault の発表登録簿) とスライド画像
   ============================================================ *)

irpRegistryQ[] := Length[DownValues[SourceVault`SourceVaultSlideDeckPresentationSpec]] > 0;

irpURLQ[s_] := StringQ[s] && StringStartsQ[s, "http://" | "https://"];

(* スライド発表ができる登録 (Sliden 用 mp4 の URL がある) の題名。60 秒は覚えておく (パネルの < > で毎回読まない) *)
irpDeckTitles[] :=
  Module[{c = Lookup[$irpState, "DeckCache", None], list},
    If[AssociationQ[c] && irpNow[] - c["Time"] < 60, Return[c["Titles"]]];
    list = If[irpRegistryQ[], Quiet[SourceVault`SourceVaultSlideDeckList[]], {}];
    list = If[ListQ[list],
      Select[ToString[Lookup[#, "title", ""]] & /@ Select[list, AssociationQ[#] && irpURLQ[Lookup[#, "url", ""]] &],
        # =!= "" &], {}];
    $irpState["DeckCache"] = <|"Time" -> irpNow[], "Titles" -> list|>;
    list];

irpSelectedTitle[] :=
  With[{t = irpDeckTitles[]},
    If[t === {}, None, t[[Mod[$irpDeckIndex - 1, Length[t]] + 1]]]];

irpResolveSpec[target_String] :=
  Module[{value = StringTrim[target], spec},
    If[irpURLQ[value],
      Return[<|"found" -> True, "released" -> True, "direct" -> True,
        "id" -> "url-" <> StringTake[Hash[value, "SHA256", "HexString"], 10],
        "title" -> FileBaseName[Last[StringSplit[value, "/"]]], "url" -> value,
        "privacyLevel" -> 0., "talk" -> Null, "slideCount" -> Null, "narrationInstructions" -> ""|>]];
    If[!irpRegistryQ[],
      Return[irpFail["PresentationRegistryUnavailable",
        "SourceVault の発表登録簿が読み込まれていません (SourceVault をロードしてください)。mp4 の URL を直接渡すこともできます。"]]];
    spec = Quiet[SourceVault`SourceVaultSlideDeckPresentationSpec[value]];
    Which[
      !AssociationQ[spec],
        irpFail["PresentationRegistryUnavailable", "発表登録簿を読めませんでした。"],
      !TrueQ[Lookup[spec, "found", False]],
        irpFail["PresentationNotRegistered",
          "その発表は登録されていません。SlideWorkflow パレットの「登録」で登録してください。",
          <|"Query" -> value, "Available" -> Lookup[spec, "available", {}]|>],
      !TrueQ[Lookup[spec, "released", True]],
        irpFail["PresentationWithheld", "その発表は privacy 判定により外へ出せません。", <|"Query" -> value|>],
      !irpURLQ[ToString @ Lookup[spec, "url", ""]],
        irpFail["PresentationNoSlides",
          "その発表にはスライド (Sliden 用 mp4) がありません (ポスターだけの登録です)。", <|"Query" -> value|>],
      True, spec]];

(* 表示してよいか: 機密度が表示上限 (ResoniteAccessLevel) 以上のものは出さない (tablet と同じ規則。取れない値は 1.0) *)
irpDisplayAllowedQ[pl_] :=
  With[{p = If[NumericQ[pl] && 0 <= pl <= 1, N[pl], 1.]},
    p < N[ResoniteRealtime`ResoniteAccessLevel[]] - 10^-9];

irpDeckKey[spec_Association] :=
  StringTake[Hash[{ToString @ Lookup[spec, "id", ""], ToString @ Lookup[spec, "url", ""],
    ToString @ Lookup[spec, "updatedAtUTC", ""]}, "SHA256", "HexString"], 16];

(* Sliden 用 mp4 の枚数: 先頭 29 フレーム + 1 枚 30 フレーム + 末尾 (30 または 8) フレーム (VRCRealtime_sliden.py と同じ規則) *)
irpSlidenCount[fc_Integer] :=
  With[{tail = SelectFirst[{30, 8}, fc - 29 - # >= 0 && Mod[fc - 29 - #, 30] == 0 &, None]},
    If[tail === None, None, Quotient[fc - 29 - tail, 30] + 1]];
irpSlidenCount[_] := None;

(* k 枚目の中ほどのフレームの時刻 (秒、30 fps) *)
irpSlidenTime[1] := 10/30.;
irpSlidenTime[k_Integer] := (29 + 30 (k - 2) + 10)/30.;

irpSlideFiles[dir_String] :=
  With[{sdir = FileNameJoin[{dir, "slides"}]},
    If[DirectoryQ[sdir], Sort[FileNames["s*.png", sdir]], {}]];

(* mp4 を開いてフレーム数を読む。-> <|"Video", "Frames" (読めなければ None)|> | Failure。
   開けたかどうかは結果の形で決め、開けなければ少し置いて 3 回まで試す (取ってきた直後のファイルを他のプロセスが掴んでいることがある)。
   出たメッセージは記録 ("VideoOpen") と Failure に残す *)
irpVideoOf[mp4_String] := Video[mp4];

irpOpenVideo[mp4_String] :=
  Module[{v = None, fc = None, msgs = {}, tries = 0, r},
    While[tries < 3 && !(Head[v] === Video && IntegerQ[fc] && fc > 0),
      If[tries > 0, Pause[0.7]];
      tries++;
      r = irpQuietly[
        v = irpVideoOf[mp4];
        If[Head[v] === Video, Information[v, "FrameCount"], None]];
      fc = Replace[First[r], {a_Association /; Length[a] > 0 :> First[Values[a]], k_Integer :> k, _ -> None}];
      msgs = Union[msgs, Last[r]]];
    If[msgs =!= {} || tries > 1, irpNote["VideoOpen", <|"Tries" -> tries, "Frames" -> fc, "Messages" -> msgs|>]];
    If[Head[v] === Video,
      <|"Video" -> v, "Frames" -> If[IntegerQ[fc] && fc > 0, fc, None]|>,
      irpFail["PresentationVideoFailed",
        "スライドの mp4 を開けませんでした" <> If[msgs === {}, "。", " (" <> StringRiffle[msgs, ", "] <> ")。"],
        <|"File" -> mp4, "Tries" -> tries, "Messages" -> msgs|>]]];

irpFramesQ[frames_] := ListQ[frames] && frames =!= {} && AllTrue[frames, ImageQ];

(* mp4 を取ってきて 1 枚ずつ PNG にする (2 回目以降は置き場の画像をそのまま使う)。数秒かかることがある *)
irpPrepareDeck[spec_Association] :=
  Module[{dir, sdir, mp4, files, v, fc, n, times, frames, meta, dur, opened, msgs, more},
    dir = FileNameJoin[{irpCacheRoot[], irpDeckKey[spec]}];
    sdir = FileNameJoin[{dir, "slides"}];
    meta = FileNameJoin[{dir, "deck.json"}];
    files = irpSlideFiles[dir];
    If[files =!= {} && FileExistsQ[meta], Return[<|"Directory" -> dir, "Slides" -> files|>]];
    Quiet @ CreateDirectory[sdir, CreateIntermediateDirectories -> True];
    If[!DirectoryQ[sdir], Return[irpFail["PresentationCacheFailed", "スライドの置き場を作れません: " <> sdir]]];
    mp4 = FileNameJoin[{dir, "deck.mp4"}];
    If[!FileExistsQ[mp4] || Quiet[FileByteCount[mp4]] < 1000,
      Quiet[TimeConstrained[URLDownload[spec["url"], mp4], 180, $Failed]];
      If[!FileExistsQ[mp4] || Quiet[FileByteCount[mp4]] < 1000,
        Quiet[DeleteFile[mp4]];
        Return[irpFail["PresentationDownloadFailed", "スライドの mp4 を取得できませんでした: " <> ToString[spec["url"]]]]]];
    opened = irpOpenVideo[mp4];
    If[FailureQ[opened], Return[opened]];
    v = opened["Video"]; fc = opened["Frames"];
    n = irpSlidenCount[fc];
    times = If[IntegerQ[n] && n >= 1,
      irpSlidenTime /@ Range[n],
      (* Sliden の並びでない mp4: 1 秒 1 枚とみなす (登録簿の枚数があればそれ) *)
      dur = Quiet[QuantityMagnitude[Duration[v], "Seconds"]];
      If[!NumericQ[dur], dur = 0.];
      n = With[{c = Lookup[spec, "slideCount", Null]}, If[IntegerQ[c] && c >= 1, c, Max[1, Floor[dur]]]];
      Table[k - 0.5, {k, n}]];
    {frames, msgs} = irpQuietly[VideoExtractFrames[v, times]];
    If[!irpFramesQ[frames],
      (* 1 度だけ、少し置いてやり直す *)
      Pause[0.7];
      {frames, more} = irpQuietly[VideoExtractFrames[v, times]];
      msgs = Union[msgs, more]];
    If[msgs =!= {}, irpNote["VideoFrames", <|"Slides" -> n, "Messages" -> msgs|>]];
    If[!irpFramesQ[frames],
      Return[irpFail["PresentationVideoFailed",
        "スライドの mp4 から画像を取り出せませんでした" <> If[msgs === {}, "。", " (" <> StringRiffle[msgs, ", "] <> ")。"],
        <|"File" -> mp4, "Messages" -> msgs|>]]];
    files = MapIndexed[
      With[{f = FileNameJoin[{sdir, "s" <> IntegerString[First[#2], 10, 3] <> ".png"}]},
        Quiet[Export[f, #1, "PNG"]]; f] &, frames];
    files = Select[files, FileExistsQ];
    If[files === {}, Return[irpFail["PresentationCacheFailed", "スライド画像を書けませんでした。"]]];
    irpWriteBytes[meta, ExportByteArray[
      <|"id" -> ToString @ Lookup[spec, "id", ""], "title" -> ToString @ Lookup[spec, "title", ""],
        "url" -> ToString @ Lookup[spec, "url", ""], "slides" -> Length[files]|>, "RawJSON"]];
    <|"Directory" -> dir, "Slides" -> files|>];

(* 原稿: 枚の番号 -> 読む文。Opening は先頭の枚、Closing は末尾の枚へつなぐ (SlidePlay と同じ) *)
irpTalkOf[spec_Association, first_Integer, last_Integer] :=
  Module[{talk = Lookup[spec, "talk", Null], texts = <||>, titles = <||>, k, op, cl},
    If[AssociationQ[talk],
      Scan[
        Function[s,
          If[AssociationQ[s],
            k = Lookup[s, "slide", 0];
            If[IntegerQ[k] && first <= k <= last,
              texts[k] = StringTrim[ToString[Lookup[s, "text", ""]]];
              titles[k] = StringTrim[ToString[Lookup[s, "title", ""]]]]]],
        Replace[Lookup[talk, "slides", {}], Except[_List] -> {}]];
      op = StringTrim[ToString[Lookup[talk, "opening", ""]]];
      cl = StringTrim[ToString[Lookup[talk, "closing", ""]]];
      If[op =!= "", texts[first] = StringTrim[op <> "\n" <> Lookup[texts, first, ""]]];
      If[cl =!= "", texts[last] = StringTrim[Lookup[texts, last, ""] <> "\n" <> cl]]];
    <|"Texts" -> Select[texts, # =!= "" &], "Titles" -> titles|>];

(* ============================================================
   声
   ============================================================ *)

(* ローカルの声の一覧 (SourceVaultVoices[])。AivisSpeech の声は、エンジンが動いているときしか並ばない
   (SourceVaultVoices[] は止まっているエンジンを起こさない。2026-11-23: エンジンが止まっていて
   ResonitePresentationSetVoice["ほのか"] が「見つかりません」になった)。
   止まっているエンジンへ聞くと断られるまで 2 秒かかるので、一覧は覚えておく。聞き直すのは、頼まれたとき
   (irpLocalVoices[True]) と、名指しの声が一覧に無かったときだけ。監視タスクの中では聞き直さない
   (エンジンが動き出したかは irpVoiceProbeTick が待たずに確かめる)。 *)
irpVoiceLayerQ[] := Length[DownValues[SourceVault`SourceVaultVoices]] > 0;

irpAivisEntryQ[e_] := AssociationQ[e] && ToString[Lookup[e, "Engine", ""]] === "AivisSpeech";

irpListVoices[] :=
  Module[{vs},
    (* 実行ファイルの場所を覚えておく (監視タスクの中から待たずに起こせるように)。ノートブックからの最初の 1 回だけ *)
    If[!irpTaskContextQ[] && !KeyExistsQ[$irpState, "AivisExe"], irpAivisStatus[]];
    vs = If[irpVoiceLayerQ[], Quiet[SourceVault`SourceVaultVoices[]], {}];
    vs = If[ListQ[vs], Select[vs, AssociationQ[#] && StringQ[Lookup[#, "Name", None]] &], {}];
    $irpState["VoiceCache"] = <|"Time" -> irpNow[], "Voices" -> vs|>;
    $irpState["CurVoice"] = None;
    irpVoiceMenuSync[];
    vs];

irpLocalVoices[refresh_ : False] :=
  With[{c = Lookup[$irpState, "VoiceCache", None]},
    If[TrueQ[refresh] || !AssociationQ[c], irpListVoices[], c["Voices"]]];

(* 覚えてある一覧に AivisSpeech の声があるか (問い合わせない: ノートブックのパネルの Dynamic からも引く) *)
irpAivisListedQ[] := With[{c = Lookup[$irpState, "VoiceCache", None]},
  AssociationQ[c] && AnyTrue[c["Voices"], irpAivisEntryQ]];

(* ノートブックから呼ばれた入口で、一覧をまだ聞いていなければ聞いておく (最初の問い合わせを監視タスクに回さない) *)
irpWarmVoices[] := (If[!irpTaskContextQ[] && !AssociationQ[Lookup[$irpState, "VoiceCache", None]], irpListVoices[]]; Null);

(* ノートブックのパネルの「声を選ぶ」が追う一覧 (変わったときだけ書く) *)
irpVoiceMenuSync[] := With[{names = irpVoiceNames[]}, If[names =!= $irpVoiceMenu, $irpVoiceMenu = names]; Null];

(* ---- AivisSpeech エンジン (ローカルの声の多くはここ) ----
   ノートブックから声を名指しされたら、止まっているエンジンを起こして待つ (SourceVaultVoiceSpeak と同じ扱い)。
   監視タスクの中 (ワールドのパネル・声での操作) では待たずに起こし、動き出したら一覧を聞き直す。
   SourceVault`$SourceVaultVoiceAivisAutoStart が False なら、どちらも起こさない。 *)

irpAivisEndpoint[] := With[{e = SourceVault`$SourceVaultVoiceAivisEndpoint},
  If[StringQ[e] && StringTrim[e] =!= "", StringTrim[e, "/"], "http://127.0.0.1:10101"]];

irpAivisMark[up : (True | False)] := ($irpState["AivisUp"] = up; $irpState["AivisUpTime"] = irpNow[]; Null);

(* エンジンの状態を聞く (同期。止まっていると断られるまで 2 秒)。-> "Running" | "Installed" | "Missing" *)
irpAivisStatus[] :=
  Module[{st, exe},
    st = If[Length[DownValues[SourceVault`SourceVaultVoiceAivisStatus]] > 0,
      Quiet[SourceVault`SourceVaultVoiceAivisStatus[]], $Failed];
    If[!AssociationQ[st], st = <|"Status" -> "Missing"|>];
    exe = Lookup[st, "Executable", None];
    $irpState["AivisExe"] = If[StringQ[exe], exe, None];
    irpAivisMark[Lookup[st, "Status", None] === "Running"];
    Replace[Lookup[st, "Status", "Missing"], Except["Running" | "Installed"] -> "Missing"]];

irpAivisProcAliveQ[] := With[{p = Lookup[$irpState, "AivisProc", None]},
  MatchQ[p, _ProcessObject] && Quiet[ProcessStatus[p]] === "Running"];

(* こちらで起こしたエンジンが、立ち上がりの途中か *)
irpAivisStartingQ[] := !TrueQ[Lookup[$irpState, "AivisUp", False]] && irpAivisProcAliveQ[];

irpAivisSpawn[exe_String, port_Integer] := StartProcess[{exe, "--port", ToString[port]}];

(* 止まっているエンジンを、待たずに起こす。-> "Running" | "Starting" | "Missing" | "Disabled" | "Failed" *)
irpAivisKick[] :=
  Module[{ep = irpAivisEndpoint[], exe, port, proc},
    If[irpAivisStartingQ[], Return["Starting"]];
    (* 動いているかどうかを知らない (か、知ったのが古い) ときは聞き直す: 動いているのに 2 つ目を起こさない *)
    If[!KeyExistsQ[$irpState, "AivisExe"] || !BooleanQ[Lookup[$irpState, "AivisUp", None]] ||
        irpNow[] - Lookup[$irpState, "AivisUpTime", 0] > 40,
      irpAivisStatus[]];
    If[TrueQ[$irpState["AivisUp"]], Return["Running"]];
    exe = Lookup[$irpState, "AivisExe", None];
    Which[
      !StringQ[exe], "Missing",
      !TrueQ[SourceVault`$SourceVaultVoiceAivisAutoStart] || !StringContainsQ[ep, "127.0.0.1" | "localhost"], "Disabled",
      (* 起こしたのに立ち上がらなかった: すぐには繰り返さない (5 分置く) *)
      irpNow[] - Lookup[$irpState, "AivisKickTime", 0] < 300, "Failed",
      True,
        port = Quiet[URLParse[ep, "Port"]];
        proc = Quiet[irpAivisSpawn[exe, If[IntegerQ[port], port, 10101]]];
        $irpState["AivisKickTime"] = irpNow[];
        If[MatchQ[proc, _ProcessObject],
          $irpState["AivisProc"] = proc; $irpState["AivisAnnounce"] = True; irpNote["AivisStart", exe]; "Starting",
          irpNote["AivisStartFailed", exe]; "Failed"]]];

(* こちらで起こしたエンジンが応答するまで待つ (ノートブックから。$SourceVaultVoiceAivisStartTimeout 秒、既定 180) *)
irpAivisAwait[] :=
  Module[{deadline, st = None},
    deadline = irpNow[] + With[{t = SourceVault`$SourceVaultVoiceAivisStartTimeout}, If[NumericQ[t] && t > 0, N[t], 180.]];
    While[irpNow[] < deadline && (st = irpAivisStatus[]) =!= "Running" && irpAivisProcAliveQ[], Pause[1.]];
    If[st === "Running", "Running", "Failed"]];

(* ノートブックから: エンジンが応答するようにする (止まっていれば起こして待つ。初回は 1〜2 分)。
   -> "Running" | "Missing" | "Disabled" | "Failed" *)
irpAivisEnsure[] :=
  Module[{st, t0, ok},
    If[irpAivisStartingQ[],
      (* 監視タスクが起こしている最中: 同じものを待つ (2 つ目を起こさない) *)
      Print["AivisSpeech Engine の起動を待っています (1〜2 分かかることがあります) ..."];
      Return[irpAivisAwait[]]];
    st = irpAivisStatus[];
    Which[
      st === "Running", "Running",
      st === "Missing", "Missing",
      !TrueQ[SourceVault`$SourceVaultVoiceAivisAutoStart], "Disabled",
      True,
        t0 = irpNow[];
        ok = Length[DownValues[SourceVault`SourceVaultVoiceAivisEnsure]] > 0 &&
          TrueQ[Quiet[SourceVault`SourceVaultVoiceAivisEnsure[]]];
        Which[
          ok, irpAivisMark[True]; "Running",
          (* SourceVault は、一度起こしたエンジンが落ちていると起こし直さない (すぐ False を返す): こちらで起こして待つ *)
          irpNow[] - t0 < 15 && irpAivisKick[] === "Starting",
            Print["AivisSpeech Engine を起動しています (1〜2 分かかることがあります) ..."];
            irpAivisAwait[],
          True, "Failed"]]];

(* AivisSpeech の声が一覧に無ければ、止まっているエンジンを起こす。
   wait が True (ノートブックから) なら、応答するまで待って一覧を聞き直す。
   False (ワールドのパネル・声での操作から) なら待たない: 動き出したら irpVoiceProbeTick が一覧を聞き直す。
   -> "Listed" | "Starting" | "Missing" | "Disabled" | "Failed" *)
irpWakeLocalVoices[wait_ : True] :=
  Module[{st, t0, text = "ローカルの声 (AivisSpeech) を起動しています。1〜2 分かかります"},
    Which[
      !irpVoiceLayerQ[], "Missing",
      irpAivisListedQ[], "Listed",
      !TrueQ[wait],
        st = irpAivisKick[];
        If[st === "Running", irpListVoices[]; st = If[irpAivisListedQ[], "Listed", "Starting"]];
        If[st === "Starting" && $irpPlay["Message"] =!= text, irpMessage[text]];
        st,
      True,
        st = irpAivisEnsure[];
        If[st =!= "Running", Return[st]];
        (* 動いた直後は、SourceVault が「声なし」を 30 秒覚えていることがある: 並ぶまで聞き直す *)
        t0 = irpNow[];
        While[irpListVoices[]; !irpAivisListedQ[] && irpNow[] - t0 < 32, Pause[2.]];
        If[irpAivisListedQ[], "Listed", "Failed"]]];

irpWakeHint[st_] :=
  Switch[st,
    "Starting", "。ローカルの声のエンジン (AivisSpeech) を起動しています。1〜2 分してから、もう一度選んでください。",
    "Failed", "。ローカルの声のエンジン (AivisSpeech) を起動できませんでした。",
    "Disabled", "。ローカルの声のエンジン (AivisSpeech) が止まっています (SourceVault`$SourceVaultVoiceAivisAutoStart が False なので自動では起こしません)。",
    _, ""];

(* 監視タスクから: エンジンが動いているかを待たずに確かめる (15 秒ごと。こちらで起こしている途中は 4 秒ごと)。
   動いているのに AivisSpeech の声がまだ並んでいなければ、一覧を聞き直す (動いているエンジンへは一瞬で済む) *)
irpVoiceProbeArrive[id_, data_] :=
  If[Lookup[Lookup[$irpState, "VoiceProbe", <||>], "Id", None] === id,
    $irpState["VoiceProbe"] = Join[$irpState["VoiceProbe"], <|"Inbox" -> data|>]];

irpVoiceProbeSubmit[id_String] :=
  Quiet[
    URLSubmit[HTTPRequest[irpAivisEndpoint[] <> "/version", <|"Method" -> "GET"|>],
      HandlerFunctions -> <|"TaskFinished" -> (ResoniteRealtime`Private`irpVoiceProbeArrive[id, #] &)|>,
      HandlerFunctionsKeys -> {"StatusCode"}]];

irpVoiceProbeTick[] :=
  Module[{p = Lookup[$irpState, "VoiceProbe", <||>], now = irpNow[], in, up, id, every, lists},
    If[!irpVoiceLayerQ[], Return[Null]];
    in = Lookup[p, "Inbox", None];
    If[in =!= None,
      up = AssociationQ[in] && Lookup[in, "StatusCode", 0] === 200;
      irpAivisMark[up];
      lists = If[up, Lookup[p, "Lists", 0], 0];
      (* SourceVault は「声なし」を 30 秒覚えているので、動いた直後はまだ並ばないことがある: 4 秒おきに 12 回まで聞き直す *)
      If[up && !irpAivisListedQ[] && lists < 12,
        lists++;
        irpListVoices[];
        If[irpAivisListedQ[],
          irpNote["LocalVoicesReady", Length[irpLocalVoices[]]];
          If[TrueQ[Lookup[$irpState, "AivisAnnounce", False]],
            $irpState["AivisAnnounce"] = False;
            irpMessage["ローカルの声が使えるようになりました (「声を替える」で選べます)"]]]];
      p = <|"Id" -> None, "Time" -> Lookup[p, "Time", now], "Inbox" -> None, "Lists" -> lists|>;
      $irpState["VoiceProbe"] = p];
    (* 返事が来ないまま: 捨てて次を頼む *)
    If[Lookup[p, "Id", None] =!= None && now - Lookup[p, "Time", now] > 20,
      p = Join[p, <|"Id" -> None|>]; $irpState["VoiceProbe"] = p];
    every = If[irpAivisStartingQ[] ||
        (TrueQ[Lookup[$irpState, "AivisUp", False]] && !irpAivisListedQ[] && Lookup[p, "Lists", 0] < 12), 4., 15.];
    If[Lookup[p, "Id", None] === None && now - Lookup[p, "Time", 0] >= every,
      id = CreateUUID[];
      $irpState["VoiceProbe"] = Join[p, <|"Id" -> id, "Time" -> now, "Inbox" -> None|>];
      irpVoiceProbeSubmit[id]];
    Null];

irpVoiceModel[] := With[{m = ResoniteRealtime`$ResonitePresentationVoiceModel},
  If[StringQ[m] && StringTrim[m] =!= "", m, "gpt-live-1.1"]];

irpModelLiveQ[model_String] :=
  If[Length[DownValues[SourceVault`SourceVaultRealtimeModelAPI]] > 0,
    Quiet[SourceVault`SourceVaultRealtimeModelAPI[model]] === "Live",
    StringStartsQ[model, "gpt-live"]];

irpCloudVoiceNames[] :=
  With[{vs = Select[Flatten[{ResoniteRealtime`$ResonitePresentationCloudVoices}], StringQ]},
    If[irpModelLiveQ[irpVoiceModel[]], vs, Select[vs, !MemberQ[$irpLiveOnlyVoices, ToLowerCase[#]] &]]];

irpCloudLayerQ[] := Length[DownValues[SourceVault`SourceVaultRealtimeStart]] > 0;

irpVoiceNames[] :=
  Join[Lookup[#, "Name"] & /@ irpLocalVoices[],
    If[irpCloudLayerQ[], ("realtime:" <> #) & /@ irpCloudVoiceNames[], {}]];

ResoniteRealtime`ResonitePresentationVoices[] := (irpLocalVoices[True]; irpVoiceNames[]);

(* 名前 (一部でよい) -> <|"Name", "Engine" -> "Local"|"Cloud", "Voice", "Entry"|> *)
irpMatchLocal[want_String] :=
  Module[{locals = irpLocalVoices[], hit},
    hit = SelectFirst[locals, #["Name"] === want &, None];
    If[hit === None, hit = SelectFirst[locals, StringContainsQ[#["Name"], want, IgnoreCase -> True] &, None]];
    hit];

irpResolveVoice[spec_] :=
  Module[{want, clouds = irpCloudVoiceNames[], hit, bare, wake = None},
    want = If[StringQ[spec] && StringTrim[spec] =!= "", StringTrim[spec],
      ResoniteRealtime`$ResonitePresentationVoice];
    If[!StringQ[want], want = "realtime:harema"];
    bare = If[StringStartsQ[want, "realtime:"], StringDrop[want, 9], want];
    (* クラウドの声: "realtime:" 付き、または名前が一覧と一致 *)
    If[StringStartsQ[want, "realtime:"] || MemberQ[ToLowerCase /@ clouds, ToLowerCase[bare]],
      If[!irpCloudLayerQ[],
        Return[irpFail["VoiceUnavailable", "クラウドの声を使う音声ブリッジ (SourceVault_realtime) が読み込まれていません。"]]];
      If[MemberQ[$irpLiveOnlyVoices, ToLowerCase[bare]] && !irpModelLiveQ[irpVoiceModel[]],
        Return[irpFail["VoiceLiveOnly", "声「" <> bare <> "」は GPT-Live 専用です。$ResonitePresentationVoiceModel を gpt-live-1.1 にしてください。"]]];
      Return[<|"Name" -> "realtime:" <> ToLowerCase[bare], "Engine" -> "Cloud", "Voice" -> ToLowerCase[bare],
        "Model" -> irpVoiceModel[]|>]];
    hit = irpMatchLocal[want];
    (* 一覧に無い: ノートブックからなら一覧を聞き直す。それでも無ければ、止まっている AivisSpeech を起こして探し直す
       (ノートブックからなら応答するまで待つ。監視タスクの中なら待たずに起こすだけで、動き出したら一覧に並ぶ) *)
    If[hit === None && !irpTaskContextQ[], irpListVoices[]; hit = irpMatchLocal[want]];
    If[hit === None, wake = irpWakeLocalVoices[!irpTaskContextQ[]]; hit = irpMatchLocal[want]];
    If[hit === None,
      Return[irpFail["VoiceUnavailable", "その声は見つかりません: " <> want <> irpWakeHint[wake],
        <|"Available" -> irpVoiceNames[], "LocalEngine" -> wake|>]]];
    <|"Name" -> hit["Name"], "Engine" -> "Local", "Voice" -> hit["Name"], "Entry" -> hit|>];

irpVoiceShort[name_String] := First[StringSplit[name, "(" | "（"], name];

irpVoiceLabel[] :=
  With[{v = irpCurrentVoice[]},
    If[AssociationQ[v],
      If[v["Engine"] === "Cloud", v["Voice"] <> " (" <> v["Model"] <> ")", irpVoiceShort[v["Name"]] <> " (ローカル)"],
      ToString[ResoniteRealtime`$ResonitePresentationVoice] <> If[irpAivisStartingQ[], " (起動中)", " (使えません)"]]];

ResoniteRealtime`ResonitePresentationSetVoice[name_String] :=
  Module[{v = irpResolveVoice[name]},
    If[FailureQ[v], Return[v]];
    ResoniteRealtime`$ResonitePresentationVoice = v["Name"];
    $irpState["CurVoice"] = None;
    irpNote["Voice", v["Name"]];
    irpRefreshLabel[];
    v["Name"]];

ResoniteRealtime`ResonitePresentationCycleVoice[] :=
  Module[{vs, cur, i},
    (* AivisSpeech の声が並んでいなければ、止まっているエンジンを起こす
       (ノートブックからなら待って一覧に加える。ワールドのパネルからなら待たない: 動き出してから押せば選べる) *)
    irpWakeLocalVoices[!irpTaskContextQ[]];
    vs = irpVoiceNames[];
    If[vs === {}, Return[irpFail["VoiceUnavailable", "使える声がありません。"]]];
    cur = With[{v = irpCurrentVoice[]}, If[AssociationQ[v], v["Name"], None]];
    i = FirstPosition[vs, cur, {0}][[1]];
    ResoniteRealtime`ResonitePresentationSetVoice[vs[[Mod[i, Length[vs]] + 1]]]];

(* 声ごとの音声の置き場の名前 (ASCII) *)
irpVoiceKey[v_Association] :=
  If[v["Engine"] === "Cloud",
    "cloud-" <> StringReplace[v["Model"], Except[LetterCharacter | DigitCharacter] -> "_"] <> "-" <> v["Voice"],
    "local-" <> StringTake[Hash[v["Name"], "SHA256", "HexString"], 10]];

irpAudioFile[dir_String, v_Association, k_Integer, text_String] :=
  FileNameJoin[{dir, "audio", irpVoiceKey[v],
    "a" <> IntegerString[k, 10, 3] <> "-" <> StringTake[Hash[text, "SHA256", "HexString"], 8] <> ".wav"}];

(* ============================================================
   資産の取り込み (importTexture2DFile / importAudioClipFile。待たない)
   ============================================================ *)

irpAssetURL[file_String] :=
  With[{a = Lookup[$irpAssets, file, None]},
    If[AssociationQ[a] && a["Link"] === $iState["Link"] && StringQ[a["URL"]], a["URL"], None]];

irpPendingImports[] := Count[Values[$irpAssets], a_ /; AssociationQ[a] && a["State"] === "Pending" && a["Link"] === $iState["Link"]];

(* 取り込み済みなら URL、まだなら None (必要なら取り込みを頼む) *)
irpEnsureImport[kind_String, file_String] :=
  Module[{a = Lookup[$irpAssets, file, None], sent, same},
    same = AssociationQ[a] && a["Link"] === $iState["Link"];
    Which[
      same && StringQ[a["URL"]], a["URL"],
      same && a["State"] === "Pending", None,
      same && a["State"] === "Failed" && irpNow[] - a["Time"] < 15, None,
      !irpLinkQ[] || !FileExistsQ[file], None,
      irpPendingImports[] >= 6, None,
      True,
        sent = Quiet[
          ResoniteRealtime`ResoniteRealtimeLink[
            <|"$type" -> If[kind === "Texture", "importTexture2DFile", "importAudioClipFile"], "filePath" -> file|>,
            "Wait" -> False]];
        If[AssociationQ[sent] && StringQ[Lookup[sent, "MessageId", None]],
          $irpAssets[file] = <|"State" -> "Pending", "Kind" -> kind, "MessageId" -> sent["MessageId"],
            "Time" -> irpNow[], "Link" -> $iState["Link"], "URL" -> None|>;
          irpNote["Import", FileNameTake[file]],
          irpNote["ImportSendFailed", FileNameTake[file]]];
        None]];

irpPumpImports[] :=
  Module[{now = irpNow[], res},
    KeyValueMap[
      Function[{file, a},
        If[AssociationQ[a] && a["State"] === "Pending",
          res = icPollReply[a["MessageId"]];
          Which[
            AssociationQ[res] && Lookup[res, "success", True] =!= False && StringQ[Lookup[res, "assetURL", None]],
              $irpAssets[file] = Join[a, <|"State" -> "Ready", "URL" -> res["assetURL"], "Time" -> now|>];
              irpNote["Imported", <|"File" -> FileNameTake[file], "Seconds" -> Round[now - a["Time"], 0.1]|>],
            AssociationQ[res],
              $irpAssets[file] = Join[a, <|"State" -> "Failed", "Time" -> now|>];
              irpNote["ImportFailed", <|"File" -> file, "Error" -> Lookup[res, "errorInfo", None]|>],
            now - a["Time"] > 40 || a["Link"] =!= $iState["Link"],
              $irpAssets[file] = Join[a, <|"State" -> "Failed", "Time" -> now|>];
              irpNote["ImportTimeout", file],
            True, Null]]],
      $irpAssets];
    Null];

(* ============================================================
   ローカル音声の合成 (カーネルを塞がない: AivisSpeech へ URLSubmit。それ以外の声は同期で 1 枚ずつ)
   ============================================================ *)

irpAivisQ[v_Association] :=
  v["Engine"] === "Local" && AssociationQ[Lookup[v, "Entry", None]] &&
    ToString[Lookup[v["Entry"], "Engine", ""]] === "AivisSpeech" &&
    IntegerQ[Lookup[v["Entry"], "StyleId", None]] && irpURLQ[Lookup[v["Entry"], "Root", None]];

irpSynthBusyQ[] := AssociationQ[$irpSynth];

(* 同期の合成 (SourceVaultVoiceSpeak)。Piper の声、AivisSpeech が止まっているとき、事前準備で使う *)
irpSynthSync[v_Association, text_String, file_String] :=
  Module[{a},
    Quiet @ CreateDirectory[DirectoryName[file], CreateIntermediateDirectories -> True];
    a = Quiet[SourceVault`SourceVaultVoiceSpeak[text, "Voice" -> v["Voice"], "OutputFile" -> file]];
    If[FileExistsQ[file] && irpWavSeconds[file] > 0.2, file,
      Quiet[DeleteFile[file]];
      If[FailureQ[a], a, irpFail["VoiceSynthesisFailed", "音声を合成できませんでした。"]]]];

irpSynthSubmit[phase_String, req_HTTPRequest] :=
  Module[{id = $irpSynth["Id"]},
    Block[{$CharacterEncoding = "UTF-8"},
      Quiet[
        URLSubmit[req,
          HandlerFunctions -> <|"TaskFinished" -> (ResoniteRealtime`Private`irpSynthArrive[id, phase, #] &)|>,
          HandlerFunctionsKeys -> {"StatusCode", "BodyByteArray"}]]]];

(* URLSubmit のコールバック: 届いたものを置くだけ (処理は tick) *)
irpSynthArrive[id_, phase_String, data_] :=
  If[AssociationQ[$irpSynth] && $irpSynth["Id"] === id && $irpSynth["Phase"] === phase,
    $irpSynth["Inbox"] = data];

irpSynthStart[v_Association, k_Integer, text_String, file_String] :=
  Module[{ep, sid, t},
    Quiet @ CreateDirectory[DirectoryName[file], CreateIntermediateDirectories -> True];
    If[!irpAivisQ[v],
      (* 同期 (その枚の長さの半分ほどカーネルが塞がる)。Piper は速いので実用になる *)
      irpNote["SynthSync", k];
      With[{r = irpSynthSync[v, text, file]},
        If[FailureQ[r],
          irpNote["SynthFailed", <|"Slide" -> k, "Error" -> irpFailText[r]|>];
          (* 失敗を毎回の見回りで繰り返さない *)
          $irpState["SynthRetryAt"] = irpNow[] + 10]];
      Return[Null]];
    ep = v["Entry"]["Root"]; sid = v["Entry"]["StyleId"];
    $irpSynth = <|"Id" -> CreateUUID[], "Slide" -> k, "File" -> file, "Voice" -> v, "Text" -> text,
      "Phase" -> "Query", "Time" -> irpNow[], "Inbox" -> None, "Endpoint" -> ep, "StyleId" -> sid|>;
    t = irpSynthSubmit["Query",
      HTTPRequest[ep <> "/audio_query",
        <|"Method" -> "POST", "Query" -> {"speaker" -> ToString[sid], "text" -> text}|>]];
    If[!MatchQ[t, _TaskObject], irpSynthFallback["submit"]];
    Null];

(* 非同期が使えなかった: 同期で作り直す。
   ただしエンジンが止まっているとき (down、または見回りが「止まっている」と知っているとき) は同期にしない:
   SourceVaultVoiceSpeak はエンジンの起動を待つので、監視タスクの中ではカーネルを 1〜2 分塞ぐ。待たずに起こし、動き出してから頼み直す *)
irpSynthFallback[why_String, down_ : False] :=
  Module[{s = $irpSynth, kick},
    $irpSynth = None;
    If[!AssociationQ[s], Return[Null]];
    irpNote["SynthFallback", <|"Slide" -> s["Slide"], "Why" -> why|>];
    If[irpAivisQ[s["Voice"]] && irpTaskContextQ[] && (TrueQ[down] || Lookup[$irpState, "AivisUp", None] === False),
      If[TrueQ[down], irpAivisMark[False]];
      kick = irpAivisKick[];
      $irpState["SynthRetryAt"] = irpNow[] + If[kick === "Starting", 5, 30];
      irpMessage[If[kick === "Starting", "ローカルの声 (AivisSpeech) を起動しています。1〜2 分かかります",
        "ローカルの声 (AivisSpeech) が動いていません"]];
      Return[Null]];
    With[{r = irpSynthSync[s["Voice"], s["Text"], s["File"]]},
      If[FailureQ[r],
        irpNote["SynthFailed", <|"Slide" -> s["Slide"], "Error" -> irpFailText[r]|>];
        $irpState["SynthRetryAt"] = irpNow[] + 10]];
    Null];

irpSynthTick[] :=
  Module[{s = $irpSynth, in, query, payload, ls, t},
    If[!AssociationQ[s], Return[Null]];
    in = s["Inbox"];
    If[!AssociationQ[in],
      If[irpNow[] - s["Time"] > 150, irpSynthFallback["timeout"]];
      Return[Null]];
    If[Lookup[in, "StatusCode", 0] =!= 200 || !ByteArrayQ[Lookup[in, "BodyByteArray", None]],
      (* 繋がらなかったとき (エンジンが止まっている) は StatusCode が数でない (Missing["NotAvailable"]) *)
      Return[irpSynthFallback["status " <> ToString[Lookup[in, "StatusCode", "?"]], !IntegerQ[Lookup[in, "StatusCode", None]]]]];
    Switch[s["Phase"],
      "Query",
        query = Quiet[ImportByteArray[in["BodyByteArray"], "RawJSON"]];
        If[!AssociationQ[query], Return[irpSynthFallback["query json"]]];
        ls = Lookup[s["Voice"]["Entry"], "LengthScale", 1.];
        If[NumericQ[ls] && ls > 0 && ls != 1., query["speedScale"] = N[1/ls]];
        payload = Quiet[ExportByteArray[query, "RawJSON", "Compact" -> True]];
        If[!ByteArrayQ[payload], Return[irpSynthFallback["payload"]]];
        $irpSynth = Join[s, <|"Phase" -> "Synthesis", "Inbox" -> None, "Time" -> irpNow[]|>];
        t = irpSynthSubmit["Synthesis",
          HTTPRequest[s["Endpoint"] <> "/synthesis",
            <|"Method" -> "POST", "Query" -> {"speaker" -> ToString[s["StyleId"]]},
              "ContentType" -> "application/json", "Body" -> payload|>]];
        If[!MatchQ[t, _TaskObject], irpSynthFallback["submit"]],
      "Synthesis",
        $irpSynth = None;
        If[Length[in["BodyByteArray"]] > 100 && irpWriteBytes[s["File"], in["BodyByteArray"]],
          irpNote["Synth", <|"Slide" -> s["Slide"], "Seconds" -> irpWavSeconds[s["File"]]|>],
          irpNote["SynthFailed", <|"Slide" -> s["Slide"], "Error" -> "empty"|>]],
      _, $irpSynth = None];
    Null];

(* ============================================================
   スクリーン・スピーカー・操作パネル (待たずに組む)
   ============================================================ *)

irpRigQ[] := AssociationQ[$irpRig];
irpRigBuiltQ[] := irpRigQ[] && MemberQ[{"Settle", "Wire", "Ready"}, $irpRig["Phase"]];

Options[ResoniteRealtime`ResonitePresenter] = {
  "Placement" -> "User", "User" -> Automatic, "Distance" -> 3.0, "Height" -> 0.9,
  "Position" -> {0, 1.0, 2.5}, "Parent" -> "Root", "Width" -> 2.4, "Panel" -> True,
  "Name" -> "Mathematica Presenter", "Rebuild" -> False, "Wait" -> Automatic};

irpRigOptions[opts___] :=
  Association @ Map[# -> OptionValue[ResoniteRealtime`ResonitePresenter, Flatten[{opts}], #] &,
    Keys[Options[ResoniteRealtime`ResonitePresenter]]];

irpVal[x_] := If[AssociationQ[x], Lookup[x, "value", x], x];

(* 組み立ての開始: アバターの位置を聞く (待たない)。答えは irpRigTick が受ける *)
irpRigStart[o_Association] :=
  Module[{sent},
    $irpRig = <|"Phase" -> "PoseRoot", "Options" -> o, "Time" -> irpNow[], "Pending" -> None, "Wire" -> {}|>;
    If[o["Placement"] =!= "User",
      Return[irpRigBuild[<|"Parent" -> o["Parent"], "Position" -> o["Position"], "Rotation" -> None|>]]];
    sent = Quiet[
      ResoniteRealtime`ResoniteRealtimeGetSlot["Root", "Depth" -> 2, "IncludeComponentData" -> False, "Wait" -> False]];
    If[AssociationQ[sent] && StringQ[Lookup[sent, "MessageId", None]],
      $irpRig["Pending"] = sent["MessageId"],
      irpRigBuild[<|"Parent" -> o["Parent"], "Position" -> o["Position"], "Rotation" -> None|>]];
    Null];

irpRigFallbackPose[] :=
  With[{o = $irpRig["Options"]}, <|"Parent" -> o["Parent"], "Position" -> o["Position"], "Rotation" -> None|>];

(* アバターの根の候補を応答の木から探す。アバターの根は "User <名前> (ID....)" という名の slot だが、
   名前が "User " で始まるだけの別物 (ProtoFlux の "User In VR Flux" など。2026-11-23 実機で誤って採った) もあるので、
   ここでは候補を並べるだけにして (ID 付きの名を先に)、子に "Head" があるかを次の応答で確かめてから採る *)
irpUserCandidates[res_Association, userSpec_] :=
  Module[{slots, cands},
    slots = Cases[res, a_Association /; KeyExistsQ[a, "children"] && KeyExistsQ[a, "id"] :> a, {0, Infinity}];
    cands = Select[slots, StringStartsQ[ToString[irpVal[Lookup[#, "name", ""]]], "User "] &];
    If[StringQ[userSpec],
      cands = Select[cands, StringContainsQ[ToString[irpVal[#["name"]]], userSpec] &]];
    SortBy[cands, If[StringContainsQ[ToString[irpVal[#["name"]]], "(ID"], 0, 1] &]];

(* 候補の先頭の子を聞く (待たない)。送れたら True *)
irpAskUserChildren[] :=
  Module[{c = Lookup[$irpRig, "Candidates", {}], sent},
    If[c === {}, Return[False]];
    sent = Quiet[
      ResoniteRealtime`ResoniteRealtimeGetSlot[First[c]["id"], "Depth" -> 1, "IncludeComponentData" -> False, "Wait" -> False]];
    If[AssociationQ[sent] && StringQ[Lookup[sent, "MessageId", None]],
      $irpRig = Join[$irpRig, <|"Phase" -> "PoseHead", "Pending" -> sent["MessageId"], "User" -> First[c],
        "Candidates" -> Rest[c], "Time" -> irpNow[]|>];
      True, False]];

irpPoseFrom[user_Association, head_, distance_, height_] :=
  Module[{pos, rot, hp, hr, q, f, eye, h},
    pos = Lookup[irpVal[user["position"]], {"x", "y", "z"}];
    rot = Lookup[irpVal[user["rotation"]], {"x", "y", "z", "w"}];
    If[!VectorQ[pos, NumericQ] || !VectorQ[rot, NumericQ], Return[None]];
    hp = If[AssociationQ[head], Lookup[irpVal[head["position"]], {"x", "y", "z"}], None];
    hr = If[AssociationQ[head], Lookup[irpVal[head["rotation"]], {"x", "y", "z", "w"}], None];
    q = If[VectorQ[hr, NumericQ], icQuatMul[rot, hr], rot];
    f = icQuatForward[q]; f = {f[[1]], 0, f[[3]]};
    f = If[Norm[f] < 10^-6, {0, 0, 1}, f/Norm[f]];
    eye = pos + If[VectorQ[hp, NumericQ], icQuatRotate[rot, hp], {0, 1.6, 0}];
    h = If[NumericQ[height], pos[[2]] + height, eye[[2]] - 0.6];
    <|"Parent" -> Lookup[Lookup[user, "parent", <||>], "targetId", "Root"],
      "Position" -> N[{eye[[1]], h, eye[[3]]} + distance*f], "Rotation" -> N[icYawQuat[f]]|>];

(* ---- スクリーンの大きさ (何段階かで切り替える) ----
   組み立てたときの大きさ ("Width") を等倍として、Screen Holder の倍率を書き換える。下の辺の高さは変えず、
   右に置いた操作パネルはスクリーンの右端についていく (パネル自体の大きさは変えない) *)
irpScales[] :=
  With[{s = ResoniteRealtime`$ResonitePresenterScales},
    If[VectorQ[s, NumericQ] && s =!= {} && AllTrue[s, 0.05 <= # <= 20 &],
      Union[N[s], {1.}], {0.5, 0.75, 1., 1.5, 2., 3.}]];

(* 等倍の段 *)
irpScaleHome[] := First[FirstPosition[irpScales[], 1., {1}]];

irpScaleIndex[] :=
  With[{i = If[irpRigQ[], Lookup[$irpRig, "ScaleIndex", None], None]},
    If[IntegerQ[i], Clip[i, {1, Length[irpScales[]]}], irpScaleHome[]]];

irpHolderPosition[h_, s_] := {0., s*h/2 + 0.1, 0.};
irpPanelPosition[w_, s_] := {s*w/2 + 0.62, 0.42, -0.12};

irpScaleLabel[] :=
  If[irpRigBuiltQ[] && ListQ[Lookup[$irpRig, "Size", None]],
    With[{i = irpScaleIndex[], steps = irpScales[]},
      "スクリーン: 幅 " <> ToString[NumberForm[steps[[i]]*$irpRig["Size"][[1]], {5, 1}]] <> " m (" <>
        ToString[i] <> "/" <> ToString[Length[steps]] <> ")"],
    "スクリーン: -"];

(* i 段目の大きさにする (待たない)。-> スクリーンの幅 (m) *)
irpSetScale[i_Integer] :=
  Module[{steps = irpScales[], j, s, w, h},
    If[!irpRigBuiltQ[] || !ListQ[Lookup[$irpRig, "Size", None]], Return[None]];
    j = Clip[i, {1, Length[steps]}];
    s = steps[[j]]; {w, h} = $irpRig["Size"];
    irpNoWait[Quiet[ResoniteRealtime`ResoniteRealtimeUpdateSlot[$irpRig["Holder"],
      <|"position" -> irpHolderPosition[h, s], "scale" -> {s, s, s}|>]]];
    If[StringQ[Lookup[$irpRig, "PanelRoot", None]],
      irpNoWait[Quiet[ResoniteRealtime`ResoniteRealtimeUpdateSlot[$irpRig["PanelRoot"],
        <|"position" -> irpPanelPosition[w, s]|>]]]];
    $irpRig["ScaleIndex"] = j;
    irpNote["Scale", <|"Step" -> j, "Scale" -> s, "Width" -> s*w|>];
    irpRefreshLabel[];
    s*w];

irpResize[dir : (1 | -1)] := irpSetScale[irpScaleIndex[] + dir];

irpRow[parent_String, name_String, h_] :=
  Module[{row = icSlot[name, parent]},
    icLayoutElement[row, h, 0];
    icComp[row, $icUIX <> "HorizontalLayout", <|"Spacing" -> 10., "ForceExpandWidth" -> False|>];
    row];

irpRowText[row_String, name_String, content_String, fs_, prefix_String] :=
  Module[{s = icSlot[name, row]},
    icComp[s, $icUIX <> "LayoutElement", <|"MinWidth" -> 120., "FlexibleWidth" -> 1.|>];
    itText[s, content, fs, "Left", "Middle", ResoniteRealtime`ResoniteRealtimeNewId[prefix]]];

(* すべて送りっぱなしで組む。ボタンの結線 (ButtonToggle) だけは、次の getSlot の応答でメンバ ID を拾ってから *)
irpRigBuild[pose_Association] :=
  Module[{o = $irpRig["Options"], r},
    r = Catch[
      Block[{$iLinkWaitDefault = False, $icMats = <||>, $itWireLater = {}},
        Module[{ids = <||>, w, h, root, holder, screen, spk, mesh, proot, panel, vl, row, fs = 26, csz = {900, 600},
                ps = 0.001, btn = <||>, bc = RGBColor[0.24, 0.3, 0.46, 1], bw = 150, bh = 58},
          w = N[o["Width"]]; h = w*9/16.;
          root = icSlot[o["Name"], pose["Parent"], "Position" -> N[pose["Position"]],
            Sequence @@ If[ListQ[pose["Rotation"]], {"Rotation" -> N[pose["Rotation"]]}, {}],
            "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["Presenter"]];
          ids["Root"] = root;
          icComp[root, $icFE <> "Grabbable", <|"Scalable" -> True|>];
          icComp[root, $icFE <> "AI_GeneratedContent",
            <|"Source" -> "Mathematica ResoniteRealtime presenter (slides from SlideWorkflow, AI narration voice)"|>];

          (* スクリーン: 画像 2 枚 (表と控え) を持ち、次の枚を控えに読み込んでおいて切り替える *)
          holder = icSlot["Screen Holder", root, "Position" -> irpHolderPosition[h, 1.]];
          ids["Holder"] = holder;
          icComp[holder, $icFE <> "BoxCollider", <|"Size" -> {w, h, 0.03}|>];
          itBacking[holder, {w, h}];
          screen = icSlot["Screen", holder, "Scale" -> {w, h, 1.}];
          ids["Screen"] = screen;
          ids["TexA"] = icComp[screen, $icFE <> "StaticTexture2D", <||>, ResoniteRealtime`ResoniteRealtimeNewId["TexA"]];
          ids["TexB"] = icComp[screen, $icFE <> "StaticTexture2D", <||>, ResoniteRealtime`ResoniteRealtimeNewId["TexB"]];
          mesh = icComp[screen, $icFE <> "QuadMesh", <||>];
          ids["Material"] = icComp[screen, $icFE <> "UnlitMaterial",
            <|"Texture" -> ResoniteRealtime`ResoniteRealtimeRef[ids["TexA"]]|>, ResoniteRealtime`ResoniteRealtimeNewId["ScrMat"]];
          icComp[screen, $icFE <> "MeshRenderer",
            <|"Mesh" -> ResoniteRealtime`ResoniteRealtimeRef[mesh],
              "Materials" -> <|"$type" -> "list", "elements" -> {ResoniteRealtime`ResoniteRealtimeRef[ids["Material"]]}|>|>];

          (* スピーカー: 音声 2 本 (再生中と控え) + AudioClipPlayer + AudioOutput *)
          spk = icSlot["Speaker", holder, "Position" -> {0., 0., -0.05}];
          ids["Speaker"] = spk;
          ids["ClipA"] = icComp[spk, $icFE <> "StaticAudioClip", <||>, ResoniteRealtime`ResoniteRealtimeNewId["ClipA"]];
          ids["ClipB"] = icComp[spk, $icFE <> "StaticAudioClip", <||>, ResoniteRealtime`ResoniteRealtimeNewId["ClipB"]];
          ids["Player"] = icComp[spk, $icFE <> "AudioClipPlayer",
            <|"Clip" -> ResoniteRealtime`ResoniteRealtimeRef[ids["ClipA"]]|>, ResoniteRealtime`ResoniteRealtimeNewId["Player"]];
          ids["AudioOutput"] = icComp[spk, $icFE <> "AudioOutput",
            <|"Source" -> ResoniteRealtime`ResoniteRealtimeRef[ids["Player"]],
              "Volume" -> N[ResoniteRealtime`$ResonitePresentationVolume], "MinDistance" -> 3., "MaxDistance" -> 60.|>,
            ResoniteRealtime`ResoniteRealtimeNewId["AudioOut"]];
          (* 音量の種類はマルチメディアに (利用者の音量スライダが効く)。名前が合わなければこの 1 通だけ失敗する *)
          ResoniteRealtime`ResoniteRealtimeUpdateComponent[ids["AudioOutput"], <|"AudioTypeGroup" -> itEnum["Multimedia"]|>];

          (* 操作パネル (スクリーンの右、利用者の方へ少し向ける) *)
          If[TrueQ[o["Panel"]],
            proot = icSlot["Control Panel", root, "Position" -> irpPanelPosition[w, 1.],
              "Rotation" -> N[{0, Sin[12.5 Degree], 0, Cos[12.5 Degree]}]];
            ids["PanelRoot"] = proot;
            itBacking[proot, csz*ps];
            panel = icSlot["Panel", proot, "Scale" -> {ps, ps, ps}];
            icComp[panel, $icUIX <> "Canvas", <|"Size" -> N[csz], "AcceptRemoteTouch" -> True, "AcceptPhysicalTouch" -> True|>];
            icMakeMaterials[panel];
            icImage[panel, RGBColor[0.07, 0.08, 0.11, 1]];
            vl = icSlot["VLayout", panel];
            icComp[vl, $icUIX <> "VerticalLayout",
              <|"PaddingTop" -> 22., "PaddingBottom" -> 22., "PaddingLeft" -> 22., "PaddingRight" -> 22.,
                "Spacing" -> 12., "ForceExpandWidth" -> True, "ForceExpandHeight" -> False|>];
            With[{s = icSlot["Title", vl]},
              icLayoutElement[s, fs*1.5, 0];
              itText[s, "Mathematica Presenter", fs*1.15, "Left", "Middle"]];
            (* 発表の選択 *)
            row = irpRow[vl, "DeckRow", bh];
            btn["DeckPrev"] = itButton[row, "DeckPrev", "<", 70, bh, bc, fs];
            ids["DeckText"] = irpRowText[row, "Deck", "発表: -", fs*0.9, "DeckText"];
            btn["DeckNext"] = itButton[row, "DeckNext", ">", 70, bh, bc, fs];
            (* 進行 *)
            row = irpRow[vl, "PlayRow", bh];
            btn["Play"] = itButton[row, "Play", "開始", bw, bh, RGBColor[0.2, 0.45, 0.3, 1], fs];
            btn["Pause"] = itButton[row, "Pause", "一時停止/再開", bw*1.5, bh, bc, fs*0.85];
            btn["Stop"] = itButton[row, "Stop", "停止", bw*0.8, bh, RGBColor[0.5, 0.25, 0.25, 1], fs];
            btn["Prev"] = itButton[row, "Prev", "前へ", bw*0.8, bh, bc, fs];
            btn["Next"] = itButton[row, "Next", "次へ", bw*0.8, bh, bc, fs];
            (* 声と音声応答 *)
            row = irpRow[vl, "VoiceRow", bh];
            btn["Voice"] = itButton[row, "Voice", "声を替える", bw*1.2, bh, bc, fs*0.85];
            ids["VoiceText"] = irpRowText[row, "VoiceName", "声: -", fs*0.9, "VoiceText"];
            row = irpRow[vl, "AnswerRow", bh];
            btn["Answer"] = itButton[row, "Answer", "音声応答", bw*1.2, bh, bc, fs*0.85];
            ids["AnswerText"] = irpRowText[row, "AnswerState", "音声応答: off", fs*0.9, "AnswerText"];
            (* スクリーンの大きさ *)
            row = irpRow[vl, "ScreenRow", bh];
            btn["Smaller"] = itButton[row, "Smaller", "縮小", bw*0.8, bh, bc, fs];
            btn["Larger"] = itButton[row, "Larger", "拡大", bw*0.8, bh, bc, fs];
            ids["ScaleText"] = irpRowText[row, "ScreenSize", "スクリーン: -", fs*0.9, "ScaleText"];
            (* 状態 *)
            With[{s = icSlot["Status", vl]},
              icLayoutElement[s, fs*4, 1];
              ids["StatusText"] = itText[s, "準備ができました", fs*0.85, "Left", "Top",
                ResoniteRealtime`ResoniteRealtimeNewId["Status"]]]];
          <|"Ids" -> ids, "Buttons" -> btn, "Wire" -> $itWireLater, "Size" -> {w, h}|>]],
      icTag];
    If[!AssociationQ[r],
      irpNote["RigBuildFailed", If[FailureQ[r], irpFailText[r], r]];
      $irpRig = None;
      Return[r]];
    $irpRig = Join[$irpRig, r["Ids"],
      <|"Buttons" -> r["Buttons"], "Wire" -> r["Wire"], "Size" -> r["Size"],
        "Phase" -> If[r["Wire"] === {}, "Ready", "Settle"], "Time" -> irpNow[], "Pending" -> None,
        "Front" -> "A", "TexSlide" -> <|"A" -> None, "B" -> None|>,
        "ClipFront" -> "A", "ClipFile" -> <|"A" -> None, "B" -> None|>,
        "PollFailures" -> 0, "WireTries" -> 0, "LastPoll" -> 0., "ScaleIndex" -> irpScaleHome[]|>];
    $irpTexts = <||>;
    irpNote["RigBuilt", $irpRig["Root"]];
    Null];

irpSendPanelPoll[] :=
  Module[{sent},
    If[!StringQ[Lookup[$irpRig, "PanelRoot", None]], Return[Null]];
    sent = Quiet[
      ResoniteRealtime`ResoniteRealtimeGetSlot[$irpRig["PanelRoot"], "Depth" -> -1, "IncludeComponentData" -> True, "Wait" -> False]];
    If[AssociationQ[sent] && StringQ[Lookup[sent, "MessageId", None]],
      $irpRig["Pending"] = sent["MessageId"]; $irpRig["LastPoll"] = irpNow[]];
    Null];

(* ボタンの結線: 応答から ValueField<bool>.Value のメンバ ID を拾い、ButtonToggle を足す *)
irpWire[res_Association] :=
  Module[{left = {}},
    Scan[
      Function[item,
        With[{comp = icFindComponent[res, item["ValueField"]]},
          With[{fid = If[AssociationQ[comp],
              Lookup[Lookup[Lookup[comp, "members", <||>], "Value", <||>], "id", None], None]},
            If[StringQ[fid],
              irpNoWait[icComp[item["Slot"], $icFE <> "ButtonToggle",
                <|"TargetValue" -> ResoniteRealtime`ResoniteRealtimeRef[fid]|>]],
              AppendTo[left, item]]]]],
      $irpRig["Wire"]];
    $irpRig["Wire"] = left;
    $irpRig["WireTries"] = $irpRig["WireTries"] + 1;
    If[left === {} || $irpRig["WireTries"] >= 6,
      If[left =!= {}, irpNote["WireIncomplete", Length[left]]];
      $irpRig["Phase"] = "Ready"];
    Null];

(* 押されたボタンを読み、フラグを戻して動作を予約する *)
irpReadButtons[res_Association] :=
  KeyValueMap[
    Function[{key, vf},
      If[icMemberValue[icFindComponent[res, vf], "Value"] === True,
        irpNoWait[Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateComponent[vf, <|"Value" -> False|>], Null]];
        irpEnqueue[<|"Action" -> "Button", "Key" -> key|>]]],
    $irpRig["Buttons"]];

irpRigTick[] :=
  Module[{rig = $irpRig, now = irpNow[], res, user, head, sent, o},
    If[!AssociationQ[rig], Return[Null]];
    o = rig["Options"];
    Switch[rig["Phase"],
      "PoseRoot",
        res = If[StringQ[rig["Pending"]], icPollReply[rig["Pending"]], None];
        Which[
          AssociationQ[res],
            $irpRig["Candidates"] = irpUserCandidates[res, o["User"]];
            If[!irpAskUserChildren[], irpNote["NoAvatar", "候補なし"]; irpRigBuild[irpRigFallbackPose[]]],
          now - rig["Time"] > 8, irpRigBuild[irpRigFallbackPose[]],
          True, Null],
      "PoseHead",
        res = icPollReply[rig["Pending"]];
        Which[
          AssociationQ[res] || now - rig["Time"] > 6,
            head = If[AssociationQ[res],
              SelectFirst[Replace[Lookup[Lookup[res, "data", <||>], "children", {}], Except[_List] -> {}],
                ToString[irpVal[Lookup[#, "name", ""]]] === "Head" &, None], None];
            Which[
              (* 頭のある slot = アバター。その正面に置く *)
              AssociationQ[head],
                irpNote["Avatar", ToString[irpVal[rig["User"]["name"]]]];
                irpRigBuild[With[{p = irpPoseFrom[rig["User"], head, o["Distance"], o["Height"]]},
                  If[AssociationQ[p], p, irpRigFallbackPose[]]]],
              (* 頭が無い = アバターではない。次の候補へ。尽きたら "Position" の場所に置く *)
              irpAskUserChildren[], Null,
              True, irpNote["NoAvatar", "頭のある候補なし"]; irpRigBuild[irpRigFallbackPose[]]],
          True, Null],
      "Settle",
        (* 組み立ての応答 (100 件余り) が流れ切るのを待ってから結線用の getSlot を送る *)
        If[now - rig["Time"] > 1.5, $irpRig["Phase"] = "Wire"; irpSendPanelPoll[]],
      "Wire",
        res = If[StringQ[rig["Pending"]], icPollReply[rig["Pending"]], None];
        Which[
          AssociationQ[res] && Lookup[res, "success", True] =!= False,
            $irpRig["Pending"] = None; irpWire[res];
            If[$irpRig["Phase"] === "Wire", irpSendPanelPoll[]],
          AssociationQ[res] || now - rig["LastPoll"] > 8,
            $irpRig["Pending"] = None; $irpRig["WireTries"] = rig["WireTries"] + 1;
            If[$irpRig["WireTries"] >= 6, $irpRig["Phase"] = "Ready", irpSendPanelPoll[]],
          True, Null],
      "Ready",
        If[StringQ[Lookup[rig, "PanelRoot", None]],
          If[StringQ[rig["Pending"]],
            res = icPollReply[rig["Pending"]];
            Which[
              AssociationQ[res] && Lookup[res, "success", True] =!= False,
                $irpRig["Pending"] = None; $irpRig["PollFailures"] = 0; irpReadButtons[res],
              AssociationQ[res] || now - rig["LastPoll"] > 8,
                $irpRig["Pending"] = None;
                $irpRig["PollFailures"] = rig["PollFailures"] + 1;
                (* パネルがワールドから消された (応答が失敗) *)
                If[AssociationQ[res] && $irpRig["PollFailures"] >= 3,
                  irpNote["RigLost", Lookup[res, "errorInfo", None]];
                  irpHalt["スクリーンがワールドから消えました"]; $irpRig = None],
              True, Null],
            If[now - rig["LastPoll"] > $irpPanelPollSeconds, irpSendPanelPoll[]]]],
      _, Null];
    Null];

(* ---- スクリーンとスピーカーへの書き込み (待たない) ---- *)

irpOther["A"] = "B"; irpOther["B"] = "A";

(* 控えに資産を読み込ませる (kind = "Tex" | "Clip")。読み込ませたら True、資産がまだなら False。
   読み込ませた時刻を覚えておき、表へ出すのは次の tick 以降にする (同じ tick で切り替えると、読み込みの間だけ空になる) *)
$irpLoadSettle = 0.35;

irpLoadBack[kind_String, file_String, assetKind_String] :=
  Module[{slotKey = If[kind === "Tex", "TexSlide", "ClipFile"], frontKey = If[kind === "Tex", "Front", "ClipFront"], back, url},
    back = irpOther[$irpRig[frontKey]];
    If[$irpRig[slotKey][back] === file, Return[True]];
    url = irpEnsureImport[assetKind, file];
    If[!StringQ[url], Return[False]];
    irpNoWait[ResoniteRealtime`ResoniteRealtimeUpdateComponent[$irpRig[kind <> back],
      <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", url]|>]];
    $irpRig[slotKey] = Join[$irpRig[slotKey], <|back -> file|>];
    $irpRig[kind <> "SetAt"] = irpNow[];
    True];

irpBackSettledQ[kind_String] := irpNow[] - Lookup[$irpRig, kind <> "SetAt", 0.] >= $irpLoadSettle;

(* k 枚目を映す。画像がまだ用意できていなければ False (次の tick でもう一度呼ぶ) *)
irpShowSlide[k_Integer] :=
  Module[{file, front, back},
    If[!irpRigBuiltQ[] || !(1 <= k <= Length[$irpPlay["Slides"]]), Return[False]];
    file = $irpPlay["Slides"][[k]];
    front = $irpRig["Front"]; back = irpOther[front];
    If[$irpRig["TexSlide"][front] === file, Return[True]];
    If[!irpLoadBack["Tex", file, "Texture"] || !irpBackSettledQ["Tex"], Return[False]];
    irpNoWait[ResoniteRealtime`ResoniteRealtimeUpdateComponent[$irpRig["Material"],
      <|"Texture" -> ResoniteRealtime`ResoniteRealtimeRef[$irpRig["Tex" <> back]]|>]];
    $irpRig["Front"] = back;
    True];

(* 次の枚を控えの画像に読み込んでおく (切り替えが一瞬で済む) *)
irpPreloadSlide[k_Integer] :=
  If[irpRigBuiltQ[] && 1 <= k <= Length[$irpPlay["Slides"]] &&
      $irpRig["TexSlide"][$irpRig["Front"]] =!= $irpPlay["Slides"][[k]],
    irpLoadBack["Tex", $irpPlay["Slides"][[k]], "Texture"]; Null];

irpPlayback[play : (True | False), position_?NumericQ] :=
  irpNoWait[ResoniteRealtime`ResoniteRealtimeUpdateComponent[$irpRig["Player"],
    <|"playback" -> <|"$type" -> "playback", "play" -> play, "loop" -> False,
      "position" -> N[Max[0., position]], "speed" -> 1.|>|>]];

(* 音声ファイルをスピーカーで鳴らす。資産がまだ用意できていなければ False (次の tick でもう一度呼ぶ) *)
irpPlayClip[file_String] :=
  Module[{front, back},
    If[!irpRigBuiltQ[], Return[False]];
    front = $irpRig["ClipFront"]; back = irpOther[front];
    If[$irpRig["ClipFile"][front] =!= file,
      If[!irpLoadBack["Clip", file, "Audio"] || !irpBackSettledQ["Clip"], Return[False]];
      irpNoWait[ResoniteRealtime`ResoniteRealtimeUpdateComponent[$irpRig["Player"],
        <|"Clip" -> ResoniteRealtime`ResoniteRealtimeRef[$irpRig["Clip" <> back]]|>]];
      $irpRig["ClipFront"] = back];
    irpPlayback[True, 0.];
    True];

irpPreloadClip[file_String] :=
  If[irpRigBuiltQ[] && FileExistsQ[file] && $irpRig["ClipFile"][$irpRig["ClipFront"]] =!= file,
    irpLoadBack["Clip", file, "Audio"]; Null];

irpSetText[key_String, text_String] :=
  If[irpRigBuiltQ[] && StringQ[Lookup[$irpRig, key, None]] && Lookup[$irpTexts, key, None] =!= text,
    $irpTexts[key] = text;
    irpNoWait[Quiet @ Check[
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[$irpRig[key], <|"Content" -> text|>], Null]]];

(* ============================================================
   音声ブリッジ (SourceVault の音声会話) と、声での操作
   ============================================================ *)

irpBridgeStatus[] :=
  If[irpCloudLayerQ[], Replace[Quiet[SourceVault`SourceVaultRealtimeStatus[]], Except[_Association] -> <||>], <||>];

irpBridgeRunningQ[st_Association] := TrueQ[Lookup[st, "Running", False]];

(* 話しかけに応じている最中か (この間はスクリーンの読み上げを待たせる) *)
irpBridgeBusyQ[st_Association] :=
  irpBridgeRunningQ[st] &&
    (MemberQ[{"thinking", "answering"}, Lookup[st, "Mode", None]] ||
      (TrueQ[Lookup[st, "Speaking", False]] && Lookup[st, "Mode", None] =!= "narrating"));

irpBridgeInstructions[] :=
  With[{base = If[StringQ[SourceVault`$SourceVaultRealtimeInstructions], SourceVault`$SourceVaultRealtimeInstructions, ""]},
    base <> "\n" <>
    "あなたは Resonite のワールドの中でスライド発表を手伝う司会役です。役割は、渡された原稿の読み上げと、聞き手からの質問への応答です。" <>
    "自分からは話し始めず、相手が何語で話しても日本語で答えてください。\n" <>
    "発表の操作を頼まれたら、頼まれた文をそのまま資料の問い合わせ (ask_sourcevault) に渡してください: " <>
    "発表の開始 (「計算と自然31の発表を始めて」)、一時停止、再開、終了、声の切り替え (「声をほのかに変えて」)、発表の一覧。" <>
    "スライドの移動 (次、前、最初、最後、番号、題名) は show_slide を使ってください。" <>
    "それ以外の質問は資料を引いて短く答えてください。"];

irpInstallHandlers[] :=
  If[!TrueQ[$irpHandlersInstalled],
    $irpPrevSlideHandler = SourceVault`$SourceVaultRealtimeSlideHandler;
    $irpPrevAskHandler = SourceVault`$SourceVaultRealtimeAskHandler;
    SourceVault`$SourceVaultRealtimeSlideHandler = ResoniteRealtime`Private`irpSlideHandler;
    SourceVault`$SourceVaultRealtimeAskHandler = ResoniteRealtime`Private`irpAskHandler;
    $irpHandlersInstalled = True];

irpRestoreHandlers[] :=
  If[TrueQ[$irpHandlersInstalled],
    If[SourceVault`$SourceVaultRealtimeSlideHandler === ResoniteRealtime`Private`irpSlideHandler,
      SourceVault`$SourceVaultRealtimeSlideHandler = $irpPrevSlideHandler];
    If[SourceVault`$SourceVaultRealtimeAskHandler === ResoniteRealtime`Private`irpAskHandler,
      SourceVault`$SourceVaultRealtimeAskHandler = $irpPrevAskHandler];
    $irpHandlersInstalled = False];

irpBridgeVoice[] :=
  With[{v = irpResolveVoice[Automatic], cs = irpCloudVoiceNames[]},
    Which[
      AssociationQ[v] && v["Engine"] === "Cloud", v["Voice"],
      cs =!= {}, First[cs],
      True, Automatic]];

(* 音声ブリッジを起こす (最大 4 秒ほど待つ)。ノートブックの有料 API 許可を使う *)
irpBridgeStart[] :=
  Module[{st = irpBridgeStatus[], nb = $irpControlNotebook, res},
    If[!irpCloudLayerQ[],
      Return[irpFail["VoiceBridgeUnavailable", "音声ブリッジ (SourceVault_realtime.wl) が読み込まれていません。"]]];
    If[irpBridgeRunningQ[st], irpInstallHandlers[]; Return[<|"Status" -> "AlreadyRunning"|>]];
    irpInstallHandlers[];
    (* 成否は返り値の形で決める (メッセージが出ただけで「起動できなかった」とすると、動いているブリッジを持ち主なしで残す) *)
    res = Quiet[
      SourceVault`SourceVaultRealtimeStart[
        "Model" -> irpVoiceModel[], "Voice" -> irpBridgeVoice[],
        "Notebook" -> If[Head[nb] === NotebookObject, nb, None],
        "RequirePaidAPIApproval" -> TrueQ[ResoniteRealtime`$ResonitePresentationRequirePaidAPIApproval],
        "Instructions" -> irpBridgeInstructions[],
        (* マイクは閉じたまま起こす。読み上げだけのとき (音声応答 off) はマイクの音を送らない。
           音声応答を on にする側 (ResonitePresentationVoiceControl / パネル) が起動後に開ける *)
        "StartMuted" -> True,
        "InputDevice" -> ResoniteRealtime`$ResonitePresentationInputDevice,
        "OutputDevice" -> ResoniteRealtime`$ResonitePresentationOutputDevice]];
    If[FailureQ[res] || !AssociationQ[res],
      irpRestoreHandlers[];
      irpNote["BridgeStartFailed", irpFailText[res]];
      Return[If[FailureQ[res], res, irpFail["VoiceBridgeStartFailed", "音声ブリッジを起動できませんでした。"]]]];
    $irpBridgeOwned = True;
    irpNote["BridgeStarted", KeyTake[res, {"Model", "Voice", "API"}]];
    res];

irpBridgeStop[] := (
  If[irpCloudLayerQ[] && TrueQ[$irpBridgeOwned], Quiet @ Check[SourceVault`SourceVaultRealtimeStop[], Null]];
  $irpBridgeOwned = False; $irpAnswering = False;
  irpRestoreHandlers[];
  irpNote["BridgeStopped"]; Null);

irpRememberNotebook[] :=
  If[TrueQ[$Notebooks] && !irpTaskContextQ[],
    With[{nb = Quiet[EvaluationNotebook[]]},
      If[Head[nb] === NotebookObject, $irpControlNotebook = nb]]];

ResoniteRealtime`ResonitePresentationVoiceControl[] :=
  ResoniteRealtime`ResonitePresentationVoiceControl[!TrueQ[$irpAnswering]];

ResoniteRealtime`ResonitePresentationVoiceControl[True] :=
  Module[{r},
    irpRememberNotebook[];
    irpWarmVoices[];
    r = irpBridgeStart[];
    If[FailureQ[r], irpMessage["音声応答を始められません: " <> irpFailText[r]]; irpRefreshLabel[]; Return[r]];
    $irpAnswering = True;
    Quiet @ Check[SourceVault`SourceVaultRealtimeMute[False], Null];
    irpEnsureTask[];
    irpRefreshLabel[];
    <|"Answering" -> True, "Bridge" -> r|>];

ResoniteRealtime`ResonitePresentationVoiceControl[False] := (
  $irpAnswering = False;
  (* 発表がクラウドの声で読んでいる最中はブリッジを止めず、マイクだけ閉じる *)
  If[$irpPlay["Status"] === "Playing" && $irpPlay["Route"] === "Live",
    Quiet @ Check[SourceVault`SourceVaultRealtimeMute[True], Null],
    irpBridgeStop[]];
  irpRefreshLabel[];
  <|"Answering" -> False|>);

(* ---- 声からのスライド移動 (show_slide) ---- *)

irpActiveQ[] := MemberQ[{"Starting", "Ready", "Playing", "Paused", "Finished"}, $irpPlay["Status"]] && $irpPlay["Last"] >= 1;

irpFindSlide[word_String] :=
  Module[{w = StringTrim[StringReplace[word, {"のスライド" -> "", "スライド" -> "", "の枚" -> ""}]], hit},
    If[w === "", Return[None]];
    hit = SelectFirst[Keys[$irpPlay["Titles"]], StringContainsQ[$irpPlay["Titles"][#], w, IgnoreCase -> True] &, None];
    If[hit === None,
      hit = SelectFirst[Sort[Keys[$irpPlay["Texts"]]], StringContainsQ[$irpPlay["Texts"][#], w, IgnoreCase -> True] &, None]];
    hit];

irpSlideHandler[req_Association] :=
  Module[{target, cur, k, n},
    (* 止めたあとも、発表を読み込んであってスクリーンがあれば、声でもスライドは送れる (ボタンと同じ扱い。読まずに映すだけ) *)
    If[!irpActiveQ[] && !(irpDeckLoadedQ[] && irpRigBuiltQ[]),
      Return[If[TrueQ[$irpHandlersInstalled] && $irpPrevSlideHandler =!= None &&
          $irpPrevSlideHandler =!= ResoniteRealtime`Private`irpSlideHandler,
        $irpPrevSlideHandler[req],
        <|"status" -> "error", "message" -> "発表が始まっていません。「題名の発表を始めて」と頼んでください。"|>]]];
    cur = $irpPlay["Slide"];
    target = ToLowerCase[ToString[Lookup[req, "target", ""]]];
    n = Lookup[req, "number", None];
    k = Switch[target,
      "next", cur + 1, "previous", cur - 1, "first", $irpPlay["First"], "last", $irpPlay["Last"],
      "number", If[NumericQ[n], Round[n], With[{x = StringTrim[ToString[n]]}, If[StringMatchQ[x, DigitCharacter ..], FromDigits[x], None]]],
      "title", irpFindSlide[ToString[Lookup[req, "title", ""]]],
      _, None];
    If[!IntegerQ[k] || k < $irpPlay["First"] || k > $irpPlay["Last"],
      Return[<|"status" -> "error", "message" -> "そのスライドはありません (" <> ToString[$irpPlay["First"]] <> " から " <>
        ToString[$irpPlay["Last"]] <> " まで)。"|>]];
    irpEnqueue[<|"Action" -> "GoTo", "Slide" -> k|>];
    <|"status" -> "ok", "slide" -> k, "title" -> Lookup[$irpPlay["Titles"], k, ""]|>];

(* ---- 声からの発表の操作 (資料の問い合わせに来た文のうち、操作の依頼を先に拾う) ---- *)

irpHas[q_String, words__String] := StringContainsQ[q, Alternatives[words]];

irpParseCommand[q0_String] :=
  Module[{q = StringTrim[StringReplace[q0, {"\:3000" -> " ", "\n" -> " "}]], talk},
    talk = irpHas[q, "発表", "プレゼン"];
    (* 質問 (「この発表について説明して」「発表はいつ終わりますか」) を操作と取り違えないよう、頼む形の言い方だけを拾う *)
    Which[
      talk && irpHas[q, "一覧", "リスト", "どんな発表", "何がある", "何があります"], <|"Command" -> "List"|>,
      (talk || irpHas[q, "スライド", "読み上げ"]) && irpHas[q, "一時停止", "中断して", "ポーズ", "いったん止"], <|"Command" -> "Pause"|>,
      irpHas[q, "再開"] && (talk || irpHas[q, "スライド", "読み上げ"] || MemberQ[{"Paused", "Ready"}, $irpPlay["Status"]]), <|"Command" -> "Resume"|>,
      irpHas[q, "続けて", "続きを", "続きから"] && MemberQ[{"Paused", "Ready"}, $irpPlay["Status"]], <|"Command" -> "Resume"|>,
      talk && irpHas[q, "終了して", "を終了", "発表終了", "プレゼン終了", "終わりにして", "終わらせて", "終わって", "やめて",
        "止めて", "中止", "打ち切", "ストップ"], <|"Command" -> "Stop"|>,
      irpHas[q, "声", "ボイス", "ナレーション", "ナレーター"] && irpHas[q, "変え", "替え", "切り替え", "切替", "にして", "に戻"],
        <|"Command" -> "Voice", "Query" -> q|>,
      talk && (irpHas[q, "始め", "開始", "スタート"] ||
          StringContainsQ[q, ("発表" | "プレゼン") ~~ ("" | "を") ~~ ("して" | "お願い" | "やって" | "見せて" | "流して")]),
        <|"Command" -> "Start", "Query" -> q|>,
      True, None]];

(* 「計算と自然31の発表を始めて」から題名の部分を取り出す *)
irpTitleOfQuery[q_String] :=
  Module[{m},
    m = StringCases[q, StartOfString ~~ Shortest[t__] ~~ ("の" | "を" | "") ~~ ("発表" | "プレゼン") :> t, 1];
    m = If[m === {}, "", StringTrim[First[m]]];
    (* 題名が後ろに来る言い方 (「発表を始めて、計算と自然の 31」) は、操作の語を落とした残り *)
    If[StringLength[m] < 2,
      m = StringTrim @ StringReplace[q, {"発表" -> " ", "プレゼンテーション" -> " ", "プレゼン" -> " ", "を始めて" -> " ", "始めて" -> " ",
        "開始して" -> " ", "開始" -> " ", "スタート" -> " ", "お願いします" -> " ", "お願い" -> " ", "ください" -> " ",
        "してください" -> " ", "して" -> " ", "、" -> " ", "。" -> " ", "の" -> " ", "を" -> " "}]];
    StringTrim[StringReplace[m, {"「" -> "", "」" -> "", "『" -> "", "』" -> "", "\"" -> "", Whitespace -> " "}]]];

(* 文に出てくる声を選ぶ。呼び名が重なるとき (シダ / シダー) は長く一致した方 *)
irpVoiceOfQuery[q_String] :=
  Module[{names = irpVoiceNames[], scores, best},
    scores = Map[
      Function[n,
        With[{bare = If[StringStartsQ[n, "realtime:"], StringDrop[n, 9], irpVoiceShort[n]]},
          Max[0, StringLength /@ Select[Prepend[Lookup[$irpVoiceAliases, ToLowerCase[bare], {}], bare],
            StringContainsQ[q, #, IgnoreCase -> True] &]]]], names];
    best = If[names === {} || Max[scores] === 0, None, names[[First[Ordering[scores, -1]]]]];
    If[best === None && irpHas[q, "ローカル"],
      best = SelectFirst[names, !StringStartsQ[#, "realtime:"] &, None]];
    best];

irpAnswer[text_String] := <|"status" -> "ok", "answer" -> text, "route" -> "resonite-presenter", "needWeb" -> False|>;

(* 声で言われた題名が、いまの発表の題名か (空白の有無は見ない。一部でもよい) *)
irpSameTitleQ[said_String, title_String] :=
  With[{a = StringDelete[said, Whitespace], b = StringDelete[title, Whitespace]},
    a =!= "" && b =!= "" && (StringContainsQ[b, a, IgnoreCase -> True] || StringContainsQ[a, b, IgnoreCase -> True])];

irpRunCommand[cmd_Association] :=
  Module[{title, r, v, list},
    Switch[cmd["Command"],
      "List",
        list = irpDeckTitles[];
        irpAnswer[If[list === {}, "登録されている発表はありません。",
          "始められる発表は " <> ToString[Length[list]] <> " 件です: " <> StringRiffle[Take[list, UpTo[12]], "、"] <> "。"]],
      "Pause", irpEnqueue[<|"Action" -> "Pause"|>]; irpAnswer["発表を一時停止します。"],
      "Resume", irpEnqueue[<|"Action" -> "Resume"|>]; irpAnswer["発表を再開します。"],
      "Stop", irpEnqueue[<|"Action" -> "Stop"|>]; irpAnswer["発表を終了します。"],
      "Voice",
        v = irpVoiceOfQuery[cmd["Query"]];
        If[!StringQ[v],
          (* 一覧に無い声。ローカルの声のエンジンが止まっているのかもしれない: 待たずに起こしておく *)
          irpAnswer[
            If[irpWakeLocalVoices[False] === "Starting",
              "ローカルの声を起動しています。1、2 分してから、もう一度言ってください。いま選べる声は ",
              "その声は見つかりません。選べる声は "] <>
            StringRiffle[irpVoiceShort /@ (StringReplace[#, "realtime:" -> ""] & /@ irpVoiceNames[]), "、"] <> " です。"],
          r = ResoniteRealtime`ResonitePresentationSetVoice[v];
          irpAnswer[If[FailureQ[r], "声を切り替えられませんでした。" <> irpFailText[r],
            "読み上げの声を " <> irpVoiceShort[StringReplace[v, "realtime:" -> ""]] <> " にしました。次のスライドから変わります。"]]],
      "Start",
        title = irpTitleOfQuery[cmd["Query"]];
        (* 開始待ち・一時停止中の発表を「始めて」: 映っている枚から読み始める (題名を言わないか、その発表の題名のとき) *)
        If[MemberQ[{"Ready", "Paused"}, $irpPlay["Status"]] && (StringLength[title] < 2 || irpSameTitleQ[title, $irpPlay["Title"]]),
          irpEnqueue[<|"Action" -> "Resume"|>];
          Return[irpAnswer["「" <> $irpPlay["Title"] <> "」の発表を始めます。"]]];
        If[StringLength[title] < 2, title = Replace[irpSelectedTitle[], None -> ""]];
        If[title === "", Return[irpAnswer["どの発表を始めるか、題名を言ってください。"]]];
        (* スクリーンがもう置いてあれば、すぐ読み始める。これから置くときは、位置を決める時間のために開始待ちで止まる *)
        r = irpStartRequest[title, <|"AutoStart" -> irpRigBuiltQ[]|>];
        irpAnswer[Which[
          FailureQ[r],
            "発表を始められません。" <> irpFailText[r] <>
              With[{av = Quiet @ Check[r["Available"], {}]}, If[ListQ[av] && av =!= {}, " 登録されているのは " <> StringRiffle[Take[av, UpTo[8]], "、"] <> " です。", ""]],
          TrueQ[r["AutoStart"]], "「" <> r["Title"] <> "」の発表を始めます。",
          True, "「" <> r["Title"] <> "」を用意します。スクリーンの位置を決めたら、パネルの開始を押すか、もう一度「始めて」と言ってください。"]],
      _, irpAnswer["その操作はできません。"]]];

irpAskHandler[req_Association] :=
  Module[{q = ToString[Lookup[req, "query", ""]], cmd},
    cmd = irpParseCommand[q];
    If[AssociationQ[cmd],
      irpNote["VoiceCommand", <|"Command" -> cmd["Command"], "Query" -> q|>];
      Return[irpRunCommand[cmd]]];
    If[TrueQ[$irpHandlersInstalled] && $irpPrevAskHandler =!= None &&
        $irpPrevAskHandler =!= ResoniteRealtime`Private`irpAskHandler,
      $irpPrevAskHandler[req],
      <|"status" -> "error", "message" -> "資料を引ける相手がいません。"|>]];

(* ============================================================
   発表の進行
   ============================================================ *)

(* 開始の受付 (ノートブック / パネル / 声 のどこからでも)。確かめて、スライドを用意し、開始を予約する *)
irpStartRequest[target_String, o_Association] :=
  Module[{spec, deck, voice, n, first, last, talk},
    If[!irpLinkQ[],
      Return[irpFail["NotConnected", "ResoniteLink に繋がっていません。ResoniteRealtimeLinkConnect[] を先に実行してください。"]]];
    spec = irpResolveSpec[target];
    If[FailureQ[spec], Return[spec]];
    If[!irpDisplayAllowedQ[Lookup[spec, "privacyLevel", 1.]],
      Return[irpFail["WorldAccessDenied",
        "この発表の機密度 (" <> ToString[Lookup[spec, "privacyLevel", 1.]] <> ") は、いまのワールドの表示上限 (" <>
          ToString[ResoniteRealtime`ResoniteAccessLevel[]] <> ") 以上なので出せません。"]]];
    voice = irpResolveVoice[Lookup[o, "Voice", Automatic]];
    If[FailureQ[voice], Return[voice]];
    (* AivisSpeech の声: 一覧を聞いた後でエンジンが止まっていることがある。読み始める前に起こしておく
       (ノートブックからなら応答するまで待つ。ワールドのパネル・声からなら待たずに起こし、その枚は音声ができるまで待つ) *)
    If[irpAivisQ[voice],
      If[irpTaskContextQ[],
        If[!TrueQ[Lookup[$irpState, "AivisUp", False]], irpAivisKick[]],
        With[{st = irpAivisEnsure[]},
          If[st =!= "Running",
            Return[irpFail["VoiceUnavailable",
              "ローカルの声のエンジン (AivisSpeech) が動いていません" <> Replace[irpWakeHint[st], "" -> "。"],
              <|"Voice" -> voice["Name"], "LocalEngine" -> st|>]]]]]];
    irpMessage["スライドを用意しています: " <> ToString[spec["title"]]];
    deck = irpPrepareDeck[spec];
    If[FailureQ[deck], irpMessage[irpFailText[deck]]; Return[deck]];
    n = Length[deck["Slides"]];
    first = With[{s = Lookup[o, "StartSlide", Automatic]},
      If[IntegerQ[s], s, With[{t = Lookup[spec, "startSlide", 1]}, If[IntegerQ[t], t, 1]]]];
    last = With[{s = Lookup[o, "EndSlide", Automatic]},
      If[IntegerQ[s], s, With[{t = Lookup[spec, "endSlide", Null]}, If[IntegerQ[t], t, n]]]];
    first = Clip[first, {1, n}]; last = Clip[last, {first, n}];
    talk = irpTalkOf[spec, first, last];
    If[Lookup[o, "Voice", Automatic] =!= Automatic, ResoniteRealtime`$ResonitePresentationVoice = voice["Name"]];
    irpEnqueue[<|"Action" -> "Begin", "Spec" -> KeyDrop[spec, "talk"], "Deck" -> deck, "First" -> first, "Last" -> last,
      "Texts" -> talk["Texts"], "Titles" -> talk["Titles"], "Presenter" -> Lookup[o, "Presenter", {}],
      "AutoStart" -> TrueQ[Lookup[o, "AutoStart", False]]|>];
    irpEnsureTask[];
    <|"Status" -> "Starting", "Title" -> ToString[spec["title"]], "Slides" -> n, "First" -> first, "Last" -> last,
      "Scripted" -> (Length[talk["Texts"]] > 0), "Voice" -> voice["Name"], "AutoStart" -> TrueQ[Lookup[o, "AutoStart", False]]|>];

irpBegin[a_Association] :=
  Module[{},
    irpStopAudio[];
    $irpPlay = Join[$irpIdlePlay, <|
      "Status" -> "Starting", "Spec" -> a["Spec"], "Title" -> ToString[a["Spec"]["title"]],
      "Directory" -> a["Deck"]["Directory"], "Slides" -> a["Deck"]["Slides"], "Count" -> Length[a["Deck"]["Slides"]],
      "First" -> a["First"], "Last" -> a["Last"], "Slide" -> a["First"], "Texts" -> a["Texts"], "Titles" -> a["Titles"],
      "Run" -> Lookup[$irpPlay, "Run", 0] + 1, "Phase" -> None, "Route" -> None, "Since" -> irpNow[],
      "AutoStart" -> TrueQ[Lookup[a, "AutoStart", False]],
      "Message" -> "発表を準備しています"|>];
    If[!irpRigQ[], irpRigStart[irpRigOptions[Sequence @@ Flatten[{a["Presenter"]}]]]];
    (* 質問には、この発表の資料で答える *)
    Quiet @ Check[
      If[TrueQ[$irpAnswering] && irpCloudLayerQ[] && Length[$irpPlay["Texts"]] > 0,
        SourceVault`SourceVaultRealtimeAddContext[irpDeckContext[]]], Null];
    irpNote["Begin", <|"Title" -> $irpPlay["Title"], "First" -> a["First"], "Last" -> a["Last"]|>];
    Null];

(* 質問に答えるときの背景: 題名と各枚の原稿 (長すぎる分は切る) *)
irpDeckContext[] :=
  StringTake[
    "いまの発表: " <> $irpPlay["Title"] <> "\n" <>
      StringRiffle[
        KeyValueMap["スライド " <> ToString[#1] <> ": " <> #2 &, KeySort[$irpPlay["Texts"]]], "\n"],
    UpTo[6000]];

irpSlideText[k_Integer] := Lookup[$irpPlay["Texts"], k, ""];

(* いま選ばれている声 (tick が何度も引くので、設定が変わるまで 10 秒は覚えておく) *)
irpCurrentVoice[] :=
  Module[{key = {ResoniteRealtime`$ResonitePresentationVoice, irpVoiceModel[]}, c = Lookup[$irpState, "CurVoice", None], v},
    If[AssociationQ[c] && c["Key"] === key && irpNow[] - c["Time"] < 10, Return[c["Value"]]];
    v = irpResolveVoice[Automatic];
    v = If[AssociationQ[v], v, None];
    $irpState["CurVoice"] = <|"Key" -> key, "Time" -> irpNow[], "Value" -> v|>;
    v];

(* k 枚目の読み方を決める: <|"Route" -> "Silent"|"World"|"Live"|"WaitAudio"|"Skip", "File"|> *)
irpRouteFor[k_Integer] :=
  Module[{text = irpSlideText[k], v = irpCurrentVoice[], file, route = ResoniteRealtime`$ResonitePresentationAudioRoute},
    If[text === "" || v === None, Return[<|"Route" -> "Silent"|>]];
    file = irpAudioFile[$irpPlay["Directory"], v, k, text];
    Which[
      FileExistsQ[file] && irpWavSeconds[file] > 0.2 && (v["Engine"] === "Local" || route =!= "Live"),
        <|"Route" -> "World", "File" -> file|>,
      v["Engine"] === "Local", <|"Route" -> "WaitAudio", "File" -> file|>,
      route === "World", <|"Route" -> "Skip", "File" -> file|>,
      True, <|"Route" -> "Live", "File" -> file|>]];

(* ローカルの声で、これから読む枚の音声が無ければ合成を頼む (今の枚と次の 2 枚まで) *)
irpSynthAhead[] :=
  Module[{v = irpCurrentVoice[], k, text, file},
    If[irpSynthBusyQ[] || v === None || v["Engine"] =!= "Local" || !MemberQ[{"Starting", "Ready", "Playing", "Paused"}, $irpPlay["Status"]],
      Return[Null]];
    (* 失敗の直後と、エンジンが立ち上がる途中は頼まない *)
    If[irpNow[] < Lookup[$irpState, "SynthRetryAt", 0] || (irpAivisQ[v] && irpAivisStartingQ[]), Return[Null]];
    k = SelectFirst[Range[$irpPlay["Slide"], Min[$irpPlay["Slide"] + 2, $irpPlay["Last"]]],
      (text = irpSlideText[#]; text =!= "" && !FileExistsQ[irpAudioFile[$irpPlay["Directory"], v, #, text]]) &, None];
    If[IntegerQ[k],
      text = irpSlideText[k]; file = irpAudioFile[$irpPlay["Directory"], v, k, text];
      irpSynthStart[v, k, text, file]];
    Null];

irpStopAudio[] := (
  If[irpRigBuiltQ[] && $irpPlay["Route"] === "World", irpPlayback[False, 0.]];
  If[$irpPlay["Route"] === "Live" && irpCloudLayerQ[], Quiet @ Check[SourceVault`SourceVaultRealtimeCancel[], Null]];
  Null);

(* k 枚目を始める (画像と音声がそろうまで "WaitAssets" で待つ) *)
irpBeginSlide[k_Integer] :=
  ($irpPlay = Join[$irpPlay, <|"Status" -> "Playing", "Slide" -> k, "Phase" -> "WaitAssets", "Route" -> None,
     "PhaseSince" -> irpNow[], "Shown" -> False, "Hold" -> False, "Played" -> 0., "Duration" -> 0., "Message" -> ""|>];
   Quiet @ Check[
     If[Length[DownValues[SourceVault`SourceVaultTalkQASetSlide]] > 0, SourceVault`SourceVaultTalkQASetSlide[k]], Null];
   irpTryBeginSlide[irpBridgeStatus[]]);

irpTryBeginSlide[st_Association] :=
  Module[{k = $irpPlay["Slide"], now = irpNow[], r, text, id, rec},
    If[!irpRigBuiltQ[], Return[Null]];
    If[!TrueQ[$irpPlay["Shown"]],
      If[!irpShowSlide[k],
        If[now - $irpPlay["PhaseSince"] > 45, irpHalt["スライド画像を取り込めませんでした"]];
        Return[Null]];
      $irpPlay["Shown"] = True;
      irpPreloadSlide[k + 1]];
    (* 話しかけに応じている間は読み始めない *)
    If[irpBridgeBusyQ[st], Return[Null]];
    r = irpRouteFor[k];
    Switch[r["Route"],
      "Silent" | "Skip",
        $irpPlay = Join[$irpPlay, <|"Phase" -> "Narrating", "Route" -> "Silent", "SegmentStart" -> now, "Duration" -> $irpSilentSeconds|>],
      "World",
        If[irpPlayClip[r["File"]],
          $irpPlay = Join[$irpPlay, <|"Phase" -> "Narrating", "Route" -> "World", "File" -> r["File"],
            "SegmentStart" -> now, "Played" -> 0., "Duration" -> irpWavSeconds[r["File"]] + 0.3|>];
          (* スピーカーの音をマイクが拾う環境では、読み上げの間マイクを閉じる (質問の時間に開け直す) *)
          If[TrueQ[$irpAnswering] && !TrueQ[ResoniteRealtime`$ResonitePresentationListenWhileNarrating] && irpBridgeRunningQ[st],
            Quiet @ Check[SourceVault`SourceVaultRealtimeMute[True], Null]];
          irpNote["Play", <|"Slide" -> k, "Route" -> "World", "Seconds" -> $irpPlay["Duration"]|>],
          If[now - $irpPlay["PhaseSince"] > 60, irpHalt["音声を取り込めませんでした"]]],
      "WaitAudio",
        If[now - $irpPlay["PhaseSince"] > 240,
          (* 合成が来ない: この枚は黙って見せて先へ進む *)
          irpNote["AudioTimeout", k];
          $irpPlay = Join[$irpPlay, <|"Phase" -> "Narrating", "Route" -> "Silent", "SegmentStart" -> now, "Duration" -> $irpSilentSeconds|>]],
      "Live",
        If[!irpBridgeRunningQ[st],
          With[{b = irpBridgeStart[]},
            If[FailureQ[b], Return[irpHalt["クラウドの声で読めません: " <> irpFailText[b]]]]];
          Return[Null]];
        If[!TrueQ[Lookup[st, "Connected", False]],
          If[now - $irpPlay["PhaseSince"] > 40, irpHalt["音声ブリッジが接続できませんでした"]];
          Return[Null]];
        text = irpSlideText[k];
        id = "rp-" <> ToString[$irpPlay["Run"]] <> "-" <> ToString[k] <> "-" <> ToString[Round[now*10]];
        rec = r["File"] <> ".rec.wav";
        Quiet @ CreateDirectory[DirectoryName[rec], CreateIntermediateDirectories -> True];
        Quiet[DeleteFile[rec]];
        (* 読み上げ中はマイクを閉じる (自分の声で応答が始まらないように) *)
        Quiet @ Check[SourceVault`SourceVaultRealtimeMute[True], Null];
        Quiet @ Check[
          SourceVault`SourceVaultRealtimeNarrate[id, text, "Heading" -> "スライド " <> ToString[k], "Slide" -> k,
            "Instructions" -> ToString[Lookup[$irpPlay["Spec"], "narrationInstructions", ""]], "RecordFile" -> rec], Null];
        $irpPlay = Join[$irpPlay, <|"Phase" -> "Narrating", "Route" -> "Live", "NarrationId" -> id, "RecordFile" -> rec,
          "File" -> r["File"], "SegmentStart" -> now, "Duration" -> StringLength[text]/3.5 + 60.|>];
        irpNote["Play", <|"Slide" -> k, "Route" -> "Live"|>],
      _, Null];
    Null];

(* クラウドの声で読んだ録音を取っておく (途中で切れた録音は捨てる: 原稿を毎秒 7 文字で読んだ長さの 55% に満たない) *)
irpKeepRecording[] :=
  Module[{rec = Lookup[$irpPlay, "RecordFile", None], file = Lookup[$irpPlay, "File", None], sec, need},
    If[!StringQ[rec] || !StringQ[file] || !FileExistsQ[rec], Return[Null]];
    sec = irpWavSeconds[rec];
    need = 0.55*StringLength[irpSlideText[$irpPlay["Slide"]]]/7.;
    If[sec >= Max[1., need],
      Quiet[DeleteFile[file]];
      Quiet @ Check[RenameFile[rec, file], Null];
      irpNote["Recorded", <|"Slide" -> $irpPlay["Slide"], "Seconds" -> sec|>],
      Quiet[DeleteFile[rec]];
      irpNote["RecordingDiscarded", <|"Slide" -> $irpPlay["Slide"], "Seconds" -> sec, "Need" -> need|>]];
    Null];

irpElapsed[] := $irpPlay["Played"] + If[TrueQ[$irpPlay["Hold"]], 0., irpNow[] - $irpPlay["SegmentStart"]];

irpNarrationTick[st_Association] :=
  Module[{now = irpNow[], busy = irpBridgeBusyQ[st], done},
    Switch[$irpPlay["Route"],
      "World",
        (* 話しかけに応じている間はスピーカーを止め、静かになって 2 秒したら続きから *)
        Which[
          busy && !TrueQ[$irpPlay["Hold"]],
            $irpPlay["Played"] = irpElapsed[]; $irpPlay["Hold"] = True; $irpPlay["QuietSince"] = None;
            irpPlayback[False, $irpPlay["Played"]],
          TrueQ[$irpPlay["Hold"]] && busy, $irpPlay["QuietSince"] = None,
          TrueQ[$irpPlay["Hold"]] && !busy,
            If[!NumericQ[$irpPlay["QuietSince"]], $irpPlay["QuietSince"] = now];
            If[now - $irpPlay["QuietSince"] >= 2.,
              $irpPlay["Hold"] = False; $irpPlay["SegmentStart"] = now;
              irpPlayback[True, $irpPlay["Played"]]],
          True, Null];
        done = !TrueQ[$irpPlay["Hold"]] && irpElapsed[] >= $irpPlay["Duration"],
      "Live",
        done = Lookup[st, "NarrationDone", None] === $irpPlay["NarrationId"];
        If[done, irpKeepRecording[]];
        If[!done && (now - $irpPlay["SegmentStart"] > $irpPlay["Duration"] || !irpBridgeRunningQ[st]),
          irpNote["LiveTimeout", $irpPlay["Slide"]]; done = True],
      _,
        done = now - $irpPlay["SegmentStart"] >= $irpPlay["Duration"]];
    If[TrueQ[done],
      (* 読み上げの間閉じていたマイクを、質問の時間のために開け直す *)
      If[TrueQ[$irpAnswering] && irpBridgeRunningQ[st] &&
          ($irpPlay["Route"] === "Live" ||
            ($irpPlay["Route"] === "World" && !TrueQ[ResoniteRealtime`$ResonitePresentationListenWhileNarrating])),
        Quiet @ Check[SourceVault`SourceVaultRealtimeMute[False], Null]];
      $irpPlay = Join[$irpPlay, <|"Phase" -> "Question", "PhaseSince" -> now, "QuietSince" -> now|>]];
    Null];

(* 1 枚読み終えたあと: 音声応答が on なら質問を待ち、やり取りが終わってから次へ *)
irpQuestionTick[st_Association] :=
  Module[{now = irpNow[], wait, talking},
    wait = If[TrueQ[$irpAnswering] && irpBridgeRunningQ[st],
      Max[$irpGapSeconds, N[ResoniteRealtime`$ResonitePresentationQuestionSeconds]], $irpGapSeconds];
    talking = irpBridgeRunningQ[st] && TrueQ[$irpAnswering] &&
      (irpBridgeBusyQ[st] || Lookup[st, "Mode", None] === "listening");
    If[talking && now - $irpPlay["PhaseSince"] < $irpQuestionMaxSeconds, $irpPlay["QuietSince"] = now];
    If[irpBridgeBusyQ[st], Return[Null]];
    If[now - $irpPlay["QuietSince"] >= wait,
      If[$irpPlay["Slide"] >= $irpPlay["Last"], irpFinish[], irpBeginSlide[$irpPlay["Slide"] + 1]]];
    Null];

irpFinish[] := (
  $irpPlay = Join[$irpPlay, <|"Status" -> "Finished", "Phase" -> None, "Route" -> None, "Message" -> "発表が終わりました"|>];
  (* 読み上げのためだけに起こしたブリッジは止める。残すとき (音声応答 on / 他が起こしたブリッジ) は、
     自分から話し続けないよう文脈を閉じる。止める直前に閉じると、閉じる指示が届き切る前にセッションが終わり、
     ワーカーが context_injection_incomplete のエラーを残す (2026-11-23、本物の GPT-Live で実測) *)
  If[!TrueQ[$irpAnswering] && TrueQ[$irpBridgeOwned],
    irpBridgeStop[],
    If[irpCloudLayerQ[] && irpBridgeRunningQ[irpBridgeStatus[]], Quiet @ Check[SourceVault`SourceVaultRealtimeEndTalk[], Null]]];
  irpNote["Finished", $irpPlay["Title"]]; Null);

irpHalt[why_String] := (
  irpStopAudio[];
  $irpPlay = Join[$irpPlay, <|"Status" -> "Idle", "Phase" -> None, "Route" -> None, "Message" -> why|>];
  If[!TrueQ[$irpAnswering] && TrueQ[$irpBridgeOwned], irpBridgeStop[]];
  irpNote["Halt", why]; Null);

irpPause[] :=
  If[$irpPlay["Status"] === "Playing",
    Switch[$irpPlay["Route"],
      "World", If[!TrueQ[$irpPlay["Hold"]], $irpPlay["Played"] = irpElapsed[]]; irpPlayback[False, $irpPlay["Played"]],
      "Live", Quiet @ Check[SourceVault`SourceVaultRealtimeCancel[], Null],
      _, Null];
    $irpPlay = Join[$irpPlay, <|"Status" -> "Paused", "Message" -> ""|>];
    irpNote["Pause", $irpPlay["Slide"]]];

(* 一時停止からの再開と、開始待ち ("Ready") からの開始。開始待ちからは、映っている枚を頭から読む *)
irpResume[] :=
  If[MemberQ[{"Paused", "Ready"}, $irpPlay["Status"]],
    $irpPlay = Join[$irpPlay, <|"Status" -> "Playing", "Message" -> ""|>];
    Which[
      (* スピーカーで読んでいた枚は続きから。クラウドの声は途中から話せないので、その枚を頭から *)
      $irpPlay["Phase"] === "Narrating" && $irpPlay["Route"] === "World",
        $irpPlay["Hold"] = False; $irpPlay["SegmentStart"] = irpNow[]; irpPlayback[True, $irpPlay["Played"]],
      $irpPlay["Phase"] === "Question", $irpPlay["QuietSince"] = irpNow[],
      True, irpBeginSlide[$irpPlay["Slide"]]];
    irpNote["Resume", $irpPlay["Slide"]]];

(* 発表を読み込んである (止めたあと・終わったあとも、スライドは送れる) *)
irpDeckLoadedQ[] :=
  ListQ[Lookup[$irpPlay, "Slides", None]] && Length[$irpPlay["Slides"]] >= 1 && $irpPlay["Last"] >= 1;

(* 読まずに k 枚目を映すだけ。画像の取り込みがまだなら、映るまで見回り (irpShowTick) が試す *)
irpShowOnly[k_Integer] := (
  irpStopAudio[];
  (* 一時停止中に移った枚は、再開したときに頭から読む ("Narrating" のままだと、前の枚の音声の続きから鳴らそうとする) *)
  $irpPlay = Join[$irpPlay, <|"Slide" -> k, "Shown" -> False, "ShowSince" -> irpNow[],
    "Phase" -> If[$irpPlay["Status"] === "Paused", "Moved", None], "Route" -> None,
    "Hold" -> False, "Played" -> 0., "Message" -> ""|>];
  Quiet[If[Length[DownValues[SourceVault`SourceVaultTalkQASetSlide]] > 0, SourceVault`SourceVaultTalkQASetSlide[k]]];
  irpNote["Show", <|"Slide" -> k, "Status" -> $irpPlay["Status"]|>];
  irpShowTick[];
  Null);

irpShowTick[] :=
  If[$irpPlay["Shown"] === False && MemberQ[{"Ready", "Paused", "Idle", "Finished"}, $irpPlay["Status"]] && irpDeckLoadedQ[] && irpRigBuiltQ[],
    If[irpShowSlide[$irpPlay["Slide"]],
      $irpPlay["Shown"] = True; irpPreloadSlide[$irpPlay["Slide"] + 1],
      If[irpNow[] - Lookup[$irpPlay, "ShowSince", 0.] > 45,
        $irpPlay["Shown"] = True; irpMessage["スライド画像を取り込めませんでした"]]];
    Null];

(* 開始待ち: スクリーンが組み上がったら k 枚目を映して止まる。読み始めるのは「開始」が押されてから
   (2026-11-23 利用者: スクリーンを良い位置に置く時間が要るので、既定では自動で読み始めない)。
   待っている間も、ローカルの声の音声は先に用意しておく (irpSynthAhead) *)
irpStandby[k_Integer] := (
  $irpPlay = Join[$irpPlay, <|"Status" -> "Ready", "Slide" -> k, "Phase" -> None, "Route" -> None,
    "Shown" -> False, "ShowSince" -> irpNow[], "Hold" -> False, "Played" -> 0., "Message" -> ""|>];
  Quiet[If[Length[DownValues[SourceVault`SourceVaultTalkQASetSlide]] > 0, SourceVault`SourceVaultTalkQASetSlide[k]]];
  irpNote["Ready", <|"Title" -> $irpPlay["Title"], "Slide" -> k|>];
  irpShowTick[];
  Null);

(* スクリーンが組み上がった: すぐ読み始める ("AutoStart" -> True) か、開始待ちで止まる (既定) *)
irpRigReady[] :=
  If[TrueQ[Lookup[$irpPlay, "AutoStart", False]], irpBeginSlide[$irpPlay["First"]], irpStandby[$irpPlay["Slide"]]];

(* 枚を移る。発表中は、移った枚を読み始める。一時停止中・停止中・終了後は、映すだけで読まない
   (2026-11-23 利用者: 一時停止中に「前へ」「次へ」を押すと再生が始まってしまっていた。停止中は何も起きなかった) *)
irpGoTo[k_Integer] :=
  Which[
    !(irpDeckLoadedQ[] && $irpPlay["First"] <= k <= $irpPlay["Last"]), Null,
    $irpPlay["Status"] === "Playing" || ($irpPlay["Status"] === "Starting" && TrueQ[Lookup[$irpPlay, "AutoStart", False]]),
      irpStopAudio[]; irpBeginSlide[k],
    True, irpShowOnly[k]];

irpButton[key_String] :=
  Module[{titles, r},
    Switch[key,
      "DeckPrev" | "DeckNext",
        titles = irpDeckTitles[];
        If[titles =!= {},
          $irpDeckIndex = Mod[$irpDeckIndex - 1 + If[key === "DeckNext", 1, -1], Length[titles]] + 1],
      "Play",
        Which[
          (* 開始待ち・一時停止中: 映っている枚から読み始める *)
          MemberQ[{"Paused", "Ready"}, $irpPlay["Status"]], irpResume[],
          (* スクリーンを組み立てている途中に押された: 組み上がったらすぐ読み始める *)
          $irpPlay["Status"] === "Starting", $irpPlay["AutoStart"] = True,
          $irpPlay["Status"] === "Playing", Null,
          (* 止めたあと・終わったあと: 選んである発表を 1 枚目から読み始める (スクリーンはもう置いてある) *)
          StringQ[irpSelectedTitle[]],
            r = irpStartRequest[irpSelectedTitle[], <|"AutoStart" -> True|>];
            If[FailureQ[r], irpMessage["始められません: " <> irpFailText[r]]],
          True, irpMessage["登録されている発表がありません"]],
      "Pause", If[$irpPlay["Status"] === "Paused", irpResume[], irpPause[]],
      "Stop", irpHalt["発表を止めました"],
      "Prev", irpGoTo[$irpPlay["Slide"] - 1],
      "Next", irpGoTo[$irpPlay["Slide"] + 1],
      "Smaller", irpResize[-1],
      "Larger", irpResize[1],
      "Voice", ResoniteRealtime`ResonitePresentationCycleVoice[],
      "Answer",
        If[TrueQ[$irpAnswering],
          ResoniteRealtime`ResonitePresentationVoiceControl[False],
          r = irpBridgeStart[];
          If[FailureQ[r],
            irpMessage["音声応答を始められません: " <> irpFailText[r] <>
              If[Head[$irpControlNotebook] =!= NotebookObject, " (ノートブックで ResonitePresentationVoiceControl[True] を実行してください)", ""]],
            $irpAnswering = True; Quiet @ Check[SourceVault`SourceVaultRealtimeMute[False], Null]]],
      _, Null];
    Null];

irpRunActions[] :=
  Module[{q = $irpQueue},
    $irpQueue = {};
    Scan[
      Function[a,
        Quiet @ Check[
          Switch[a["Action"],
            "Begin", irpBegin[a],
            "Button", irpButton[a["Key"]],
            "Pause", irpPause[],
            "Resume", irpResume[],
            "Toggle", If[$irpPlay["Status"] === "Paused", irpResume[], irpPause[]],
            "Stop", irpHalt["発表を止めました"],
            "GoTo", irpGoTo[a["Slide"]],
            _, Null],
          irpNote["ActionError", a["Action"]]]],
      q];
    Null];

(* ---- 表示 (パネルとノートブックのラベル。変わったときだけ書く) ---- *)

irpStatusLine[] :=
  Module[{p = $irpPlay, pos},
    pos = ToString[p["Slide"]] <> "/" <> ToString[p["Last"]];
    Switch[p["Status"],
      "Starting", "準備中… " <> p["Title"],
      "Playing",
        Switch[p["Phase"],
          "WaitAssets", pos <> " 準備中" <> If[irpSynthBusyQ[], " (音声を合成中)", ""],
          "Narrating", pos <> If[TrueQ[p["Hold"]], " 応答中 (読み上げを待たせています)",
            " 説明中" <> Switch[p["Route"], "World", " (スクリーンの音声)", "Live", " (音声ブリッジ)", _, ""]],
          "Question", pos <> If[TrueQ[$irpAnswering], " 質問をどうぞ", " 次へ"],
          _, pos],
      "Ready", pos <> " 開始待ち" <> If[irpSynthBusyQ[], " (音声を用意しています)", ""] <> "
スクリーンの位置を決めて「開始」を押してください",
      "Paused", pos <> " 一時停止中",
      "Finished", "発表が終わりました (" <> p["Title"] <> ")" <> If[p["Slide"] =!= p["Last"], "  " <> pos, ""],
      (* 止めたあとも「前へ」「次へ」でスライドは送れる: いまの枚を出しておく *)
      _, If[irpDeckLoadedQ[] && irpRigBuiltQ[],
        pos <> " 停止中" <> If[StringQ[p["Message"]] && p["Message"] =!= "", " (" <> p["Message"] <> ")", ""],
        If[StringQ[p["Message"]] && p["Message"] =!= "", p["Message"], "待機中"]]]];

irpRefreshLabel[] :=
  Module[{line = irpStatusLine[], sel = irpSelectedTitle[], msg},
    msg = If[MemberQ[{"Playing", "Paused", "Starting"}, $irpPlay["Status"]] && StringQ[$irpPlay["Message"]] &&
        $irpPlay["Message"] =!= "" && $irpPlay["Status"] =!= "Starting", "\n" <> $irpPlay["Message"], ""];
    irpSetText["DeckText", "発表: " <> If[irpActiveQ[] && $irpPlay["Status"] =!= "Finished", $irpPlay["Title"],
      If[StringQ[sel], sel, "(登録なし)"]]];
    irpSetText["VoiceText", "声: " <> irpVoiceLabel[]];
    irpSetText["AnswerText", "音声応答: " <> If[TrueQ[$irpAnswering], "on", "off"]];
    irpSetText["ScaleText", irpScaleLabel[]];
    irpSetText["StatusText", line <> msg];
    With[{label = line <> "  |  声: " <> irpVoiceLabel[] <> "  |  音声応答: " <> If[TrueQ[$irpAnswering], "on", "off"]},
      If[label =!= $irpLabel, $irpLabel = label]];
    Null];

(* ============================================================
   監視タスク
   ============================================================ *)

irpTick[] :=
  Module[{st},
    If[TrueQ[$irpState["Busy"]] || TrueQ[$irpState["Ticking"]], Return[Null]];
    $irpState["Ticking"] = True;
    $irpState["Ticks"] = $irpState["Ticks"] + 1;
    Quiet @ Check[
      CheckAbort[
        irpPumpImports[];
        irpSynthTick[];
        irpVoiceProbeTick[];
        If[irpLinkQ[], irpRigTick[]];
        irpRunActions[];
        st = If[TrueQ[$irpAnswering] || TrueQ[$irpBridgeOwned] || $irpPlay["Route"] === "Live", irpBridgeStatus[], <||>];
        (* 音声応答を on にしたブリッジが落ちた *)
        If[TrueQ[$irpAnswering] && TrueQ[$irpBridgeOwned] && !irpBridgeRunningQ[st] && irpNow[] - Lookup[$irpState, "BridgeCheck", 0] > 5,
          $irpState["BridgeCheck"] = irpNow[];
          If[!irpBridgeRunningQ[irpBridgeStatus[]],
            $irpAnswering = False; $irpBridgeOwned = False; irpRestoreHandlers[]; irpMessage["音声応答が止まりました"]]];
        If[irpLinkQ[],
          Switch[$irpPlay["Status"],
            "Starting",
              (* スクリーンが組み上がったら 1 枚目へ *)
              Which[
                irpRigBuiltQ[], irpRigReady[],
                !irpRigQ[], irpHalt["スクリーンを作れませんでした"],
                irpNow[] - $irpPlay["Since"] > 40, irpHalt["スクリーンの準備が終わりませんでした"],
                True, Null],
            "Playing",
              Switch[$irpPlay["Phase"],
                "WaitAssets", irpTryBeginSlide[st],
                "Narrating", irpNarrationTick[st],
                "Question", irpQuestionTick[st],
                _, Null];
              (* 次の枚の音声を先に用意する。資産の取り込みはいつでもよいが、控えへの読み込みは今の枚が鳴り始めてから
                 (今の枚もまだ控えにいる間に次の枚を読み込むと、同じ控えを奪い合って永久に始まらない。2026-11-23 実機) *)
              If[$irpPlay["Status"] === "Playing" && $irpPlay["Slide"] < $irpPlay["Last"],
                With[{r = irpRouteFor[$irpPlay["Slide"] + 1]},
                  If[r["Route"] === "World",
                    If[MemberQ[{"Narrating", "Question"}, $irpPlay["Phase"]],
                      irpPreloadClip[r["File"]],
                      irpEnsureImport["Audio", r["File"]]]]]],
            (* 一時停止中・停止中・終了後に送った枚: 画像の取り込みが済んだら映す (読まない) *)
            "Ready" | "Paused" | "Idle" | "Finished", irpShowTick[],
            _, Null];
          irpSynthAhead[];
          irpRefreshLabel[]],
        irpNote["TickAbort"]],
      irpNote["TickError"]];
    $irpState["Ticking"] = False;
    Null];

irpEnsureTask[] :=
  If[!MatchQ[$irpState["Task"], _TaskObject],
    $irpState["Ticking"] = False;
    $irpState["Task"] = SessionSubmit[ScheduledTask[ResoniteRealtime`Private`irpTick[], $irpTickSeconds]]];

irpStopTask[] := (
  If[MatchQ[$irpState["Task"], _TaskObject], Quiet[TaskRemove[$irpState["Task"]]]];
  $irpState["Task"] = None; $irpState["Ticking"] = False; Null);

(* ノートブックから呼んだとき、tick が進めるのを少し待つ (tick は Pause の間も走る) *)
irpWaitFor[test_, seconds_] :=
  Module[{t0 = irpNow[]},
    While[!TrueQ[test[]] && irpNow[] - t0 < seconds, Pause[0.1]];
    TrueQ[test[]]];

(* ============================================================
   公開 API
   ============================================================ *)

irpEnsureLink[] :=
  Which[
    irpLinkQ[], True,
    irpTaskContextQ[], False,
    True, StringQ[Quiet[ResoniteRealtime`ResoniteRealtimeLinkConnect[Automatic, "Quiet" -> True]]]];

ResoniteRealtime`ResonitePresenterStatus[] :=
  If[!irpRigQ[], <|"Phase" -> None|>,
    Join[KeyTake[$irpRig, {"Phase", "Root", "Screen", "Speaker", "PanelRoot", "Size"}],
      irpScaleInfo[],
      <|"Buttons" -> Keys[Lookup[$irpRig, "Buttons", <||>]], "Unwired" -> Length[Lookup[$irpRig, "Wire", {}]],
        "Task" -> $irpState["Task"]|>]];

irpScaleInfo[] :=
  With[{i = irpScaleIndex[], steps = irpScales[], size = If[irpRigQ[], Lookup[$irpRig, "Size", None], None]},
    <|"Step" -> i, "Steps" -> Length[steps], "Scale" -> steps[[i]],
      "Width" -> If[ListQ[size], steps[[i]]*First[size], None]|>];

ResoniteRealtime`ResonitePresenterResize[spec_] :=
  Module[{i},
    If[!irpRigBuiltQ[],
      Return[irpFail["PresenterNotBuilt", "スクリーンがありません。ResonitePresenter[] か ResonitePresentationStart[...] で置いてください。"]]];
    i = Switch[spec,
      "Larger", irpScaleIndex[] + 1, "Smaller", irpScaleIndex[] - 1, "Reset", irpScaleHome[], _Integer, spec, _, None];
    If[!IntegerQ[i],
      Return[irpFail["InvalidPresenterSize", "指定は \"Larger\" | \"Smaller\" | \"Reset\" | 段の番号 (1〜" <> ToString[Length[irpScales[]]] <> ") です。"]]];
    irpSetScale[i];
    irpScaleInfo[]];

ResoniteRealtime`ResonitePresenter[opts : OptionsPattern[]] :=
  Module[{o = irpRigOptions[opts], wait},
    irpRememberNotebook[];
    If[!irpEnsureLink[],
      Return[irpFail["NotConnected",
        "スクリーンの組み立てには ResoniteLink が要ります (Resonite でホストして Enable ResoniteLink)。ResoniteRealtimeLinkConnect[] を先に実行してください。"]]];
    If[irpRigQ[] && TrueQ[o["Rebuild"]], ResoniteRealtime`ResonitePresenterRemove[]];
    If[!irpRigQ[], irpRigStart[o]];
    irpEnsureTask[];
    irpWarmVoices[];
    wait = Replace[o["Wait"], Automatic :> !irpTaskContextQ[]];
    If[TrueQ[wait], irpWaitFor[(!irpRigQ[] || $irpRig["Phase"] === "Ready") &, 25]];
    If[!irpRigQ[], Return[irpFail["PresenterBuildFailed", "スクリーンを組み立てられませんでした (ResonitePresentationLog[] に記録)。"]]];
    ResoniteRealtime`ResonitePresenterStatus[]];

ResoniteRealtime`ResonitePresenterRemove[] :=
  Module[{root = If[irpRigQ[], Lookup[$irpRig, "Root", None], None], r = None},
    irpHalt["スクリーンを片付けました"];
    If[StringQ[root] && irpLinkQ[],
      r = If[irpTaskContextQ[],
        irpNoWait[ResoniteRealtime`ResoniteRealtimeRemoveSlot[root]],
        Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[root], $Failed]]];
    $irpRig = None; $irpTexts = <||>;
    If[!TrueQ[$irpAnswering], irpStopTask[]];
    r];

Options[ResoniteRealtime`ResonitePresentationStart] = {
  "Voice" -> Automatic, "StartSlide" -> Automatic, "EndSlide" -> Automatic, "Presenter" -> {}, "AutoStart" -> False};

ResoniteRealtime`ResonitePresentationStart[opts : OptionsPattern[]] :=
  With[{t = irpSelectedTitle[]},
    If[StringQ[t], ResoniteRealtime`ResonitePresentationStart[t, opts],
      irpFail["PresentationNotRegistered", "登録されている発表がありません。SlideWorkflow パレットの「登録」で登録してください。"]]];

ResoniteRealtime`ResonitePresentationStart[target_String, opts : OptionsPattern[]] :=
  Module[{o, r},
    irpRememberNotebook[];
    If[!irpEnsureLink[],
      Return[irpFail["NotConnected",
        "ResoniteLink に繋がっていません (Resonite でホストして Enable ResoniteLink)。ResoniteRealtimeLinkConnect[] を先に実行してください。"]]];
    o = Association @ Map[# -> OptionValue[ResoniteRealtime`ResonitePresentationStart, {opts}, #] &,
      {"Voice", "StartSlide", "EndSlide", "Presenter", "AutoStart"}];
    irpWarmVoices[];
    r = irpStartRequest[target, o];
    If[FailureQ[r], Return[r]];
    If[TrueQ[r["AutoStart"]], r,
      Append[r, "Next" -> "スクリーンの位置を決めてから、操作パネルの「開始」か ResonitePresentationControl[\"Start\"] で読み始めます。"]]];

Options[ResoniteRealtime`ResonitePresentationPrepare] = {"Voice" -> Automatic, "StartSlide" -> Automatic, "EndSlide" -> Automatic};

ResoniteRealtime`ResonitePresentationPrepare[target_String, opts : OptionsPattern[]] :=
  Module[{spec, deck, voice, n, talk, made = 0, had = 0, failed = {}, file, first, last},
    spec = irpResolveSpec[target];
    If[FailureQ[spec], Return[spec]];
    voice = irpResolveVoice[OptionValue[ResoniteRealtime`ResonitePresentationPrepare, {opts}, "Voice"]];
    If[FailureQ[voice], Return[voice]];
    deck = irpPrepareDeck[spec];
    If[FailureQ[deck], Return[deck]];
    n = Length[deck["Slides"]];
    (* 原稿の分け方 (Opening / Closing をつなぐ枚) は発表のときと同じにする。範囲を変えると文が変わり、音声も別になる *)
    first = With[{s = OptionValue[ResoniteRealtime`ResonitePresentationPrepare, {opts}, "StartSlide"]},
      Clip[If[IntegerQ[s], s, With[{t = Lookup[spec, "startSlide", 1]}, If[IntegerQ[t], t, 1]]], {1, n}]];
    last = With[{s = OptionValue[ResoniteRealtime`ResonitePresentationPrepare, {opts}, "EndSlide"]},
      Clip[If[IntegerQ[s], s, With[{t = Lookup[spec, "endSlide", Null]}, If[IntegerQ[t], t, n]]], {first, n}]];
    talk = irpTalkOf[spec, first, last];
    If[voice["Engine"] === "Local",
      KeyValueMap[
        Function[{k, text},
          file = irpAudioFile[deck["Directory"], voice, k, text];
          If[FileExistsQ[file] && irpWavSeconds[file] > 0.2, had++,
            If[FailureQ[irpSynthSync[voice, text, file]], AppendTo[failed, k], made++]]],
        KeySort[talk["Texts"]]],
      had = Count[KeyValueMap[irpAudioFile[deck["Directory"], voice, #1, #2] &, talk["Texts"]], _?FileExistsQ]];
    <|"Title" -> ToString[spec["title"]], "Slides" -> n, "Scripted" -> Length[talk["Texts"]], "Voice" -> voice["Name"],
      "AudioReady" -> had + made, "Synthesized" -> made, "Failed" -> failed, "Directory" -> deck["Directory"],
      "Note" -> If[voice["Engine"] === "Cloud",
        "クラウドの声は事前に作れません。最初の発表で話した音を録り、次からスクリーンのスピーカーで鳴らします。", None]|>];

ResoniteRealtime`ResonitePresentationControl[action_] :=
  Module[{a},
    a = Switch[action,
      "Pause", <|"Action" -> "Pause"|>, "Resume" | "Start", <|"Action" -> "Resume"|>, "Toggle", <|"Action" -> "Toggle"|>,
      "Stop", <|"Action" -> "Stop"|>,
      "Next", <|"Action" -> "GoTo", "Slide" -> $irpPlay["Slide"] + 1|>,
      "Previous", <|"Action" -> "GoTo", "Slide" -> $irpPlay["Slide"] - 1|>,
      "First", <|"Action" -> "GoTo", "Slide" -> $irpPlay["First"]|>,
      "Last", <|"Action" -> "GoTo", "Slide" -> $irpPlay["Last"]|>,
      _Integer, <|"Action" -> "GoTo", "Slide" -> action|>,
      _, None];
    If[a === None,
      Return[irpFail["InvalidPresentationControl",
        "action は \"Start\" | \"Pause\" | \"Resume\" | \"Toggle\" | \"Stop\" | \"Next\" | \"Previous\" | \"First\" | \"Last\" | 番号 です。"]]];
    irpEnqueue[a];
    irpEnsureTask[];
    (* ノートブックから呼んだときは、監視タスクが受け取るのを少し待ってから状態を返す *)
    If[!irpTaskContextQ[], irpWaitFor[($irpQueue === {}) &, 1.5]];
    ResoniteRealtime`ResonitePresentationStatus[]];

ResoniteRealtime`ResonitePresentationStop[] := ResoniteRealtime`ResonitePresentationControl["Stop"];

ResoniteRealtime`ResonitePresentationStatus[] :=
  <|"Status" -> $irpPlay["Status"], "Title" -> $irpPlay["Title"], "Slide" -> $irpPlay["Slide"],
    "First" -> $irpPlay["First"], "Last" -> $irpPlay["Last"], "Count" -> $irpPlay["Count"],
    "Phase" -> $irpPlay["Phase"], "Route" -> $irpPlay["Route"],
    "Voice" -> With[{v = irpCurrentVoice[]}, If[AssociationQ[v], v["Name"], None]],
    "VoiceModel" -> irpVoiceModel[], "Answering" -> TrueQ[$irpAnswering],
    "Presenter" -> If[irpRigQ[], $irpRig["Phase"], None],
    "Synthesizing" -> If[irpSynthBusyQ[], $irpSynth["Slide"], None],
    "Message" -> $irpPlay["Message"], "Line" -> irpStatusLine[],
    "AccessLevel" -> ResoniteRealtime`ResoniteAccessLevel[], "Task" -> $irpState["Task"]|>;

ResoniteRealtime`ResonitePresentationList[] := ($irpState["DeckCache"] = None; irpDeckTitles[]);

ResoniteRealtime`ResonitePresentationLog[n_Integer : 30] := Take[$irpLog, -Min[n, Length[$irpLog]]];

(* ノートブックの操作パネル。常駐ポーリングはしない: 状態行は文字列変数 1 つを TrackedSymbols で追うだけ *)
ResoniteRealtime`ResonitePresentationPanel[] :=
  With[{titles = ResoniteRealtime`ResonitePresentationList[], voices = ResoniteRealtime`ResonitePresentationVoices[],
        bs = {ImageSize -> {Automatic, 26}, Method -> "Queued"}},
    Panel[
      Column[{
        Style["Resonite Presenter", Bold],
        Dynamic[Style[ResoniteRealtime`Private`$irpLabel, FontSize -> 12],
          TrackedSymbols :> {ResoniteRealtime`Private`$irpLabel}],
        Row[{
          (* 選ぶとスクリーンを置いて最初の枚を映し、開始待ちで止まる。読み始めるのは「開始」 *)
          ActionMenu["発表を選ぶ",
            Map[With[{t = #}, t :> ResoniteRealtime`ResonitePresentationStart[t]] &, titles], Sequence @@ bs],
          Spacer[4],
          Button["開始", ResoniteRealtime`ResonitePresentationControl["Start"], Sequence @@ bs], Spacer[4],
          Button["一時停止/再開", ResoniteRealtime`ResonitePresentationControl["Toggle"], Sequence @@ bs], Spacer[4],
          Button["停止", ResoniteRealtime`ResonitePresentationControl["Stop"], Sequence @@ bs], Spacer[4],
          Button["前へ", ResoniteRealtime`ResonitePresentationControl["Previous"], Sequence @@ bs], Spacer[4],
          Button["次へ", ResoniteRealtime`ResonitePresentationControl["Next"], Sequence @@ bs]}],
        Row[{
          (* 声の一覧は、ローカルの声のエンジンが動き出すと増える。一覧の変数 1 つを追うだけ (ポーリングはしない) *)
          Dynamic[
            ActionMenu["声を選ぶ",
              Join[
                Map[With[{v = #}, ResoniteRealtime`Private`irpVoiceShort[v] :> ResoniteRealtime`ResonitePresentationSetVoice[v]] &,
                  ResoniteRealtime`Private`$irpVoiceMenu],
                If[ResoniteRealtime`Private`irpVoiceLayerQ[] && !ResoniteRealtime`Private`irpAivisListedQ[],
                  {"ローカルの声を起動 (AivisSpeech)" :> ResoniteRealtime`Private`irpWakeLocalVoices[True]}, {}]],
              Sequence @@ bs],
            TrackedSymbols :> {ResoniteRealtime`Private`$irpVoiceMenu}],
          Spacer[4],
          Button["音声応答 on/off", ResoniteRealtime`ResonitePresentationVoiceControl[], Sequence @@ bs], Spacer[4],
          Button["スクリーンを置く", ResoniteRealtime`ResonitePresenter[], Sequence @@ bs], Spacer[4],
          Button["縮小", ResoniteRealtime`ResonitePresenterResize["Smaller"], Sequence @@ bs], Spacer[4],
          Button["拡大", ResoniteRealtime`ResonitePresenterResize["Larger"], Sequence @@ bs], Spacer[4],
          Button["片付ける", ResoniteRealtime`ResonitePresenterRemove[], Sequence @@ bs]}]},
        Spacings -> 0.6],
      Background -> GrayLevel[0.97]]];

End[];
EndPackage[];

(* 再ロードの間止めていた tick を戻す *)
If[AssociationQ[ResoniteRealtime`Private`$irpState], ResoniteRealtime`Private`$irpState["Busy"] = False];
