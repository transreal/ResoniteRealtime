(* ::Package:: *)

(* ResoniteRealtime_tablet.wl -- ClaudeEval をワールド内で走らせる「タブレット」ガジェット

   This file is encoded in UTF-8.
   ResoniteRealtime.wl が自動でロードする (同じ ResoniteRealtime` コンテキスト。
   ResoniteRealtime_chat.wl の UIX ヘルパ (icSlot / icComp / icText / icMemberId / icUserFrontPose ...)
   とアクセスレベル (ResoniteAccessLevel) の上に載る)。

   ---- 何をするか ----

   1. ResoniteTablet[] が ResoniteLink (L2) だけでワールド内にタブレット (入力欄 / Eval ボタン /
      状態行 / 承認・拒否ボタン / スクロールする出力欄 / 画像ビューア) を組み立てる。
   2. Eval を押すと、専用ノートブック「Resonite Tablet」に ResoniteTabletTurn["..."] の Input セルを
      書いて評価する。中身は ClaudeEval (runtime 経路)。つまり **ノートブックで ClaudeInput セルを
      評価したのと同じ処理** が走る (提案コードの実行、承認、結果セル)。
   3. ポーリング (ScheduledTask 1 本) が runtime の状態を見張り、
        承認待ち     -> タブレットに説明と式を出し、承認/拒否ボタンを有効化
                        (押すと claudecode の ClaudeRuntimeDecide でノートブックの承認ボタンと同じ処理)
        完了/失敗    -> 新しく増えたセルを機密度でふるい、平文を出力欄へ、ラスタライズ画像をビューアへ
   4. ResoniteShowObject[x] は SourceVault オブジェクト (sv:// URI / 行 / ファイル / 画像 / 式) を
      ワールド内に出す一般 API (画像・PDF (ページ送り)・動画・テキスト・行リスト)。
   5. ResoniteListGadget[rows] は SourceVault の core 関数の行リスト (arXiv / Eagle / mail ...) を
      ボタン付き一覧にする。行の ▶ を押すとその PDF / 画像 / 本文がビューアに出る。

   ---- アクセスレベル (表示上限) ----

   ResoniteAccessLevel[] (chat 側): オーナーのワールドなら Private 1.0 / Contacts 0.5 /
   ContactsPlus, Public 0.25。オーナーでなければ一律 0.25 ($ResoniteWorldOwner)。
   - 表示: 機密度 (NBCellExprPrivacyLevel / 行・オブジェクトの PrivacyLevel) がこれ**以上**のものは
     出さない (上限と等しいものも出さない。2026-09-23 指示)。数値が取れないものは fail-closed
     (1.0 扱い) で出さない。
   - LLM に渡す AccessLevel: Min[表示上限, 0.5] (クラウドモデルに 0.5 を超えるデータは渡さない)。
     "Model" にローカルモデルを指定したときだけ表示上限と同じにする。

   ---- 設計上の約束 (chat と同じ) ----

   - 監視は ScheduledTask 1 本。tick の中では ResoniteLink の応答を**待たない**
     (getSlot は "Wait" -> False で送り、次の tick で sourceMessageId を照合)。
   - 書き込みは Block[{$iLinkWaitDefault = False}, ...] で送りっぱなし。
   - FrontEnd を触るのは、ターン開始のセル書き込み/評価と、完了時のラスタライズだけ。
   - ResoniteLink のメッセージは本体の ResoniteRealtimeAddSlot / AddComponent / UpdateComponent /
     UpdateSlot / GetSlot を通す。enum は <|"$type" -> "enum", "value" -> "Name"|> (2026-09-22 実測)。
*)

BeginPackage["ResoniteRealtime`"];

ResoniteRealtime`ResoniteTablet::usage =
  "ResoniteTablet[] はワールド内にタブレット (入力欄 / Eval / 承認・拒否 / スクロール出力 / 画像ビューア) を組み立て、\n" <>
  "監視 (ResoniteTabletStart) も始める。ClaudeEval と同じ処理を専用ノートブック「Resonite Tablet」経由で走らせる。\n" <>
  "オプション: \"Placement\" -> \"User\" | \"World\", \"Distance\" -> 1.2, \"Height\" -> Automatic, \"User\" -> Automatic,\n" <>
  "  \"Position\" -> {0, 1.3, 1.2}, \"Parent\" -> \"Root\", \"Name\" -> \"Mathematica Tablet\",\n" <>
  "  \"CanvasSize\" -> {1000, 1500}, \"PanelScale\" -> 0.0006, \"FontSize\" -> 26, \"Viewer\" -> True, \"ViewerSize\" -> 1.2,\n" <>
  "  \"Notebook\" -> Automatic (専用ノートブックを作る) | NotebookObject, \"NotebookVisible\" -> True,\n" <>
  "  \"Model\" -> Automatic (ローカルモデル指定時は表示上限まで LLM に渡す), \"Start\" -> True。\n" <>
  "戻り値: ID の Association。";
ResoniteRealtime`ResoniteTabletStart::usage =
  "ResoniteTabletStart[] はタブレット (とリストガジェット) のボタン監視と runtime 監視の ScheduledTask を 1 本だけ起動する。\n" <>
  "オプション: \"PollInterval\" -> 1.0 (秒)。";
ResoniteRealtime`ResoniteTabletStop::usage = "ResoniteTabletStop[] は監視タスクを止める。";
ResoniteRealtime`ResoniteTabletTick::usage =
  "ResoniteTabletTick[] は監視 1 回分 (runtime の状態確認 + ボタン読み取り) を手で回す。テスト/デバッグ用。\n" <>
  "getSlot は送るだけなので、応答の処理は次の呼び出しで行われる。";
ResoniteRealtime`ResoniteTabletEval::usage =
  "ResoniteTabletEval[prompt] はタブレットの Eval ボタンを押したのと同じ (専用ノートブックで ClaudeEval を開始し、\n" <>
  "結果をタブレットへ出す)。ノートブックからの動作確認用。";
ResoniteRealtime`ResoniteTabletTurn::usage =
  "ResoniteTabletTurn[prompt] はタブレットの 1 ターン。専用ノートブックの Input セルとして書き込まれ評価される\n" <>
  "(中身は runtime 経路の ClaudeEval。PrivacySpec の AccessLevel は表示上限と 0.5 の小さい方)。直接呼ぶものではない。";
ResoniteRealtime`ResoniteTabletApprove::usage = "ResoniteTabletApprove[] は承認待ちの提案を承認する (タブレットの承認ボタンと同じ)。";
ResoniteRealtime`ResoniteTabletDeny::usage = "ResoniteTabletDeny[] は承認待ちの提案を拒否する (タブレットの拒否ボタンと同じ)。";
ResoniteRealtime`ResoniteTabletCancel::usage = "ResoniteTabletCancel[] は実行中のターンを止める。";
ResoniteRealtime`ResoniteTabletShow::usage =
  "ResoniteTabletShow[text] は出力欄に文字列を出す。ResoniteTabletShow[expr] (文字列以外) はビューアに画像で出す。";
ResoniteRealtime`ResoniteTabletNoteTurnResult::usage =
  "ResoniteTabletNoteTurnResult[res] は ResoniteTabletTurn の戻り値を見て、ClaudeOrchestrator の非同期ジョブ\n" <>
  "(<|\"OrchJobId\" -> ...|>) に回っていたら監視対象にする (ClaudeOrchestrationStatus で完了を待つ)。戻り値は jobId か None。";
ResoniteRealtime`ResoniteTabletMake3D::usage =
  "ResoniteTabletMake3D[] は直前のターンの結果にある Graphics3D (Plot3D 等) をワールド内の 3D オブジェクトにする\n" <>
  "(タブレットの「3D生成」ボタン。ResoniteGraphics3D 経由)。表示上限を超える結果は作らない。\n" <>
  "戻り値: ResoniteGraphics3D の結果のリスト。オプションは ResoniteGraphics3D と同じ。";
ResoniteRealtime`ResoniteTabletStatus::usage = "ResoniteTabletStatus[] はタブレット・監視・ターン・ビューア・リストの状態を返す。";
ResoniteRealtime`ResoniteTabletRemove::usage = "ResoniteTabletRemove[] はタブレット (ビューア含む) をワールドから消し、監視を止める。";
ResoniteRealtime`ResoniteTabletAttach::usage = "ResoniteTabletAttach[ids] は別カーネルが作ったタブレット (ResoniteTablet の戻り値) を引き継ぐ。";
ResoniteRealtime`ResoniteTabletNotebook::usage = "ResoniteTabletNotebook[] はタブレット専用ノートブック (無ければ作る) を返す。";
ResoniteRealtime`ResoniteTabletLog::usage = "ResoniteTabletLog[n] は直近 n ターンの記録 (<|\"Time\",\"Prompt\",\"Status\",\"Seconds\",\"Text\",\"Pages\"|>) を返す。";
ResoniteRealtime`ResoniteTabletRegisterHeads::usage =
  "ResoniteTabletRegisterHeads[] はタブレットの表示 API (ResoniteShowObject / ResoniteListGadget 等) を NBAccess の許可ヘッドに登録する\n" <>
  "(2 層: NBRegisterAllowedHeads + NBRegisterTrustedPackageHeads)。ロード時に自動で呼ばれる。";

ResoniteRealtime`ResoniteShowObject::usage =
  "ResoniteShowObject[x] は SourceVault のオブジェクトをワールド内 (タブレットのビューア / 出力欄) に出す一般 API。\n" <>
  "x: sv:// URI | SourceVault の行 (Kind/URI/File/Title ...) | ファイルパス (pdf/png/jpg/mp4/txt/md/nb) | Image/Graphics |\n" <>
  "   行リスト {<|...|>, ...} (-> ResoniteListGadget) | 文字列 (出力欄)。\n" <>
  "機密度が表示上限 (ResoniteAccessLevel[]) 以上のもの・機密度が数値で取れないものは出さない (Failure[\"PrivacyExceeded\"])。\n" <>
  "PDF はページ送り (タブレットの ◀ ▶)。オプション: \"Title\", \"MaxPages\" -> 200, \"PageSize\" -> 1200。\n" <>
  "戻り値: <|\"Kind\", \"Pages\", \"Title\", ...|> か Failure。";
ResoniteRealtime`ResoniteViewer::usage =
  "ResoniteViewer[] は画像ビューア (板) だけをワールドに作る (タブレット無しで ResoniteShowObject を使うとき)。\n" <>
  "オプションは ResoniteRealtimeBoard と同じ + \"Placement\" -> \"User\" | \"World\", \"Distance\" -> 1.5。";
ResoniteRealtime`ResoniteViewerShow::usage =
  "ResoniteViewerShow[pages] はページ (Image | Graphics | {\"PDF\", file, n} | {\"File\", path}) のリストをビューアに出し 1 ページ目を映す。\n" <>
  "オプション: \"Title\" -> \"\"。";
ResoniteRealtime`ResoniteViewerPage::usage =
  "ResoniteViewerPage[n] は n ページ目を映す。ResoniteViewerPage[\"Next\" | \"Prev\" | \"First\" | \"Last\"] も可。";
ResoniteRealtime`ResoniteViewerRemove::usage = "ResoniteViewerRemove[] は単独で作ったビューアを消す。";
ResoniteRealtime`ResoniteListGadget::usage =
  "ResoniteListGadget[rows] は SourceVault の行リスト (SourceVaultArXiv / SourceVaultEagleSummaries / SourceVaultSummaries /\n" <>
  "SourceVaultMailSearchIndex 等 core 関数の戻り値) をワールド内のボタン付き一覧にする。行の ▶ でその PDF / 画像 / 本文がビューアに出る。\n" <>
  "表示上限を超える行は落とす。オプション: \"Title\" -> \"SourceVault\", \"RowsPerPage\" -> 8,\n" <>
  "  \"Placement\" -> Automatic (タブレットがあればその左隣、無ければアバター正面) | \"User\" | \"World\",\n" <>
  "  \"Distance\", \"Height\", \"Position\", \"Parent\", \"CanvasSize\" -> {1400, 1000}, \"PanelScale\" -> 0.0006, \"FontSize\" -> 30。\n" <>
  "戻り値: <|\"Root\", \"Count\", \"Hidden\", ...|>。";
ResoniteRealtime`ResoniteListGadgetRemove::usage =
  "ResoniteListGadgetRemove[rootId] は一覧ガジェットを消す。ResoniteListGadgetRemove[] は全部消す。";
ResoniteRealtime`ResonitePDFViewer::usage =
  "ResonitePDFViewer[file] は PDF / 画像 / ノートブックを、ページ送りつきの掴めるビューアパネル (Resonite の\n" <>
  "ドキュメントビューア風: ページ画像 + [<<] [<] n/N [>] [>>] [閉じる]) でワールドに出す。\n" <>
  "ResonitePDFViewer[pages] (ページ仕様のリスト: Image | {\"PDF\", file, n} | {\"File\", path}) も可。\n" <>
  "呼ぶたびに新しいビューアを増やす (前のは残る。少しずつ右下手前へずらして並ぶ)。\"Reuse\" -> True で最新のビューアへ、\n" <>
  "\"Reuse\" -> root でそのビューアへ読み込む。\n" <>
  "オプション: \"Placement\" -> \"User\" | \"World\", \"Distance\" -> 1.0, \"Offset\" -> {0.65, 0, 0} (利用者の右へ),\n" <>
  "  \"Position\", \"Parent\", \"CanvasSize\" -> {1000, 1400}, \"PanelScale\" -> 0.0006, \"FontSize\" -> 30, \"Title\"。\n" <>
  "戻り値: <|\"Root\", \"Pages\", \"Page\", \"Title\"|> か、非同期文脈なら <|\"Deferred\" -> True, ...|>。";
ResoniteRealtime`ResonitePDFViewerPage::usage =
  "ResonitePDFViewerPage[n | \"Next\" | \"Prev\" | \"First\" | \"Last\" | \"+10\" | \"-10\"] は最新の PDF ビューアのページを変える。\n" <>
  "ResonitePDFViewerPage[root, ...] でそのビューア。";
ResoniteRealtime`ResonitePDFViewerRemove::usage =
  "ResonitePDFViewerRemove[] は最新の PDF ビューアを、ResonitePDFViewerRemove[root] はそのビューアを、ResonitePDFViewerRemove[All] は全部をワールドから消す。";
ResoniteRealtime`ResoniteVideoBoard::usage =
  "ResoniteVideoBoard[urlOrFile] は動画を映す板 (VideoTextureProvider + AudioOutput) をワールドに作る。\n" <>
  "オプションは ResoniteRealtimeBoard と同じ。戻り値: ID の Association。(2026-09-22: 再生開始の挙動は実機未確認)";
ResoniteRealtime`ResoniteColorToggleBox::usage =
  "ResoniteColorToggleBox[{c1, c2}] はクリック (レーザー / タッチ) するたびに色が c1 <-> c2 と切り替わる箱をワールドに作る\n" <>
  "(BoxMesh + UnlitMaterial + MeshRenderer + BoxCollider + TouchButton + BooleanValueDriver<colorX> (TargetField -> TintColor) +\n" <>
  "ButtonToggle (-> driver の State)。ProtoFlux 不要)。ResoniteColorToggleBox[] は {Red, Blue}。\n" <>
  "非同期文脈 (LLM の提案コードの実行中 / ScheduledTask) では組み立てを予約して <|\"Deferred\" -> True, ...|> を返す (成功)。\n" <>
  "オプション: \"Shape\" -> \"Box\" | \"Sphere\", \"Size\" -> 0.2 (m), \"Placement\" -> \"User\" | \"World\", \"Distance\" -> 1.0,\n" <>
  "  \"Height\" -> Automatic, \"Position\" -> {0, 1.2, 1.0}, \"Parent\" -> \"Root\", \"Offset\" -> {-0.55, -0.1, -0.2} (タブレットの子になるとき),\n" <>
  "  \"Name\" -> \"Mathematica Toggle Box\", \"Grabbable\" -> True, \"ButtonComponent\" -> \"TouchButton\"。\n" <>
  "戻り値: <|\"Root\", \"Mesh\", \"Material\", \"Driver\", \"Colors\", ...|> か Failure。";
ResoniteRealtime`$ResoniteTabletTurnRunner::usage =
  "$ResoniteTabletTurnRunner にFunction[{prompt, notebook}] を置くと、Eval がノートブックのセル評価の代わりにそれを呼ぶ (テスト用)。既定 None。";
ResoniteRealtime`$ResoniteTabletMaxChars::usage = "$ResoniteTabletMaxChars は出力欄に出す最大文字数 (既定 6000)。";
ResoniteRealtime`$ResoniteTabletShowCode::usage =
  "$ResoniteTabletShowCode が True なら LLM の提案コード (Input セル) もタブレットに出す。既定 False (結果だけ出す。ノートブックには残る)。";
ResoniteRealtime`$ResoniteTabletDeferMode::usage =
  "$ResoniteTabletDeferMode: 一覧ガジェット等の組み立てを専用ノートブックのセル評価に予約するか。\n" <>
  "Automatic (既定) = $CurrentTask が TaskObject のとき (ScheduledTask / runtime の実行ジョブの中) だけ予約、True = 常に、False = しない。";
ResoniteRealtime`$ResoniteTabletBuildMode::usage =
  "$ResoniteTabletBuildMode: 予約した組み立てをどこで行うか。Automatic (既定) = 監視 tick が動いていれば tick の中で待たずに組む\n" <>
  "(Send → 次の tick で getSlot → 応答からボタンを結線)、無ければ専用ノートブックのセル評価。\"Tick\" | \"Notebook\" で固定。";
ResoniteRealtime`$ResoniteTabletDeferRunner::usage =
  "$ResoniteTabletDeferRunner に Function[{id, notebook}] を置くと、予約セルの書き込み+評価の代わりにそれを呼ぶ (テスト用)。既定 None。";
ResoniteRealtime`ResoniteTabletRunDeferred::usage =
  "ResoniteTabletRunDeferred[id] は予約した組み立て (ResoniteListGadget 等) を実行する。専用ノートブックの Input セルとして\n" <>
  "評価される (トップレベル評価なので ResoniteLink の応答を受けられる)。直接呼ぶものではない。";
ResoniteRealtime`ResoniteTabletDeferred::usage = "ResoniteTabletDeferred[] は予約した組み立ての台帳 (id -> <|Label, Status, Result, Time|>) を返す。";
ResoniteRealtime`ResoniteTabletServe::usage =
  "ResoniteTabletServe[] は常駐監視を始める: ResoniteLink が無ければ ResoniteRealtimeDiscover[] で見つけて繋ぎ (15 秒ごと)、\n" <>
  "ワールドの Root 直下の \"Mathematica Tablet\" (インベントリから出した物も) を探し、その「接続」ボタンが押されたら\n" <>
  "そのタブレットを名前で読み取って引き継ぐ (ResoniteTabletAdopt)。ノートブックのセッションではロード時に自動で始まる\n" <>
  "($ResoniteTabletAutoServe)。ResoniteTabletServe[False] で止める。オプション: \"PollInterval\" -> 1.0, \"Start\" -> True。";
ResoniteRealtime`ResoniteTabletFind::usage =
  "ResoniteTabletFind[] はワールドの Root 直下にあるタブレット ({<|\"Id\", \"Name\", \"Attached\"|> ...}) を返す。";
ResoniteRealtime`ResoniteTabletAdopt::usage =
  "ResoniteTabletAdopt[root] はワールドにあるタブレット (インベントリから出した物。ID は付け直されている) の構造を\n" <>
  "スロット名とコンポーネント型で読み取り、このカーネルのタブレットとして引き継いで監視を始める。ResoniteTabletAdopt[] は\n" <>
  "見つかった最後の 1 つ。";
ResoniteRealtime`$ResoniteTabletAutoServe::usage =
  "$ResoniteTabletAutoServe (既定 True): ノートブックのセッションで ResoniteRealtime.wl をロードしたとき ResoniteTabletServe[] を自動で始めるか。";
ResoniteRealtime`ResoniteTabletCleanup::usage =
  "ResoniteTabletCleanup[] は Root 直下のガジェット (タブレット / 一覧 / PDF ビューア / 板。名前で判定) をワールドから消し、\n" <>
  "タブレットの状態を空にする。カーネル再起動で台帳を失ったときの片付け用。オプション: \"Names\", \"Prefixes\"。戻り値: 消した slot のリスト。";
ResoniteRealtime`$ResoniteTabletPagePoints::usage =
  "$ResoniteTabletPagePoints は結果セルをページ画像にするときの PageWidth (pt、既定 480)。小さくすると板の上の文字が大きくなる。";
ResoniteRealtime`$ResoniteTabletPageResolution::usage =
  "$ResoniteTabletPageResolution はページ画像の解像度 (dpi、既定 192)。ページの幅 px = PagePoints * dpi / 72 (既定 1280)。";
ResoniteRealtime`$ResoniteTabletCloudMaxLevel::usage =
  "$ResoniteTabletCloudMaxLevel はモデル未指定時に LLM へ渡す AccessLevel の上限 (既定 0.5)。表示上限とは別。";

Begin["`Private`"];

Scan[Quiet[Clear[#]] &,
  Join[Names["ResoniteRealtime`ResoniteTablet*"], Names["ResoniteRealtime`ResoniteViewer*"],
    Names["ResoniteRealtime`ResoniteListGadget*"], Names["ResoniteRealtime`ResonitePDFViewer*"],
    {"ResoniteRealtime`ResoniteShowObject", "ResoniteRealtime`ResoniteVideoBoard",
     "ResoniteRealtime`ResoniteColorToggleBox"}]];

(* ---- 状態 (再ロードで壊さない) ---- *)
If[!AssociationQ[$itState],
  $itState = <|"Gadget" -> None, "Task" -> None, "Turn" -> None, "Viewer" -> None,
    "Lists" -> <||>, "Notebook" -> None, "Pending" -> None, "PollFailures" -> 0,
    "LastError" -> None, "PollIndex" -> 0, "Busy" -> False, "Options" -> <||>|>];
If[!ListQ[$itLog], $itLog = {}];
If[!AssociationQ[$itPageCache], $itPageCache = <||>];
If[!ValueQ[ResoniteRealtime`$ResoniteTabletTurnRunner], ResoniteRealtime`$ResoniteTabletTurnRunner = None];
If[!IntegerQ[ResoniteRealtime`$ResoniteTabletMaxChars], ResoniteRealtime`$ResoniteTabletMaxChars = 6000];
If[!BooleanQ[ResoniteRealtime`$ResoniteTabletShowCode], ResoniteRealtime`$ResoniteTabletShowCode = False];
If[!ValueQ[ResoniteRealtime`$ResoniteTabletDeferMode], ResoniteRealtime`$ResoniteTabletDeferMode = Automatic];
If[!ValueQ[ResoniteRealtime`$ResoniteTabletDeferRunner], ResoniteRealtime`$ResoniteTabletDeferRunner = None];
If[!AssociationQ[$itDeferred], $itDeferred = <||>];

(* ============================================================
   非同期文脈からの組み立ての予約 (トップレベル評価へ回す)

   ResoniteLink の応答待ちは ScheduledTask / SessionSubmit / runtime の実行ジョブの中では必ずタイムアウトする
   (受信ハンドラが走れない。2026-09-06 chat、2026-09-22 タブレット: LLM の提案コードが呼んだ
   ResoniteListGadget が「ResoniteLink 無応答」になった)。$CurrentTask が TaskObject ならその文脈。
   応答が要る組み立ては専用ノートブックの Input セル ResoniteTabletRunDeferred["id"] として評価を予約し、
   即座に <|"Deferred" -> True, "Id" -> id|> を返す。セルはトップレベル評価なので応答を受けられる。
   ============================================================ *)

(* 予約する文脈: Task の中、または タブレットのターンが進行中 (LLM の提案コードの実行は 30 秒の TimeConstrained
   つきで、$CurrentTask が None の経路もある。2026-09-22 実機: 22 行の一覧を直接組み始めて 30 秒で中断され、
   待ちループ内の Abort でカーネルが固着した)。予約セル自身の中 ($itInDeferredRun) では組む。 *)
itTurnActiveQ[] :=
  With[{t = Lookup[$itState, "Turn", None]},
    AssociationQ[t] && MemberQ[{"Starting", "Running", "Orchestrating", "Finishing"}, t["Phase"]]];

itAsyncContextQ[] :=
  Switch[ResoniteRealtime`$ResoniteTabletDeferMode,
    True, True,
    False, False,
    _, !TrueQ[$itInDeferredRun] && (MatchQ[$CurrentTask, _TaskObject] || itTurnActiveQ[])];

SetAttributes[itDeferToTopLevel, HoldFirst];
itDeferToTopLevel[expr_, label_String] :=
  Module[{id = StringTake[CreateUUID[], 8], nb, cell, runner = ResoniteRealtime`$ResoniteTabletDeferRunner},
    nb = Quiet @ Check[ResoniteRealtime`ResoniteTabletNotebook[], $Failed];
    If[Head[nb] =!= NotebookObject, Return[None]];
    $itDeferred[id] = <|"Expr" -> Hold[expr], "Label" -> label, "Time" -> iNow[], "Status" -> "Pending"|>;
    itSetStatus[label <> " を作成中 (予約 " <> id <> ")"];
    If[runner =!= None, runner[id, nb]; Return[id]];
    cell = Cell[BoxData[RowBox[{"ResoniteTabletRunDeferred", "[", "\"" <> id <> "\"", "]"}]], "Input"];
    Quiet @ Check[(SelectionMove[nb, After, Notebook]; NotebookWrite[nb, cell, All]; SelectionEvaluate[nb]),
      ($itDeferred[id, "Status"] = "Failed"; Return[None])];
    id];

ResoniteRealtime`ResoniteTabletRunDeferred[id_String] :=
  Module[{d = Lookup[$itDeferred, id, None], r},
    If[!AssociationQ[d] || d["Status"] =!= "Pending" || !MatchQ[d["Expr"], _Hold], Return[Null]];
    r = Block[{$itInDeferredRun = True}, Quiet @ Check[ReleaseHold[d["Expr"]], $Failed]];
    $itDeferred[id] = Join[d, <|"Status" -> If[FailureQ[r] || r === $Failed, "Failed", "Done"],
      "Result" -> r, "Expr" -> None|>];
    itSetStatus[If[AssociationQ[r], d["Label"] <> ": 作成しました",
      d["Label"] <> ": 失敗 " <> ToString[If[FailureQ[r], r["MessageTemplate"], r]]]];
    Null];

ResoniteRealtime`ResoniteTabletDeferred[] := $itDeferred;

(* ============================================================
   tick 駆動の非同期ビルド (待たない組み立て)

   ノートブックのセル評価に予約する方式は、組み立て中 (応答待ちのループ) に runtime の非同期タスクが割り込むと
   FrontEnd とカーネルが待ち合って固まった (2026-09-22 実機、2 回)。なので監視 tick の中で
     Send : スロット/コンポーネントを全部送りっぱなし ($iLinkWaitDefault = False)。ボタンの ButtonToggle だけ後回し
     Wire : 次の tick で root の getSlot (待たない) を送り、応答から ValueField<bool>.Value のメンバ ID を拾って
            ButtonToggle を結線する (10 秒来なければ再送、3 回で諦める)
   の 2 段で組む。どの文脈から呼ばれても待たない。$ResoniteTabletBuildMode: Automatic (監視 tick が動いていれば
   Tick、無ければノートブックのセル) | "Tick" | "Notebook"。
   ============================================================ *)
If[!ValueQ[ResoniteRealtime`$ResoniteTabletBuildMode], ResoniteRealtime`$ResoniteTabletBuildMode = Automatic];
If[!AssociationQ[$itBuilds], $itBuilds = <||>];
$itWireLater = None;
$itWireRounds = None;   (* 2026-09-23: 参照を持つコンポーネントを巡 (getSlot 1 回ごと) に分けて足す。{round1Items, round2Items, ...} *)
$itBuildRoot = None;
$itFrontOffset = 0.35;
itAsyncBuildQ[] := ListQ[$itWireLater];

itTickActiveQ[] := MatchQ[Lookup[$itState, "Task", None], _TaskObject];
itBuildModeTick[] :=
  Switch[ResoniteRealtime`$ResoniteTabletBuildMode, "Tick", True, "Notebook", False, _, itTickActiveQ[]];

itEnqueueBuild[label_String, sender_Function] :=
  Module[{id = StringTake[CreateUUID[], 8]},
    $itBuilds[id] = <|"Phase" -> "Send", "Sender" -> sender, "Label" -> label, "Time" -> iNow[], "Tries" -> 0|>;
    $itDeferred[id] = <|"Expr" -> None, "Label" -> label, "Time" -> iNow[], "Status" -> "Pending", "Via" -> "Tick"|>;
    itSetStatus[label <> " を作成中 (予約 " <> id <> ")"];
    id];

(* 組み立てを予約する共通口: expr は itListGadgetBuild[...] 等の (待つ) ビルダー呼び出し *)
SetAttributes[itDeferBuild, HoldFirst];
itDeferBuild[expr_, label_String, marker_Association] :=
  If[itBuildModeTick[],
    With[{id = itEnqueueBuild[label, Function[expr]]}, Join[<|"Deferred" -> True, "Id" -> id, "Via" -> "Tick"|>, marker]],
    With[{id = itDeferToTopLevel[expr, label]},
      If[StringQ[id], Join[<|"Deferred" -> True, "Id" -> id, "Via" -> "Notebook"|>, marker], expr]]];

itBuildFinish[id_String, status_String, result_] :=
  Module[{b = Lookup[$itBuilds, id, <||>]},
    $itBuilds = KeyDrop[$itBuilds, id];
    (* 失敗したら組みかけの残骸を消す (ボタンが結線されていない一覧は使えない) *)
    If[status =!= "Done" && StringQ[Lookup[b, "Root", None]],
      Block[{$iLinkWaitDefault = False},
        Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[b["Root"]], Null]];
      itForgetGadget[b["Root"]]];
    $itDeferred[id] = Join[Lookup[$itDeferred, id, <||>],
      <|"Status" -> status, "Result" -> result, "Finished" -> iNow[]|>];
    If[status =!= "Done", $itState["LastError"] = <|"Build" -> id, "Label" -> Lookup[b, "Label", ""], "Result" -> result|>];
    itSetStatus[Lookup[b, "Label", "組み立て"] <> If[status === "Done", ": 作成しました",
      ": 失敗 " <> ToString[If[FailureQ[result], result["MessageTemplate"], result]]]]];

itBuildSend[id_String, b_Association] :=
  Module[{res, wires, rounds, root, sent},
    {res, wires, rounds, root} = Block[{$iLinkWaitDefault = False, $itWireLater = {}, $itWireRounds = {}, $itBuildRoot = None},
      {Quiet @ Check[b["Sender"][], $Failed], $itWireLater, $itWireRounds, $itBuildRoot}];
    If[StringQ[root], $itBuilds[id, "Root"] = root];
    If[!AssociationQ[res] || !StringQ[Lookup[res, "Root", None]],
      Return[itBuildFinish[id, "Failed", res]]];
    If[!ListQ[rounds], rounds = {}];
    If[wires === {} && rounds === {}, Return[itBuildFinish[id, "Done", res]]];
    sent = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[res["Root"], "Depth" -> -1,
      "IncludeComponentData" -> True, "Wait" -> False], $Failed];
    If[!AssociationQ[sent] || !StringQ[Lookup[sent, "MessageId", None]],
      Return[itBuildFinish[id, "Failed", iFailure["GetSlot", "結線用の getSlot を送れませんでした。"]]]];
    $itBuilds[id] = Join[b, <|"Phase" -> "Wire", "Round" -> 1, "Result" -> res, "Wires" -> wires, "Rounds" -> rounds,
      "Root" -> res["Root"], "MessageId" -> sent["MessageId"], "Sent" -> iNow[], "Tries" -> 1|>]];

(* 失敗して消したガジェットを台帳からも外す *)
itForgetGadget[root_String] :=
  ($itState["Lists"] = KeyDrop[Lookup[$itState, "Lists", <||>], root];
   $itState["PDFViewers"] = KeyDrop[itPDFViewers[], root];
   With[{v = itViewer[]}, If[AssociationQ[v] && Lookup[Lookup[v, "Board", <||>], "Slot", None] === root,
     $itState["Viewer"] = None]]);

(* Wire 相 (2026-09-23 に「巡」を導入): 1 巡目はボタン (Button + ValueField<bool>) への ButtonToggle 結線と Rounds[[1]]、
   2 巡目以降は Rounds[[n]] (前の巡で足したコンポーネントのメンバ ID を、もう 1 回の getSlot で取ってから足す。
   例: 色トグル箱 = 1 巡目 BooleanValueDriver (TargetField -> 材質の TintColor)、2 巡目 ButtonToggle (-> その State))。
   どれか 1 つでもメンバ ID が取れなければ失敗 (組みかけは消す)。 *)
itBuildWire[id_String, b_Association] :=
  Module[{res = icPollReply[b["MessageId"]], missing = 0, sent, round = Lookup[b, "Round", 1],
          rounds = Replace[Lookup[b, "Rounds", {}], Except[_List] -> {}], items},
    Which[
      AssociationQ[res],
        Block[{$iLinkWaitDefault = False},
          If[round === 1,
            Do[With[{fieldId = itMemberIdFromReply[res, w["ValueField"], "Value"]},
                If[StringQ[fieldId],
                  Quiet @ Check[icComp[w["Slot"], $icFE <> "ButtonToggle",
                    <|"TargetValue" -> ResoniteRealtime`ResoniteRealtimeRef[fieldId]|>], Null],
                  missing++]],
              {w, Replace[Lookup[b, "Wires", {}], Except[_List] -> {}]}]];
          items = If[round <= Length[rounds], rounds[[round]], {}];
          Do[If[!TrueQ[itWireItem[res, item]], missing++], {item, items}]];
        Which[
          missing > 0,
            itBuildFinish[id, "Failed", iFailure["NoMemberId",
              ToString[missing] <> " 個の結線でメンバ ID が取れませんでした (" <> ToString[round] <> " 巡目)。"]],
          round < Length[rounds],
            (* 次の巡: いま足したコンポーネントのメンバ ID を取りに行く *)
            sent = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[b["Result"]["Root"], "Depth" -> -1,
              "IncludeComponentData" -> True, "Wait" -> False], $Failed];
            If[!AssociationQ[sent] || !StringQ[Lookup[sent, "MessageId", None]],
              itBuildFinish[id, "Failed", iFailure["GetSlot", "結線用の getSlot を送れませんでした。"]],
              $itBuilds[id] = Join[b, <|"Round" -> round + 1, "MessageId" -> sent["MessageId"], "Sent" -> iNow[], "Tries" -> 1|>]],
          True, itBuildFinish[id, "Done", b["Result"]]],
      iNow[] - b["Sent"] > 10 && b["Tries"] < 3,
        sent = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[b["Result"]["Root"], "Depth" -> -1,
          "IncludeComponentData" -> True, "Wait" -> False], $Failed];
        $itBuilds[id] = Join[b, <|"MessageId" -> Lookup[sent, "MessageId", b["MessageId"]], "Sent" -> iNow[],
          "Tries" -> b["Tries"] + 1|>],
      iNow[] - b["Sent"] > 10,
        itBuildFinish[id, "Failed", iFailure["Timeout", "結線用の getSlot の応答が来ませんでした。"]],
      True, Null]];

itProcessBuilds[] :=
  KeyValueMap[Function[{id, b},
    Switch[b["Phase"], "Send", itBuildSend[id, b], "Wire", itBuildWire[id, b], _, Null]], $itBuilds];

(* getSlot (Depth -1, IncludeComponentData) の応答からコンポーネントのメンバ (フィールド) の ID を拾う *)
itMemberIdFromReply[res_, compId_String, member_String] :=
  With[{comp = icFindComponent[res, compId]},
    If[AssociationQ[comp], Lookup[Lookup[Lookup[comp, "members", <||>], member, <||>], "id", None], None]];
itMemberIdFromReply[___] := None;

(* <|"TargetField" -> {compId, "TintColor"}, ...|> を <|"TargetField" -> reference, ...|> に解決する。1 つでも取れなければ None *)
itResolveRefs[res_, refs_Association] :=
  Module[{out = <||>, id},
    Do[
      id = itMemberIdFromReply[res, refs[k][[1]], refs[k][[2]]];
      If[!StringQ[id], Return[None, Module]];
      out[k] = ResoniteRealtime`ResoniteRealtimeRef[id],
      {k, Keys[refs]}];
    out];
itResolveRefs[___] := None;

(* 巡の 1 項目: <|"Action" -> "Add" | "Update", "Slot", "Type", "Id" (Add、省略可), "Component" (Update),
   "Members" -> <|...|>, "Refs" -> <|member -> {compId, member}|>|>。参照を解決してから送る (待たない)。 *)
itWireItem[res_, item_Association] :=
  Module[{refs = itResolveRefs[res, Replace[Lookup[item, "Refs", <||>], Except[_Association] -> <||>]], members},
    If[!AssociationQ[refs], Return[False]];
    members = Join[Replace[Lookup[item, "Members", <||>], Except[_Association] -> <||>], refs];
    Switch[Lookup[item, "Action", "Add"],
      "Add", Quiet @ Check[(icComp[item["Slot"], item["Type"], members, Lookup[item, "Id", Automatic]]; True), False],
      "Update", Quiet @ Check[(ResoniteRealtime`ResoniteRealtimeUpdateComponent[item["Component"], members]; True), False],
      _, False]];
itWireItem[___] := False;

(* カーネル再起動などで台帳を失ったガジェットの残骸を、名前でワールドから消す *)
Options[ResoniteRealtime`ResoniteTabletCleanup] = {
  "Names" -> {"Mathematica Tablet", "SourceVault List", "PDF Viewer", "Mathematica Viewer", "Mathematica Video", "Mathematica Chat",
    "Mathematica Toggle Box"},
  "Prefixes" -> {"Mathematica Tablet"}};

ResoniteRealtime`ResoniteTabletCleanup[opts : OptionsPattern[]] :=
  Module[{names, prefixes, tree, val, kids, hits, removed = {}},
    If[!itLinkQ[], Return[iFailure["NotConnected", "ResoniteLink が未接続です。"]]];
    names = OptionValue["Names"]; prefixes = OptionValue["Prefixes"];
    val = If[AssociationQ[#], Lookup[#, "value", #], #] &;
    tree = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot["Root", "Depth" -> 1, "Timeout" -> 30], $Failed];
    If[!AssociationQ[tree], Return[iFailure["GetSlot", "Root の階層が取れませんでした。"]]];
    kids = Lookup[Lookup[tree, "data", <||>], "children", {}];
    hits = Select[kids, With[{nm = ToString[val[Lookup[#, "name", ""]]]},
      MemberQ[names, nm] || AnyTrue[prefixes, StringStartsQ[nm, #] &]] &];
    Do[
      With[{id = Lookup[h, "id", None]},
        If[StringQ[id],
          Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[id], Null];
          AppendTo[removed, <|"Id" -> id, "Name" -> ToString[val[Lookup[h, "name", ""]]]|>]]],
      {h, hits}];
    ResoniteRealtime`ResoniteTabletStop[];
    $itState = Join[$itState, <|"Gadget" -> None, "Viewer" -> None, "PDFViewers" -> <||>, "Lists" -> <||>, "Turn" -> None|>];
    $itBuilds = <||>;
    $itState["Candidates"] = {};
    itRestartServeIfNeeded[];
    removed];
If[!NumericQ[ResoniteRealtime`$ResoniteTabletCloudMaxLevel], ResoniteRealtime`$ResoniteTabletCloudMaxLevel = 0.5];
$itLogLimit = 50;
$itStyleSheet = "SourceVault default.nb";

(* ============================================================
   小物
   ============================================================ *)

SetAttributes[itNoWait, HoldFirst];
itNoWait[expr_] := Block[{$iLinkWaitDefault = False}, expr];

itEnum[name_String] := <|"$type" -> "enum", "value" -> name|>;

itGadget[] := Lookup[$itState, "Gadget", None];
itGadgetQ[] := AssociationQ[itGadget[]];
itLinkQ[] := StringQ[$iState["Link"]];

itAccessLevel[] := N @ ResoniteRealtime`ResoniteAccessLevel[];

itAccessLabel[] :=
  "PL<" <> ToString[NumberForm[itAccessLevel[], {3, 2}]] <> " " <>
  If[TrueQ[ResoniteRealtime`$ResoniteWorldOwner], icAccessName[], "guest"];

itFmt[x_] := ToString[NumberForm[N[x], {3, 2}]];

itTruncate[s_String, n_Integer] :=
  If[StringLength[s] <= n, s, StringTake[s, n] <> " ..."];
itTruncate[s_String] := itTruncate[s, ResoniteRealtime`$ResoniteTabletMaxChars];

(* 機密度が数値で取れなければ fail-closed (1.0 扱い) *)
itPL[pl_] := If[NumericQ[pl] && 0 <= pl <= 1, N[pl], 1.0];

(* 表示上限は「未満」。上限と等しい機密度は出さない (2026-09-23 指示)。
   これで fail-closed (機密度不明 = 1.0) が上限 1.0 の Private ワールドでも効く。 *)
itAllowedQ[pl_] := itPL[pl] < itAccessLevel[] - 10^-9;

itHiddenNote[pl_] :=
  "[非表示: 機密度 " <> itFmt[itPL[pl]] <> " >= 表示上限 " <> itFmt[itAccessLevel[]] <> "]";

(* UIX Text の幅見積り (単位 = キャンバス単位)。ASCII 0.55 em、それ以外 1.0 em *)
itLineWidth[line_String, fs_] :=
  fs * Total[Map[If[# > 255, 1.0, 0.55] &, ToCharacterCode[line]]];

itTextHeight[text_String, fs_, width_] :=
  Module[{lines = StringSplit[text, "\n", All], n},
    n = Total[Map[Max[1, Ceiling[itLineWidth[#, fs] / Max[width, 1.]]] &, lines]];
    n * fs * 1.3 + 24.];

itRecord[key_String, value_] := ($itState = Join[$itState, <|key -> value|>]; value);

(* ============================================================
   UIX 部品 (chat のヘルパの上に、整列つき Text とボタンを足す)
   ============================================================ *)

itText[slot_String, content_String, size_, halign_String : "Left", valign_String : "Top",
    id_ : Automatic, color_ : RGBColor[0.95, 0.95, 0.95, 1]] :=
  icComp[slot, $icUIX <> "Text",
    Join[<|"Content" -> content, "Size" -> N[size], "ParseRichText" -> False, "Color" -> color,
        "HorizontalAlign" -> itEnum[halign], "VerticalAlign" -> itEnum[valign]|>,
      If[StringQ[Lookup[$icMats, "Text", None]],
        <|"Materials" -> <|"$type" -> "list",
            "elements" -> {ResoniteRealtime`ResoniteRealtimeRef[$icMats["Text"]]}|>|>, <||>]], id];

(* 押せるボタン = Button + ValueField<bool> + ButtonToggle (Checkbox は Button ではない。2026-09-06 実機)。
   押すと Value が True になり、WL が読んで False に戻す。戻り値は ValueField の ID。 *)
itButton[parent_String, key_String, label_String, w_, h_, color_RGBColor, fs_] :=
  Module[{s, vf, fieldId, lbl},
    s = icSlot[key, parent];
    icComp[s, $icUIX <> "LayoutElement",
      <|"MinWidth" -> N[w], "MinHeight" -> N[h], "FlexibleWidth" -> 0.|>];
    icImage[s, color];
    icComp[s, $icUIX <> "Button", <||>];
    vf = icComp[s, $icFE <> "ValueField<bool>", <|"Value" -> False|>,
      ResoniteRealtime`ResoniteRealtimeNewId["Btn"]];
    If[ListQ[$itWireLater],
      (* 非同期ビルド: メンバ ID は後で getSlot の応答から拾って ButtonToggle を結線する *)
      AppendTo[$itWireLater, <|"Slot" -> s, "ValueField" -> vf, "Key" -> key|>],
      fieldId = icMemberId[s, vf, "Value"];
      If[!StringQ[fieldId],
        Throw[iFailure["NoMemberId", "ValueField<bool>.Value のメンバ ID が取れませんでした (" <> key <> ")。"], icTag]];
      icComp[s, $icFE <> "ButtonToggle",
        <|"TargetValue" -> ResoniteRealtime`ResoniteRealtimeRef[fieldId]|>]];
    lbl = icSlot["Label", s];
    icComp[lbl, $icUIX <> "RectTransform", <|"AnchorMin" -> {0., 0.}, "AnchorMax" -> {1., 1.}|>];
    itText[lbl, label, fs, "Center", "Middle"];
    vf];

(* ---- スクロールする出力欄 ----
   Output (Image + Mask) > Content (RectTransform 上端固定 + VerticalLayout + ContentSizeFitter(MinSize) + ScrollRect)
   > Text (LayoutElement の MinHeight を文字数から見積る。ContentSizeFitter が Content の高さに写す)。
   2026-09-22: uix skill の「Viewport(Image+Mask) / Content(VerticalLayout+ContentSizeFitter+ScrollRect)」構成。 *)
itOutputArea[parent_String, fs_, minH_] :=
  Module[{out, content, txt, ids = <||>},
    out = icSlot["Output", parent];
    icComp[out, $icUIX <> "LayoutElement", <|"MinHeight" -> N[minH], "FlexibleHeight" -> 1.|>];
    icImage[out, RGBColor[0.12, 0.13, 0.17, 1]];
    icComp[out, $icUIX <> "Mask", <|"ShowMaskGraphic" -> True|>];
    content = icSlot["Content", out];
    icComp[content, $icUIX <> "RectTransform",
      <|"AnchorMin" -> {0., 1.}, "AnchorMax" -> {1., 1.}, "Pivot" -> {0.5, 1.},
        "OffsetMin" -> {0., -N[minH]}, "OffsetMax" -> {0., 0.}|>];
    icComp[content, $icUIX <> "VerticalLayout",
      <|"PaddingTop" -> 12., "PaddingBottom" -> 12., "PaddingLeft" -> 16., "PaddingRight" -> 16.,
        "ForceExpandWidth" -> True, "ForceExpandHeight" -> False|>];
    icComp[content, $icUIX <> "ContentSizeFitter",
      <|"HorizontalFit" -> itEnum["Disabled"], "VerticalFit" -> itEnum["MinSize"]|>];
    ids["Scroll"] = icComp[content, $icUIX <> "ScrollRect", <||>,
      ResoniteRealtime`ResoniteRealtimeNewId["Scroll"]];
    txt = icSlot["Text", content];
    ids["OutputLayout"] = icComp[txt, $icUIX <> "LayoutElement",
      <|"MinHeight" -> N[fs*2], "FlexibleHeight" -> 0.|>,
      ResoniteRealtime`ResoniteRealtimeNewId["OutLayout"]];
    ids["OutputText"] = itText[txt, "", fs*0.85, "Left", "Top",
      ResoniteRealtime`ResoniteRealtimeNewId["OutText"]];
    ids];

(* 置き場所 (chat と同じ): 既定はアバターの正面。見つからなければ Position/Parent *)
itPose[placement_, userSpec_, distance_, height_, pos_, parent_] :=
  Module[{p, g = itGadget[]},
    If[placement === "User",
      (* tick 内の組み立てでは待てない (アバターの位置は getSlot 数回の応答待ち) ので、タブレットがあればその子にする。
         タブレット自体がアバターの正面にあり、掴んで動かしても付いてくる。同じ平面 (z = 0) だと右隣の板
         (Tablet Viewer、幅 1.2 m) に隠れる (2026-09-22 実機: PDF ビューアが板の裏に出て見えなかった) ので、
         利用者側 (-z) に $itFrontOffset だけ出す *)
      If[itAsyncBuildQ[],
        Return[If[AssociationQ[g],
          <|"Parent" -> g["Root"], "Position" -> {0., 0., -$itFrontOffset}, "Rotation" -> None, "User" -> None|>,
          <|"Parent" -> parent, "Position" -> pos, "Rotation" -> None, "User" -> None|>]]];
      p = icUserFrontPose[userSpec, distance, height];
      If[AssociationQ[p], Return[p]]];
    <|"Parent" -> parent, "Position" -> pos, "Rotation" -> None, "User" -> None|>];

(* ============================================================
   タブレット本体
   ============================================================ *)

(* 構成:
   <Name>                 Grabbable, AI_GeneratedContent
   ├─ Panel               Canvas (CanvasSize 単位, PanelScale で縮小), 背景 Image, UI マテリアル
   │  └─ VLayout          VerticalLayout
   │     ├─ Title         Text (名前 + 表示上限)
   │     ├─ Input         Image + Button + TextEditor + TextField / Text
   │     ├─ ButtonRow     [Eval] [Clear] [Cancel]
   │     ├─ Status        Text
   │     ├─ ApprovalRow   [承認] [拒否]   (isActive = False。承認待ちのときだけ有効)
   │     ├─ Output        スクロールする出力欄
   │     └─ ViewerBar     [◀] [n/N] [▶] [閉じる]
   └─ Viewer              ResoniteRealtimeBoard (パネルの右隣)                                     *)
Options[ResoniteRealtime`ResoniteTablet] = {
  "Placement" -> "User", "Distance" -> 1.2, "Height" -> Automatic, "User" -> Automatic,
  "Position" -> {0, 1.3, 1.2}, "Parent" -> "Root", "Name" -> "Mathematica Tablet",
  "CanvasSize" -> {1000, 1500}, "PanelScale" -> 0.0006, "FontSize" -> 26,
  "Viewer" -> True, "ViewerSize" -> 1.2, "Notebook" -> Automatic, "NotebookVisible" -> True,
  "Model" -> Automatic, "Start" -> True, "PollInterval" -> 1.0};

ResoniteRealtime`ResoniteTablet[opts : OptionsPattern[]] :=
  Catch[
    Module[{o, pose, name, csz, pscale, fs, ids, root, panel, vl, input, inText, row, w, board},
      If[!itLinkQ[],
        Return[iFailure["NotConnected",
          "タブレットの組み立てには ResoniteLink が要ります。ResoniteRealtimeLinkConnect[port] を先に実行してください。"]]];
      o = Association @ Join[Options[ResoniteRealtime`ResoniteTablet], {opts}];
      If[itGadgetQ[], Quiet @ ResoniteRealtime`ResoniteTabletRemove[]];
      name = o["Name"]; csz = N[o["CanvasSize"]]; pscale = N[o["PanelScale"]]; fs = N[o["FontSize"]];
      w = csz[[1]] - 48.;
      ids = <|"Buttons" -> <||>|>;
      pose = itPose[o["Placement"], o["User"], o["Distance"], o["Height"], o["Position"], o["Parent"]];
      ids["User"] = pose["User"];

      root = icSlot[name, pose["Parent"], "Position" -> pose["Position"],
        Sequence @@ If[ListQ[pose["Rotation"]], {"Rotation" -> pose["Rotation"]}, {}],
        "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["Tablet"]];
      ids["Root"] = root;
      icComp[root, $icFE <> "Grabbable", <|"Scalable" -> True|>];
      icComp[root, $icFE <> "AI_GeneratedContent",
        <|"Source" -> "Mathematica ResoniteRealtime tablet (ClaudeEval in world)"|>];

      panel = icSlot["Panel", root, "Scale" -> {pscale, pscale, pscale}];
      ids["Panel"] = panel;
      icComp[panel, $icUIX <> "Canvas",
        <|"Size" -> csz, "AcceptRemoteTouch" -> True, "AcceptPhysicalTouch" -> True|>];
      icMakeMaterials[panel];
      ids = Join[ids, $icMats];
      icImage[panel, RGBColor[0.07, 0.08, 0.11, 1]];

      vl = icSlot["VLayout", panel];
      icComp[vl, $icUIX <> "VerticalLayout",
        <|"PaddingTop" -> 24., "PaddingBottom" -> 24., "PaddingLeft" -> 24., "PaddingRight" -> 24.,
          "Spacing" -> 10., "ForceExpandWidth" -> True, "ForceExpandHeight" -> False|>];

      With[{s = icSlot["Title", vl]},
        icLayoutElement[s, fs*1.6, 0];
        ids["TitleText"] = itText[s, name <> "   [" <> itAccessLabel[] <> "]", fs*1.1, "Left", "Middle",
          ResoniteRealtime`ResoniteRealtimeNewId["Title"]]];

      (* 入力欄 (chat と同じ結線: TextEditor.Text -> 子 Text、TextField.Editor -> TextEditor) *)
      input = icSlot["Input", vl];
      ids["Input"] = input;
      icLayoutElement[input, fs*5, 0];
      icImage[input, RGBColor[0.22, 0.24, 0.32, 1]];
      inText = icSlot["Text", input];
      ids["InputText"] = itText[inText, "", fs, "Left", "Top",
        ResoniteRealtime`ResoniteRealtimeNewId["InText"]];
      icComp[input, $icUIX <> "Button", <||>];
      ids["Editor"] = icComp[input, $icFE <> "TextEditor",
        <|"Text" -> ResoniteRealtime`ResoniteRealtimeRef[ids["InputText"]]|>,
        ResoniteRealtime`ResoniteRealtimeNewId["Editor"]];
      icComp[input, $icUIX <> "TextField",
        <|"Editor" -> ResoniteRealtime`ResoniteRealtimeRef[ids["Editor"]]|>];

      (* ボタン行 *)
      row = icSlot["ButtonRow", vl];
      icLayoutElement[row, fs*2.2, 0];
      icComp[row, $icUIX <> "HorizontalLayout", <|"Spacing" -> 12., "ForceExpandWidth" -> False|>];
      ids["Buttons", "Eval"]   = itButton[row, "Eval", "Eval", fs*5, fs*2.2, RGBColor[0.2, 0.45, 0.75, 1], fs];
      ids["Buttons", "Clear"]  = itButton[row, "Clear", "Clear", fs*4, fs*2.2, RGBColor[0.3, 0.32, 0.4, 1], fs*0.9];
      ids["Buttons", "Cancel"] = itButton[row, "Cancel", "Cancel", fs*4.5, fs*2.2, RGBColor[0.5, 0.25, 0.25, 1], fs*0.9];
      ids["Buttons", "Make3D"] = itButton[row, "Make3D", "3D生成", fs*5, fs*2.2, RGBColor[0.25, 0.5, 0.4, 1], fs*0.9];
      (* 接続: インベントリから出したタブレットを Mathematica 側の常駐監視 (ResoniteTabletServe) が引き継ぐ合図 *)
      ids["Buttons", "Connect"] = itButton[row, "Connect", "接続", fs*4, fs*2.2, RGBColor[0.35, 0.3, 0.55, 1], fs*0.9];

      With[{s = icSlot["Status", vl]},
        icLayoutElement[s, fs*1.3, 0];
        ids["StatusText"] = itText[s, "ready", fs*0.75, "Left", "Middle",
          ResoniteRealtime`ResoniteRealtimeNewId["Status"], RGBColor[0.75, 0.85, 0.95, 1]]];

      (* 承認行 (承認待ちのときだけ有効化) *)
      row = icSlot["ApprovalRow", vl];
      ids["ApprovalRow"] = row;
      icLayoutElement[row, fs*2.2, 0];
      icComp[row, $icUIX <> "HorizontalLayout", <|"Spacing" -> 12., "ForceExpandWidth" -> False|>];
      ids["Buttons", "Approve"] = itButton[row, "Approve", "承認 / Approve", fs*9, fs*2.2, RGBColor[0.15, 0.5, 0.25, 1], fs*0.9];
      ids["Buttons", "Deny"]    = itButton[row, "Deny", "拒否 / Deny", fs*7, fs*2.2, RGBColor[0.55, 0.3, 0.15, 1], fs*0.9];
      With[{s = icSlot["ApprovalLabel", row]},
        ids["ApprovalText"] = itText[s, "", fs*0.7, "Left", "Middle",
          ResoniteRealtime`ResoniteRealtimeNewId["ApprLabel"], RGBColor[1, 0.85, 0.5, 1]]];
      icCheck @ ResoniteRealtime`ResoniteRealtimeUpdateSlot[row, <|"isActive" -> False|>];

      (* 出力欄 *)
      ids = Join[ids, itOutputArea[vl, fs, fs*6]];
      ids["ContentWidth"] = w - 32.;
      ids["FontSize"] = fs;

      (* ビューアのページ送り行 *)
      row = icSlot["ViewerBar", vl];
      icLayoutElement[row, fs*2.0, 0];
      icComp[row, $icUIX <> "HorizontalLayout", <|"Spacing" -> 12., "ForceExpandWidth" -> False|>];
      ids["Buttons", "Prev"]  = itButton[row, "Prev", "<", fs*3, fs*2.0, RGBColor[0.3, 0.32, 0.4, 1], fs];
      With[{s = icSlot["PageLabel", row]},
        icComp[s, $icUIX <> "LayoutElement", <|"MinWidth" -> N[fs*6], "FlexibleWidth" -> 0.|>];
        ids["PageText"] = itText[s, "-/-", fs*0.8, "Center", "Middle",
          ResoniteRealtime`ResoniteRealtimeNewId["Page"]]];
      ids["Buttons", "Next"]  = itButton[row, "Next", ">", fs*3, fs*2.0, RGBColor[0.3, 0.32, 0.4, 1], fs];
      ids["Buttons", "Close"] = itButton[row, "Close", "閉じる", fs*5, fs*2.0, RGBColor[0.3, 0.32, 0.4, 1], fs*0.8];

      (* ビューア (板): パネルの右隣。親を root にして一緒に動く *)
      If[TrueQ[o["Viewer"]],
        board = ResoniteRealtime`ResoniteRealtimeBoard["Parent" -> root,
          "Position" -> {csz[[1]]*pscale*0.5 + o["ViewerSize"]*0.5 + 0.08, 0.05, 0},
          "Size" -> o["ViewerSize"], "Name" -> "Tablet Viewer"];
        If[MatchQ[board, _Failure], Throw[board, icTag]];
        ids["Board"] = board;
        (* URL が空の板は市松模様 (テクスチャ無し) で見えるので、最初のページを出すまで隠す (itViewerGo が isActive True にする) *)
        itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateSlot[board["Slot"], <|"isActive" -> False|>], Null];
        $itState = Join[$itState, <|"Viewer" -> <|"Board" -> board, "Pages" -> {}, "Page" -> 0,
          "Title" -> "", "Standalone" -> False|>|>]];

      ids = Join[ids, <|"Name" -> name, "Created" -> DateObject[], "CanvasSize" -> csz, "PanelScale" -> pscale|>];
      $itState = Join[$itState, <|"Gadget" -> ids,
        "Options" -> KeyTake[o, {"Notebook", "NotebookVisible", "Model"}]|>];
      If[Head[o["Notebook"]] === NotebookObject, $itState = Join[$itState, <|"Notebook" -> o["Notebook"]|>]];
      If[TrueQ[o["Start"]], ResoniteRealtime`ResoniteTabletStart["PollInterval" -> o["PollInterval"]]];
      ids],
    icTag];

ResoniteRealtime`ResoniteTabletAttach[ids_Association] /; KeyExistsQ[ids, "Root"] :=
  ($itState = Join[$itState, <|"Gadget" -> ids, "TargetFailures" -> <||>|>];
   If[AssociationQ[Lookup[ids, "Board", None]],
     $itState = Join[$itState, <|"Viewer" -> <|"Board" -> ids["Board"], "Pages" -> {}, "Page" -> 0,
       "Title" -> "", "Standalone" -> False|>|>]];
   ids);

ResoniteRealtime`ResoniteTabletRemove[] :=
  Module[{g = itGadget[], r},
    ResoniteRealtime`ResoniteTabletStop[];
    If[!AssociationQ[g], Return[None]];
    r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[g["Root"]], $Failed];
    If[AssociationQ[Lookup[$iState, "Board", None]] && AssociationQ[Lookup[g, "Board", None]] &&
       $iState["Board"]["Slot"] === g["Board"]["Slot"],
      $iState = Join[$iState, <|"Board" -> None|>]];
    $itState = Join[$itState, <|"Gadget" -> None, "Viewer" -> None, "Turn" -> None|>];
    itRestartServeIfNeeded[];
    r];

(* ---- パネルへの書き込み (待たない) ---- *)

itSetText[key_String, text_String] :=
  Module[{g = itGadget[]},
    If[!AssociationQ[g] || !itLinkQ[] || !StringQ[Lookup[g, key, None]], Return[None]];
    itNoWait @ Quiet @ Check[
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[g[key], <|"Content" -> text|>], $Failed]];

itSetStatus[text_String] := itSetText["StatusText", itTruncate[text, 200]];

itSetOutput[text_String] :=
  Module[{g = itGadget[], t, h},
    If[!AssociationQ[g] || !itLinkQ[], Return[None]];
    t = itTruncate[text];
    h = itTextHeight[t, g["FontSize"]*0.85, Lookup[g, "ContentWidth", 900.]];
    itNoWait @ Quiet @ Check[(
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[g["OutputText"], <|"Content" -> t|>];
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[g["OutputLayout"], <|"MinHeight" -> N[h]|>];
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[g["Scroll"], <|"NormalizedPosition" -> {0., 1.}|>]), $Failed];
    t];

itSetFlag[compId_String, value : (True | False)] :=
  itNoWait @ Quiet @ Check[
    ResoniteRealtime`ResoniteRealtimeUpdateComponent[compId, <|"Value" -> value|>], $Failed];

itSetApprovalRow[active : (True | False), label_String : ""] :=
  Module[{g = itGadget[]},
    If[!AssociationQ[g] || !itLinkQ[], Return[None]];
    itNoWait @ Quiet @ Check[(
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[g["ApprovalText"], <|"Content" -> label|>];
      ResoniteRealtime`ResoniteRealtimeUpdateSlot[g["ApprovalRow"], <|"isActive" -> active|>]), $Failed]];

itSetInput[text_String] :=
  Module[{g = itGadget[]},
    If[!AssociationQ[g] || !itLinkQ[], Return[None]];
    itNoWait @ Quiet @ Check[
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[g["InputText"], <|"Content" -> text|>], $Failed]];

(* ============================================================
   ビューア (ページ画像の板)
   ============================================================ *)

itViewer[] := Lookup[$itState, "Viewer", None];

Options[ResoniteRealtime`ResoniteViewer] = {
  "Placement" -> "User", "Distance" -> 1.5, "Height" -> Automatic, "User" -> Automatic,
  "Position" -> {0, 1.5, 1.2}, "Rotation" -> None, "Parent" -> "Root", "Size" -> 0.9,
  "Name" -> "Mathematica Viewer"};

ResoniteRealtime`ResoniteViewer[opts : OptionsPattern[]] :=
  If[itAsyncContextQ[],
    itDeferBuild[itViewerBuild[opts], "ビューア", <|"Kind" -> "Viewer"|>],
    itViewerBuild[opts]];

itViewerBuild[opts : OptionsPattern[ResoniteRealtime`ResoniteViewer]] :=
  Module[{o, pose, board},
    If[!itLinkQ[], Return[iFailure["NotConnected", "ResoniteLink が未接続です。"]]];
    o = Association @ Join[Options[ResoniteRealtime`ResoniteViewer], {opts}];
    pose = itPose[o["Placement"], o["User"], o["Distance"], o["Height"], o["Position"], o["Parent"]];
    board = ResoniteRealtime`ResoniteRealtimeBoard["Parent" -> pose["Parent"], "Position" -> pose["Position"],
      "Rotation" -> If[ListQ[pose["Rotation"]], pose["Rotation"], o["Rotation"]],
      "Size" -> o["Size"], "Name" -> o["Name"]];
    If[MatchQ[board, _Failure], Return[board]];
    itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateSlot[board["Slot"], <|"isActive" -> False|>], Null];
    $itState = Join[$itState, <|"Viewer" -> <|"Board" -> board, "Pages" -> {}, "Page" -> 0,
      "Title" -> "", "Standalone" -> True|>|>];
    board];

ResoniteRealtime`ResoniteViewerRemove[] :=
  Module[{v = itViewer[], r = None},
    If[AssociationQ[v] && TrueQ[v["Standalone"]],
      r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[v["Board"]["Slot"]], $Failed];
      $itState = Join[$itState, <|"Viewer" -> None|>]];
    r];

(* ビューアが無ければ、タブレットがあればその板、無ければ単独ビューアを作る *)
itEnsureViewer[] :=
  Module[{v = itViewer[]},
    If[AssociationQ[v], Return[v]];
    (* 予約を挟まず直接組む (応答待ちが要るので非同期文脈では失敗するが、タブレットがあれば板は既にある) *)
    If[MatchQ[itViewerBuild[], _Failure], Return[None]];
    itViewer[]];

(* 画像配信 (L3) が無ければ L1/L3 サーバを立てる *)
itEnsureImageServer[] :=
  (If[!icImageServerQ[], Quiet @ Check[ResoniteRealtime`ResoniteRealtimeStart[], Null]];
   icImageServerQ[]);

(* ---- ページ仕様 -> PNG の URL (キャッシュ) ----
   仕様: Image | Graphics 等 | {"PDF", file, n} | {"File", path} | {"URL", url, {w,h}} *)
itPageKey[spec_] := Hash[spec, "SHA256", "HexString"];

itRenderPage[img_?ImageQ, size_] := img;
(* PDF ページ: まず FrontEnd を使わない "PageImages" (監視 tick の中でも安全)、駄目なら "Pages" + Rasterize *)
itRenderPage[{"PDF", file_String, n_Integer}, size_] :=
  Module[{img, pg},
    img = Quiet @ Check[TimeConstrained[
      Import[file, {"PDF", "PageImages", {n}}, ImageResolution -> Round[150*size/1200]], 60, $Failed], $Failed];
    If[ListQ[img] && img =!= {} && ImageQ[First[img]], Return[First[img]]];
    pg = Quiet @ Check[TimeConstrained[Import[file, {"PDF", "Pages", {n}}], 60, $Failed], $Failed];
    If[!ListQ[pg] || pg === {}, Return[$Failed]];
    iRasterize[First[pg], size]];
itRenderPage[{"File", path_String}, size_] :=
  Module[{img = Quiet @ Check[Import[path], $Failed]},
    If[ImageQ[img], img, $Failed]];
itRenderPage[expr_, size_] := iRasterize[expr, size];

itPageURL[spec_, size_ : 1200] :=
  Module[{key = itPageKey[spec], hit, img, dir, name, file, url},
    hit = Lookup[$itPageCache, key, None];
    If[AssociationQ[hit] && FileExistsQ[hit["File"]], Return[hit]];
    If[MatchQ[spec, {"URL", _String, _List}],
      Return[$itPageCache[key] = <|"URL" -> spec[[2]], "Dim" -> spec[[3]], "File" -> ""|>]];
    img = Quiet @ Check[UsingFrontEnd @ itRenderPage[spec, size], $Failed];
    If[!ImageQ[img], Return[$Failed]];
    dir = iEnsureAssetDirectory[];
    name = "pg" <> StringTake[key, 16] <> ".png";
    file = FileNameJoin[{dir, name}];
    Quiet @ Check[Export[file, img, "PNG"], Return[$Failed]];
    url = iBaseURL[] <> "/" <> name;
    $itPageCache[key] = <|"URL" -> url, "Dim" -> ImageDimensions[img], "File" -> file|>];

itFitBoardDim[board_Association, {w_, h_}] :=
  Module[{sz = Lookup[board, "Size", 0.6], m = Max[w, h, 1]},
    itNoWait @ Quiet @ Check[
      ResoniteRealtime`ResoniteRealtimeUpdateSlot[board["Slot"],
        <|"scale" -> {sz*w/m, sz*h/m, sz}, "isActive" -> True|>], $Failed]];

itSetPageLabel[] :=
  Module[{v = itViewer[], n, total},
    If[!AssociationQ[v], Return[None]];
    n = v["Page"]; total = Length[v["Pages"]];
    itSetText["PageText", If[total === 0, "-/-", ToString[n] <> "/" <> ToString[total]]]];

itViewerGo[n_Integer] :=
  Module[{v = itViewer[], pages, k, page},
    If[!AssociationQ[v], Return[iFailure["NoViewer", "ビューアがありません。"]]];
    pages = v["Pages"];
    If[pages === {}, Return[None]];
    k = Clip[n, {1, Length[pages]}];
    If[!itEnsureImageServer[],
      itSetStatus["(画像配信サーバが無いので板に出せません: ResoniteRealtimeStart[])"];
      Return[iFailure["NoServer", "画像配信 (ResoniteRealtimeStart[]) が要ります。"]]];
    page = itPageURL[pages[[k]]];
    If[!AssociationQ[page],
      $itState["LastError"] = iFailure["PageRender",
        "ページ " <> ToString[k] <> " を描けませんでした: " <> ToString[Short[pages[[k]], 2]]];
      itSetStatus["ページ " <> ToString[k] <> " を描けませんでした"];
      Return[$itState["LastError"]]];
    $itState["Viewer"]["Page"] = k;
    itNoWait @ Quiet @ Check[
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[v["Board"]["Texture"],
        <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", page["URL"]]|>], $Failed];
    itFitBoardDim[v["Board"], page["Dim"]];
    itSetPageLabel[];
    k];

Options[ResoniteRealtime`ResoniteViewerShow] = {"Title" -> ""};

ResoniteRealtime`ResoniteViewerShow[pages_List, opts : OptionsPattern[]] :=
  Module[{v = itEnsureViewer[]},
    If[!AssociationQ[v], Return[iFailure["NoViewer", "ビューアを作れませんでした (ResoniteLink 未接続?)。"]]];
    $itState["Viewer"]["Pages"] = pages;
    $itState["Viewer"]["Page"] = 0;
    $itState["Viewer"]["Title"] = OptionValue["Title"];
    If[pages === {}, itSetPageLabel[]; Return[0]];
    itViewerGo[1]];

ResoniteRealtime`ResoniteViewerShow[page_, opts : OptionsPattern[]] /; !ListQ[page] :=
  ResoniteRealtime`ResoniteViewerShow[{page}, opts];

ResoniteRealtime`ResoniteViewerPage[n_Integer] := itViewerGo[n];
ResoniteRealtime`ResoniteViewerPage[dir_String] :=
  Module[{v = itViewer[]},
    If[!AssociationQ[v] || v["Pages"] === {}, Return[None]];
    itViewerGo @ Switch[dir,
      "Next", v["Page"] + 1, "Prev", v["Page"] - 1, "First", 1, "Last", Length[v["Pages"]], _, v["Page"]]];

itViewerHide[] :=
  Module[{v = itViewer[]},
    If[!AssociationQ[v], Return[None]];
    itNoWait @ Quiet @ Check[
      ResoniteRealtime`ResoniteRealtimeUpdateSlot[v["Board"]["Slot"], <|"isActive" -> False|>], $Failed]];

(* ---- 動画の板 (実機未確認 2026-09-22) ----
   本体の Options[ResoniteRealtimeBoard] はこのファイルより後で定義されるので写さず、ここに書く *)
Options[ResoniteRealtime`ResoniteVideoBoard] = {
  "Position" -> {0, 1.5, 1.2}, "Rotation" -> None, "Size" -> 0.8,
  "Name" -> "Mathematica Video", "Parent" -> "Root"};

ResoniteRealtime`ResoniteVideoBoard[src_String, opts : OptionsPattern[]] :=
  If[itAsyncContextQ[],
    itDeferBuild[itVideoBoardBuild[src, opts], "動画の板", <|"Kind" -> "VideoBoard"|>],
    itVideoBoardBuild[src, opts]];

itVideoBoardBuild[src_String, opts : OptionsPattern[ResoniteRealtime`ResoniteVideoBoard]] :=
  Catch[
    Module[{url, o, ids, slot},
      If[!itLinkQ[], Return[iFailure["NotConnected", "ResoniteLink が未接続です。"]]];
      url = If[StringStartsQ[src, "http://" | "https://"], src,
        (itEnsureImageServer[]; ResoniteRealtime`ResoniteRealtimeAsset[src])];
      If[MatchQ[url, _Failure], Return[url]];
      o = Association @ Join[Options[ResoniteRealtime`ResoniteVideoBoard], {opts}];
      ids = <|"Slot" -> ResoniteRealtime`ResoniteRealtimeNewId["Video"],
        "Provider" -> ResoniteRealtime`ResoniteRealtimeNewId["VidTex"],
        "Mesh" -> ResoniteRealtime`ResoniteRealtimeNewId["Quad"],
        "Material" -> ResoniteRealtime`ResoniteRealtimeNewId["Mat"],
        "Renderer" -> ResoniteRealtime`ResoniteRealtimeNewId["Rend"],
        "Audio" -> ResoniteRealtime`ResoniteRealtimeNewId["Audio"], "URL" -> url|>;
      slot = icSlot[o["Name"], o["Parent"], "Position" -> o["Position"],
        "Scale" -> {o["Size"], o["Size"]*9/16, o["Size"]},
        Sequence @@ If[ListQ[o["Rotation"]], {"Rotation" -> o["Rotation"]}, {}], "Id" -> ids["Slot"]];
      $itBuildRoot = slot;
      icComp[slot, $icFE <> "VideoTextureProvider",
        <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", url], "Stream" -> False|>, ids["Provider"]];
      icComp[slot, $icFE <> "QuadMesh", <||>, ids["Mesh"]];
      icComp[slot, $icFE <> "UnlitMaterial",
        <|"Texture" -> ResoniteRealtime`ResoniteRealtimeRef[ids["Provider"]]|>, ids["Material"]];
      icComp[slot, $icFE <> "MeshRenderer",
        <|"Mesh" -> ResoniteRealtime`ResoniteRealtimeRef[ids["Mesh"]],
          "Materials" -> <|"$type" -> "list",
            "elements" -> {ResoniteRealtime`ResoniteRealtimeRef[ids["Material"]]}|>|>, ids["Renderer"]];
      Quiet @ Check[icComp[slot, $icFE <> "AudioOutput",
        <|"Source" -> ResoniteRealtime`ResoniteRealtimeRef[ids["Provider"]]|>, ids["Audio"]], Null];
      ids],
    icTag];

(* ============================================================
   PDF ビューア (掴めるパネル + ページ送り)。Resonite のドキュメントビューア風

   <Name>                 Grabbable, AI_GeneratedContent
   ├─ Panel               Canvas (CanvasSize 単位, PanelScale), 背景 Image, UI マテリアル
   │  └─ VLayout
   │     ├─ Header        [<<] [<] n/N [>] [>>] [閉じる]
   │     ├─ Title         Text
   │     └─ Page          Image (Sprite <- SpriteProvider <- StaticTexture2D の URL。PreserveAspect)
   ページ画像は itPageURL (PNG を L3 で配信) で作り、StaticTexture2D の URL を差し替える (待たない送信)。
   ============================================================ *)

Options[ResoniteRealtime`ResonitePDFViewer] = {
  "Placement" -> "User", "Distance" -> 1.0, "Height" -> Automatic, "User" -> Automatic, "Offset" -> {0.65, 0, 0},
  "Position" -> {0, 1.3, 1.0}, "Parent" -> "Root", "CanvasSize" -> {1000, 1400}, "PanelScale" -> 0.0006,
  "FontSize" -> 30, "Name" -> "PDF Viewer", "Title" -> "", "PageSize" -> 1200, "MaxPages" -> 400, "Reuse" -> False};

(* ビューアは複数 (root -> 記録、作った順)。▶ を押すたびに増え、前のは残る (2026-09-22 ユーザー指示)。
   itPDF[] は最新、itPDF[root] はそのビューア *)
itPDFViewers[] := Replace[Lookup[$itState, "PDFViewers", <||>], Except[_Association] -> <||>];
itPDF[] := With[{vs = itPDFViewers[]}, If[Length[vs] === 0, None, Last[vs]]];
itPDF[root_String] := Lookup[itPDFViewers[], root, None];
itPDFRoot[] := With[{vs = itPDFViewers[]}, If[Length[vs] === 0, None, Last[Keys[vs]]]];
(* "Reuse" の解決: True = 最新のビューア、root 文字列 = そのビューア (在れば)、それ以外 = 新規 *)
itPDFReuseRoot[reuse_] :=
  Switch[reuse, True, itPDFRoot[], _String, If[AssociationQ[itPDF[reuse]], reuse, None], _, None];
(* 2 つ目以降は右下手前へ少しずつずらす (重ならない。掴んで並べ替えられる) *)
$itPDFCascade = {0.12, -0.05, -0.06};

(* 利用者の局所座標 (x 右, y 上, z 前) での offset を足す *)
itPoseWithOffset[pose_Association, off_List] :=
  If[ListQ[pose["Rotation"]] && Length[pose["Rotation"]] === 4,
    Join[pose, <|"Position" -> pose["Position"] + icQuatRotate[pose["Rotation"], N[off]]|>],
    Join[pose, <|"Position" -> pose["Position"] + N[off]|>]];

(* ファイル -> ページ仕様 *)
itPagesOfFile[file_String, maxPages_Integer] :=
  Module[{ext = itExt[file], n, nb, cells},
    Switch[ext,
      "pdf",
        n = Quiet @ Check[Import[file, "PageCount"], $Failed];
        If[!IntegerQ[n] || n < 1, Throw[iFailure["PDF", file <> " のページ数が取れませんでした。"], icTag]];
        Table[{"PDF", file, k}, {k, 1, Min[n, maxPages]}],
      "png" | "jpg" | "jpeg" | "gif" | "bmp" | "tif" | "tiff" | "webp", {{"File", file}},
      "nb",
        nb = Quiet @ Check[Import[file, "Notebook"], $Failed];
        cells = If[MatchQ[nb, Notebook[_List, ___]], First[nb], {}];
        If[cells === {}, Throw[iFailure["Notebook", file <> " を読めませんでした。"], icTag]];
        itRasterPages[cells],
      _, Throw[iFailure["Unsupported", "拡張子 ." <> ext <> " はビューアに出せません: " <> file], icTag]]];

ResoniteRealtime`ResonitePDFViewer[file_String, opts : OptionsPattern[]] :=
  Catch[
    With[{o = Association @ Join[Options[ResoniteRealtime`ResonitePDFViewer], {opts}]},
      ResoniteRealtime`ResonitePDFViewer[itPagesOfFile[file, o["MaxPages"]],
        "Title" -> Replace[o["Title"], "" -> FileNameTake[file]], opts]],
    icTag];

ResoniteRealtime`ResonitePDFViewer[pages_List, opts : OptionsPattern[]] :=
  Module[{o = Association @ Join[Options[ResoniteRealtime`ResonitePDFViewer], {opts}]},
    Which[
      pages === {}, iFailure["NoPages", "ページがありません。"],
      StringQ[itPDFReuseRoot[o["Reuse"]]], itPDFLoad[itPDFReuseRoot[o["Reuse"]], pages, o["Title"]],
      itAsyncContextQ[],
        itDeferBuild[itPDFViewerBuild[pages, opts], "PDF ビューア",
          <|"Kind" -> "PDFViewer", "Pages" -> Length[pages], "Title" -> o["Title"]|>],
      True, itPDFViewerBuild[pages, opts]]];

itPDFViewerBuild[pages_List, opts : OptionsPattern[ResoniteRealtime`ResonitePDFViewer]] :=
  Catch[
    Module[{o, pose, ids, root, panel, vl, fs, csz, pscale, row, pageSlot, first, k},
      If[!itLinkQ[], Return[iFailure["NotConnected", "PDF ビューアの組み立てには ResoniteLink が要ります。"]]];
      o = Association @ Join[Options[ResoniteRealtime`ResonitePDFViewer], {opts}];
      k = Length[itPDFViewers[]];
      If[!itEnsureImageServer[], Return[iFailure["NoServer", "画像配信 (ResoniteRealtimeStart[]) が要ります。"]]];
      first = itPageURL[First[pages], o["PageSize"]];
      If[!AssociationQ[first], Return[iFailure["PageRender", "1 ページ目を描けませんでした。"]]];
      fs = N[o["FontSize"]]; csz = N[o["CanvasSize"]]; pscale = N[o["PanelScale"]];
      pose = itPoseWithOffset[itPose[o["Placement"], o["User"], o["Distance"], o["Height"], o["Position"], o["Parent"]],
        If[o["Placement"] === "User", o["Offset"], {0, 0, 0}] + k*$itPDFCascade];
      ids = <|"Buttons" -> <||>|>;
      root = icSlot[o["Name"], pose["Parent"], "Position" -> pose["Position"],
        Sequence @@ If[ListQ[pose["Rotation"]], {"Rotation" -> pose["Rotation"]}, {}],
        "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["PDF"]];
      ids["Root"] = root; $itBuildRoot = root;
      icComp[root, $icFE <> "Grabbable", <|"Scalable" -> True|>];
      icComp[root, $icFE <> "AI_GeneratedContent",
        <|"Source" -> "Mathematica ResoniteRealtime PDF viewer (page images)"|>];
      panel = icSlot["Panel", root, "Scale" -> {pscale, pscale, pscale}];
      icComp[panel, $icUIX <> "Canvas",
        <|"Size" -> csz, "AcceptRemoteTouch" -> True, "AcceptPhysicalTouch" -> True|>];
      icMakeMaterials[panel];
      ids = Join[ids, $icMats];
      icImage[panel, RGBColor[0.12, 0.12, 0.14, 1]];
      vl = icSlot["VLayout", panel];
      icComp[vl, $icUIX <> "VerticalLayout",
        <|"PaddingTop" -> 16., "PaddingBottom" -> 16., "PaddingLeft" -> 16., "PaddingRight" -> 16.,
          "Spacing" -> 10., "ForceExpandWidth" -> True, "ForceExpandHeight" -> False|>];
      row = icSlot["Header", vl];
      icLayoutElement[row, fs*2.0, 0];
      icComp[row, $icUIX <> "HorizontalLayout", <|"Spacing" -> 10., "ForceExpandWidth" -> False|>];
      ids["Buttons", "Prev10"] = itButton[row, "Prev10", "<<", fs*2.6, fs*2.0, RGBColor[0.3, 0.32, 0.4, 1], fs*0.9];
      ids["Buttons", "Prev"]   = itButton[row, "Prev", "<", fs*2.6, fs*2.0, RGBColor[0.3, 0.32, 0.4, 1], fs];
      With[{s = icSlot["PageLabel", row]},
        icComp[s, $icUIX <> "LayoutElement", <|"MinWidth" -> N[fs*6], "FlexibleWidth" -> 0.|>];
        ids["PageText"] = itText[s, "1/" <> ToString[Length[pages]], fs*0.85, "Center", "Middle",
          ResoniteRealtime`ResoniteRealtimeNewId["PdfPage"]]];
      ids["Buttons", "Next"]   = itButton[row, "Next", ">", fs*2.6, fs*2.0, RGBColor[0.3, 0.32, 0.4, 1], fs];
      ids["Buttons", "Next10"] = itButton[row, "Next10", ">>", fs*2.6, fs*2.0, RGBColor[0.3, 0.32, 0.4, 1], fs*0.9];
      ids["Buttons", "Close"]  = itButton[row, "Close", "閉じる", fs*4.5, fs*2.0, RGBColor[0.5, 0.25, 0.25, 1], fs*0.8];
      With[{s = icSlot["Title", vl]},
        icLayoutElement[s, fs*1.2, 0];
        ids["TitleText"] = itText[s, itTruncate[o["Title"], 80], fs*0.7, "Left", "Middle",
          ResoniteRealtime`ResoniteRealtimeNewId["PdfTitle"], RGBColor[0.85, 0.88, 0.95, 1]]];
      (* ページ画像: StaticTexture2D -> SpriteProvider -> Image (PreserveAspect) *)
      pageSlot = icSlot["Page", vl];
      icComp[pageSlot, $icUIX <> "LayoutElement", <|"MinHeight" -> N[fs*10], "FlexibleHeight" -> 1.|>];
      ids["Texture"] = icComp[pageSlot, $icFE <> "StaticTexture2D",
        <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", first["URL"]]|>,
        ResoniteRealtime`ResoniteRealtimeNewId["PdfTex"]];
      ids["Sprite"] = icComp[pageSlot, $icFE <> "SpriteProvider",
        <|"Texture" -> ResoniteRealtime`ResoniteRealtimeRef[ids["Texture"]]|>,
        ResoniteRealtime`ResoniteRealtimeNewId["PdfSprite"]];
      ids["Image"] = icComp[pageSlot, $icUIX <> "Image",
        Join[<|"Sprite" -> ResoniteRealtime`ResoniteRealtimeRef[ids["Sprite"]], "PreserveAspect" -> True,
            "Tint" -> RGBColor[1, 1, 1, 1]|>,
          If[StringQ[Lookup[$icMats, "Image", None]],
            <|"Material" -> ResoniteRealtime`ResoniteRealtimeRef[$icMats["Image"]]|>, <||>]],
        ResoniteRealtime`ResoniteRealtimeNewId["PdfImage"]];
      ids = Join[ids, <|"Name" -> o["Name"], "Created" -> DateObject[]|>];
      $itState["PDFViewers"] = Append[itPDFViewers[], root -> <|"Ids" -> ids, "Pages" -> pages, "Page" -> 1,
        "Title" -> o["Title"], "PageSize" -> o["PageSize"], "Created" -> iNow[]|>];
      itSetStatus["PDF ビューア: " <> itTruncate[o["Title"], 40] <> " (" <> ToString[Length[pages]] <> " ページ)"];
      <|"Root" -> root, "Pages" -> Length[pages], "Page" -> 1, "Title" -> o["Title"]|>],
    icTag];

(* 既存のビューアへ読み込む (待たない送信だけ。tick の中からも呼べる) *)
itPDFLoad[root_String, pages_List, title_String] :=
  Module[{v = itPDF[root]},
    If[!AssociationQ[v], Return[iFailure["NoViewer", "PDF ビューアがありません。"]]];
    $itState["PDFViewers", root, "Pages"] = pages;
    $itState["PDFViewers", root, "Page"] = 0;
    $itState["PDFViewers", root, "Title"] = title;
    itNoWait @ Quiet @ Check[
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[v["Ids"]["TitleText"], <|"Content" -> itTruncate[title, 80]|>], $Failed];
    itPDFGo[root, 1];
    <|"Root" -> root, "Pages" -> Length[pages], "Page" -> 1, "Title" -> title|>];

itPDFGo[n_Integer] := With[{r = itPDFRoot[]}, If[StringQ[r], itPDFGo[r, n], iFailure["NoViewer", "PDF ビューアがありません。"]]];
itPDFGo[root_String, n_Integer] :=
  Module[{v = itPDF[root], pages, k, page},
    If[!AssociationQ[v], Return[iFailure["NoViewer", "PDF ビューアがありません。"]]];
    pages = v["Pages"];
    If[pages === {}, Return[None]];
    k = Clip[n, {1, Length[pages]}];
    page = itPageURL[pages[[k]], Lookup[v, "PageSize", 1200]];
    If[!AssociationQ[page],
      $itState["LastError"] = iFailure["PageRender", "ページ " <> ToString[k] <> " を描けませんでした: " <> ToString[Short[pages[[k]], 2]]];
      itSetStatus["ページ " <> ToString[k] <> " を描けませんでした"];
      Return[$itState["LastError"]]];
    $itState["PDFViewers", root, "Page"] = k;
    itNoWait @ Quiet @ Check[(
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[v["Ids"]["Texture"],
        <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", page["URL"]]|>];
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[v["Ids"]["PageText"],
        <|"Content" -> ToString[k] <> "/" <> ToString[Length[pages]]|>]), $Failed];
    k];

ResoniteRealtime`ResonitePDFViewerPage[n_Integer] := itPDFGo[n];
ResoniteRealtime`ResonitePDFViewerPage[root_String, n_Integer] := itPDFGo[root, n];
ResoniteRealtime`ResonitePDFViewerPage[dir_String] :=
  With[{r = itPDFRoot[]}, If[StringQ[r], ResoniteRealtime`ResonitePDFViewerPage[r, dir], None]];
ResoniteRealtime`ResonitePDFViewerPage[root_String, dir_String] :=
  Module[{v = itPDF[root]},
    If[!AssociationQ[v] || v["Pages"] === {}, Return[None]];
    itPDFGo[root, Switch[dir,
      "Next", v["Page"] + 1, "Prev", v["Page"] - 1, "First", 1, "Last", Length[v["Pages"]],
      "+10", v["Page"] + 10, "-10", v["Page"] - 10, _, v["Page"]]]];

ResoniteRealtime`ResonitePDFViewerRemove[] :=
  With[{r = itPDFRoot[]}, If[StringQ[r], ResoniteRealtime`ResonitePDFViewerRemove[r], None]];
ResoniteRealtime`ResonitePDFViewerRemove[All] :=
  Map[ResoniteRealtime`ResonitePDFViewerRemove, Keys[itPDFViewers[]]];
ResoniteRealtime`ResonitePDFViewerRemove[root_String] :=
  Module[{v = itPDF[root], r = None},
    If[AssociationQ[v],
      r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[root], $Failed];
      $itState["PDFViewers"] = KeyDrop[itPDFViewers[], root]];
    r];

itHandlePDF[root_String, res_Association] :=
  Module[{v = itPDF[root], pressed},
    If[!AssociationQ[v], Return[Null]];
    pressed = itPressed[res, v["Ids"]["Buttons"]];
    If[pressed === {}, Return[Null]];
    Scan[itSetFlag[v["Ids"]["Buttons"][#], False] &, pressed];
    Which[
      MemberQ[pressed, "Close"], ResoniteRealtime`ResonitePDFViewerRemove[root],
      MemberQ[pressed, "Prev10"], ResoniteRealtime`ResonitePDFViewerPage[root, "-10"],
      MemberQ[pressed, "Next10"], ResoniteRealtime`ResonitePDFViewerPage[root, "+10"],
      MemberQ[pressed, "Prev"], ResoniteRealtime`ResonitePDFViewerPage[root, "Prev"],
      MemberQ[pressed, "Next"], ResoniteRealtime`ResonitePDFViewerPage[root, "Next"],
      True, Null];
    pressed];

(* ============================================================
   SourceVault オブジェクトの表示 (一般 API)
   ============================================================ *)

Options[ResoniteRealtime`ResoniteShowObject] = {"Title" -> Automatic, "MaxPages" -> 200, "PageSize" -> 1200};

ResoniteRealtime`ResoniteShowObject[x_, opts : OptionsPattern[]] :=
  Catch[
    Module[{o = Association @ Join[Options[ResoniteRealtime`ResoniteShowObject], {opts}], r},
      r = itShowObject[x, o];
      If[AssociationQ[r], itSetStatus["表示: " <> ToString[Lookup[r, "Title", ""]]]];
      r],
    icTag];

itRefuse[pl_, what_String] :=
  (itSetStatus["表示不可: " <> what <> " の機密度 " <> itFmt[itPL[pl]] <> " >= 表示上限 " <> itFmt[itAccessLevel[]]];
   Throw[iFailure["PrivacyExceeded",
     what <> " の機密度 " <> itFmt[itPL[pl]] <> " が表示上限 " <> itFmt[itAccessLevel[]] <> " 以上です。"], icTag]);

itGate[pl_, what_String] := If[!itAllowedQ[pl], itRefuse[pl, what]];

(* sv:// オブジェクトの機密度 (fail-closed) *)
itObjectPL[uri_String] :=
  Module[{f = icSym["SourceVault`SourceVaultObjectPrivacyLevel"], pl},
    If[f === None, Return[1.0]];
    pl = Quiet @ Check[f[uri], $Failed];
    itPL[pl]];

(* 行のキーは core 関数の共通スキーマ (PrivacyLevel / Kind / Date / Title) が正だが、LLM が手で組んだ行
   (PL / 種別 / 日付 など) も受ける (2026-09-22 実機) *)
itRowGet[row_Association, keys_List, default_] :=
  With[{hit = SelectFirst[keys, KeyExistsQ[row, #] &, None]}, If[hit === None, default, row[hit]]];

itRowPL[row_Association] :=
  Module[{pl = itRowGet[row, {"PrivacyLevel", "PL", "Privacy", "privacyLevel", "機密度"}, None]},
    Which[
      NumericQ[pl], itPL[pl],
      StringQ[Lookup[row, "URI", None]] && StringStartsQ[row["URI"], "sv://"], itObjectPL[row["URI"]],
      True, 1.0]];

itRowKind[row_Association] := ToString[itRowGet[row, {"Kind", "kind", "種別", "Type"}, ""]];
itRowTitle[row_Association] :=
  ToString[itRowGet[row, {"Title", "Subject", "Name", "title", "題名", "件名", "Id"}, "?"]];

itExt[file_String] := ToLowerCase[FileExtension[file]];

itKindLabel[row_Association] :=
  StringRiffle[DeleteCases[{itRowKind[row],
    With[{d = itRowGet[row, {"Date", "Published", "日付", "date", "Time"}, ""]},
      If[StringQ[d], StringTake[d, UpTo[16]], If[DateObjectQ[d], DateString[d, "ISODate"], ""]]]}, ""], ", "];

(* ---- 種別ごとの分岐 ---- *)

(* 行リスト -> 一覧ガジェット *)
itShowObject[rows : {__Association}, o_] :=
  ResoniteRealtime`ResoniteListGadget[rows,
    "Title" -> Replace[o["Title"], Automatic -> "SourceVault"]];
itShowObject[ds_Dataset, o_] := itShowObject[Normal[ds], o];
itShowObject[{}, o_] := (itSetOutput["(該当なし)"]; <|"Kind" -> "Empty", "Pages" -> 0|>);

(* sv:// URI *)
itShowObject[uri_String, o_] /; StringStartsQ[uri, "sv://"] :=
  Module[{pl, props, kind, file, ref, data, title},
    If[!icSVQ[], Throw[iFailure["NoSourceVault", "SourceVault がロードされていません。"], icTag]];
    pl = itObjectPL[uri];
    itGate[pl, uri];
    props = Quiet @ Check[icSym["SourceVault`SourceVaultObjectProperties"][uri], $Failed];
    kind = If[AssociationQ[props], ToString[Lookup[props, "Kind", ""]], ""];
    title = If[AssociationQ[props], ToString[Lookup[props, "Name", Lookup[props, "Title", uri]]], uri];
    file = If[AssociationQ[props], Lookup[props, "FilePath", None], None];
    If[!StringQ[file] || !FileExistsQ[file],
      ref = Quiet @ Check[icSym["SourceVault`SourceVaultResolveReference"][uri], $Failed];
      If[AssociationQ[ref],
        file = Lookup[ref, "File", ""];
        title = Replace[Lookup[ref, "Title", title], "" -> title]]];
    If[StringQ[file] && file =!= "" && FileExistsQ[file],
      Return[itShowFile[file, pl, Replace[o["Title"], Automatic -> title], o]]];
    data = Quiet @ Check[icSym["SourceVault`SourceVaultObjectData"][uri], $Failed];
    Which[
      ImageQ[data], itShowPages[{data}, title, pl, o, "Image"],
      AssociationQ[data] && StringQ[Lookup[data, "FilePath", None]] && FileExistsQ[data["FilePath"]],
        itShowFile[data["FilePath"], pl, title, o],
      StringQ[data], itShowText[data, title, pl],
      AssociationQ[data], itShowText[itAssocText[data], title, pl],
      True, Throw[iFailure["Unresolved", uri <> " を表示できる形に解決できませんでした。"], icTag]]];

(* SourceVault の共通スキーマ行 *)
itShowObject[row_Association, o_] /; KeyExistsQ[row, "Kind"] || KeyExistsQ[row, "URI"] || KeyExistsQ[row, "File"] :=
  Module[{pl = itRowPL[row], kind = itRowKind[row], file, title, body, uri},
    title = Replace[o["Title"], Automatic -> itRowTitle[row]];
    itGate[pl, title];
    uri = Lookup[row, "URI", None];
    Which[
      kind === "mail",
        body = Quiet @ Check[icSym["SourceVault`SourceVaultMailGetBody"][Lookup[row, "Id", ""]], $Failed];
        If[!StringQ[body], body = itAssocText[row]];
        itShowText[body, title, pl],
      True,
        file = Lookup[row, "File", ""];
        If[(!StringQ[file] || file === "" || !FileExistsQ[file]) && StringQ[uri] && StringStartsQ[uri, "sv://"],
          Return[itShowObject[uri, Append[o, "Title" -> title]]]];
        If[StringQ[file] && file =!= "" && FileExistsQ[file],
          itShowFile[file, pl, title, o],
          itShowText[itAssocText[row], title, pl]]]];

(* ファイル *)
itShowObject[file_String, o_] /; FileExistsQ[file] && !DirectoryQ[file] :=
  itShowFile[file, 0.0, Replace[o["Title"], Automatic -> FileNameTake[file]], o];

(* 画像・図 (縦長の画像はページに割る) *)
itShowObject[img_?ImageQ, o_] :=
  itShowPages[itSplitPages[img, o["PageSize"]], Replace[o["Title"], Automatic -> "image"], 0.0, o, "Image"];
itShowObject[g : (_Graphics | _Graphics3D | _Legended | _Grid | _Column | _Row | _Dataset), o_] :=
  itShowPages[{g}, Replace[o["Title"], Automatic -> "graphics"], 0.0, o, "Graphics"];

(* 素の文字列 *)
itShowObject[s_String, o_] := itShowText[s, Replace[o["Title"], Automatic -> "text"], 0.0];

(* その他の式: 画像にして出す *)
itShowObject[expr_, o_] := itShowPages[{expr}, Replace[o["Title"], Automatic -> "expression"], 0.0, o, "Expression"];

itAssocText[a_Association] :=
  StringRiffle[KeyValueMap[ToString[#1] <> ": " <> itTruncate[ToString[#2], 400] &,
    KeyDrop[a, {"Raw", "EagleRaw"}]], "\n"];

itShowText[text_String, title_String, pl_] :=
  (itSetOutput["# " <> title <> "\n\n" <> text];
   <|"Kind" -> "Text", "Title" -> title, "PrivacyLevel" -> itPL[pl], "Pages" -> 0,
     "Characters" -> StringLength[text]|>);

itShowPages[pages_List, title_String, pl_, o_, kind_String] :=
  Module[{r},
    r = ResoniteRealtime`ResoniteViewerShow[pages, "Title" -> title];
    If[MatchQ[r, _Failure], Throw[r, icTag]];
    If[r === $Failed, Throw[iFailure["Viewer", "ビューアに出せませんでした: " <> title], icTag]];
    <|"Kind" -> kind, "Title" -> title, "PrivacyLevel" -> itPL[pl], "Pages" -> Length[pages]|>];

(* PDF / 画像 / ノートブックは掴める PDF ビューアへ (2026-09-22: 板 1 枚では他のページが読めず掴めない、との指摘) *)
itShowDocument[file_String, pl_, title_String, o_, kind_String] :=
  Module[{pages = itPagesOfFile[file, o["MaxPages"]], r},
    r = ResoniteRealtime`ResonitePDFViewer[pages, "Title" -> title, "PageSize" -> o["PageSize"]];
    If[FailureQ[r], Throw[r, icTag]];
    Join[<|"Kind" -> kind, "Title" -> title, "PrivacyLevel" -> itPL[pl], "Pages" -> Length[pages], "File" -> file|>,
      If[AssociationQ[r], KeyTake[r, {"Deferred", "Id", "Root"}], <||>]]];

itShowFile[file_String, pl_, title_String, o_] :=
  Module[{ext = itExt[file], n, pages, txt, nb, cells},
    Switch[ext,
      "pdf", itShowDocument[file, pl, title, o, "PDF"],
      "png" | "jpg" | "jpeg" | "gif" | "bmp" | "tif" | "tiff" | "webp", itShowDocument[file, pl, title, o, "Image"],
      "mp4" | "webm" | "mov" | "mkv" | "avi" | "m4v",
        With[{v = ResoniteRealtime`ResoniteVideoBoard[file, "Parent" -> itVideoParent[], "Position" -> itVideoPosition[]]},
          If[MatchQ[v, _Failure], Throw[v, icTag]];
          itSetOutput["# " <> title <> "\n\n(動画を板に出しました)"];
          <|"Kind" -> "Video", "Title" -> title, "PrivacyLevel" -> itPL[pl], "Pages" -> 0, "File" -> file, "Board" -> v|>],
      "nb", itShowDocument[file, pl, title, o, "Notebook"],
      "txt" | "md" | "csv" | "json" | "wl" | "m" | "py" | "tex" | "log",
        txt = Quiet @ Check[Import[file, "Text"], $Failed];
        If[!StringQ[txt], Throw[iFailure["Text", file <> " を読めませんでした。"], icTag]];
        Append[itShowText[txt, title, pl], "File" -> file],
      "html" | "htm",
        (* arXiv の abs ページ等のスナップショット: 本文の平文を出力欄へ。Plaintext が失敗するファイルがある
           (2026-09-22 実測) ので Text + タグ除去に落とす *)
        txt = Quiet @ Check[Import[file, "Plaintext"], $Failed];
        If[!StringQ[txt] || StringTrim[txt] === "",
          txt = Quiet @ Check[Import[file, "Text"], $Failed];
          If[StringQ[txt],
            txt = StringTrim @ StringReplace[txt, {
              RegularExpression["(?is)<(script|style)[^>]*>.*?</\\1>"] -> "",
              RegularExpression["<[^>]+>"] -> " ", RegularExpression["[ \\t]+"] -> " ",
              RegularExpression["\\n\\s*\\n+"] -> "\n"}]]];
        If[!StringQ[txt], Throw[iFailure["Text", file <> " を読めませんでした。"], icTag]];
        Append[itShowText[txt, title, pl], "File" -> file],
      _,
        Throw[iFailure["Unsupported", "拡張子 ." <> ext <> " はまだ表示できません: " <> file], icTag]]];

itVideoParent[] := With[{g = itGadget[]}, If[AssociationQ[g], g["Root"], "Root"]];
itVideoPosition[] :=
  With[{g = itGadget[]},
    If[AssociationQ[g],
      {-(g["CanvasSize"][[1]]*g["PanelScale"]*0.5 + 0.6), 0.1, 0},
      {0, 1.5, 1.5}]];

(* 縦長画像をページに割る。分割したページは高さを揃える (最後のページは下を白で埋める) ので、
   ページ送りで板の大きさが変わらない。分割しない短い画像はそのまま。 *)
itSplitPages[img_?ImageQ, pageH_] :=
  Module[{w, h, n},
    {w, h} = ImageDimensions[img];
    If[h <= pageH*1.25, Return[{img}]];
    n = Ceiling[h/pageH];
    Table[With[{p = ImageTake[img, {(k - 1)*pageH + 1, Min[k*pageH, h]}]},
      If[ImageDimensions[p][[2]] < pageH,
        ImagePad[p, {{0, 0}, {pageH - ImageDimensions[p][[2]], 0}}, White], p]], {k, n}]];
itSplitPages[_, _] := {};

(* セル列をページ画像にする (2026-09-22 実測):
   - Notebook のラスタライズは画面の DPI 倍率で膨らみ、ImageSize は上限にならない
     (長い Input の行が 1500 px 幅になり横長ページになった)。ImageResolution を固定して
     DPI から切り離し、PageWidth (pt) で Input/Text を折り返す。
   - 板の上での文字の大きさは PageWidth (pt) だけで決まる (dpi は鮮明さ)。
     $ResoniteTabletPagePoints = 480 pt で 12 pt の文字が板幅の 2.5%、1.2 m の板なら 3 cm。
   - 空白のない長い文字列など折り返せないセルが 1 つあると全体が広がり、全体を縮めると
     他のセルまで読めなくなる (ユーザー指摘)。幅を超えたときはセルごとに描き、広いセルだけ
     縮めて幅を揃えて縦に積む。 *)
If[!NumericQ[ResoniteRealtime`$ResoniteTabletPagePoints], ResoniteRealtime`$ResoniteTabletPagePoints = 480];
If[!NumericQ[ResoniteRealtime`$ResoniteTabletPageResolution], ResoniteRealtime`$ResoniteTabletPageResolution = 192];

itPagePixels[] :=
  Round[ResoniteRealtime`$ResoniteTabletPagePoints * ResoniteRealtime`$ResoniteTabletPageResolution / 72];

itRasterCells[cells_List] :=
  Quiet @ Check[UsingFrontEnd @ Rasterize[
      Notebook[cells, StyleDefinitions -> $itStyleSheet,
        PageWidth -> ResoniteRealtime`$ResoniteTabletPagePoints],
      "Image", ImageResolution -> ResoniteRealtime`$ResoniteTabletPageResolution], None];

itRasterPages[cells_List] :=
  Module[{img, w = itPagePixels[], parts},
    If[cells === {}, Return[{}]];
    img = itRasterCells[cells];
    If[!ImageQ[img], Return[{}]];
    If[ImageDimensions[img][[1]] > w,
      parts = Map[Function[c, With[{ci = itRasterCells[{c}]},
        Which[
          !ImageQ[ci], Nothing,
          ImageDimensions[ci][[1]] > w, ImageResize[ci, w],
          True, ImagePad[ci, {{0, w - ImageDimensions[ci][[1]]}, {0, 0}}, White]]]], cells];
      If[parts === {}, Return[{}]];
      img = Quiet @ Check[ImageAssemble[Map[List, parts]], ImageResize[img, w]];
      If[!ImageQ[img], Return[{}]]];
    itSplitPages[img, w]];

(* ============================================================
   一覧ガジェット (SourceVault の行リスト)
   ============================================================ *)

Options[ResoniteRealtime`ResoniteListGadget] = {
  "Title" -> "SourceVault", "RowsPerPage" -> 8, "Placement" -> Automatic,
  "Distance" -> 1.4, "Height" -> Automatic, "User" -> Automatic,
  "Position" -> {0, 1.3, 1.4}, "Parent" -> "Root", "CanvasSize" -> {1400, 1000},
  "PanelScale" -> 0.0006, "FontSize" -> 30, "Name" -> "SourceVault List"};

itRowsOf[rows_List] := Select[rows, AssociationQ];
itRowsOf[ds_Dataset] := itRowsOf[Normal[ds]];
itRowsOf[_] := {};

itRowLabel[row_Association, i_Integer, maxChars_Integer] :=
  Module[{t = itRowTitle[row], k},
    t = StringReplace[t, {"\n" -> " ", "\r" -> ""}];
    k = itKindLabel[row];
    itTruncate[ToString[i] <> ". " <> t, maxChars] <> If[k === "", "", "   (" <> k <> ")"]];

(* 非同期文脈 (runtime の提案コード実行 / tick) では組み立てを予約して即返す。それ以外はその場で組む *)
ResoniteRealtime`ResoniteListGadget[rowsIn_, opts : OptionsPattern[]] :=
  If[itAsyncContextQ[],
    itDeferBuild[itListGadgetBuild[rowsIn, opts], "一覧ガジェット",
      <|"Kind" -> "ListGadget", "Rows" -> Length[itRowsOf[rowsIn]]|>],
    itListGadgetBuild[rowsIn, opts]];

itListGadgetBuild[rowsIn_, opts : OptionsPattern[ResoniteRealtime`ResoniteListGadget]] :=
  Catch[
    Module[{o, rows, hidden, pose, ids, root, panel, vl, fs, csz, pscale, per, row, rec, g, placement},
      If[!itLinkQ[],
        Return[iFailure["NotConnected", "一覧ガジェットの組み立てには ResoniteLink が要ります。"]]];
      o = Association @ Join[Options[ResoniteRealtime`ResoniteListGadget], {opts}];
      rows = itRowsOf[rowsIn];
      hidden = Count[rows, r_ /; !itAllowedQ[itRowPL[r]]];
      rows = Select[rows, itAllowedQ[itRowPL[#]] &];
      fs = N[o["FontSize"]]; csz = N[o["CanvasSize"]]; pscale = N[o["PanelScale"]]; per = o["RowsPerPage"];
      g = itGadget[];
      placement = o["Placement"];
      If[placement === Automatic, placement = If[AssociationQ[g], "Tablet", "User"]];
      pose = If[placement === "Tablet" && AssociationQ[g],
        <|"Parent" -> g["Root"],
          "Position" -> {-(g["CanvasSize"][[1]]*g["PanelScale"]*0.5 + csz[[1]]*pscale*0.5 + 0.08), 0.1, 0},
          "Rotation" -> None, "User" -> None|>,
        itPose[placement, o["User"], o["Distance"], o["Height"], o["Position"], o["Parent"]]];
      ids = <|"Buttons" -> <||>, "RowTexts" -> {}|>;
      root = icSlot[o["Name"], pose["Parent"], "Position" -> pose["Position"],
        Sequence @@ If[ListQ[pose["Rotation"]], {"Rotation" -> pose["Rotation"]}, {}],
        "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["List"]];
      ids["Root"] = root; $itBuildRoot = root;
      icComp[root, $icFE <> "Grabbable", <|"Scalable" -> True|>];
      icComp[root, $icFE <> "AI_GeneratedContent",
        <|"Source" -> "Mathematica ResoniteRealtime list gadget (SourceVault rows)"|>];
      panel = icSlot["Panel", root, "Scale" -> {pscale, pscale, pscale}];
      icComp[panel, $icUIX <> "Canvas",
        <|"Size" -> csz, "AcceptRemoteTouch" -> True, "AcceptPhysicalTouch" -> True|>];
      icMakeMaterials[panel];
      ids = Join[ids, $icMats];
      icImage[panel, RGBColor[0.08, 0.1, 0.12, 1]];
      vl = icSlot["VLayout", panel];
      icComp[vl, $icUIX <> "VerticalLayout",
        <|"PaddingTop" -> 20., "PaddingBottom" -> 20., "PaddingLeft" -> 20., "PaddingRight" -> 20.,
          "Spacing" -> 8., "ForceExpandWidth" -> True, "ForceExpandHeight" -> False|>];
      With[{s = icSlot["Title", vl]},
        icLayoutElement[s, fs*1.5, 0];
        ids["TitleText"] = itText[s, o["Title"], fs*1.0, "Left", "Middle",
          ResoniteRealtime`ResoniteRealtimeNewId["ListTitle"]]];
      Do[
        row = icSlot["Row" <> ToString[i], vl];
        icLayoutElement[row, fs*1.7, 0];
        icComp[row, $icUIX <> "HorizontalLayout", <|"Spacing" -> 10., "ForceExpandWidth" -> False|>];
        ids["Buttons", "Open" <> ToString[i]] =
          itButton[row, "Open", ">", fs*2.2, fs*1.6, RGBColor[0.2, 0.45, 0.75, 1], fs*0.9];
        With[{s = icSlot["Text", row]},
          icComp[s, $icUIX <> "LayoutElement", <|"MinWidth" -> N[csz[[1]] - 40 - fs*3], "FlexibleWidth" -> 1.|>];
          AppendTo[ids["RowTexts"],
            itText[s, "", fs*0.75, "Left", "Middle", ResoniteRealtime`ResoniteRealtimeNewId["RowText"]]]],
        {i, per}];
      row = icSlot["Footer", vl];
      icLayoutElement[row, fs*1.8, 0];
      icComp[row, $icUIX <> "HorizontalLayout", <|"Spacing" -> 12., "ForceExpandWidth" -> False|>];
      ids["Buttons", "Prev"] = itButton[row, "Prev", "<", fs*2.5, fs*1.7, RGBColor[0.3, 0.32, 0.4, 1], fs];
      With[{s = icSlot["PageLabel", row]},
        icComp[s, $icUIX <> "LayoutElement", <|"MinWidth" -> N[fs*6], "FlexibleWidth" -> 0.|>];
        ids["PageText"] = itText[s, "", fs*0.75, "Center", "Middle",
          ResoniteRealtime`ResoniteRealtimeNewId["ListPage"]]];
      ids["Buttons", "Next"] = itButton[row, "Next", ">", fs*2.5, fs*1.7, RGBColor[0.3, 0.32, 0.4, 1], fs];
      ids["Buttons", "Close"] = itButton[row, "Close", "閉じる", fs*4.5, fs*1.7, RGBColor[0.5, 0.25, 0.25, 1], fs*0.8];
      rec = <|"Ids" -> ids, "Rows" -> rows, "Page" -> 1, "PerPage" -> per, "Title" -> o["Title"],
        "Hidden" -> hidden, "MaxChars" -> Floor[(csz[[1]] - 40 - fs*3)/(fs*0.75*0.6)], "Created" -> DateObject[]|>;
      $itState["Lists", root] = rec;
      itListRender[root];
      <|"Root" -> root, "Count" -> Length[rows], "Hidden" -> hidden, "Pages" -> Ceiling[Length[rows]/per],
        "Title" -> o["Title"]|>],
    icTag];

(* ページの行テキストと n/N を書き直す (待たない) *)
itListRender[root_String] :=
  Module[{rec = Lookup[$itState["Lists"], root, None], ids, rows, page, per, total, k, label},
    If[!AssociationQ[rec], Return[None]];
    ids = rec["Ids"]; rows = rec["Rows"]; per = rec["PerPage"];
    total = Max[1, Ceiling[Length[rows]/per]];
    page = Clip[rec["Page"], {1, total}];
    $itState["Lists", root, "Page"] = page;
    itNoWait @ Quiet @ Check[(
      Do[
        k = (page - 1)*per + i;
        label = If[k <= Length[rows], itRowLabel[rows[[k]], k, rec["MaxChars"]], ""];
        ResoniteRealtime`ResoniteRealtimeUpdateComponent[ids["RowTexts"][[i]], <|"Content" -> label|>],
        {i, per}];
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[ids["PageText"],
        <|"Content" -> ToString[page] <> "/" <> ToString[total] <> "  (" <> ToString[Length[rows]] <>
          If[rec["Hidden"] > 0, ", 非表示 " <> ToString[rec["Hidden"]], ""] <> ")"|>]), $Failed];
    page];

ResoniteRealtime`ResoniteListGadgetRemove[root_String] :=
  Module[{r},
    r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[root], $Failed];
    $itState["Lists"] = KeyDrop[$itState["Lists"], root];
    r];
ResoniteRealtime`ResoniteListGadgetRemove[] :=
  Map[ResoniteRealtime`ResoniteListGadgetRemove, Keys[$itState["Lists"]]];

(* 行の ▶。結果は $itState["LastShow"] に残す (ResoniteTabletStatus[]["LastShow"] で診断) *)
itListOpen[root_String, i_Integer] :=
  Module[{rec = Lookup[$itState["Lists"], root, None], k, row, r, t0 = iNow[]},
    If[!AssociationQ[rec], Return[None]];
    k = (rec["Page"] - 1)*rec["PerPage"] + i;
    If[k > Length[rec["Rows"]], Return[None]];
    row = rec["Rows"][[k]];
    itSetStatus["開いています: " <> itTruncate[itRowTitle[row], 60]];
    r = Quiet @ Check[ResoniteRealtime`ResoniteShowObject[row], $Failed];
    $itState["LastShow"] = <|"Time" -> DateObject[], "Row" -> KeyTake[row, {"Kind", "Title", "URI", "File", "Id", "PrivacyLevel"}],
      "Result" -> r, "Seconds" -> Round[iNow[] - t0, 0.1], "LastError" -> Lookup[$itState, "LastError", None]|>;
    If[FailureQ[r], itSetStatus["開けません: " <> ToString[r["MessageTemplate"]]]];
    r];

(* ============================================================
   クリックで色が切り替わる箱 (ResoniteColorToggleBox)

   2026-09-23: 「クリックしたら赤と青の色が変わる Box を生成して」がタブレットから通らなかった
   (LLM が状態確認の式を提案 → 承認 → 続きの応答を 10 分待つ → ...) ので、提案コード 1 つで作れる部品にする。
   構成 (すべて L2、ProtoFlux 不要。型とフィールドは FrooxEngine.dll の反射で確認、2026-09-23):
     <Name>   Grabbable, AI_GeneratedContent, BoxMesh|SphereMesh, UnlitMaterial (TintColor: Sync<colorX> = c1), MeshRenderer,
              BoxCollider|SphereCollider, TouchButton (IButton + ITouchable。レーザー / 手で押せる),
              BooleanValueDriver<colorX> (State: Sync<bool> = False, TargetField: FieldDrive<colorX> -> 材質の TintColor,
                TrueValue = c2, FalseValue = c1),
              ButtonToggle (TargetValue: SyncRef<IField<bool>> -> BooleanValueDriver.State)
   注意: BooleanValueDriver.State は **参照ではなく bool 値** (初版は ValueField への参照を書いて動かなかった。実機 2026-09-23)。
   参照が要るのは driver の TargetField (材質の TintColor のメンバ ID) と ButtonToggle の TargetValue (driver の State の
   メンバ ID)。後者は driver を足した後でないと ID が無いので、非同期文脈では監視 tick の Send → getSlot → 1 巡目 (driver)
   → getSlot → 2 巡目 (toggle) で結線する ($itWireRounds)。トップレベルなら icMemberId で待って順に結線する。
   ============================================================ *)

Options[ResoniteRealtime`ResoniteColorToggleBox] = {
  "Size" -> 0.2, "Shape" -> "Box", "Placement" -> "User", "Distance" -> 1.0, "Height" -> Automatic,
  "User" -> Automatic, "Position" -> {0, 1.2, 1.0}, "Parent" -> "Root", "Offset" -> {-0.55, -0.1, -0.2},
  "Name" -> "Mathematica Toggle Box", "Grabbable" -> True, "ButtonComponent" -> "TouchButton"};

ResoniteRealtime`ResoniteColorToggleBox[colors_List, opts : OptionsPattern[]] :=
  If[itAsyncContextQ[],
    itDeferBuild[itToggleBoxBuild[colors, opts], "色トグル箱", <|"Kind" -> "ToggleBox"|>],
    itToggleBoxBuild[colors, opts]];
ResoniteRealtime`ResoniteColorToggleBox[opts : OptionsPattern[]] :=
  ResoniteRealtime`ResoniteColorToggleBox[{Red, Blue}, opts];

itToRGB[c_] := Quiet @ Check[If[ColorQ[c], ColorConvert[c, "RGB"], $Failed], $Failed];

itToggleBoxBuild[colorsIn_List, opts : OptionsPattern[ResoniteRealtime`ResoniteColorToggleBox]] :=
  Catch[
    Module[{o, cols, c1, c2, s, shape, meshType, colType, geom, pose, g, root, mesh, mat, drvId, drvMembers,
            tintId, stateId, ids},
      If[!itLinkQ[], Return[iFailure["NotConnected", "ResoniteLink が未接続です。"]]];
      o = Association @ Join[Options[ResoniteRealtime`ResoniteColorToggleBox], {opts}];
      cols = itToRGB /@ colorsIn;
      If[Length[cols] < 2 || !AllTrue[cols, MatchQ[#, _RGBColor] &],
        Return[iFailure["Colors", "色は 2 つを色オブジェクト (Red, RGBColor[1, 0, 0] 等) で指定してください。"]]];
      {c1, c2} = Take[cols, 2];
      s = N[o["Size"]];
      shape = If[o["Shape"] === "Sphere", "Sphere", "Box"];
      meshType = If[shape === "Sphere", "SphereMesh", "BoxMesh"];
      colType  = If[shape === "Sphere", "SphereCollider", "BoxCollider"];
      geom = If[shape === "Sphere", <|"Radius" -> s/2|>, <|"Size" -> {s, s, s}|>];
      pose = itPose[o["Placement"], o["User"], o["Distance"], o["Height"], o["Position"], o["Parent"]];
      (* tick 内の組み立てはタブレットの子になる (itPose)。板 (右隣) と重ならない左手前へずらす *)
      g = itGadget[];
      If[itAsyncBuildQ[] && AssociationQ[g] && pose["Parent"] === g["Root"], pose["Position"] = N[o["Offset"]]];
      root = icSlot[o["Name"], pose["Parent"], "Position" -> pose["Position"],
        Sequence @@ If[ListQ[pose["Rotation"]], {"Rotation" -> pose["Rotation"]}, {}],
        "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["TBox"]];
      $itBuildRoot = root;
      If[TrueQ[o["Grabbable"]], icComp[root, $icFE <> "Grabbable", <|"Scalable" -> True|>]];
      icComp[root, $icFE <> "AI_GeneratedContent",
        <|"Source" -> "Mathematica ResoniteRealtime (ResoniteColorToggleBox)"|>];
      mesh = icComp[root, $icFE <> meshType, geom, ResoniteRealtime`ResoniteRealtimeNewId["TBoxMesh"]];
      mat  = icComp[root, $icFE <> "UnlitMaterial", <|"TintColor" -> c1|>, ResoniteRealtime`ResoniteRealtimeNewId["TBoxMat"]];
      icComp[root, $icFE <> "MeshRenderer",
        <|"Mesh" -> ResoniteRealtime`ResoniteRealtimeRef[mesh],
          "Materials" -> <|"$type" -> "list", "elements" -> {ResoniteRealtime`ResoniteRealtimeRef[mat]}|>|>];
      icComp[root, $icFE <> colType, geom];
      icComp[root, $icFE <> ToString[o["ButtonComponent"]], <|"AcceptPhysicalTouch" -> True, "AcceptRemoteTouch" -> True|>];
      drvId = ResoniteRealtime`ResoniteRealtimeNewId["TBoxDrv"];
      drvMembers = <|"State" -> False, "TrueValue" -> c2, "FalseValue" -> c1|>;
      If[ListQ[$itWireLater],
        (* 非同期ビルド: 1 巡目 driver (TargetField -> 材質の TintColor)、2 巡目 ButtonToggle (-> driver の State)。
           メンバ ID は各巡の getSlot の応答から拾う (itBuildWire) *)
        $itWireRounds = {
          {<|"Action" -> "Add", "Slot" -> root, "Type" -> $icFE <> "BooleanValueDriver<colorX>", "Id" -> drvId,
             "Members" -> drvMembers, "Refs" -> <|"TargetField" -> {mat, "TintColor"}|>|>},
          {<|"Action" -> "Add", "Slot" -> root, "Type" -> $icFE <> "ButtonToggle",
             "Refs" -> <|"TargetValue" -> {drvId, "State"}|>|>}},
        tintId = icMemberId[root, mat, "TintColor"];
        If[!StringQ[tintId], Throw[iFailure["NoMemberId", "UnlitMaterial.TintColor のメンバ ID が取れませんでした。"], icTag]];
        icComp[root, $icFE <> "BooleanValueDriver<colorX>",
          Join[drvMembers, <|"TargetField" -> ResoniteRealtime`ResoniteRealtimeRef[tintId]|>], drvId];
        stateId = icMemberId[root, drvId, "State"];
        If[!StringQ[stateId], Throw[iFailure["NoMemberId", "BooleanValueDriver.State のメンバ ID が取れませんでした。"], icTag]];
        icComp[root, $icFE <> "ButtonToggle", <|"TargetValue" -> ResoniteRealtime`ResoniteRealtimeRef[stateId]|>]];
      ids = <|"Root" -> root, "Mesh" -> mesh, "Material" -> mat, "Driver" -> drvId, "Colors" -> {c1, c2},
        "Shape" -> shape, "Size" -> s, "Parent" -> pose["Parent"], "Kind" -> "ToggleBox"|>;
      $itState["ToggleBoxes"] = Append[Replace[Lookup[$itState, "ToggleBoxes", {}], Except[_List] -> {}], ids];
      ids],
    icTag];

(* ============================================================
   ClaudeEval のターン
   ============================================================ *)

(* 専用ノートブック (無ければ作る)。ClaudeInput スタイルのため SourceVault default.nb を使う。 *)
ResoniteRealtime`ResoniteTabletNotebook[] :=
  Module[{nb = Lookup[$itState, "Notebook", None], visible},
    If[Head[nb] === NotebookObject && MemberQ[Quiet @ Notebooks[], nb], Return[nb]];
    visible = TrueQ[Lookup[Lookup[$itState, "Options", <||>], "NotebookVisible", True]];
    nb = Quiet @ Check[
      CreateDocument[{Cell["Resonite Tablet", "Title"],
          Cell["ワールド内タブレットから送られたプロンプトとその結果。タブレットは機密度が表示上限を超えるセルを出さない。", "Text"]},
        WindowTitle -> "Resonite Tablet", StyleDefinitions -> $itStyleSheet,
        Visible -> visible, WindowSize -> {720, 820}],
      $Failed];
    If[Head[nb] =!= NotebookObject, Return[$Failed]];
    $itState = Join[$itState, <|"Notebook" -> nb|>];
    nb];

(* プロンプトに世界側の文脈を付ける (LLM 向け。表示上限と使う API を教える) *)
itPromptWithContext[prompt_String, level_] :=
  "[Resonite tablet] このプロンプトは Resonite ワールド内のタブレットから送られた。答えはワールド内のタブレット\n" <>
  "(幅の狭いスクロールするテキスト欄 + 画像ビューア) に出る。\n" <>
  "- 表示上限 PL " <> itFmt[level] <> " 未満。これ以上の機密度のデータは表示されない (機密度不明も非表示)。\n" <>
  "- SourceVault のオブジェクト (画像/PDF/動画/本文) をワールドに出すには ResoniteShowObject[uriOrRow] を使う\n" <>
  "  (PDF はページ送りつきの掴めるビューアに出る。ファイルなら ResonitePDFViewer[file] でも可)。\n" <>
  "- 一覧 (arXiv / Eagle / メール等のリスト) を求められたら core 関数 (SourceVaultArXiv / SourceVaultEagleSummaries /\n" <>
  "  SourceVaultSummaries / SourceVaultMailSearchIndex 等) の行リストを ResoniteListGadget[rows, \"Title\" -> \"...\"]\n" <>
  "  に渡してワールド内に一覧ガジェットを作る (提案コードとして実行する。コードを書いて見せるだけでは作られない)。\n" <>
  "  戻り値が <|\"Deferred\" -> True, ...|> なら作成を予約できた (成功)。失敗扱いにしたり再試行したりしない。\n" <>
  "  core 関数には検索語を渡す (SourceVaultEagleSummaries[\"自然計算\"] のように)。全件取得して自分で絞らない\n" <>
  "  (数分かかり 30 秒の実行上限でタイムアウトする)。Eagle / メールの一覧は MCP の sourcevault_search\n" <>
  "  (kinds=[\"eagle\"], filters.ext=\"pdf\" 等) で検索し、結果の Id / URI (sv://object/eagle-...) / Title /\n" <>
  "  PrivacyLevel から行を組むのが速い。\n" <>
  "  行を自分で組むときのキーは Title / URI (sv://...) / Kind / Date / PrivacyLevel。View 関数 (…View) はワールドでは使えない。\n" <>
  "- 図やグラフはそのまま出力すればビューアに映る。文章は簡潔に (Markdown 装飾は最小限)。\n" <>
  "- 「ワールドに 3D で出して」「3D オブジェクトにして」と言われたら ResoniteGraphics3D[Plot3D[...]] のように\n" <>
  "  Graphics3D を ResoniteGraphics3D に渡す (アバターの正面に実体のメッシュができる)。言われなければ普通に出力する\n" <>
  "  (タブレットの「3D生成」ボタンで後から作れる)。\n" <>
  "- 「クリックしたら色が変わる (切り替わる) 箱 / 球」を求められたら ResoniteColorToggleBox[{Red, Blue}]\n" <>
  "  (\"Shape\" -> \"Box\" | \"Sphere\", \"Size\" -> 0.2 (m)) を提案コードとして 1 回だけ実行する (これだけで作られる)。\n" <>
  "  戻り値が <|\"Deferred\" -> True, ...|> なら作成を予約できた (成功)。事前の状態確認 (ResoniteRealtimeStatus /\n" <>
  "  ResoniteFluxCatalogSearch) や ResoniteRealtimeAddSlot 等の低レベル API、ProtoFlux は使わない (応答待ちで失敗する)。\n" <>
  "[プロンプト]\n" <> prompt;

(* ノートブックのセルとして評価される 1 ターン。ClaudeEval (runtime 経路) をそのまま呼ぶ。
   振り分け層 (PromptRouter / natural dispatch / $ClaudeEvalMode "Auto") は ClaudeOrchestrator の非同期ジョブに回すことが
   あり、その場合 runtime が作られずタブレットが結果を追えない (2026-09-22 実機: Eagle の PDF 一覧が Pending のまま)。
   タブレットのターンは Single (runtime 経路) に固定する。それでもオーケストレーションに回ったときは
   OrchJobId を控えて完了まで見張る (ResoniteTabletNoteTurnResult)。 *)
ResoniteRealtime`ResoniteTabletTurn[prompt_String] :=
  Module[{lvl, llmLvl, model, ev, full, extra, res},
    If[!icClaudeQ[], Return[iFailure["NoClaudeCode", "claudecode.wl がロードされていません。"]]];
    lvl = itAccessLevel[];
    model = Lookup[Lookup[$itState, "Options", <||>], "Model", Automatic];
    llmLvl = If[model === Automatic, Min[lvl, ResoniteRealtime`$ResoniteTabletCloudMaxLevel], lvl];
    ev = icSym["ClaudeCode`ClaudeEval"];
    full = itPromptWithContext[prompt, lvl];
    extra = If[model === Automatic, {}, {icOpt[ev, "Model"] -> model}];
    res = Block[{ClaudeCode`$UseClaudeRuntime = True, ClaudeCode`$ClaudeEvalMode = "Single",
        ClaudeCode`$ClaudeEvalPromptRouterDispatch = False, ClaudeCode`$ClaudeEvalNaturalDispatch = False},
      ev[full, icOpt[ev, "PrivacySpec"] -> <|"AccessLevel" -> N[llmLvl]|>, Sequence @@ extra]];
    ResoniteRealtime`ResoniteTabletNoteTurnResult[res];
    res];

(* ターンの戻り値を見て、オーケストレーション (OrchJobId) に回っていたら見張り対象にする *)
ResoniteRealtime`ResoniteTabletNoteTurnResult[res_] :=
  Module[{t = Lookup[$itState, "Turn", None], id},
    If[!AssociationQ[t] || !AssociationQ[res], Return[None]];
    id = Lookup[res, "OrchJobId", None];
    If[StringQ[id] && MemberQ[{"Starting", "Running"}, t["Phase"]],
      $itState["Turn", "OrchJobId"] = id;
      $itState["Turn", "Phase"] = "Orchestrating";
      itSetStatus["オーケストレーション実行中 (" <> id <> ")"];
      id,
      None]];

(* ターン開始: ノートブックに Input セルを書いて評価する (ユーザーが Shift+Enter したのと同じ) *)
itStartTurn[prompt_String] :=
  Module[{nb, t = Lookup[$itState, "Turn", None], rid, runner, cell},
    If[AssociationQ[t] && !MemberQ[{"Done"}, t["Phase"]],
      itSetStatus["実行中です (Cancel で中止できます)"]; Return[None]];
    runner = ResoniteRealtime`$ResoniteTabletTurnRunner;
    If[runner === None && !icClaudeQ[], itSetStatus["claudecode.wl が未ロード"]; Return[$Failed]];
    nb = ResoniteRealtime`ResoniteTabletNotebook[];
    If[Head[nb] =!= NotebookObject, itSetStatus["ノートブックを作れませんでした"]; Return[$Failed]];
    rid = Quiet @ Check[ClaudeCode`$ClaudeLastRuntimeId, None];
    $itState = Join[$itState, <|"Turn" -> <|"Prompt" -> prompt, "Start" -> iNow[], "Notebook" -> nb,
      "CellsBefore" -> Replace[Quiet @ Cells[nb], Except[_List] -> {}],
      "RuntimeIdBefore" -> rid, "RuntimeId" -> None, "Phase" -> "Starting", "Approval" -> None,
      "CellCount" -> None, "StableCount" -> 0, "LastStatus" -> ""|>|>];
    itSetApprovalRow[False];
    itSetStatus["送信中 ..."];
    itSetOutput["> " <> prompt <> "\n\n(実行中)"];
    runner = ResoniteRealtime`$ResoniteTabletTurnRunner;
    If[runner =!= None, Return[runner[prompt, nb]]];
    cell = Cell[BoxData[RowBox[{"ResoniteTabletTurn", "[", ToString[prompt, InputForm], "]"}]], "Input"];
    Quiet @ Check[(
      SelectionMove[nb, After, Notebook];
      NotebookWrite[nb, cell, All];
      SelectionEvaluate[nb]),
      (itSetStatus["セルの評価を始められませんでした"]; $itState["Turn", "Phase"] = "Done"; $Failed)]];

ResoniteRealtime`ResoniteTabletEval[prompt_String] := itStartTurn[prompt];

(* runtime の状態を読む (claudecode / ClaudeRuntime は弱結合) *)
itRuntimeState[rid_String] :=
  Module[{f = icSym["ClaudeRuntime`ClaudeRuntimeState"], st},
    If[f === None, Return[None]];
    st = Quiet @ Check[f[rid], None];
    If[AssociationQ[st], st, None]];

(* 「実行中」の内訳 (2026-09-23: 承認後に LLM の続きの応答を 10 分待つ間、何をしているか分からなかった)。
   runtime の DAG (CurrentJobId) にまだ動いているノードがあれば LLM 応答待ち、無ければ CurrentPhase で判定。 *)
itRunPhaseLabel[st_] :=
  Module[{job = Lookup[st, "CurrentJobId", None], f = icSym["ClaudeCode`LLMGraphDAGStatus"], dag, ph},
    dag = If[StringQ[job] && f =!= None, Quiet @ Check[f[job], None], None];
    ph = ToString[Lookup[st, "CurrentPhase", ""]];
    Which[
      AssociationQ[dag] && Lookup[dag, "Running", 0] + Lookup[dag, "Pending", 0] > 0, ": LLM 応答待ち",
      ph === "Execute", ": 式を実行",
      MemberQ[{"Redact", "ContinuationCheck"}, ph], ": 結果を処理",
      True, ""]];
itRunPhaseLabel[_] := "";

itDecide[decision_] :=
  Module[{t = Lookup[$itState, "Turn", None], rid, f, st, status},
    If[!AssociationQ[t] || !StringQ[t["RuntimeId"]], itSetStatus["応答するターンがありません"]; Return[None]];
    rid = t["RuntimeId"];
    (* 2026-09-23: runtime が承認待ちでなければ送らない (ボタンの押し直し / 古い読み取りで、後から来た別の提案を
       勝手に承認しない。ClaudeRuntimeDecide も NotAwaiting を返すが、こちらで「承認しました」と出してしまっていた) *)
    If[decision =!= "Cancel",
      st = itRuntimeState[rid];
      status = If[AssociationQ[st], ToString[Lookup[st, "Status", "?"]], "?"];
      If[status =!= "AwaitingApproval",
        itSetApprovalRow[False];
        $itState["Turn", "Approval"] = None;
        itSetStatus["承認待ちではありません (" <> status <> ")"];
        Return[None]]];
    f = icSym["ClaudeCode`ClaudeRuntimeDecide"];
    itSetApprovalRow[False];
    $itState["Turn", "Approval"] = None;
    itSetStatus[Switch[decision, "Approve", "承認しました", {"ApproveTimeout", _}, "延長して承認しました",
      "Deny", "拒否しました", "Cancel", "中止しました", _, "応答"]];
    (* 出力欄の「承認が必要です」を消す (残すと、実行中に 2 度目の承認要求が出ているように見える。2026-09-23 実機) *)
    itSetOutput["> " <> t["Prompt"] <> "\n\n" <>
      Switch[decision,
        "Approve" | {"ApproveTimeout", _},
          "承認しました。runtime が式を実行し、続きを LLM に問い合わせています (数分かかることがあります) ...",
        "Deny", "拒否しました。",
        "Cancel", "中止しました。",
        _, "(実行中)"]];
    (* 承認後の実行は重いので tick の外 (別 ScheduledTask) で。ノートブックの承認ボタンと同じ手順。
       Module 変数を held 式に残さないよう With で値を焼き込む *)
    With[{ff = f, r = rid, d = decision},
      If[ff =!= None,
        SessionSubmit[ScheduledTask[ff[r, d], {0.2, 1}]],
        SessionSubmit[ScheduledTask[Switch[d,
          "Approve", ClaudeRuntime`ClaudeApproveProposal[r],
          {"ApproveTimeout", _}, ClaudeRuntime`ClaudeApproveProposalWithTimeout[r, d[[2]]],
          "Cancel", ClaudeRuntime`ClaudeRuntimeCancel[r],
          _, ClaudeRuntime`ClaudeDenyProposal[r]], {0.2, 1}]]]];
    decision];

ResoniteRealtime`ResoniteTabletApprove[] :=
  Module[{t = Lookup[$itState, "Turn", None]},
    If[AssociationQ[t] && MatchQ[t["Approval"], _Association] && t["Approval"]["Kind"] === "TimeoutExtension",
      itDecide[{"ApproveTimeout", t["Approval"]["ExpectedSeconds"]}],
      itDecide["Approve"]]];
ResoniteRealtime`ResoniteTabletDeny[] := itDecide["Deny"];
ResoniteRealtime`ResoniteTabletCancel[] :=
  Module[{t = Lookup[$itState, "Turn", None]},
    If[!AssociationQ[t] || t["Phase"] === "Done", itSetStatus["実行中のターンはありません"]; Return[None]];
    If[StringQ[t["RuntimeId"]], itDecide["Cancel"]];
    $itState["Turn", "Cancelled"] = True;
    $itState["Turn", "Phase"] = "Finishing";
    $itState["Turn", "LastStatus"] = "Cancelled";
    "Cancelled"];

(* ---- 承認待ちの表示 ---- *)
itShowApproval[st_Association] :=
  Module[{pending, kind, expSec, defSec, expl, held, exprStr, key, label},
    pending = Lookup[st, "PendingApproval", <||>];
    If[!AssociationQ[pending], pending = <||>];
    kind = Lookup[pending, "Kind", "Approval"];
    expSec = Lookup[pending, "ExpectedSeconds", None];
    defSec = Lookup[pending, "DefaultTimeoutSeconds", 30];
    expl = ToString[Lookup[Lookup[pending, "ValidationResult", <||>], "VisibleExplanation", ""]];
    held = Lookup[Lookup[pending, "Proposal", <||>], "HeldExpr", None];
    exprStr = If[held =!= None, itTruncate[ToString[held, InputForm], 600],
      itTruncate[ToString[Lookup[Lookup[pending, "Proposal", <||>], "RawCode", "(式なし)"]], 600]];
    key = Hash[{kind, expl, exprStr}];
    If[AssociationQ[$itState["Turn", "Approval"]] && $itState["Turn", "Approval"]["Key"] === key, Return[None]];
    $itState["Turn", "Approval"] = <|"Key" -> key, "Kind" -> kind, "ExpectedSeconds" -> expSec|>;
    label = If[kind === "TimeoutExtension",
      "タイムアウト延長 " <> ToString[defSec] <> "s -> " <> ToString[expSec] <> "s",
      "式の実行"];
    itSetApprovalRow[True, label];
    itSetStatus["承認待ち: " <> label];
    itSetOutput["> " <> $itState["Turn", "Prompt"] <> "\n\n" <>
      "!! 承認が必要です (" <> label <> ")\n" <> If[expl === "", "", expl <> "\n"] <> "\n" <>
      exprStr <> "\n\n[承認] で実行、[拒否] で中止。ノートブック側の承認ボタンでも可。"]];

(* ---- 完了時: 増えたセルを機密度でふるって、平文 + 画像にする ---- *)
itCellText[e_] :=
  Module[{s},
    s = Quiet @ Check[First @ FrontEndExecute[FrontEnd`ExportPacket[e, "PlainText"]], ""];
    If[!StringQ[s], s = ""];
    s = StringTrim[s];
    If[s === "" && !FreeQ[e, _GraphicsBox | _Graphics3DBox | _RasterBox | _GraphicsBox3D], "[図]", itTruncate[s, 3000]]];

itCellStyle[Cell[_, style_String, ___]] := style;
itCellStyle[_] := "";

itCellTags[Cell[_, _String, opts___]] :=
  With[{ct = Lookup[Association[Cases[{opts}, _Rule | _RuleDelayed]], CellTags, {}]},
    Select[Flatten[{ct}], StringQ]];
itCellTags[_] := {};

(* 落とすセル: Input (自分の呼び出し・予約セル・LLM の提案コード。$ResoniteTabletShowCode = True なら提案コードは出す)、
   ボタン入り (承認 UI / ContinueEval)、診断用の Code セル (ClaudeTurnTrace 等)、ノートブック側の承認 UI ブロック
   (CellTags claudecode-approval-*。タブレットは自前の承認行を持つ)。機密度が上限を超えるセルは注記に置き換える *)
itFilterCell[e_, level_] :=
  Module[{pl, f, style = itCellStyle[e], tags},
    If[style === "Input" &&
       (!TrueQ[ResoniteRealtime`$ResoniteTabletShowCode] ||
        !FreeQ[e, "ResoniteTabletTurn" | "ResoniteTabletRunDeferred"]), Return[None]];
    If[style === "Code" && !TrueQ[ResoniteRealtime`$ResoniteTabletShowCode], Return[None]];
    tags = itCellTags[e];
    If[AnyTrue[tags, StringStartsQ[#, "claudecode-approval-"] &], Return[None]];
    If[!FreeQ[e, _DynamicModuleBox | _ButtonBox | _DynamicBox | _PaneSelectorBox], Return[None]];
    f = icSym["NBAccess`NBCellExprPrivacyLevel"];
    pl = If[f === None, 1.0, itPL[Quiet @ Check[f[e], $Failed]]];
    If[pl >= level - 10^-9, Cell[itHiddenNote[pl], "Text"], e]];

itRenderCells[nb_NotebookObject, before_List, level_, rid_ : None] :=
  Module[{after, new, exprs, kept, hidden, texts, pages, extra = {}},
    after = Replace[Quiet @ Cells[nb], Except[_List] -> {}];
    new = Select[after, !MemberQ[before, #] &];
    exprs = If[new === {}, {}, Replace[Quiet @ Check[NotebookRead[new], {}], Except[_List] -> {}]];
    kept = DeleteCases[Map[itFilterCell[#, level] &, exprs], None];
    (* 結果セルに図が無いとき (runtime の表示セルは応答より後に書かれることがあり、間に合わない。2026-09-22 実機: ガンマ関数の
       Plot が板に出なかった) は、実行時に $ClaudeRuntimeDisplayHook で拾っておいた生の結果 (StashDisplay) から図のページを作る *)
    If[StringQ[rid] && FreeQ[kept, _GraphicsBox | _Graphics3DBox | _RasterBox],
      extra = itStashDisplayCells[rid, level]];
    hidden = Count[Join[kept, extra], Cell[_String?(StringStartsQ["[非表示"]), "Text"]];
    texts = DeleteCases[Map[itCellText, kept], ""];
    pages = itRasterPages[Join[kept, extra]];
    <|"Text" -> StringRiffle[texts, "\n\n"], "Pages" -> pages, "Count" -> Length[kept] + Length[extra],
      "Hidden" -> hidden, "NewCells" -> Length[new], "StashFigures" -> Length[extra]|>];

(* この runtime の未描画の stash を Output セル (機密度超えは注意書き) にし、描画済みにする *)
itStashDisplayCells[rid_String, level_] :=
  Module[{stash = Replace[Lookup[$itState, "StashDisplay", {}], Except[_List] -> {}], mine, cells},
    mine = Select[stash, #["RuntimeId"] === rid && !TrueQ[#["Rendered"]] &];
    If[mine === {}, Return[{}]];
    cells = Map[Function[e,
      If[itAllowedQ[e["Privacy"]],
        With[{b = Quiet @ Check[TimeConstrained[ToBoxes[e["Raw"], StandardForm], 20, $Failed], $Failed]},
          If[b === $Failed, Nothing, Cell[BoxData[b], "Output"]]],
        Cell[itHiddenNote[e["Privacy"]], "Text"]]], mine];
    $itState["StashDisplay"] = Map[If[#["RuntimeId"] === rid, Append[#, "Rendered" -> True], #] &, stash];
    cells];

itFinishTurn[statusWord_String] :=
  Module[{t = $itState["Turn"], r, secs, text, lvl = itAccessLevel[]},
    secs = Round[iNow[] - t["Start"]];
    r = Quiet @ Check[itRenderCells[t["Notebook"], t["CellsBefore"], lvl, Lookup[t, "RuntimeId", None]], $Failed];
    If[!AssociationQ[r], r = <|"Text" -> "(結果セルを読めませんでした)", "Pages" -> {}, "Count" -> 0, "Hidden" -> 0|>];
    text = "> " <> t["Prompt"] <> "\n\n" <> If[r["Text"] === "", "(表示できる結果がありません)", r["Text"]] <>
      If[r["Hidden"] > 0, "\n\n(" <> ToString[r["Hidden"]] <> " セルは表示上限 " <> itFmt[lvl] <> " を超えるため非表示)", ""];
    itSetOutput[text];
    If[r["Pages"] =!= {} && AssociationQ[itViewer[]],
      Quiet @ Check[ResoniteRealtime`ResoniteViewerShow[r["Pages"], "Title" -> t["Prompt"]], Null]];
    itSetApprovalRow[False];
    itSetStatus[statusWord <> " (" <> ToString[secs] <> " s, " <> ToString[r["Count"]] <> " cells)"];
    With[{entry = <|"Time" -> DateObject[], "Prompt" -> t["Prompt"], "Status" -> statusWord,
        "Seconds" -> secs, "Text" -> itTruncate[r["Text"], 2000], "Pages" -> Length[r["Pages"]],
        "Hidden" -> r["Hidden"], "RuntimeId" -> t["RuntimeId"]|>},
      (* 遅れて来たセルの描き直しは同じターンの記録を置き換える *)
      $itLog = If[TrueQ[t["Rerender"]] && $itLog =!= {} && Last[$itLog]["Prompt"] === t["Prompt"],
        ReplacePart[$itLog, -1 -> entry],
        Take[Append[$itLog, entry], -Min[$itLogLimit, Length[$itLog] + 1]]]];
    $itState["Turn", "Rerender"] = False;
    $itState["Turn", "Phase"] = "Done";
    $itState["Turn", "LastStatus"] = statusWord;
    $itState["Turn", "FinishedAt"] = iNow[];
    r];

(* ---- tick から呼ばれる: ターンの監視 ---- *)
(* runtime が終端 (Done/Failed) の後で承認待ちに戻ることがある (タイムアウト → 失敗 → 修復ターンが同じコードを
   延長申告で再提案 → AwaitingApproval。2026-09-22 実機)。Finishing の間と、Done の後 $itDoneWatchSeconds の間は
   状態を見張り、承認待ち/実行中に戻ったらターンを再開する。 *)
$itDoneWatchSeconds = 600;
$itLateCellSeconds = 180;   (* Done の後、この間に増えた結果セルは描き直す *)

itResumeTurn[status_String] :=
  ($itState["Turn", "Phase"] = "Running";
   $itState["Turn", "LastStatus"] = status;
   $itState["Turn", "Approval"] = None;
   itSetStatus["再開: " <> status]);

itWatchTurn[] :=
  Module[{t = Lookup[$itState, "Turn", None], rid, st, status, elapsed, c, meta},
    If[!AssociationQ[t], Return[None]];
    elapsed = Round[iNow[] - t["Start"]];
    If[t["Phase"] === "Done",
      (* 終わった後の再開 (承認待ち / 再実行) を一定時間だけ見張る (中止したターンは除く) *)
      If[StringQ[t["RuntimeId"]] && !TrueQ[t["Cancelled"]] && NumericQ[Lookup[t, "FinishedAt", None]] &&
         iNow[] - t["FinishedAt"] < $itDoneWatchSeconds,
        st = itRuntimeState[t["RuntimeId"]];
        status = If[AssociationQ[st], ToString[Lookup[st, "Status", "?"]], "?"];
        If[MemberQ[{"AwaitingApproval", "Running"}, status],
          itResumeTurn[status];
          If[status === "AwaitingApproval", itShowApproval[st]];
          Return[None]]];
      (* 描いた後に結果セルが増えた (runtime の表示セル / 応答の続き) ら、落ち着いてから描き直す *)
      If[NumericQ[Lookup[t, "FinishedAt", None]] && iNow[] - t["FinishedAt"] < $itLateCellSeconds &&
         Head[t["Notebook"]] === NotebookObject,
        c = Length[Replace[Quiet @ Cells[t["Notebook"]], Except[_List] -> {}]];
        If[IntegerQ[t["CellCount"]] && c > t["CellCount"],
          $itState["Turn", "Phase"] = "Finishing";
          $itState["Turn", "Rerender"] = True;
          $itState["Turn", "CellCount"] = None;
          $itState["Turn", "StableCount"] = 0]];
      Return[None]];
    Switch[t["Phase"],
      "Starting",
        rid = Quiet @ Check[ClaudeCode`$ClaudeLastRuntimeId, None];
        Which[
          StringQ[rid] && rid =!= t["RuntimeIdBefore"],
            $itState["Turn", "RuntimeId"] = rid;
            $itState["Turn", "Phase"] = "Running";
            itSetStatus["実行中 (" <> ToString[elapsed] <> " s)"],
          elapsed > 90,
            (* runtime が立たない (拒否メッセージだけ出た等)。増えたセルがあればそれを出して終わる *)
            $itState["Turn", "Phase"] = "Finishing";
            $itState["Turn", "LastStatus"] = "NoRuntime",
          True,
            itSetStatus["送信中 (" <> ToString[elapsed] <> " s)"]],
      "Running",
        st = itRuntimeState[t["RuntimeId"]];
        status = If[AssociationQ[st], ToString[Lookup[st, "Status", "?"]], "?"];
        Which[
          status === "AwaitingApproval", itShowApproval[st],
          MemberQ[{"Done", "Failed", "Cancelled"}, status],
            $itState["Turn", "Phase"] = "Finishing";
            $itState["Turn", "LastStatus"] = status;
            $itState["Turn", "CellCount"] = None;
            $itState["Turn", "StableCount"] = 0,
          status === "Running",
            If[t["Approval"] =!= None, $itState["Turn", "Approval"] = None; itSetApprovalRow[False]];
            itSetStatus["実行中" <> itRunPhaseLabel[st] <> " (" <> ToString[elapsed] <> " s)"],
          True,
            itSetStatus[status <> " (" <> ToString[elapsed] <> " s)"]];
        If[elapsed > 3600, $itState["Turn", "Phase"] = "Finishing"; $itState["Turn", "LastStatus"] = "Timeout"],
      "Orchestrating",
        (* ClaudeOrchestrator の非同期ジョブ。完了/失敗で Finishing へ (結果はノートブックに書かれる) *)
        st = With[{f = icSym["ClaudeOrchestrator`ClaudeOrchestrationStatus"]},
          If[f === None, None, Quiet @ Check[f[t["OrchJobId"]], None]]];
        status = If[AssociationQ[st], ToString[Lookup[st, "Status", "?"]], "?"];
        Which[
          MemberQ[{"Done", "Failed", "Cancelled"}, status] || elapsed > 3600,
            $itState["Turn", "Phase"] = "Finishing";
            $itState["Turn", "LastStatus"] = If[elapsed > 3600, "Timeout", status];
            $itState["Turn", "CellCount"] = None;
            $itState["Turn", "StableCount"] = 0,
          True,
            itSetStatus["オーケストレーション " <> status <> " (" <> ToString[elapsed] <> " s)"]],
      "Finishing",
        (* 終端のはずの runtime が承認待ち/実行中に戻っていたら描かずに再開する (タブレットから中止したときは除く) *)
        If[StringQ[t["RuntimeId"]] && !TrueQ[t["Cancelled"]],
          st = itRuntimeState[t["RuntimeId"]];
          status = If[AssociationQ[st], ToString[Lookup[st, "Status", "?"]], "?"];
          If[MemberQ[{"AwaitingApproval", "Running"}, status],
            itResumeTurn[status];
            If[status === "AwaitingApproval", itShowApproval[st]];
            Return[None]]];
        (* 結果セルの書き込みが落ち着くまで待つ (2 tick 連続で数が変わらなければ描く) *)
        c = Length[Replace[Quiet @ Cells[t["Notebook"]], Except[_List] -> {}]];
        If[c === t["CellCount"],
          $itState["Turn", "StableCount"] = t["StableCount"] + 1,
          $itState["Turn", "CellCount"] = c; $itState["Turn", "StableCount"] = 0];
        If[$itState["Turn", "StableCount"] >= 2,
          itFinishTurn[Replace[t["LastStatus"], {"Done" -> "完了", "Failed" -> "失敗", "Cancelled" -> "中止",
            "NoRuntime" -> "終了", "Timeout" -> "タイムアウト", s_ :> s}]]],
      _, Null];
    None];

(* ============================================================
   監視 (ScheduledTask 1 本。chat と同じ 2 相ポーリング: 送るだけ / 応答を照合)
   ============================================================ *)

itPollTargets[] :=
  Join[itScanTargets[],
    If[itGadgetQ[], {<|"Kind" -> "Tablet", "Root" -> itGadget[]["Root"]|>}, {}],
    Map[<|"Kind" -> "PDF", "Root" -> #|> &, Keys[itPDFViewers[]]],
    Map[<|"Kind" -> "List", "Root" -> #|> &, Keys[$itState["Lists"]]]];

itPoll[] :=
  Module[{pending, targets, idx, target, sent, res},
    If[TrueQ[$itState["Busy"]], Return[Null]];
    If[!itLinkQ[],
      If[TrueQ[$itState["Serve"]],
        $itState["Busy"] = True;
        Quiet @ Check[itServeConnect[], $itState["LastError"] = "connect"];
        $itState["Busy"] = False];
      Return[Null]];
    $itState["Busy"] = True;
    Quiet @ Check[itWatchTurn[], $itState["LastError"] = "watch"];
    Quiet @ Check[itProcessBuilds[], $itState["LastError"] = "build"];
    targets = itPollTargets[];
    If[targets === {}, $itState["Busy"] = False; Return[Null]];
    pending = Lookup[$itState, "Pending", None];
    If[!AssociationQ[pending],
      idx = Mod[$itState["PollIndex"], Length[targets]] + 1;
      target = targets[[idx]];
      $itState["PollIndex"] = idx;
      sent = Quiet @ Check[
        ResoniteRealtime`ResoniteRealtimeGetSlot[target["Root"], "Depth" -> Lookup[target, "Depth", -1],
          "IncludeComponentData" -> Lookup[target, "Components", True], "Wait" -> False], $Failed];
      If[AssociationQ[sent] && StringQ[Lookup[sent, "MessageId", None]],
        $itState["Pending"] = <|"MessageId" -> sent["MessageId"], "Time" -> iNow[], "Target" -> target|>,
        $itState["PollFailures"] = $itState["PollFailures"] + 1;
        $itState["LastError"] = sent];
      $itState["Busy"] = False;
      Return[Null]];
    res = icPollReply[pending["MessageId"]];
    Which[
      AssociationQ[res],
        $itState["Pending"] = None; $itState["PollFailures"] = 0;
        If[Lookup[res, "success", True] === False,
          $itState["LastError"] = res; itNoteTargetFailure[pending["Target"]],
          itNoteTargetOK[pending["Target"]];
          Quiet @ Check[itHandleReply[pending["Target"], res], $itState["LastError"] = "handle"]],
      iNow[] - pending["Time"] > 10,
        $itState["Pending"] = None;
        $itState["PollFailures"] = $itState["PollFailures"] + 1;
        $itState["LastError"] = iFailure["Timeout", "getSlot の応答が 10 秒来ませんでした。"];
        (* 常駐監視中に応答が続けて来ない = ResoniteLink が死んだ (Resonite 再起動等)。切って再探索に戻る *)
        If[TrueQ[$itState["Serve"]] && $itState["PollFailures"] >= 5,
          Quiet @ ResoniteRealtime`ResoniteRealtimeLinkDisconnect[];
          $itState["PollFailures"] = 0; $itState["LastConnectTry"] = 0;
          $itState["LastError"] = iFailure["LinkLost", "ResoniteLink の応答が途絶えたので切断しました。再探索します。"]],
      True, Null];
    $itState["Busy"] = False;
    Null];

(* ============================================================
   常駐監視 (ResoniteTabletServe): ResoniteLink の自動接続と、ワールドにあるタブレットの引き継ぎ

   狙い: ResoniteRealtime.wl をロードして ResoniteLink をオンにしておけば、インベントリに保存したタブレットを
   出して「接続」を押すだけで使える (2026-09-22 ユーザー指示)。ポート指定も ResoniteTablet[] の呼び出しも要らない。
     - 未接続: 15 秒ごとに ResoniteRealtimeDiscover[] (netsh、即時)。見つかったときだけ繋ぐ (握手は同期読みなので task 内で可)。
     - 接続中: 5 秒 (タブレット引き継ぎ済みなら 15 秒) ごとに Root 直下 (Depth 1) を見て "Mathematica Tablet" を候補にし、
       候補ごとに Depth -1 で読んで「接続」の ValueField が True なら引き継ぐ (itParseTabletTree で名前と型から ID を復元)。
   すべて tick の 2 相ポーリング (送るだけ / 次の tick で照合) の上に載せ、待たない。
   ============================================================ *)
$itServeRetrySeconds = 15; $itScanSeconds = 5; $itScanSecondsAttached = 15;
itVal[x_] := If[AssociationQ[x], Lookup[x, "value", x], x];
itGadgetRoot[] := If[itGadgetQ[], itGadget[]["Root"], None];

itServeConnect[] :=
  Module[{found, r},
    If[iNow[] - Lookup[$itState, "LastConnectTry", 0] < $itServeRetrySeconds, Return[None]];
    $itState["LastConnectTry"] = iNow[];
    found = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeDiscover[], {}];
    If[!ListQ[found] || found === {}, Return[None]];
    r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeLinkConnect[First[found]["Port"], "Quiet" -> True], $Failed];
    If[StringQ[r], $itState["LastScan"] = 0; $itState["PollFailures"] = 0];
    r];

itScanTargets[] :=
  If[!TrueQ[$itState["Serve"]], {},
    Join[
      If[iNow[] - Lookup[$itState, "LastScan", 0] > If[itGadgetQ[], $itScanSecondsAttached, $itScanSeconds],
        {<|"Kind" -> "Scan", "Root" -> "Root", "Depth" -> 1, "Components" -> False|>}, {}],
      Map[<|"Kind" -> "Candidate", "Root" -> #, "Depth" -> -1, "Components" -> True|> &,
        Replace[Lookup[$itState, "Candidates", {}], Except[_List] -> {}]]]];

itHandleScan[res_Association] :=
  Module[{kids, cands},
    $itState["LastScan"] = iNow[];
    kids = Lookup[Lookup[res, "data", <||>], "children", {}];
    cands = Select[kids, AssociationQ[#] && StringQ[Lookup[#, "id", None]] &&
      StringStartsQ[ToString[itVal[Lookup[#, "name", ""]]], "Mathematica Tablet"] && Lookup[#, "id"] =!= itGadgetRoot[] &];
    $itState["Candidates"] = DeleteDuplicates[Lookup[cands, "id"]];
    Length[cands]];

itHandleCandidate[root_String, res_Association] :=
  Module[{ids, connect, pressed},
    $itState["Candidates"] = DeleteCases[Replace[Lookup[$itState, "Candidates", {}], Except[_List] -> {}], root];
    ids = itParseTabletTree[res];
    If[!AssociationQ[ids], Return[None]];
    connect = Lookup[ids["Buttons"], "Connect", None];
    pressed = StringQ[connect] && icMemberValue[icFindComponent[res, connect], "Value"] === True;
    If[!pressed, Return[None]];
    itAdoptIds[ids];
    ids["Root"]];

(* 引き継ぎ: 台帳に載せ、ノートブックと表示フックを用意し、板を隠し、ボタンの旗を戻す。tick の中から呼べる (待たない) *)
itAdoptIds[ids_Association] :=
  Module[{g},
    ResoniteRealtime`ResoniteTabletAttach[ids];
    g = itGadget[];
    Scan[itSetFlag[#, False] &, Select[Values[Lookup[g, "Buttons", <||>]], StringQ]];
    If[AssociationQ[Lookup[g, "Board", None]],
      itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateSlot[g["Board"]["Slot"], <|"isActive" -> False|>], Null]];
    Quiet @ Check[ResoniteRealtime`ResoniteTabletNotebook[], Null];
    Quiet @ Check[itInstallDisplayHook[], Null];
    $itState = Join[$itState, <|"Turn" -> None, "LastScan" -> iNow[], "TargetFailures" -> <||>|>];
    itSetText["TitleText", Lookup[g, "Name", "Mathematica Tablet"] <> "   [" <> itAccessLabel[] <> "]"];
    itSetOutput[""];
    itSetStatus["接続しました (" <> itAccessLabel[] <> ")"];
    g];

itConnectPressed[] :=
  Module[{g = itGadget[]},
    If[!AssociationQ[g], Return[None]];
    Quiet @ Check[ResoniteRealtime`ResoniteTabletNotebook[], Null];
    itSetText["TitleText", Lookup[g, "Name", "Mathematica Tablet"] <> "   [" <> itAccessLabel[] <> "]"];
    itSetStatus["接続済み (" <> itAccessLabel[] <> ")"]];

itRestartServeIfNeeded[] :=
  If[TrueQ[$itState["Serve"]] && !MatchQ[Lookup[$itState, "Task", None], _TaskObject],
    Quiet @ Check[ResoniteRealtime`ResoniteTabletStart["Serve" -> True,
      "PollInterval" -> Lookup[$itState, "PollInterval", 1.0]], Null]];

(* ---- タブレットの木 (getSlot Depth -1, component data 付き) から ids を復元 ----
   組み立て (ResoniteTablet) と同じスロット名・コンポーネント型で探す。ID はインベントリ経由で付け直されているので名前だけが頼り。 *)
itChild[s_, name_String] :=
  If[!AssociationQ[s], None,
    SelectFirst[Lookup[s, "children", {}], AssociationQ[#] && ToString[itVal[Lookup[#, "name", ""]]] === name &, None]];
itPath[s_, names_List] := Fold[itChild, s, names];
itCompOf[s_, suffix_String] :=
  If[!AssociationQ[s], None,
    SelectFirst[Lookup[s, "components", {}],
      AssociationQ[#] && StringEndsQ[ToString[Lookup[#, "componentType", ""]], suffix] &, None]];
itCompId[s_, suffix_String] := With[{c = itCompOf[s, suffix]}, If[AssociationQ[c], Lookup[c, "id", None], None]];
itSlotId[s_] := If[AssociationQ[s], Lookup[s, "id", None], None];
itSlotScaleX[s_, default_] :=
  With[{v = If[AssociationQ[s], itVal[Lookup[s, "scale", None]], None]},
    If[AssociationQ[v] && NumericQ[Lookup[v, "x", None]], N[v["x"]], default]];

itParseTabletTree[res_Association] :=
  Module[{root = Lookup[res, "data", <||>], ids, panel, vl, input, appr, content, txt, board, canvas, sz, st},
    If[!AssociationQ[root] || !StringQ[Lookup[root, "id", None]], Return[None]];
    panel = itChild[root, "Panel"]; vl = itPath[root, {"Panel", "VLayout"}];
    If[!AssociationQ[vl], Return[None]];
    ids = <|"Root" -> root["id"], "Name" -> ToString[itVal[Lookup[root, "name", "Mathematica Tablet"]]],
      "Buttons" -> <||>, "Panel" -> panel["id"],
      "Image" -> itCompId[panel, "UI_UnlitMaterial"], "Text" -> itCompId[panel, "UI_TextUnlitMaterial"]|>;
    canvas = itCompOf[panel, "UIX.Canvas"];
    sz = If[AssociationQ[canvas], icMemberValue[canvas, "Size"], None];
    ids["CanvasSize"] = If[AssociationQ[sz] && NumericQ[Lookup[sz, "x", None]], N[{sz["x"], sz["y"]}], {1000., 1500.}];
    ids["PanelScale"] = itSlotScaleX[panel, 0.0006];
    ids["TitleText"] = itCompId[itChild[vl, "Title"], "UIX.Text"];
    input = itChild[vl, "Input"];
    ids["Input"] = itSlotId[input];
    ids["InputText"] = itCompId[itChild[input, "Text"], "UIX.Text"];
    ids["Editor"] = itCompId[input, "TextEditor"];
    Do[With[{row = itChild[vl, spec[[1]]]},
        Do[With[{vf = itCompId[itChild[row, key], "ValueField<bool>"]},
            If[StringQ[vf], ids["Buttons", key] = vf]],
          {key, spec[[2]]}]],
      {spec, {{"ButtonRow", {"Eval", "Clear", "Cancel", "Make3D", "Connect"}},
              {"ApprovalRow", {"Approve", "Deny"}}, {"ViewerBar", {"Prev", "Next", "Close"}}}}];
    st = itCompOf[itChild[vl, "Status"], "UIX.Text"];
    ids["StatusText"] = If[AssociationQ[st], Lookup[st, "id", None], None];
    ids["FontSize"] = With[{s = If[AssociationQ[st], icMemberValue[st, "Size"], None]},
      If[NumericQ[s] && s > 0, N[s/0.75], 26.]];
    appr = itChild[vl, "ApprovalRow"];
    ids["ApprovalRow"] = itSlotId[appr];
    ids["ApprovalText"] = itCompId[itChild[appr, "ApprovalLabel"], "UIX.Text"];
    content = itPath[vl, {"Output", "Content"}];
    ids["Scroll"] = itCompId[content, "UIX.ScrollRect"];
    txt = itChild[content, "Text"];
    ids["OutputLayout"] = itCompId[txt, "UIX.LayoutElement"];
    ids["OutputText"] = itCompId[txt, "UIX.Text"];
    ids["PageText"] = itCompId[itPath[vl, {"ViewerBar", "PageLabel"}], "UIX.Text"];
    ids["ContentWidth"] = ids["CanvasSize"][[1]] - 48. - 32.;
    board = itChild[root, "Tablet Viewer"];
    If[AssociationQ[board],
      ids["Board"] = <|"Slot" -> board["id"], "Texture" -> itCompId[board, "StaticTexture2D"],
        "Mesh" -> itCompId[board, "QuadMesh"], "Material" -> itCompId[board, "FrooxEngine.UnlitMaterial"],
        "Renderer" -> itCompId[board, "MeshRenderer"], "Size" -> itSlotScaleX[board, 1.2], "URL" -> ""|>];
    If[!AllTrue[{ids["InputText"], ids["StatusText"], ids["OutputText"], Lookup[ids["Buttons"], "Eval", None]}, StringQ],
      Return[None]];
    Join[ids, <|"Created" -> DateObject[], "Adopted" -> True|>]];

ResoniteRealtime`ResoniteTabletFind[] :=
  Module[{tree, kids},
    If[!itLinkQ[], Return[iFailure["NotConnected", "ResoniteLink が未接続です (ResoniteRealtimeLinkConnect[])。"]]];
    tree = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot["Root", "Depth" -> 1, "Timeout" -> 30], $Failed];
    If[!AssociationQ[tree], Return[iFailure["GetSlot", "Root の階層が取れませんでした。"]]];
    kids = Lookup[Lookup[tree, "data", <||>], "children", {}];
    Map[<|"Id" -> #["id"], "Name" -> ToString[itVal[Lookup[#, "name", ""]]], "Attached" -> (#["id"] === itGadgetRoot[])|> &,
      Select[kids, AssociationQ[#] && StringQ[Lookup[#, "id", None]] &&
        StringStartsQ[ToString[itVal[Lookup[#, "name", ""]]], "Mathematica Tablet"] &]]];

Options[ResoniteRealtime`ResoniteTabletAdopt] = {"PollInterval" -> 1.0};
ResoniteRealtime`ResoniteTabletAdopt[opts : OptionsPattern[]] :=
  With[{found = ResoniteRealtime`ResoniteTabletFind[]},
    Which[FailureQ[found], found,
      found === {}, iFailure["NoTablet", "ワールドにタブレット (\"Mathematica Tablet\") がありません。"],
      True, ResoniteRealtime`ResoniteTabletAdopt[Last[found]["Id"], opts]]];
ResoniteRealtime`ResoniteTabletAdopt[root_String, opts : OptionsPattern[]] :=
  Module[{tree, ids},
    If[!itLinkQ[], Return[iFailure["NotConnected", "ResoniteLink が未接続です (ResoniteRealtimeLinkConnect[])。"]]];
    tree = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[root, "Depth" -> -1, "IncludeComponentData" -> True,
      "Timeout" -> 30], $Failed];
    If[!AssociationQ[tree], Return[iFailure["GetSlot", root <> " が読めませんでした。"]]];
    ids = itParseTabletTree[tree];
    If[!AssociationQ[ids], Return[iFailure["NotATablet", root <> " はタブレットの構造ではありません。"]]];
    itAdoptIds[ids];
    If[!MatchQ[Lookup[$itState, "Task", None], _TaskObject],
      ResoniteRealtime`ResoniteTabletStart["PollInterval" -> OptionValue["PollInterval"]];
      itSetStatus["接続しました (" <> itAccessLabel[] <> ")"]];
    ids];

Options[ResoniteRealtime`ResoniteTabletServe] = {"PollInterval" -> 1.0, "Start" -> True};
ResoniteRealtime`ResoniteTabletServe[opts : OptionsPattern[]] :=
  Module[{o = Association @ Join[Options[ResoniteRealtime`ResoniteTabletServe], {opts}]},
    $itState = Join[$itState, <|"Serve" -> True, "LastScan" -> 0, "LastConnectTry" -> 0,
      "Candidates" -> Replace[Lookup[$itState, "Candidates", {}], Except[_List] -> {}]|>];
    If[TrueQ[o["Start"]] && !MatchQ[Lookup[$itState, "Task", None], _TaskObject],
      ResoniteRealtime`ResoniteTabletStart["PollInterval" -> o["PollInterval"], "Serve" -> True]];
    <|"Serve" -> True, "Linked" -> itLinkQ[], "Gadget" -> itGadgetQ[], "Task" -> Lookup[$itState, "Task", None]|>];
ResoniteRealtime`ResoniteTabletServe[False] :=
  ($itState = Join[$itState, <|"Serve" -> False, "Candidates" -> {}|>];
   If[!itGadgetQ[] && $itState["Lists"] === <||>, ResoniteRealtime`ResoniteTabletStop[]];
   False);

(* ワールドから消えたガジェット (getSlot が 2 回続けて失敗) は台帳から外す。残したままだと次の ▶ が Reuse で
   存在しないビューアに書き込んで何も出ない (2026-09-22)。タブレット本体は外さない *)
itNoteTargetOK[t_Association] :=
  ($itState["TargetFailures"] = KeyDrop[Lookup[$itState, "TargetFailures", <||>], t["Root"]]);
itNoteTargetFailure[t_Association] :=
  Module[{root = t["Root"], fails = Lookup[$itState, "TargetFailures", <||>], n},
    If[!AssociationQ[fails], fails = <||>];
    n = Lookup[fails, root, 0] + 1;
    $itState["TargetFailures"] = Append[fails, root -> n];
    If[n >= 2 && MemberQ[{"List", "PDF"}, t["Kind"]],
      itForgetGadget[root];
      $itState["TargetFailures"] = KeyDrop[$itState["TargetFailures"], root];
      $itState["LastError"] = iFailure["GadgetGone", t["Kind"] <> " " <> root <> " はワールドに無いので台帳から外しました。"]];
    If[n >= 3 && t["Kind"] === "Tablet" && TrueQ[$itState["Serve"]],
      $itState = Join[$itState, <|"Gadget" -> None, "Viewer" -> None, "Turn" -> None, "LastScan" -> 0|>];
      $itState["TargetFailures"] = KeyDrop[$itState["TargetFailures"], root];
      $itState["LastError"] = iFailure["GadgetGone", "タブレット " <> root <> " はワールドに無いので台帳から外しました (常駐監視は続く)。"]];
    (* Scan / Candidate の失敗は次の走査で拾い直す *)
    If[MemberQ[{"Scan", "Candidate"}, t["Kind"]],
      $itState["Candidates"] = DeleteCases[Replace[Lookup[$itState, "Candidates", {}], Except[_List] -> {}], root];
      $itState["TargetFailures"] = KeyDrop[$itState["TargetFailures"], root]]];

(* 押されたボタン (Value = True) を集めて False に戻し、種類ごとに処理する *)
itPressed[res_Association, buttons_Association] :=
  Select[Keys[buttons],
    icMemberValue[icFindComponent[res, buttons[#]], "Value"] === True &];

itHandleReply[target_Association, res_Association] :=
  Switch[target["Kind"],
    "Tablet", itHandleTablet[res],
    "List", itHandleList[target["Root"], res],
    "PDF", itHandlePDF[target["Root"], res],
    "Scan", itHandleScan[res],
    "Candidate", itHandleCandidate[target["Root"], res],
    _, Null];

itHandleTablet[res_Association] :=
  Module[{g = itGadget[], pressed, txt},
    If[!AssociationQ[g], Return[Null]];
    pressed = itPressed[res, g["Buttons"]];
    If[pressed === {}, Return[Null]];
    Scan[itSetFlag[g["Buttons"][#], False] &, pressed];
    Which[
      MemberQ[pressed, "Cancel"],
        If[AssociationQ[$itState["Turn"]] && $itState["Turn"]["Phase"] =!= "Done",
          ResoniteRealtime`ResoniteTabletCancel[], itSetStatus["実行中のターンはありません"]],
      MemberQ[pressed, "Deny"], ResoniteRealtime`ResoniteTabletDeny[],
      MemberQ[pressed, "Approve"], ResoniteRealtime`ResoniteTabletApprove[],
      MemberQ[pressed, "Eval"],
        txt = icMemberValue[icFindComponent[res, g["InputText"]], "Content"];
        If[!StringQ[txt] || StringTrim[txt] === "",
          itSetStatus["(入力が空です)"],
          itStartTurn[StringTrim[txt]]],
      MemberQ[pressed, "Clear"],
        itSetInput[""]; itSetOutput[""]; itSetStatus["ready"],
      MemberQ[pressed, "Make3D"], ResoniteRealtime`ResoniteTabletMake3D[],
      MemberQ[pressed, "Connect"], itConnectPressed[],
      MemberQ[pressed, "Prev"], ResoniteRealtime`ResoniteViewerPage["Prev"],
      MemberQ[pressed, "Next"], ResoniteRealtime`ResoniteViewerPage["Next"],
      MemberQ[pressed, "Close"], itViewerHide[],
      True, Null];
    pressed];

itHandleList[root_String, res_Association] :=
  Module[{rec = Lookup[$itState["Lists"], root, None], ids, pressed, opens},
    If[!AssociationQ[rec], Return[Null]];
    ids = rec["Ids"];
    pressed = itPressed[res, ids["Buttons"]];
    If[pressed === {}, Return[Null]];
    Scan[itSetFlag[ids["Buttons"][#], False] &, pressed];
    opens = Cases[pressed, s_String /; StringStartsQ[s, "Open"] :> ToExpression[StringDrop[s, 4]]];
    Which[
      MemberQ[pressed, "Close"], ResoniteRealtime`ResoniteListGadgetRemove[root],
      MemberQ[pressed, "Prev"], $itState["Lists", root, "Page"] = rec["Page"] - 1; itListRender[root],
      MemberQ[pressed, "Next"], $itState["Lists", root, "Page"] = rec["Page"] + 1; itListRender[root],
      opens =!= {}, itListOpen[root, First[opens]],
      True, Null];
    pressed];

Options[ResoniteRealtime`ResoniteTabletStart] = {"PollInterval" -> 1.0, "Serve" -> False};

ResoniteRealtime`ResoniteTabletStart[opts : OptionsPattern[]] :=
  Module[{dt, task},
    If[TrueQ[OptionValue[ResoniteRealtime`ResoniteTabletStart, {opts}, "Serve"]], $itState["Serve"] = True];
    If[!itGadgetQ[] && $itState["Lists"] === <||> && !TrueQ[$itState["Serve"]],
      Return[iFailure["NoGadget", "先に ResoniteTablet[] でタブレットを作ってください (常駐監視は ResoniteTabletServe[])。"]]];
    ResoniteRealtime`ResoniteTabletStop[];
    dt = OptionValue[ResoniteRealtime`ResoniteTabletStart, {opts}, "PollInterval"];
    task = SessionSubmit[ScheduledTask[ResoniteRealtime`Private`itPoll[], dt]];
    $itState = Join[$itState, <|"Task" -> task, "PollInterval" -> dt, "Busy" -> False, "Pending" -> None|>];
    Quiet @ Check[itInstallDisplayHook[], Null];
    itSetStatus["ready (" <> itAccessLabel[] <> ")"];
    task];

ResoniteRealtime`ResoniteTabletStop[] :=
  Module[{t = Lookup[$itState, "Task", None]},
    If[MatchQ[t, _TaskObject], Quiet[TaskRemove[t]]];
    $itState = Join[$itState, <|"Task" -> None, "Busy" -> False, "Pending" -> None|>];
    None];

ResoniteRealtime`ResoniteTabletTick[] := itPoll[];

(* ============================================================
   3D 生成: 直前のターンの Graphics3D をワールド内の 3D オブジェクトに (ResoniteRealtime_mesh.wl)
   ============================================================ *)

(* claudecode の $ClaudeRuntimeDisplayHook から呼ばれる: 生の結果に Graphics3D があれば機密度つきで溜める *)
itStash3D[rec_Association] :=
  Module[{gs, pl},
    gs = Cases[Lookup[rec, "Raw", Null], _Graphics3D | Legended[_Graphics3D, ___], {0, Infinity}];
    If[gs === {}, Return[Null]];
    pl = itPL[Lookup[rec, "Privacy", 1.]];
    With[{all = Join[Lookup[$itState, "Stash3D", {}],
        Map[<|"RuntimeId" -> Lookup[rec, "RuntimeId", None], "Turn" -> Lookup[rec, "Turn", None],
          "Graphics" -> #, "Privacy" -> pl, "Time" -> iNow[]|> &, gs]]},
      $itState["Stash3D"] = Take[all, -Min[20, Length[all]]]];
    Null];

(* 実行結果のうち図 (Graphics / Graphics3D / Legended / Image。リストなら直下の要素) を runtime ごとに取っておく。
   結果セルに図が来なかったターンの描画 (itStashDisplayCells) に使う。3D は itStash3D にも入る (3D生成用) *)
itStashDisplay[rec_Association] :=
  Module[{raw = Lookup[rec, "Raw", Null], gl = _Graphics | _Graphics3D | _Legended | _Image, items, pl},
    itStash3D[rec];
    items = Which[MatchQ[raw, gl], {raw}, ListQ[raw], Select[raw, MatchQ[#, gl] &], True, {}];
    If[items === {}, Return[Null]];
    pl = itPL[Lookup[rec, "Privacy", 1.]];
    With[{all = Join[Replace[Lookup[$itState, "StashDisplay", {}], Except[_List] -> {}],
        Map[<|"RuntimeId" -> Lookup[rec, "RuntimeId", None], "Turn" -> Lookup[rec, "Turn", None],
          "Raw" -> #, "Privacy" -> pl, "Time" -> iNow[], "Rendered" -> False|> &, items]]},
      $itState["StashDisplay"] = Take[all, -Min[20, Length[all]]]];
    Null];

itInstallDisplayHook[] :=
  If[Names["ClaudeCode`$ClaudeRuntimeDisplayHook"] =!= {},
    With[{prev = ClaudeCode`$ClaudeRuntimeDisplayHook},
      Which[
        MatchQ[prev, _Function] && !FreeQ[prev, itStashDisplay], Null,
        (* 無い、または自分の古い版 (itStash3D だけ) → 置き換える *)
        !MatchQ[prev, _Function] || !FreeQ[prev, itStash3D],
          ClaudeCode`$ClaudeRuntimeDisplayHook = Function[rec, ResoniteRealtime`Private`itStashDisplay[rec]],
        True,
          ClaudeCode`$ClaudeRuntimeDisplayHook = Function[rec, prev[rec]; ResoniteRealtime`Private`itStashDisplay[rec]]]]];

(* 直前のターンの Graphics3D 候補: stash (runtime 一致) -> runtime の LastExecutionResult -> 結果セルの Graphics3DBox *)
itGraphics3DCandidates[] :=
  Module[{t = Lookup[$itState, "Turn", None], rid, stash, res, gs = {}, st, raw, cells, exprs},
    If[!AssociationQ[t], Return[{}]];
    rid = t["RuntimeId"];
    stash = Select[Lookup[$itState, "Stash3D", {}], #["RuntimeId"] === rid && StringQ[rid] &];
    If[stash =!= {},
      Return[Map[<|"Graphics" -> #["Graphics"], "Privacy" -> #["Privacy"]|> &, stash]]];
    If[StringQ[rid],
      st = itRuntimeState[rid];
      raw = If[AssociationQ[st], Lookup[Lookup[st, "LastExecutionResult", <||>], "RawResult", Null], Null];
      gs = Cases[raw, _Graphics3D | Legended[_Graphics3D, ___], {0, Infinity}];
      If[gs =!= {}, Return[Map[<|"Graphics" -> #, "Privacy" -> itPL[Lookup[If[AssociationQ[st],
        Lookup[st, "LastExecutionResult", <||>], <||>], "EvaluationPrivacy", 0.]]|> &, gs]]]];
    (* 結果セルの Graphics3DBox (boxes が小さいときだけ残っている) *)
    cells = Select[Replace[Quiet @ Cells[t["Notebook"]], Except[_List] -> {}], !MemberQ[t["CellsBefore"], #] &];
    exprs = If[cells === {}, {}, Replace[Quiet @ Check[NotebookRead[cells], {}], Except[_List] -> {}]];
    gs = Join @@ Map[Function[c, Cases[c, b_Graphics3DBox :> Quiet @ Check[ToExpression[b], $Failed], {0, Infinity}]], exprs];
    gs = Select[gs, MatchQ[#, _Graphics3D] &];
    Map[<|"Graphics" -> #, "Privacy" -> itPL[Quiet @ Check[icSym["NBAccess`NBCellExprPrivacyLevel"][
      SelectFirst[exprs, !FreeQ[#, Graphics3DBox] &, Cell[""]]], $Failed]]|> &, gs]];

ResoniteRealtime`ResoniteTabletMake3D[opts : OptionsPattern[ResoniteRealtime`ResoniteGraphics3D]] :=
  Module[{cands, results = {}, r, n, i = 0, lvl = itAccessLevel[]},
    cands = Quiet @ Check[itGraphics3DCandidates[], {}];
    If[cands === {}, itSetStatus["直前のターンに 3D グラフィックスがありません"]; Return[{}]];
    n = Length[cands];
    Do[
      i++;
      If[!itAllowedQ[c["Privacy"]],
        itSetStatus["3D 生成: 機密度 " <> itFmt[c["Privacy"]] <> " > 表示上限 " <> itFmt[lvl] <> " のため作りません"];
        AppendTo[results, Failure["PrivacyExceeded", <|"MessageTemplate" -> "表示上限を超えています"|>]];
        Continue[]];
      itSetStatus["3D 生成中 (" <> ToString[i] <> "/" <> ToString[n] <> ") ..."];
      r = Quiet @ Check[ResoniteRealtime`ResoniteGraphics3D[c["Graphics"],
        "Offset" -> {0.8*(i - 1), 0, 0}, opts], $Failed];
      AppendTo[results, r];
      itSetStatus[If[AssociationQ[r],
        "3D 生成: " <> r["Root"] <> " (" <> ToString[r["Triangles"]] <> " tris, " <> ToString[r["Seconds"]] <> " s)",
        "3D 生成に失敗: " <> If[FailureQ[r], ToString[r["MessageTemplate"]], ToString[r]]]],
      {c, cands}];
    results];

(* ============================================================
   その他の公開 API
   ============================================================ *)

ResoniteRealtime`ResoniteTabletShow[text_String] := itSetOutput[text];
ResoniteRealtime`ResoniteTabletShow[expr_] :=
  Catch[itShowObject[expr, Association @ Options[ResoniteRealtime`ResoniteShowObject]], icTag];

ResoniteRealtime`ResoniteTabletLog[n_Integer : 10] := Take[$itLog, -Min[n, Length[$itLog]]];

ResoniteRealtime`ResoniteTabletStatus[] :=
  Module[{t = Lookup[$itState, "Turn", None], v = itViewer[]},
    <|"Gadget" -> itGadgetQ[],
      "Root" -> If[itGadgetQ[], itGadget[]["Root"], None],
      "Task" -> Lookup[$itState, "Task", None],
      "Polling" -> MatchQ[Lookup[$itState, "Task", None], _TaskObject],
      "Serve" -> TrueQ[Lookup[$itState, "Serve", False]],
      "Linked" -> itLinkQ[], "LinkPort" -> Lookup[$iState, "LinkPort", None],
      "Candidates" -> Replace[Lookup[$itState, "Candidates", {}], Except[_List] -> {}],
      "Adopted" -> If[itGadgetQ[], TrueQ[Lookup[itGadget[], "Adopted", False]], None],
      "AccessLevel" -> itAccessLevel[], "Owner" -> TrueQ[ResoniteRealtime`$ResoniteWorldOwner],
      "WorldAccess" -> icAccessName[],
      "Turn" -> If[AssociationQ[t], KeyTake[t, {"Prompt", "Phase", "RuntimeId", "LastStatus", "Start"}], None],
      "Viewer" -> If[AssociationQ[v], <|"Pages" -> Length[v["Pages"]], "Page" -> v["Page"], "Title" -> v["Title"]|>, None],
      "PDFViewer" -> With[{p = itPDF[]},
        If[AssociationQ[p], <|"Root" -> p["Ids"]["Root"], "Pages" -> Length[p["Pages"]], "Page" -> p["Page"], "Title" -> p["Title"]|>, None]],
      "PDFViewers" -> KeyValueMap[#1 -> <|"Pages" -> Length[#2["Pages"]], "Page" -> #2["Page"], "Title" -> #2["Title"]|> &, itPDFViewers[]],
      "Lists" -> KeyValueMap[#1 -> <|"Title" -> #2["Title"], "Rows" -> Length[#2["Rows"]], "Page" -> #2["Page"]|> &, $itState["Lists"]],
      "Notebook" -> Lookup[$itState, "Notebook", None],
      "PollFailures" -> Lookup[$itState, "PollFailures", 0],
      "LastError" -> Lookup[$itState, "LastError", None],
      "LastShow" -> Lookup[$itState, "LastShow", None],
      "Deferred" -> KeyValueMap[#1 -> KeyTake[#2, {"Label", "Status", "Time", "Via"}] &, $itDeferred],
      "Builds" -> Map[KeyTake[#, {"Label", "Phase", "Round", "Tries", "Root"}] &, $itBuilds],
      "BuildMode" -> If[itBuildModeTick[], "Tick", "Notebook"],
      "ImageServer" -> icImageServerQ[]|>];

(* LLM が提案コードの中で呼べるように、表示 API を NBAccess の許可ヘッドに 2 層登録する *)
$itAgentHeads = {
  "ResoniteShowObject", "ResoniteListGadget", "ResoniteViewerShow", "ResoniteViewerPage",
  "ResoniteTabletShow", "ResoniteTabletStatus", "ResoniteTabletLog", "ResoniteTabletNotebook",
  "ResoniteAccessLevel", "ResoniteChatStatus",
  "ResoniteGraphics3D", "ResoniteGraphics3DMesh", "ResoniteMeshJSON", "ResoniteTabletMake3D",
  "ResonitePDFViewer", "ResonitePDFViewerPage",
  (* 2026-09-23: 世界に物を作る部品と、読むだけの状態確認。LLM が状態確認 (ResoniteRealtimeStatus /
     ResoniteFluxCatalogSearch) を提案して承認待ちになり、本題に進めなかった実例から *)
  "ResoniteColorToggleBox", "ResoniteTabletDeferred",
  "ResoniteRealtimeStatus", "ResoniteRealtimeLinkMessages", "ResoniteFluxCatalog", "ResoniteFluxCatalogSearch"};
$itApprovalHeads = {
  "ResoniteTablet", "ResoniteTabletRemove", "ResoniteListGadgetRemove", "ResoniteViewerRemove",
  "ResoniteVideoBoard", "ResoniteViewer", "ResoniteGraphics3DRemove", "ResonitePDFViewerRemove"};

(* DownValues は HoldAll なので Symbol["..."] を直接渡せない (DownValues::sym)。icSym で解決した
   シンボルを Apply で渡す。NBAccess 不在なら Missing。 *)
ResoniteRealtime`ResoniteTabletRegisterHeads[] :=
  Module[{reg, trusted, appr},
    reg     = icSym["NBAccess`NBRegisterAllowedHeads"];
    trusted = icSym["NBAccess`NBRegisterTrustedPackageHeads"];
    appr    = icSym["NBAccess`NBRegisterApprovalHeads"];
    If[reg === None || Length[DownValues @@ {reg}] === 0, Return[Missing["NoNBAccess"]]];
    Quiet @ Check[reg[$itAgentHeads], Null];
    If[trusted =!= None, Quiet @ Check[trusted["ResoniteRealtime`", $itAgentHeads], Null]];
    If[appr =!= None, Quiet @ Check[appr[$itApprovalHeads], Null]];
    <|"Registered" -> Length[$itAgentHeads], "Approval" -> Length[$itApprovalHeads]|>];

ResoniteRealtime`ResoniteTabletRegisterHeads[];

End[];
EndPackage[];
