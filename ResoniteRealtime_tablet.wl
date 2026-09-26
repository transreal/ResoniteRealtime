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
  "  \"Distance\", \"Height\", \"Position\", \"Parent\", \"CanvasSize\" -> {1400, 1000}, \"PanelScale\" -> 0.0006, \"FontSize\" -> 30,\n" <>
  "  \"View\" -> Automatic (直近のタブレットのプロンプトに「サムネ / 一覧」があればサムネイル一覧) | \"List\" | \"Thumbnails\"。\n" <>
  "フッタの「サムネ」ボタンでサムネイル一覧に切り替わる。戻り値: <|\"Root\", \"Count\", \"Hidden\", ...|>。";
ResoniteRealtime`ResoniteListGadgetRemove::usage =
  "ResoniteListGadgetRemove[rootId] は一覧ガジェットを消す。ResoniteListGadgetRemove[] は全部消す。";
ResoniteRealtime`ResoniteThumbnailGadget::usage =
  "ResoniteThumbnailGadget[rows] は行リストのサムネイルを 1 枚の大きな面 (Canvas 1 つ、テクスチャは貼り合わせた JPEG) に\n" <>
  "升目で並べる。升目をクリックするとその PDF / 画像が開く (ResoniteShowObject と同じ)。「リスト」ボタンで一覧に戻る。\n" <>
  "サムネイル: Eagle の項目は <name>_thumbnail.png、画像はそのもの、PDF は 1 ページ目、無ければ空カード。\n" <>
  "タブレットの左隣 (タブレットの子にはしない) に出る。オプション: \"Title\", \"Columns\" -> Automatic, \"ThumbSize\" -> {200, 260} (px),\n" <>
  "\"ThumbMeters\" -> 0.12 (サムネイル 1 枚の幅 m), \"MaxRows\" -> 7, \"MaxItems\" -> Infinity, \"FontSize\" -> 18。\n" <>
  "縦は MaxRows 段まで積み、それ以上は横にいくらでも広げる (全件を並べる。289 件 = 42 x 7)。高さ 2.4 m を超える面だけ縮める。\n" <>
  "横に長い面は 36 列ずつの帯 (帯ごとに JPEG 1 枚) に分けて貼る。帯の JPEG は元画像と配置が同じなら使い回す。\n" <>
  "見出しの「機密度で非表示 N」は表示上限を超える行、「ほか N 件はリストで」は MaxItems (整数を与えたとき) を超えた行。\n" <>
  "\"Shape\" -> \"Plane\" (既定) | \"Cylinder\" (アバターを囲む円筒) | \"SphereInside\" (アバターを中心とする球の内側) | \"Mobius\" (メビウスの帯) |\n" <>
  "ResoniteThumbnailSurface[...] (任意の面)。曲面は升目ごとのタイルを面の点と接平面に置き、中心はアバターの目 (\"Center\" -> Automatic)。\n" <>
  "見出しの「形を変更」ボタンで $ResoniteThumbnailShapes の順に切り替わる (ResoniteThumbnailShape)。";
ResoniteRealtime`ResoniteThumbnailGadgetRemove::usage =
  "ResoniteThumbnailGadgetRemove[rootId] はサムネイル一覧を消す。ResoniteThumbnailGadgetRemove[] は全部消す。";
ResoniteRealtime`ResoniteEagleFolderGadget::usage =
  "ResoniteEagleFolderGadget[folder] は Eagle のフォルダ (名前または id、スマートフォルダも可) の項目を一覧 / サムネイル一覧に出す\n" <>
  "(行は SourceVaultEagleSummaryRow)。オプション: \"View\" -> Automatic (「サムネ / 一覧」ならサムネイル) | \"List\" | \"Thumbnails\",\n" <>
  "\"Recursive\" -> False, \"Ext\" -> All | \"pdf\" | {...}, \"Title\" -> Automatic。";
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
ResoniteRealtime`$ResoniteTabletStashTemplate::usage =
  "$ResoniteTabletStashTemplate (既定 True) のとき、ワールドの標準 PDF ビューアの雛形を 1 つ複製してタブレットの子に\n" <>
  "\"PDF Template (Mathematica)\" として非表示で保管し、以後の雛形に使う (雛形の出し直しや削除に強くなり、\n" <>
  "インベントリに保存したタブレットにも入る)。False で保管しない。";
ResoniteRealtime`$ResoniteNativeLogFile::usage =
  "$ResoniteNativeLogFile は標準ビューア (Native PDF) の段階記録 NativeLog の追記先。既定 %TEMP%\\ResoniteRealtime\\native_pdf.log (タブ区切り: 時刻 / NB か headless / PID / ジョブ / 段階 / 試行 / 注記)。None で書かない。";
ResoniteRealtime`$ResonitePDFMode::usage =
  "$ResonitePDFMode: \"Native\" (既定) なら PDF を Resonite 標準のドキュメントビューア (雛形 = タブレット / サムネイル一覧に保管した物、\n" <>
  "無ければワールドにある物を ProtoFlux で複製し、配信 URL を差し替える) で開く。雛形が無いときは Resonite の文書表示\n" <>
  "(ResoniteDocViewer: StaticDocument + DocumentPageTexture。ページ送りはワールドの中だけで動く) で開く ($ResonitePDFLite = False なら\n" <>
  "自前パネルに落ちる)。\"Lite\" なら常に文書表示、\"Panel\" なら自前のページ画像パネル (ResonitePDFViewer)。";
ResoniteRealtime`ResonitePDFTemplate::usage =
  "ResonitePDFTemplate[] は複製の雛形 (Resonite 標準の PDF ビューア。名前が \"PDF Template\" で始まる物、無ければ *.pdf) を\n" <>
  "ワールド (Root から 2 段) で探して覚える。ResonitePDFTemplate[slotId] で明示、ResonitePDFTemplate[None] で忘れる。";
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
ResoniteRealtime`$ResoniteOwnerPresenceGate::usage =
  "$ResoniteOwnerPresenceGate (既定 True): ワールド内のボタン (タブレット / 一覧 / サムネイル一覧 / PDF ビューア / 接続) の操作を、\n" <>
  "オーナー (= ResoniteLink をつないでいるホスト) がそのワールドにいて見ているときだけ、このカーネルで実行する。\n" <>
  "判定はワールド側の ProtoFlux (HostUser -> IsUserPresent。ホストだけが評価) に毎回問い合わせる: そのワールドにフォーカスが\n" <>
  "あり、VR ならヘッドセットを着けていること。別のワールドにフォーカスを移している (ResoniteLink は残っている) ときや、\n" <>
  "問い合わせに答えが来ないときは、誰が押しても実行しない (厳しい側)。False にすると判定しない (単独でのデバッグ用)。";
ResoniteRealtime`$ResoniteOwnerPresenceFreshSeconds::usage =
  "$ResoniteOwnerPresenceFreshSeconds (既定 5): 直近の在席確認がこの秒数以内に「在席」なら、ボタンの操作をすぐ実行する。\n" <>
  "それより古ければ、押された操作を保留して問い合わせ直し、答えを見てから実行するか断る。";
ResoniteRealtime`$ResoniteThumbnailsDisclosable::usage =
  "$ResoniteThumbnailsDisclosable (既定 True、2026-09-26 方針): サムネイル一覧の升目 (縮小画像と題名) は機密度にかかわらず見せてよい物として扱う。\n" <>
  "機密度で行を落とさず、覆い (非表示) も付けず、インベントリから出したときも升目を隠さない。秘匿するのは中身 (開いた PDF 等) だけで、\n" <>
  "開くときに表示上限で判定する。False にすると前の動き (表示上限以上の行を落とす / 覆う、出し直すと「接続」まで隠す)。";
ResoniteRealtime`$ResonitePDFPageClick::usage =
  "$ResonitePDFPageClick (既定 True): PDF のページそのものを押すと次のページへ進むようにする。文書表示 (ResoniteDocViewer) は\n" <>
  "組み立て時に、標準ビューアの複製は置いた直後に木を読んでページ表示と [次へ] を探して結ぶ (結果は ResoniteTabletStatus[][\"NativeLog\"])。";
ResoniteRealtime`ResoniteOwnerPresence::usage =
  "ResoniteOwnerPresence[] はオーナー在席の判定の状態 <|\"Gate\", \"Present\", \"Watching\", \"AckSecondsAgo\", \"Nonce\", \"AckNonce\",\n" <>
  "\"Ready\", \"Held\" (保留中の操作), \"Log\" (直近の実行 / 拒否)|> を返す。";

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

itEnqueueBuild[label_String, sender_Function, id0_ : Automatic] :=
  Module[{id = If[StringQ[id0], id0, StringTake[CreateUUID[], 8]]},
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

(* 結線用に読むスロット: 組み立ての戻り値が "WireSlot" を持てばそれ (サムネイル一覧の State。升目が多いと根ごとは重い) *)
itWireTarget[res_Association] := Lookup[res, "WireSlot", res["Root"]];
(* 巡ごとに読むスロットを変えられる ("WireSlots" -> {1 巡目, 2 巡目, ...}。2026-09-25: サムネイル一覧の 2 巡目は覆いの文字) *)
itWireTarget[res_Association, k_Integer] :=
  With[{ws = Lookup[res, "WireSlots", None]},
    If[ListQ[ws] && 1 <= k <= Length[ws] && StringQ[ws[[k]]], ws[[k]], itWireTarget[res]]];

(* 組み立ての送信を tick に分ける (2026-09-25): サムネイル一覧 289 件は 2,100 通、1 tick で送ると ~2 s 塞ぎ、件数が増えると
   FE の「動的評価の放棄」ダイアログの範囲に入る。Sender の間は ResoniteLink への送信を記録するだけにし (返事は待たない
   送信と同じ <|"Sent", "MessageId"|>)、tick ごとに $itDrainSeconds ぶん送る。小さい組み立てはその tick で送り終わる *)
$itDrainSeconds = 0.3;
itRecordLink[m_Association, opts_List] :=
  Module[{msgId = Lookup[m, "messageId", ResoniteRealtime`ResoniteRealtimeNewId["Msg"]]},
    AppendTo[$itOutbox, Join[<|"messageId" -> msgId|>, m]];
    <|"Sent" -> True, "MessageId" -> msgId|>];
$itOutbox = {};

itBuildSend[id_String, b_Association] :=
  Module[{res, wires, rounds, root, outbox},
    {res, wires, rounds, root, outbox} = Block[{$iLinkWaitDefault = False, $itWireLater = {}, $itWireRounds = {}, $itBuildRoot = None,
        $itOutbox = {}},
      Block[{ResoniteRealtime`ResoniteRealtimeLink},
        ResoniteRealtime`ResoniteRealtimeLink[m_Association, o___] := itRecordLink[m, {o}];
        {Quiet @ Check[b["Sender"][], $Failed], $itWireLater, $itWireRounds, $itBuildRoot, $itOutbox}]];
    If[StringQ[root], $itBuilds[id, "Root"] = root];
    If[!AssociationQ[res] || !StringQ[Lookup[res, "Root", None]],
      Return[itBuildFinish[id, "Failed", res]]];   (* 何も送っていない *)
    If[!ListQ[rounds], rounds = {}];
    $itBuilds[id] = Join[b, <|"Phase" -> "Drain", "Outbox" -> outbox, "Result" -> res, "Wires" -> wires, "Rounds" -> rounds,
      "Root" -> res["Root"], "Total" -> Length[outbox]|>];
    itBuildDrain[id, $itBuilds[id]]];

itBuildDrain[id_String, b_Association] :=
  Module[{out = Replace[Lookup[b, "Outbox", {}], Except[_List] -> {}], t0 = iNow[], k = 0, n, res = b["Result"], sent},
    n = Length[out];
    While[k < n && (k === 0 || iNow[] - t0 < $itDrainSeconds),
      k++; Quiet @ Check[ResoniteRealtime`ResoniteRealtimeLink[out[[k]], "Wait" -> False], Null]];
    If[k < n,
      $itBuilds[id, "Outbox"] = Drop[out, k];
      itSetStatus[Lookup[b, "Label", "組み立て"] <> " を送っています (" <> ToString[b["Total"] - (n - k)] <> " / " <>
        ToString[b["Total"]] <> ")"];
      Return[Null]];
    (* 全部送った: 結線 (あれば) *)
    If[b["Wires"] === {} && b["Rounds"] === {}, Return[itBuildFinish[id, "Done", res]]];
    sent = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[itWireTarget[res, 1], "Depth" -> -1,
      "IncludeComponentData" -> True, "Wait" -> False], $Failed];
    If[!AssociationQ[sent] || !StringQ[Lookup[sent, "MessageId", None]],
      Return[itBuildFinish[id, "Failed", iFailure["GetSlot", "結線用の getSlot を送れませんでした。"]]]];
    $itBuilds[id] = Join[KeyDrop[b, "Outbox"], <|"Phase" -> "Wire", "Round" -> 1, "MessageId" -> sent["MessageId"], "Sent" -> iNow[],
      "Tries" -> 1|>]];

(* 失敗して消したガジェットを台帳からも外す *)
itForgetGadget[root_String] :=
  ($itState["Lists"] = KeyDrop[Lookup[$itState, "Lists", <||>], root];
   $itState["Thumbs"] = KeyDrop[itThumbs[], root];
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
            sent = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[itWireTarget[b["Result"], round + 1], "Depth" -> -1,
              "IncludeComponentData" -> True, "Wait" -> False], $Failed];
            If[!AssociationQ[sent] || !StringQ[Lookup[sent, "MessageId", None]],
              itBuildFinish[id, "Failed", iFailure["GetSlot", "結線用の getSlot を送れませんでした。"]],
              $itBuilds[id] = Join[b, <|"Round" -> round + 1, "MessageId" -> sent["MessageId"], "Sent" -> iNow[], "Tries" -> 1|>]],
          True, itBuildFinish[id, "Done", b["Result"]]],
      iNow[] - b["Sent"] > 10 && b["Tries"] < 3,
        sent = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[itWireTarget[b["Result"], round], "Depth" -> -1,
          "IncludeComponentData" -> True, "Wait" -> False], $Failed];
        $itBuilds[id] = Join[b, <|"MessageId" -> Lookup[sent, "MessageId", b["MessageId"]], "Sent" -> iNow[],
          "Tries" -> b["Tries"] + 1|>],
      iNow[] - b["Sent"] > 10,
        itBuildFinish[id, "Failed", iFailure["Timeout", "結線用の getSlot の応答が来ませんでした。"]],
      True, Null]];

itProcessBuilds[] :=
  KeyValueMap[Function[{id, b},
    Switch[b["Phase"], "Send", itBuildSend[id, b], "Drain", itBuildDrain[id, b], "Wire", itBuildWire[id, b], _, Null]], $itBuilds];

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
    "Mathematica Toggle Box", "Mathematica PDFs", "SourceVault Thumbnails", "Mathematica World Info", "Mathematica PDF Viewer"},
  "Prefixes" -> {"Mathematica Tablet", "SourceVault Thumbnails"}};

ResoniteRealtime`ResoniteTabletCleanup[opts : OptionsPattern[]] :=
  Module[{names, prefixes, tree, val, kids, hits, removed = {}},
    If[!itLinkQ[], Return[iFailure["NotConnected", "ResoniteLink が未接続です。"]]];
    names = OptionValue["Names"]; prefixes = OptionValue["Prefixes"];
    val = If[AssociationQ[#], Lookup[#, "value", #], #] &;
    tree = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot["Root", "Depth" -> 1, "Timeout" -> 30], $Failed];
    If[!AssociationQ[tree], Return[iFailure["GetSlot", "Root の階層が取れませんでした。"]]];
    (* サムネイル一覧もタブレットの隣に置くので名前では拾えない。台帳から消す *)
    Do[
      Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[id], Null];
      AppendTo[removed, <|"Id" -> id, "Name" -> ToString[Lookup[itThumbs[][id], "Title", "Thumbnails"]]|>],
      {id, Keys[itThumbs[]]}];
    (* 標準ビューアの複製はタブレットの隣 (タブレットの親の子) に置くので名前では拾えない。台帳から消す *)
    Do[
      Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[id], Null];
      AppendTo[removed, <|"Id" -> id, "Name" -> ToString[Lookup[itNativeDocs[][id], "Title", "PDF"]]|>],
      {id, Keys[itNativeDocs[]]}];
    Do[
      Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[id], Null];
      AppendTo[removed, <|"Id" -> id, "Name" -> ToString[Lookup[idDocViewers[][id], "Title", "PDF"]]|>],
      {id, Keys[Quiet @ Check[idDocViewers[], <||>]]}];
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
    $itState = Join[$itState, <|"Gadget" -> None, "Viewer" -> None, "PDFViewers" -> <||>, "Lists" -> <||>, "Turn" -> None,
      "NativeDocs" -> <||>, "PDFDup" -> None, "DocJobs" -> {}, "Thumbs" -> <||>, "WorldInfo" -> None, "WorldInfoBuilding" -> False,
      "DocViewers" -> <||>, "TexImports" -> {}, "BoardJobs" -> <||>, "BoardCands" -> {}, "BoardCandInfo" -> <||>,
      "Presence" -> <||>, "HeldPresses" -> {}|>];
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

(* ---- 裏板 (2026-09-24 ユーザー指示) ----
   UIX のパネルは奥行きを書かない半透明の扱いなので、後ろのガラスや空が手前に描かれて透けて見え、厚みも無いので
   横から見ると消える。パネルの裏 (+z。利用者は -z 側) に薄い不透明な箱を置く (奥行きを書くので後ろが隠れ、縁が見える) *)
$itBackingDepth = 0.015; $itBackingMargin = 0.012;
$itBackingColor = RGBColor[0.1, 0.11, 0.13];
itBacking[parent_String, {w_?NumericQ, h_?NumericQ}] :=
  Module[{s, mesh, mat},
    s = icSlot["Backing", parent, "Position" -> N[{0., 0., $itBackingDepth/2 + 0.002}]];
    mesh = icComp[s, $icFE <> "BoxMesh", <|"Size" -> N[{w + 2 $itBackingMargin, h + 2 $itBackingMargin, $itBackingDepth}]|>];
    mat = icComp[s, $icFE <> "PBS_Metallic", <|"AlbedoColor" -> $itBackingColor, "Metallic" -> 0., "Smoothness" -> 0.25|>];
    icComp[s, $icFE <> "MeshRenderer",
      <|"Mesh" -> ResoniteRealtime`ResoniteRealtimeRef[mesh],
        "Materials" -> <|"$type" -> "list", "elements" -> {ResoniteRealtime`ResoniteRealtimeRef[mat]}|>|>];
    s];

(* 裏板の無いタブレット (この版より前に作った / インベントリから出した) に 1 回だけ後付けする (tick、待たない) *)
itMaybeBacking[] :=
  Module[{g = itGadget[], s},
    If[!AssociationQ[g] || StringQ[Lookup[g, "Backing", None]] || !StringQ[Lookup[g, "Root", None]] || !itLinkQ[] ||
       TrueQ[Lookup[g, "BackingTried", False]], Return[None]];
    $itState["Gadget", "BackingTried"] = True;
    s = itNoWait @ Quiet @ Check[itBacking[g["Root"], Lookup[g, "CanvasSize", {1000, 1500}]*Lookup[g, "PanelScale", 0.0006]], $Failed];
    If[StringQ[s], $itState["Gadget", "Backing"] = s];
    s];

(* ---- ワールドの公開度と所有者を自動で知る (2026-09-25 ユーザー指示) ----
   「プライベートで、オーナー (nconc) だけが admin で所有するワールドなら表示上限 1.0 になるはず」。
   ResoniteLink のメッセージにセッション情報は無い (status は版番号だけ、ワールド設定はスロットに属さない) が、
   部品 SessionInfoSource は SessionId を入れると公開度 / ホスト / ワールド記録の所有者 / 人数を埋める (実機:
   AccessLevel "Private"、HostUserId "U-nconc"、CorrespondingOwnerId "U-nconc")。今のセッション ID は ProtoFlux の
   WorldSessionID でしか取れない (ログには開いている全ワールドが混ざる) ので、Root 直下に小さな仕掛けを置く:
     Mathematica World Info
     ├─ info       SessionInfoSource
     ├─ trigger    ValueInput<bool>            (WL が True にする)
     ├─ sessionId  WorldSessionID
     ├─ target     ObjectValueSource<string> + GlobalReference<IValue<string>> (-> info.SessionId)
     ├─ write      ObjectWrite<FrooxEngineContext, string> (Value <- sessionId, Variable -> target)
     └─ fire       FireOnTrue (Condition <- trigger, OnChanged -> write)
   罠: ObjectWrite<string> (ExecutionContext 版) は FrooxEngine の変数を受けず Variable が空のまま (実機)。
   空の SessionInfoSource も AccessLevel は既定値 "Private" を示すので、SessionId とホストが入るまで信じない。
   ResoniteLink は自分がホストのワールドでしか使えないので、つないでいる自分 = ホスト。オーナー = ホストがワールド記録の
   所有者 ($ResoniteOwnerUserId を文字列で置けば、その ID であることも要求する)。

   ---- オーナー在席の確認 (2026-09-25 ユーザー指示) ----
   「フレンドが押した操作も、オーナーの PC で実行したい。ただしオーナーがそのワールドにいて、目が行き届くときだけ」。
   FrooxEngine.dll の IL で確かめたこと (2026-09-25):
     - ホストが抜けるとセッションは終わる: クライアントは SessionConnectionManager.OnHostConnectionClosed ->
       World.HostConnectionClosed -> World.Destroy (ホストの移譲は無い)。VRChat のように残り続けることはない。
     - ただしホストは別のワールドにフォーカスを移せる (元のワールドは裏で動き続け、ResoniteLink も残る)。このとき
       User.IsPresentInWorld が False になる (WorldManager.BeginUpdate がフォーカスの切り替えで各ワールドの LocalUser に書く)。
     - User.IsPresent = IsPresentInWorld && (VR でなければ真 | IsPresentInHeadset)。VR でヘッドセットを外しても False。
       デスクトップで Mathematica のウインドウに切り替えても IsPresentInWorld は変わらない (Resonite 内のフォーカスの話)。
   ワールドの中でボタンを押せるのはそのワールドにフォーカスしている人だけなので、「オーナーが在席していない」なら押したのは
   オーナー以外。押した人を個別に調べなくても、在席を確かめれば要求どおりになる。
   在席はワールド側の ProtoFlux に問い合わせる (ホストだけが評価。OnlyForUser = HostUser):
     ├─ nonce        ValueInput<int>              (WL が問い合わせのたびに 1 増やす)
     ├─ host         HostUser
     ├─ present      IsUserPresent (User <- host)
     ├─ presentTarget / ackTarget   ValueSource<bool> / ValueSource<int> + GlobalReference (-> info の ValueField)
     ├─ writePresent ValueWrite<FrooxEngineContext, bool> (present -> Present) --OnWritten--> writeAck
     ├─ writeAck     ValueWrite<FrooxEngineContext, int>  (nonce -> Ack)
     └─ probe        FireOnValueChange<int> (Value <- nonce, OnlyForUser <- host, OnChanged -> writePresent)
   info スロットに ValueField<bool> Present / ValueField<int> Ack を置き、SessionInfoSource と一緒に 1 回の getSlot で読む。
   Ack が送った nonce と一致したら、それはホストのクライアントがいまこのワールドで評価した答え。答えが来なければ不在扱い。 *)
$itWorldInfoName = "Mathematica World Info";
$itWorldInfoSeconds = 10;     (* 読み直しの間隔 *)
$itWorldInfoStale = 90;       (* これより古い読み取りは信じない (厳しい側へ) *)
If[!ValueQ[ResoniteRealtime`$ResoniteOwnerUserId], ResoniteRealtime`$ResoniteOwnerUserId = Automatic];

itWorldInfo[] := With[{w = Lookup[$itState, "WorldInfo", None]}, If[AssociationQ[w], w, None]];
itAutoAccessQ[] := ResoniteRealtime`$ResoniteWorldAccessMode === Automatic;

itWorldInfoBuild[] :=
  Catch[
    Module[{pfb = $itPFB, ref = ResoniteRealtime`ResoniteRealtimeRef, root, info, sInfo, s, trig, wsid, tgt, vsrc, ow, fire, grefId, fid,
        vPres, vAck, nonce, host, pres, presT, presSrc, ackT, ackSrc, wAck, wPres, gPres, gAck, fec, pid, aid},
      If[!itLinkQ[], Throw[iFailure["NotConnected", "ResoniteLink が未接続です。"], icTag]];
      root = icSlot[$itWorldInfoName, "Root", "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["WInfo"]];
      $itBuildRoot = root;
      icComp[root, $icFE <> "AI_GeneratedContent",
        <|"Source" -> "Mathematica ResoniteRealtime world info (session access level for the tablet display limit)"|>];
      info = icSlot["info", root];
      sInfo = icComp[info, $icFE <> "SessionInfoSource", <|"SessionId" -> ""|>, ResoniteRealtime`ResoniteRealtimeNewId["SInfo"]];
      s = icSlot["trigger", root];
      trig = icComp[s, pfb <> "ProtoFlux.Runtimes.Execution.Nodes.ValueInput<bool>", <|"Value" -> False|>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["sessionId", root];
      wsid = icComp[s, pfb <> "ProtoFlux.Runtimes.Execution.Nodes.FrooxEngine.Worlds.WorldSessionID", <||>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      tgt = icSlot["target", root];
      vsrc = icComp[tgt, pfb <> "FrooxEngine.ProtoFlux.CoreNodes.ObjectValueSource<string>", <||>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["write", root];
      ow = icComp[s, pfb <> "ProtoFlux.Runtimes.Execution.Nodes.ObjectWrite<[FrooxEngine]FrooxEngine.ProtoFlux.FrooxEngineContext,string>",
        <|"Value" -> ref[wsid], "Variable" -> ref[vsrc]|>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["fire", root];
      fire = icComp[s, pfb <> "ProtoFlux.Runtimes.Execution.Nodes.Actions.FireOnTrue",
        <|"Condition" -> ref[trig], "OnChanged" -> ref[ow]|>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      (* オーナー在席の問い合わせ (上の注記)。答えの置き場は info (SessionInfoSource と一緒に読む) *)
      fec = "[FrooxEngine]FrooxEngine.ProtoFlux.FrooxEngineContext";
      vPres = icComp[info, $icFE <> "ValueField<bool>", <|"Value" -> False|>, ResoniteRealtime`ResoniteRealtimeNewId["WPres"]];
      vAck = icComp[info, $icFE <> "ValueField<int>", <|"Value" -> 0|>, ResoniteRealtime`ResoniteRealtimeNewId["WAck"]];
      s = icSlot["nonce", root];
      nonce = icComp[s, pfb <> "ProtoFlux.Runtimes.Execution.Nodes.ValueInput<int>", <|"Value" -> 0|>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["host", root];
      host = icComp[s, pfb <> "ProtoFlux.Runtimes.Execution.Nodes.FrooxEngine.Users.HostUser", <||>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["present", root];
      pres = icComp[s, pfb <> "ProtoFlux.Runtimes.Execution.Nodes.FrooxEngine.Users.IsUserPresent", <|"User" -> ref[host]|>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      presT = icSlot["presentTarget", root];
      presSrc = icComp[presT, pfb <> "FrooxEngine.ProtoFlux.CoreNodes.ValueSource<bool>", <||>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      ackT = icSlot["ackTarget", root];
      ackSrc = icComp[ackT, pfb <> "FrooxEngine.ProtoFlux.CoreNodes.ValueSource<int>", <||>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["writeAck", root];
      wAck = icComp[s, pfb <> "ProtoFlux.Runtimes.Execution.Nodes.ValueWrite<" <> fec <> ",int>",
        <|"Value" -> ref[nonce], "Variable" -> ref[ackSrc]|>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["writePresent", root];
      wPres = icComp[s, pfb <> "ProtoFlux.Runtimes.Execution.Nodes.ValueWrite<" <> fec <> ",bool>",
        <|"Value" -> ref[pres], "Variable" -> ref[presSrc], "OnWritten" -> ref[wAck]|>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["probe", root];
      icComp[s, pfb <> "ProtoFlux.Runtimes.Execution.Nodes.Actions.FireOnValueChange<int>",
        <|"Value" -> ref[nonce], "OnlyForUser" -> ref[host], "OnChanged" -> ref[wPres]|>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      (* 書き込み先 = info.SessionId / Present.Value / Ack.Value のメンバ ID。tick の組み立てでは 1 巡目に結線 (読むのは info スロットだけ) *)
      grefId = ResoniteRealtime`ResoniteRealtimeNewId["GRef"];
      gPres = ResoniteRealtime`ResoniteRealtimeNewId["GRef"]; gAck = ResoniteRealtime`ResoniteRealtimeNewId["GRef"];
      If[ListQ[$itWireLater],
        $itWireRounds = {{
          <|"Action" -> "Add", "Slot" -> tgt, "Type" -> $icFE <> "ProtoFlux.GlobalReference<[FrooxEngine]FrooxEngine.IValue<string>>",
            "Id" -> grefId, "Refs" -> <|"Reference" -> {sInfo, "SessionId"}|>|>,
          <|"Action" -> "Update", "Component" -> vsrc, "Members" -> <|"Source" -> ref[grefId]|>|>,
          <|"Action" -> "Add", "Slot" -> presT, "Type" -> $icFE <> "ProtoFlux.GlobalReference<[FrooxEngine]FrooxEngine.IValue<bool>>",
            "Id" -> gPres, "Refs" -> <|"Reference" -> {vPres, "Value"}|>|>,
          <|"Action" -> "Update", "Component" -> presSrc, "Members" -> <|"Source" -> ref[gPres]|>|>,
          <|"Action" -> "Add", "Slot" -> ackT, "Type" -> $icFE <> "ProtoFlux.GlobalReference<[FrooxEngine]FrooxEngine.IValue<int>>",
            "Id" -> gAck, "Refs" -> <|"Reference" -> {vAck, "Value"}|>|>,
          <|"Action" -> "Update", "Component" -> ackSrc, "Members" -> <|"Source" -> ref[gAck]|>|>}},
        fid = icMemberId[info, sInfo, "SessionId"];
        pid = icMemberId[info, vPres, "Value"];
        aid = icMemberId[info, vAck, "Value"];
        If[!StringQ[fid] || !StringQ[pid] || !StringQ[aid],
          Throw[iFailure["NoMemberId", "ワールド情報の結線先 (SessionId / Present / Ack) のメンバ ID が取れませんでした。"], icTag]];
        icComp[tgt, $icFE <> "ProtoFlux.GlobalReference<[FrooxEngine]FrooxEngine.IValue<string>>", <|"Reference" -> ref[fid]|>, grefId];
        icCheck @ ResoniteRealtime`ResoniteRealtimeUpdateComponent[vsrc, <|"Source" -> ref[grefId]|>];
        icComp[presT, $icFE <> "ProtoFlux.GlobalReference<[FrooxEngine]FrooxEngine.IValue<bool>>", <|"Reference" -> ref[pid]|>, gPres];
        icCheck @ ResoniteRealtime`ResoniteRealtimeUpdateComponent[presSrc, <|"Source" -> ref[gPres]|>];
        icComp[ackT, $icFE <> "ProtoFlux.GlobalReference<[FrooxEngine]FrooxEngine.IValue<int>>", <|"Reference" -> ref[aid]|>, gAck];
        icCheck @ ResoniteRealtime`ResoniteRealtimeUpdateComponent[ackSrc, <|"Source" -> ref[gAck]|>]];
      $itState["Presence"] = <||>;
      $itState["WorldInfo"] = <|"Root" -> root, "Info" -> info, "SInfo" -> sInfo, "Trigger" -> trig,
        "Present" -> vPres, "Ack" -> vAck, "Nonce" -> nonce,
        "Link" -> Lookup[$iState, "Link", None], "Built" -> None, "Fired" -> None, "Data" -> None, "Time" -> None,
        "LastRead" -> 0, "Created" -> iNow[]|>;
      <|"Root" -> root, "WireSlot" -> info, "Kind" -> "WorldInfo"|>],
    icTag];

(* tick: 仕掛けが無い / 接続が変わった (ワールドが変わったかも) なら作り直し、組み上がって 3 s 後に 1 回発火する *)
itMaybeWorldInfo[] :=
  Module[{w = itWorldInfo[], st},
    (* 在席の確認にも使うので、公開度が手動 ("Manual") でも在席ゲートが有効なら組む *)
    If[!(itAutoAccessQ[] || itGateOnQ[]) || !itLinkQ[], Return[None]];
    (* 接続が変わった (ワールドが変わったかも) / 在席の問い合わせが無い古い版 (再ロード前に組んだ物。$itState は再ロードで残る) は作り直す *)
    If[AssociationQ[w] && (w["Link"] =!= Lookup[$iState, "Link", None] ||
        (itGateOnQ[] && NumericQ[Lookup[w, "Built", None]] && !StringQ[Lookup[w, "Nonce", None]])),
      itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[w["Root"]], Null];
      $itState["WorldInfo"] = None; w = None; $itState["Presence"] = <||>;
      itWorldInfoApply[None]];
    If[w === None,
      If[TrueQ[Lookup[$itState, "WorldInfoBuilding", False]], Return[None]];
      $itState["WorldInfoBuilding"] = True;
      $itState["WorldInfoBuildId"] = If[itBuildModeTick[] || itAsyncContextQ[],
        itEnqueueBuild["ワールド情報", Function[itWorldInfoBuild[]]],
        (itWorldInfoBuild[]; $itState["WorldInfo", "Built"] = iNow[]; None)];
      Return[None]];
    If[w["Built"] === None,
      st = Lookup[Lookup[$itDeferred, Lookup[$itState, "WorldInfoBuildId", ""], <||>], "Status", None];
      Which[
        st === "Done", $itState["WorldInfo", "Built"] = iNow[]; $itState["WorldInfoBuilding"] = False,
        st === "Failed", $itState["WorldInfo"] = None; $itState["WorldInfoBuilding"] = False];
      Return[None]];
    $itState["WorldInfoBuilding"] = False;
    Which[
      w["Fired"] === None && iNow[] - w["Built"] >= $itNativeWarmupSeconds,
        itSetFlag[w["Trigger"], True]; $itState["WorldInfo", "Fired"] = iNow[],
      NumericQ[w["Fired"]] && iNow[] - w["Fired"] > 2 && !TrueQ[Lookup[w, "Reset", False]],
        itSetFlag[w["Trigger"], False]; $itState["WorldInfo", "Reset"] = True];
    (* 読み取りが途絶えたら厳しい側へ *)
    If[NumericQ[w["Time"]] && iNow[] - w["Time"] > $itWorldInfoStale, itWorldInfoApply[None]]];

(* 在席の問い合わせの答え待ちなら急ぎで読む ("Urgent": 巡回を待たずに次の getSlot にする。押された操作を保留している) *)
itWorldInfoTargets[] :=
  With[{w = itWorldInfo[]},
    Which[
      !AssociationQ[w], {},
      itPresenceOutstandingQ[] && iNow[] - Lookup[w, "LastRead", 0] > 0.4,
        {<|"Kind" -> "WorldInfo", "Root" -> w["Info"], "Depth" -> 0, "Components" -> True, "Urgent" -> itHeld[] =!= {}|>},
      itAutoAccessQ[] && NumericQ[w["Fired"]] && iNow[] - w["Fired"] > 1 &&
        iNow[] - Lookup[w, "LastRead", 0] > $itWorldInfoSeconds,
        {<|"Kind" -> "WorldInfo", "Root" -> w["Info"], "Depth" -> 0, "Components" -> True|>},
      True, {}]];

itHandleWorldInfo[res_Association] :=
  Module[{w = itWorldInfo[], comp, m, d},
    If[!AssociationQ[w], Return[None]];
    $itState["WorldInfo", "LastRead"] = iNow[];
    Quiet @ Check[itHandlePresence[res, w], $itState["LastError"] = "presence"];
    comp = icFindComponent[res, w["SInfo"]];
    If[!AssociationQ[comp], Return[None]];
    m = Lookup[comp, "members", <||>];
    d = AssociationMap[icMemberValue[comp, #] &,
      {"SessionId", "Name", "HostUserId", "HostUsername", "CorrespondingOwnerId", "AccessLevel", "JoinedUsers"}];
    $itState["WorldInfo", "Data"] = d;
    $itState["WorldInfo", "Time"] = iNow[];
    itWorldInfoApply[d]];

(* 読み取りを公開度とオーナーに写す。SessionId とホストが入っていなければ (空の SessionInfoSource) 厳しい側 *)
itWorldInfoApply[d_] :=
  Module[{before = itAccessLabel[], ok, access, owner, cfg = ResoniteRealtime`$ResoniteOwnerUserId},
    If[!itAutoAccessQ[], Return[None]];
    ok = AssociationQ[d] && StringQ[d["SessionId"]] && d["SessionId"] =!= "" &&
      StringQ[d["HostUserId"]] && d["HostUserId"] =!= "" && StringQ[d["AccessLevel"]];
    If[ok,
      access = Switch[d["AccessLevel"], "Private", "Private", "Contacts", "Contacts", "ContactsPlus", "ContactsPlus", _, "Public"];
      owner = StringQ[d["CorrespondingOwnerId"]] && d["HostUserId"] === d["CorrespondingOwnerId"] &&
        (!StringQ[cfg] || d["HostUserId"] === cfg);
      ResoniteRealtime`$ResoniteWorldAccess = access;
      ResoniteRealtime`$ResoniteWorldOwner = owner,
      ResoniteRealtime`$ResoniteWorldAccess = "Public";
      ResoniteRealtime`$ResoniteWorldOwner = False];
    If[itAccessLabel[] =!= before && itGadgetQ[],
      itSetText["TitleText", Lookup[itGadget[], "Name", "Mathematica Tablet"] <> "   [" <> itAccessLabel[] <> "]"];
      itSetStatus["表示上限: " <> itAccessLabel[] <>
        If[ok, " (" <> d["AccessLevel"] <> "、ホスト " <> d["HostUserId"] <> "、所有者 " <> ToString[d["CorrespondingOwnerId"]] <> ")",
          " (ワールドの情報が取れないので厳しい側)"]]];
    itAccessLevel[]];

(* ---- オーナー在席の確認とボタン操作のゲート (2026-09-25 ユーザー指示。仕組みは itWorldInfoBuild の前の注記) ----
   ワールドのボタンはだれが押しても同期されたフィールドが変わり、このカーネル (オーナーの PC) の監視が読んで実行する。
   その実行の前に itPressGate を通す:
     - 直近 $ResoniteOwnerPresenceFreshSeconds 秒以内の答えが「在席」なら、すぐ実行する。
     - そうでなければ操作を保留し、問い合わせ (nonce を 1 増やす) を出して、答えを見てから実行する / 断る。
       押した後に出した問い合わせに「不在」と答えがあった、または $itPresenceHoldSeconds 秒答えが無い -> 断る
       (ボタンの旗は押された時点で戻してあるので、断った操作は消える)。
   問い合わせは $itPresenceSeconds 秒ごとにも出す (巡回の読み取りに載るので、在席中はたいていすぐ実行できる)。 *)
If[!BooleanQ[ResoniteRealtime`$ResoniteOwnerPresenceGate], ResoniteRealtime`$ResoniteOwnerPresenceGate = True];
If[!NumericQ[ResoniteRealtime`$ResoniteOwnerPresenceFreshSeconds], ResoniteRealtime`$ResoniteOwnerPresenceFreshSeconds = 5];
$itPresenceSeconds = 3;        (* 定期の問い合わせの間隔 *)
$itPresenceRetrySeconds = 4;   (* 答えの来ない問い合わせを出し直すまで *)
$itPresenceHoldSeconds = 8;    (* 保留した操作をこれ以上待たせない (答えが来なければ断る) *)
$itHeldMax = 5;
$itGateBypass = False;

itGateOnQ[] := TrueQ[ResoniteRealtime`$ResoniteOwnerPresenceGate];
itPresence[] := Replace[Lookup[$itState, "Presence", <||>], Except[_Association] -> <||>];
itHeld[] := Replace[Lookup[$itState, "HeldPresses", {}], Except[_List] -> {}];

(* 問い合わせの仕掛けが組み上がって落ち着いたか (組み立て直後に書くと ProtoFlux が永久に沈黙する。$itNativeWarmupSeconds) *)
itPresenceReadyQ[] :=
  With[{w = itWorldInfo[]},
    AssociationQ[w] && StringQ[Lookup[w, "Nonce", None]] && NumericQ[Lookup[w, "Built", None]] &&
      iNow[] - w["Built"] >= $itNativeWarmupSeconds];

(* 答え待ち = 送った nonce の答えがまだ無い (出し直しまでの間) *)
itPresenceOutstandingQ[] :=
  With[{p = itPresence[]},
    IntegerQ[Lookup[p, "Nonce", None]] && Lookup[p, "AckNonce", 0] =!= p["Nonce"] &&
      iNow[] - Lookup[p, "SentAt", 0] <= $itPresenceRetrySeconds];

itOwnerWatchingQ[] :=
  With[{p = itPresence[]},
    TrueQ[Lookup[p, "Present", False]] && NumericQ[Lookup[p, "AckAt", None]] &&
      iNow[] - p["AckAt"] <= ResoniteRealtime`$ResoniteOwnerPresenceFreshSeconds];

itPresenceProbe[] :=
  Module[{w = itWorldInfo[], p = itPresence[], n, r},
    If[!itPresenceReadyQ[] || !itLinkQ[], Return[None]];
    n = Lookup[p, "Nonce", 0] + 1;
    r = itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateComponent[w["Nonce"], <|"Value" -> n|>], $Failed];
    If[r === $Failed || FailureQ[r], Return[None]];
    $itState["Presence"] = Join[p, <|"Nonce" -> n, "SentAt" -> iNow[]|>];
    n];

(* info の getSlot 応答から答えを拾う。いま待っている nonce の答えだけ数える (出し直す前の分が遅れて来ても使わない) *)
itHandlePresence[res_, w_Association] :=
  Module[{p = itPresence[], ack, pres},
    If[!StringQ[Lookup[w, "Ack", None]] || !StringQ[Lookup[w, "Present", None]], Return[None]];
    ack = icMemberValue[icFindComponent[res, w["Ack"]], "Value"];
    pres = icMemberValue[icFindComponent[res, w["Present"]], "Value"];
    If[!IntegerQ[ack] || !IntegerQ[Lookup[p, "Nonce", None]] || ack =!= p["Nonce"] || Lookup[p, "AckNonce", 0] === ack,
      Return[None]];
    $itState["Presence"] = Join[p, <|"AckNonce" -> ack, "AckAt" -> iNow[], "AckSentAt" -> Lookup[p, "SentAt", iNow[]],
      "Present" -> TrueQ[pres]|>];
    itPresenceResolve[]];

itSayHeld[h_Association, msg_String] :=
  (itSetStatus[msg]; If[Lookup[h, "Say", None] =!= None, Quiet @ Check[h["Say"][msg], Null]]);

itRunHeld[h_Association] :=
  Module[{r},
    r = Block[{$itGateBypass = True}, Quiet @ Check[ReleaseHold[h["Action"]], $Failed]];
    $itState["PressLog"] = Take[Append[Replace[Lookup[$itState, "PressLog", {}], Except[_List] -> {}],
      <|"Time" -> DateString[{"Hour", ":", "Minute", ":", "Second"}], "Label" -> h["Label"], "Result" -> "Run",
        "HeldSeconds" -> Round[iNow[] - h["Time"], 0.1]|>], -Min[20, Length[Lookup[$itState, "PressLog", {}]] + 1]];
    r];

itRefuseHeld[h_Association] :=
  Module[{msg},
    msg = If[h["Reason"] === "Absent",
      "オーナーがこのワールドを見ていないので実行しません",
      "オーナーの在席を確かめられないので実行しません"] <> " (" <> h["Label"] <> ")";
    itSayHeld[h, msg];
    $itState["PressLog"] = Take[Append[Replace[Lookup[$itState, "PressLog", {}], Except[_List] -> {}],
      <|"Time" -> DateString[{"Hour", ":", "Minute", ":", "Second"}], "Label" -> h["Label"], "Result" -> "Refused",
        "Reason" -> h["Reason"]|>], -Min[20, Length[Lookup[$itState, "PressLog", {}]] + 1]];
    msg];

itPresenceResolve[] :=
  Module[{held = itHeld[], p = itPresence[], keep = {}, run = {}, refuse = {}},
    If[held === {}, Return[0]];
    Do[Which[
        !itGateOnQ[] || itOwnerWatchingQ[], AppendTo[run, h],
        (* 押した後に出した問い合わせに「不在」と答えがあった *)
        Lookup[p, "Present", None] === False && NumericQ[Lookup[p, "AckSentAt", None]] && p["AckSentAt"] >= h["Time"],
          AppendTo[refuse, Append[h, "Reason" -> "Absent"]],
        iNow[] - h["Time"] > $itPresenceHoldSeconds || !itLinkQ[],
          AppendTo[refuse, Append[h, "Reason" -> "NoAnswer"]],
        True, AppendTo[keep, h]],
      {h, held}];
    $itState["HeldPresses"] = keep;
    Scan[itRefuseHeld, refuse];
    Scan[itRunHeld, run];
    Length[run]];

(* tick: 定期の問い合わせ (保留があって在席が確かでなければすぐ) と、保留の期限切れ *)
itPresenceTick[] :=
  Module[{p = itPresence[]},
    If[itGateOnQ[] && itPresenceReadyQ[] && !itPresenceOutstandingQ[] &&
       ((itHeld[] =!= {} && !itOwnerWatchingQ[]) || iNow[] - Lookup[p, "SentAt", 0] >= $itPresenceSeconds),
      itPresenceProbe[]];
    itPresenceResolve[]];

(* ボタンの操作の関門。action は保留されうるので、ハンドラの局所変数は With で値を埋めて渡す。
   say: 保留・拒否の知らせをガジェット自身の状態欄にも出す関数 (None ならタブレットの状態欄だけ) *)
SetAttributes[itPressGate, HoldRest];
itPressGate[label_String, say_, action_] :=
  Which[
    !itGateOnQ[] || TrueQ[$itGateBypass] || itOwnerWatchingQ[], action,
    True,
      Module[{h = <|"Label" -> label, "Say" -> say, "Action" -> Hold[action], "Time" -> iNow[]|>, held = itHeld[]},
        $itState["HeldPresses"] = Take[Append[held, h], -Min[$itHeldMax, Length[held] + 1]];
        If[!itPresenceOutstandingQ[], itPresenceProbe[]];
        itSayHeld[h, "オーナーの在席を確かめています… (" <> label <> ")"];
        <|"Held" -> True, "Label" -> label|>]];

ResoniteRealtime`ResoniteOwnerPresence[] :=
  With[{p = itPresence[]},
    <|"Gate" -> itGateOnQ[], "Present" -> Lookup[p, "Present", None], "Watching" -> itOwnerWatchingQ[],
      "AckSecondsAgo" -> If[NumericQ[Lookup[p, "AckAt", None]], Round[iNow[] - p["AckAt"], 0.1], None],
      "Nonce" -> Lookup[p, "Nonce", None], "AckNonce" -> Lookup[p, "AckNonce", None], "Ready" -> itPresenceReadyQ[],
      "Held" -> Lookup[itHeld[], "Label", {}],
      "Log" -> Replace[Lookup[$itState, "PressLog", {}], Except[_List] -> {}]|>];

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
      ids["Backing"] = itBacking[root, csz*pscale];
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

(* 題名の [表示上限] を今の値に合わせる (2026-09-25 ユーザー指摘: 題名 [PL<0.25 guest] と状態 ready (PL<1.00 Private) が食い違った。
   題名は表示上限が「変わったとき」だけ書いていたので、再ロード・引き継ぎ・インベントリから出した直後に古いまま残った)。
   tick ごとに比べ、違うときだけ書く *)
itSyncTitle[] :=
  Module[{g = itGadget[], want},
    If[!AssociationQ[g] || !itLinkQ[] || !StringQ[Lookup[g, "TitleText", None]], Return[None]];
    want = Lookup[g, "Name", "Mathematica Tablet"] <> "   [" <> itAccessLabel[] <> "]";
    If[Lookup[g, "TitleShown", None] =!= want,
      itSetText["TitleText", want]; $itState["Gadget", "TitleShown"] = want];
    want];

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
  "FontSize" -> 30, "Name" -> "PDF Viewer", "Title" -> "", "PageSize" -> 1200, "MaxPages" -> 400, "Reuse" -> False,
  "Native" -> Automatic};

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
      (* Resonite 標準のビューアで開く (雛形があるとき)。PDF だけ。画像 / .nb は自前パネル *)
      If[itExt[file] === "pdf" && (o["Native"] === True || (o["Native"] === Automatic && itNativeTryQ[])),
        Return[itNativeSpawn[file, Replace[o["Title"], "" -> FileNameTake[file]]]]];
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
      itBacking[root, csz*pscale];
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
  Map[ResoniteRealtime`ResonitePDFViewerRemove,
    Join[Keys[itPDFViewers[]], Keys[itNativeDocs[]], Keys[Quiet @ Check[idDocViewers[], <||>]]]];
ResoniteRealtime`ResonitePDFViewerRemove[root_String] :=
  Module[{v = itPDF[root], r = None},
    If[AssociationQ[v],
      r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[root], $Failed];
      $itState["PDFViewers"] = KeyDrop[itPDFViewers[], root]];
    If[KeyExistsQ[itNativeDocs[], root],
      r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[root], $Failed];
      $itState["NativeDocs"] = KeyDrop[itNativeDocs[], root]];
    If[KeyExistsQ[Quiet @ Check[idDocViewers[], <||>], root],
      r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[root], $Failed];
      $itState["DocViewers"] = KeyDrop[idDocViewers[], root]];
    r];

(* ============================================================
   Resonite 標準のドキュメントビューアで PDF を開く ("Native"、2026-09-24)

   ResoniteLink には「インポート」も「複製」も無い (0.13.1 は mesh / texture 資産だけ)。標準ビューアは 155 slot /
   348 component / ProtoFlux 111 個の雛形で、コンポーネントを一つずつ作り直すのは非現実的。代わりに
     1. ワールドにある標準ビューア (雛形: 名前が "PDF Template" で始まる物、無ければ *.pdf) を覚え、
     2. 小さな ProtoFlux (ValueInput<bool> → FireOnTrue → DuplicateSlot(雛形, OverrideParent = 置き場)) を一度だけ置き、
     3. 開くたびに ValueInput の Value を True にして複製させ、置き場に現れた複製の StaticDocument.URL を
        配信 URL (L3) に差し替え、名前と位置を整える (実機 2026-09-24: http の PDF を標準ビューアが描画した)。
   すべて tick の 2 相 (送る / 次の tick で照合) で待たない。ValueInput<bool> を使うのは出力が一つでプロキシ解決
   (待つ getSlot) が要らないから。
   ============================================================ *)
If[!MemberQ[{"Native", "Panel"}, ResoniteRealtime`$ResonitePDFMode], ResoniteRealtime`$ResonitePDFMode = "Native"];
$itPFB = "[ProtoFluxBindings]FrooxEngine.";
(* 複製待ち: 実機はトリガから約 2 s で現れる (2026-09-24、NB / headless とも。照会は 2 s ごと)。現れないときは
   ガジェットが死んでいる (カーネルの最初のガジェットがときどき沈黙する。作り直すと動く) ので、長く待たずに 6 s で作り直す *)
$itNativeSpawnSeconds = 6; $itNativeReplySeconds = 10;
(* 組み立て直後にトリガを書くと ProtoFlux のノード群が二度と発火しない (2026-09-24 実機: 0 s 後は永久に沈黙、0.5 s 後は動く。
   NB の tick は前の tick の終わりから 0.1 s 後に来ることがある) ので、組み立てから $itNativeWarmupSeconds は触らない *)
$itNativeWarmupSeconds = 3;

itNativeDocs[] := Replace[Lookup[$itState, "NativeDocs", <||>], Except[_Association] -> <||>];
(* 雛形の保管 (2026-09-24 ユーザー指示): ワールドの雛形はユーザーが出し直すと ID が変わり、消えることもある。
   複製を 1 つタブレットの子に「PDF Template (Mathematica)」として非表示 (isActive False) で保管し、あればそれを雛形に使う。
   タブレットをインベントリに保存すると一緒に入り、引き継ぎ (根を Depth 1 で読む) で見つかる *)
$itStashName = "PDF Template (Mathematica)";
If[!ValueQ[ResoniteRealtime`$ResoniteTabletStashTemplate], ResoniteRealtime`$ResoniteTabletStashTemplate = True];
itStashId[] := With[{g = itGadget[]}, If[AssociationQ[g] && StringQ[Lookup[g, "Stash", None]], g["Stash"], None]];
(* 雛形の出どころ: タブレットの保管 > サムネイル一覧の保管 (2026-09-25: 一覧だけでも開けるように) > ワールドの雛形 *)
itNativeTemplate[] :=
  With[{st = itStashId[], bs = Quiet @ Check[idBoardStash[], None], t = Lookup[$itState, "PDFTemplate", None]},
    Which[StringQ[st], <|"Id" -> st, "Name" -> $itStashName, "Stash" -> True|>,
      StringQ[bs], <|"Id" -> bs, "Name" -> $itStashName, "Stash" -> True, "Board" -> True|>,
      AssociationQ[t], t, True, None]];
(* 無くなった雛形を忘れる (保管ならタブレットの記録から、ワールドの雛形なら PDFTemplate から) *)
itForgetTemplate[id_] :=
  (If[StringQ[id] && itStashId[] === id, $itState["Gadget", "Stash"] = None];
   If[StringQ[id], Scan[If[Lookup[itThumbs[][#], "Stash", None] === id, $itState["Thumbs", #, "Stash"] = None] &, Keys[itThumbs[]]]];
   With[{t = Lookup[$itState, "PDFTemplate", None]},
     If[!StringQ[id] || (AssociationQ[t] && Lookup[t, "Id", None] === id), $itState["PDFTemplate"] = None]]);
itNativeTemplateId[] := With[{t = itNativeTemplate[]}, If[AssociationQ[t], Lookup[t, "Id", None], None]];
itNativeReadyQ[] := ResoniteRealtime`$ResonitePDFMode === "Native" && StringQ[itNativeTemplateId[]];
(* 標準ビューアで試すか: 雛形を知っている、または直近 5 分に「雛形が無い」と分かっていない (その間は探しに行かず自前パネル)。
   2026-09-24 実機: ユーザーが雛形を出し直して ID が変わり、古い ID のまま 3 回とも複製が出ず自前パネルに落ちた *)
itNativeTryQ[] :=
  itLinkQ[] && (ResoniteRealtime`$ResonitePDFMode === "Lite" ||
    ResoniteRealtime`$ResonitePDFMode === "Native" &&
      (TrueQ[ResoniteRealtime`$ResonitePDFLite] || StringQ[itNativeTemplateId[]] ||
        iNow[] - Lookup[$itState, "TemplateMissingAt", -1000] > 300));
(* 2026-09-25: 雛形が無いと分かっているときは文書ビューア (ResoniteRealtime_docboard.wl) で開く (自前パネルに落とさない) *)
itNativeDup[] := With[{d = Lookup[$itState, "PDFDup", None]},
  If[AssociationQ[d] && d["Template"] === itNativeTemplateId[], d, None]];

(* 木を平らに (depth 段まで)。自分の置き場の下は見ない *)
itSlotsUpTo[tree_Association, depth_Integer] :=
  Module[{acc = {}, holder = Lookup[Replace[Lookup[$itState, "PDFDup", <||>], Except[_Association] -> <||>], "Holder", None], walk},
    walk[s_, d_] := If[AssociationQ[s] && Lookup[s, "id", None] =!= holder,
      AppendTo[acc, s]; If[d < depth, Scan[walk[#, d + 1] &, Lookup[s, "children", {}]]]];
    Scan[walk[#, 1] &, Lookup[tree, "children", {}]];
    acc];

(* 雛形の候補: "PDF Template" で始まる名前 > ".pdf" で終わる名前。自分が出した複製は除く *)
itNativeTemplateCandidates[slots_List] :=
  Module[{own = Keys[itNativeDocs[]], named, hits, nameOf, keyOf},
    nameOf = ToLowerCase[ToString[itVal[Lookup[#, "name", ""]]]] &;
    (* "PDF Template" / "PDF_Template" / "pdf-template" を同じに扱う *)
    keyOf = StringDelete[nameOf[#], " " | "_" | "-"] &;
    (* 自分が出した複製と、タブレットに保管した雛形 (別のタブレットの物も) は除く *)
    named = Select[slots, AssociationQ[#] && StringQ[Lookup[#, "id", None]] && !MemberQ[own, #["id"]] &&
      ToString[itVal[Lookup[#, "name", ""]]] =!= $itStashName &];
    hits = Select[named, StringStartsQ[keyOf[#], "pdftemplate"] &];
    If[hits === {}, hits = Select[named, StringEndsQ[nameOf[#], ".pdf"] &]];
    Map[<|"Id" -> #["id"], "Name" -> ToString[itVal[Lookup[#, "name", ""]]]|> &, hits]];

ResoniteRealtime`ResonitePDFTemplate[] :=
  Module[{t = itNativeTemplate[], tree, cands},
    If[AssociationQ[t], Return[t]];
    If[!itLinkQ[], Return[iFailure["NotConnected", "ResoniteLink が未接続です。"]]];
    tree = itScanSlotsNow[];
    If[FailureQ[tree], Return[tree]];
    cands = itNativeTemplateCandidates[tree];
    If[cands === {},
      Return[iFailure["NoTemplate",
        "Resonite 標準の PDF ビューア (名前が \"PDF Template\" で始まる物、または *.pdf) がワールドにありません。1 つインポートして置いてください。"]]];
    $itState["TemplateWanted"] = False; $itState["TemplateCheckedAt"] = iNow[];
    $itState["PDFTemplate"] = First[cands]];
ResoniteRealtime`ResonitePDFTemplate[None] := ($itState["PDFTemplate"] = None; $itState["PDFDup"] = None; None);
ResoniteRealtime`ResonitePDFTemplate[id_String] :=
  ($itState["TemplateWanted"] = False; $itState["TemplateMissingAt"] = -1000; $itState["TemplateCheckedAt"] = 0;
   $itState["StashFailedAt"] = -10^6;
   $itState["PDFTemplate"] = <|"Id" -> id, "Name" -> id|>);

(* 複製ガジェット: 置き場 "Mathematica PDFs" (Root 直下) + ProtoFlux 5 ノード。結線は 2 段目 (fluxlink と同じ)。待たない *)
itNativeDupBuild[] :=
  Catch[
    Module[{tpl = itNativeTemplateId[], holder, root, s, trig, tplRef, tplNode, holdRef, holdNode, dup, fire, ref},
      If[!StringQ[tpl], Throw[iFailure["NoTemplate", "雛形が未設定です (ResonitePDFTemplate[])。"], icTag]];
      If[!itLinkQ[], Throw[iFailure["NotConnected", "ResoniteLink が未接続です。"], icTag]];
      ref = ResoniteRealtime`ResoniteRealtimeRef;
      holder = icSlot["Mathematica PDFs", "Root", "Position" -> {0., 0., 0.}];
      root = icSlot["PDF Duplicator", holder, "Position" -> {0., -3., 0.}, "Scale" -> {0.05, 0.05, 0.05}];
      icComp[root, $icFE <> "AI_GeneratedContent", <|"Source" -> "Mathematica ResoniteRealtime PDF duplicator (ProtoFlux)"|>];
      s = icSlot["trigger", root];
      trig = icComp[s, $itPFB <> "ProtoFlux.Runtimes.Execution.Nodes.ValueInput<bool>", <|"Value" -> False|>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["templateSlot", root];
      tplRef = icComp[s, $icFE <> "ProtoFlux.GlobalReference<[FrooxEngine]FrooxEngine.Slot>", <|"Reference" -> ref[tpl]|>];
      tplNode = icComp[s, $itPFB <> "FrooxEngine.ProtoFlux.CoreNodes.ElementSource<[FrooxEngine]FrooxEngine.Slot>",
        <|"Source" -> ref[tplRef]|>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["parentSlot", root];
      holdRef = icComp[s, $icFE <> "ProtoFlux.GlobalReference<[FrooxEngine]FrooxEngine.Slot>", <|"Reference" -> ref[holder]|>];
      holdNode = icComp[s, $itPFB <> "FrooxEngine.ProtoFlux.CoreNodes.ElementSource<[FrooxEngine]FrooxEngine.Slot>",
        <|"Source" -> ref[holdRef]|>, ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["duplicate", root];
      dup = icComp[s, $itPFB <> "ProtoFlux.Runtimes.Execution.Nodes.FrooxEngine.Slots.DuplicateSlot", <||>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      s = icSlot["fire", root];
      fire = icComp[s, $itPFB <> "ProtoFlux.Runtimes.Execution.Nodes.Actions.FireOnTrue", <||>,
        ResoniteRealtime`ResoniteRealtimeNewId["Node"]];
      icCheck @ ResoniteRealtime`ResoniteRealtimeUpdateComponent[dup, <|"Template" -> ref[tplNode], "OverrideParent" -> ref[holdNode]|>];
      icCheck @ ResoniteRealtime`ResoniteRealtimeUpdateComponent[fire, <|"Condition" -> ref[trig], "OnChanged" -> ref[dup]|>];
      $itState["PDFDup"] = <|"Holder" -> holder, "Root" -> root, "Trigger" -> trig, "Template" -> tpl, "Created" -> iNow[]|>],
    icTag];

(* 開く = ジョブを積むだけ。tick が進める *)
(* 開く PDF の機密度 (itShowDocument が Block で渡す。不明なら None = 1.0 扱いで写しを置かない) *)
If[!ValueQ[$itOpenPL], $itOpenPL = None];
(* 写し (ResoniteRealtime_pdfcache.wl): Private / Contacts のワールドなら web サーバの URL を使う (無ければ送り始めて、今は local) *)
itOpenDocURL[file_String, local_String, title_String] :=
  Replace[Quiet @ Check[ipcOpenURL[file, local, $itOpenPL, title], None],
    Except[_Association] -> <|"URL" -> local, "CacheKey" -> None|>];

itNativeSpawn[file_String, title_String] :=
  Module[{url, n, id, c},
    If[!itEnsureImageServer[], Return[iFailure["NoServer", "画像配信 (ResoniteRealtimeStart[]) が要ります。"]]];
    url = ResoniteRealtime`ResoniteRealtimeAsset[file];
    If[FailureQ[url], Return[url]];
    c = itOpenDocURL[file, url, title];
    (* ページ数: 130 MB の PDF で 5-8 s かかる (2026-09-25 実測)。大きい物は作業用カーネルで数え、分かるまで 0 *)
    n = Quiet @ Check[idPageCount[file], 0];
    id = StringTake[CreateUUID[], 8];
    $itState["DocJobs"] = Append[Replace[Lookup[$itState, "DocJobs", {}], Except[_List] -> {}],
      <|"Id" -> id, "Phase" -> If[TrueQ[Quiet @ Check[idLiteDirectQ[], False]], "LiteInit", "Init"], "URL" -> url,
        "Title" -> title, "File" -> file, "Pages" -> n, "Time" -> iNow[], "Tries" -> 0, "Anchor" -> $itOpenAnchor,
        "CacheKey" -> c["CacheKey"]|>];
    itSetStatus["PDF を開いています: " <> itTruncate[title, 40]];
    <|"Native" -> True, "Deferred" -> True, "Id" -> id, "Pages" -> n, "Title" -> title|>];

itSendGet[root_String, depth_Integer, comps : (True | False)] :=
  With[{r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[root, "Depth" -> depth,
      "IncludeComponentData" -> comps, "Wait" -> False], $Failed]},
    If[AssociationQ[r], Lookup[r, "MessageId", None], None]];
itNativeFail[j_Association, why_String] /; Lookup[j, "Kind", "Doc"] === "Doc" && TrueQ[ResoniteRealtime`$ResonitePDFLite] &&
    StringQ[Lookup[j, "URL", None]] && !StringStartsQ[ToString[j["Phase"]], "Lite"] :=
  (itNativeLog[j["Id"], "Failed", j["Tries"], why <> " -> Resonite の文書表示で開きます"];
   itSetStatus["標準ビューアが使えないので Resonite の文書表示で開きます: " <> itTruncate[j["Title"], 40]];
   Join[j, <|"Phase" -> "LiteInit", "Tries" -> 0|>]);
itNativeFail[j_Association, why_String] :=
  (itNativeLog[j["Id"], "Failed", j["Tries"], why];
   $itState["LastError"] = iFailure["NativePDF", why, KeyTake[j, {"Id", "Title", "Phase", "Tries", "Kind"}]];
   If[Lookup[j, "Kind", "Doc"] === "Stash",
     $itState["StashFailedAt"] = iNow[],
     itSetStatus["PDF を開けません: " <> why];
     itNativeFallback[j]];
   None);

(* 保管が無ければ作る: タブレットがあり、ワールドの雛形を知っていて、PDF を開いていない (DocJobs が空) とき。
   失敗したら 10 分は試さない *)
(* 2026-09-25: 保管先はタブレット (保管が無ければ) → サムネイル一覧 (保管が無い物、組み上がって接続済み)。元の雛形は
   どこの物でもよい (ワールドの雛形 / タブレットの保管 / 別の一覧の保管) *)
itStashTarget[] :=
  Module[{g = itGadget[], b},
    If[AssociationQ[g] && StringQ[Lookup[g, "Root", None]] && !StringQ[itStashId[]], Return[g["Root"]]];
    b = SelectFirst[Keys[itThumbs[]], !StringQ[Lookup[itThumbs[][#], "Stash", None]] &&
      Lookup[itThumbs[][#], "Phase", "Ready"] === "Ready" && !TrueQ[Lookup[itThumbs[][#], "StashTried", False]] &, None];
    b];
itMaybeStash[] :=
  Module[{target = itStashTarget[], tid = itNativeTemplateId[], jobs = Replace[Lookup[$itState, "DocJobs", {}], Except[_List] -> {}], id},
    If[!StringQ[target] || !TrueQ[ResoniteRealtime`$ResoniteTabletStashTemplate] ||
       ResoniteRealtime`$ResonitePDFMode =!= "Native" || !StringQ[tid] ||
       jobs =!= {} || iNow[] - Lookup[$itState, "StashFailedAt", -10^6] < 600 || !itLinkQ[],
      Return[None]];
    If[KeyExistsQ[itThumbs[], target], $itState["Thumbs", target, "StashTried"] = True];
    id = "stash-" <> StringTake[CreateUUID[], 6];
    itNativeLog[id, "Stash", 0, "雛形 " <> tid <> " の複製を " <> target <> " に保管します"];
    $itState["DocJobs"] = {<|"Id" -> id, "Kind" -> "Stash", "Phase" -> "Init", "Title" -> $itStashName,
      "Time" -> iNow[], "Tries" -> 0, "Target" -> target|>};
    id];

(* 標準ビューアで開けなかったら同じ PDF を自前パネル (Panel) で開く (見えないよりよい。2026-09-24: ノートブックカーネルだけ
   複製が現れない事象への保険)。tick の中なので組み立ては次の tick (itDeferBuild) *)
itNativeFallback[j_Association] :=
  Module[{pages, r},
    If[!StringQ[Lookup[j, "File", None]] || !FileExistsQ[j["File"]], Return[None]];
    pages = Catch[Quiet @ Check[itPagesOfFile[j["File"], 400], {}], icTag];
    If[!ListQ[pages] || pages === {}, Return[None]];
    r = Quiet @ Check[ResoniteRealtime`ResonitePDFViewer[pages, "Title" -> j["Title"]], $Failed];
    itNativeLog[j["Id"], "Fallback", j["Tries"], "自前パネル " <> ToString[Length[pages]] <> " ページ"];
    itSetStatus["標準ビューアで開けなかったので自前パネルで開きます: " <> itTruncate[j["Title"], 40]];
    r];
(* 置き場所: タブレットの隣 (タブレットの親の子) に、タブレットから見て右前。タブレットの子にはしない
   (2026-09-24 実機: 子にすると監視・引き継ぎ・インベントリ保存が 1 枚 155 slot / 400 KB ずつ重くなり、2 枚で 1.2 MB)。
   タブレット根の姿勢 (親から見た position / rotation / scale) は Configure の直前に Depth 0 で読む。
   タブレットが無いときは Root の原点の前 *)
itQRotate[{x_, y_, z_, w_}, v_List] :=
  With[{u = {x, y, z}}, v + 2 w Cross[u, v] + 2 Cross[u, Cross[u, v]]];
itSlotVec[d_Association, key_String, comps_List, default_] :=
  With[{v = itVal[Lookup[d, key, None]]},
    If[AssociationQ[v] && VectorQ[Lookup[v, comps, None], NumericQ], N[Lookup[v, comps]], default]];
itNativePose[k_Integer, tab_ : None] :=
  Module[{off = {0.65 + 0.12 k, 0., -0.35 - 0.06 k}, p, q, sc, parent},
    If[AssociationQ[tab],
      p = itSlotVec[tab, "position", {"x", "y", "z"}, None];
      q = itSlotVec[tab, "rotation", {"x", "y", "z", "w"}, {0., 0., 0., 1.}];
      sc = itSlotVec[tab, "scale", {"x", "y", "z"}, {1., 1., 1.}];
      parent = Lookup[Replace[Lookup[tab, "parent", <||>], Except[_Association] -> <||>], "targetId", None];
      If[ListQ[p] && StringQ[parent],
        Return[<|"Parent" -> parent, "Position" -> p + itQRotate[q, sc*off], "Rotation" -> q|>]]];
    (* 置き場 (Root 原点、回転なし) と同じ座標で Root に出す。置き場に残すと、やり直しで置き場ごと捨てたときに消える *)
    <|"Parent" -> "Root", "Position" -> {0., 1.3, 1.0} + {0.12 k, -0.05 k, -0.06 k}, "Rotation" -> None|>];

itProcessDocJobs[] :=
  Module[{jobs = Replace[Lookup[$itState, "DocJobs", {}], Except[_List] -> {}], j, before},
    If[jobs === {} || !itLinkQ[], Return[Null]];
    before = First[jobs];
    j = itNativeStep[before];
    (* 段階が変わったら記録 (診断用。ResoniteTabletStatus[]["NativeLog"]) *)
    If[!AssociationQ[j] || j["Phase"] =!= before["Phase"] || j["Tries"] =!= before["Tries"],
      itNativeLog[before["Id"], If[AssociationQ[j], j["Phase"], "End"], If[AssociationQ[j], j["Tries"], before["Tries"]]]];
    $itState["DocJobs"] = If[AssociationQ[j], ReplacePart[jobs, 1 -> j], Rest[jobs]]];

itNativeLog[id_, phase_, tries_, note_ : ""] :=
  With[{all = Append[Replace[Lookup[$itState, "NativeLog", {}], Except[_List] -> {}],
      <|"Time" -> DateString[Now, {"Hour", ":", "Minute", ":", "Second"}], "Job" -> id, "Phase" -> phase, "Tries" -> tries, "Note" -> note|>]},
    $itState["NativeLog"] = Take[all, -Min[60, Length[all]]];
    itNativeLogFile[id, phase, tries, note]];

(* 同じ記録をファイルにも追記する (ノートブックのカーネルでだけ失敗するとき、外から読めるように。2026-09-24) *)
If[!ValueQ[ResoniteRealtime`$ResoniteNativeLogFile],
  ResoniteRealtime`$ResoniteNativeLogFile = FileNameJoin[{$TemporaryDirectory, "ResoniteRealtime", "native_pdf.log"}]];
itNativeLogFile[id_, phase_, tries_, note_] :=
  Module[{f = ResoniteRealtime`$ResoniteNativeLogFile, st},
    If[!StringQ[f], Return[Null]];
    Quiet @ Check[
      If[!DirectoryQ[DirectoryName[f]], CreateDirectory[DirectoryName[f], CreateIntermediateDirectories -> True]];
      st = OpenAppend[f, CharacterEncoding -> "UTF-8"];
      WriteString[st, StringRiffle[{DateString[Now, "ISODateTimeMillisecond"], If[TrueQ[$Notebooks], "NB", "headless"],
        ToString[$ProcessID], ToString[id], ToString[phase], ToString[tries], ToString[note]}, "\t"] <> "\n"];
      Close[st], If[Head[st] === OutputStream, Quiet[Close[st]]]];
    Null];

(* タブレット根を Depth 0 で読む (姿勢と親)。タブレットが無ければ None *)
itNativePoseRequest[] :=
  With[{g = itGadget[]},
    If[AssociationQ[g] && StringQ[Lookup[g, "Root", None]], itSendGet[g["Root"], 0, False], None]];

itNativeStep[j_Association] :=
  Module[{d = itNativeDup[], res, tab, sent, kids, new, dupId, pose, sd, k},
    Switch[j["Phase"],
      "Init",
        (* 雛形を知らない (忘れた / 出し直された) なら探す *)
        If[!StringQ[itNativeTemplateId[]], Return[itNativeFindTemplate[j]]];
        (* 雛形がまだワールドにあるかを 1 回読んで確かめる (Depth 0、待たない)。直近 60 s に確かめていれば省く
           (出し直されると ID が変わり、古い ID のガジェットは黙って何も複製しない) *)
        If[!TrueQ[Lookup[j, "TplOK", False]] && iNow[] - Lookup[$itState, "TemplateCheckedAt", 0] > 60,
          sent = itSendGet[itNativeTemplateId[], 0, False];
          If[!StringQ[sent], Return[itNativeFail[j, "getSlot を送れませんでした"]]];
          Return[Join[j, <|"Phase" -> "CheckTpl", "MessageId" -> sent, "Sent" -> iNow[]|>]]];
        If[d === None,
          d = Block[{$iLinkWaitDefault = False}, Quiet @ Check[itNativeDupBuild[], $Failed]];
          If[AssociationQ[d], itNativeLog[j["Id"], "Build", j["Tries"],
            "holder " <> d["Holder"] <> " trigger " <> d["Trigger"] <> " template " <> d["Template"]]]];
        If[!AssociationQ[d], Return[itNativeFail[j, "複製ガジェットを作れませんでした"]]];
        If[iNow[] - Lookup[d, "Created", 0] < $itNativeWarmupSeconds, Return[j]];   (* 暖機 *)
        sent = itSendGet[d["Holder"], 1, False];
        If[!StringQ[sent], Return[itNativeFail[j, "getSlot を送れませんでした"]]];
        Join[j, <|"Phase" -> "Before", "MessageId" -> sent, "Sent" -> iNow[]|>],
      "CheckTpl",
        res = icPollReply[j["MessageId"]];
        Which[
          AssociationQ[res] && Lookup[res, "success", True] =!= False && AssociationQ[Lookup[res, "data", None]],
            $itState["TemplateCheckedAt"] = iNow[];
            Join[j, <|"Phase" -> "Init", "TplOK" -> True|>],
          AssociationQ[res] || iNow[] - j["Sent"] > $itNativeReplySeconds,
            itNativeLog[j["Id"], "Template", j["Tries"], "雛形 " <> ToString[itNativeTemplateId[]] <> " がワールドにありません。探し直します"];
            itNativeDupDiscard[];
            itForgetTemplate[itNativeTemplateId[]];
            (* 次の候補 (保管が消えたならワールドの雛形の記録) が残っていれば、それも確かめ直す。無ければ走査で探す *)
            If[StringQ[itNativeTemplateId[]],
              $itState["TemplateCheckedAt"] = 0;
              Join[j, <|"Phase" -> "Init", "TplOK" -> False|>],
              itNativeFindTemplate[j]],
          True, j],
      "FindTpl",
        Which[
          StringQ[itNativeTemplateId[]],
            $itState["TemplateWanted"] = False;
            $itState["TemplateCheckedAt"] = iNow[];
            itNativeLog[j["Id"], "Template", j["Tries"], "雛形 " <> itNativeTemplateId[] <> " を見つけました"];
            Join[j, <|"Phase" -> "Init", "TplOK" -> True|>],
          iNow[] - j["Since"] > $itNativeFindSeconds,
            $itState["TemplateWanted"] = False;
            $itState["TemplateMissingAt"] = iNow[];
            itNativeFail[j, "ワールドに雛形 (Resonite 標準の PDF ビューア) が見つかりません"],
          True, j],
      "LiteInit" | "LitePose", idLiteStep[j],
      "Before",
        res = icPollReply[j["MessageId"]];
        Which[
          AssociationQ[res],
            kids = Lookup[Select[Lookup[Lookup[res, "data", <||>], "children", {}], AssociationQ], "id", Nothing];
            itSetFlag[d["Trigger"], True];
            Join[j, <|"Phase" -> "Fired", "Known" -> kids, "FiredAt" -> iNow[]|>],
          iNow[] - j["Sent"] > $itNativeReplySeconds, itNativeRetry[j, "getSlot の応答が来ません"],
          True, j],
      "Fired",
        sent = itSendGet[d["Holder"], 1, False];
        If[!StringQ[sent], Return[itNativeFail[j, "getSlot を送れませんでした"]]];
        Join[j, <|"Phase" -> "Await", "MessageId" -> sent, "Sent" -> iNow[]|>],
      "Await",
        res = icPollReply[j["MessageId"]];
        Which[
          AssociationQ[res],
            new = Select[Lookup[Lookup[res, "data", <||>], "children", {}],
              AssociationQ[#] && StringQ[Lookup[#, "id", None]] && !MemberQ[j["Known"], #["id"]] && #["id"] =!= d["Root"] &];
            If[new =!= {},
              dupId = First[new]["id"];
              itSetFlag[d["Trigger"], False];
              Join[j, <|"Phase" -> "Configure", "Root" -> dupId, "MessageId" -> itSendGet[dupId, 0, True],
                "PoseMessageId" -> If[Lookup[j, "Kind", "Doc"] === "Stash", None, idJobPoseRequest[j]], "Sent" -> iNow[]|>],
              itNativeLog[j["Id"], "Poll", j["Tries"], "holder children " <> ToString[Length[Lookup[Lookup[res, "data", <||>], "children", {}]]] <>
                ", " <> ToString[Round[iNow[] - j["FiredAt"], 0.1]] <> " s since trigger"];
              If[iNow[] - j["FiredAt"] > $itNativeSpawnSeconds,
                itSetFlag[d["Trigger"], False];
                itNativeRetry[j, "複製が現れません (雛形が消えた?)"],
                Join[j, <|"Phase" -> "Fired"|>]]],
          iNow[] - j["Sent"] > $itNativeReplySeconds, Join[j, <|"Phase" -> "Fired"|>],
          True, j],
      "Configure",
        res = If[StringQ[j["MessageId"]], icPollReply[j["MessageId"]], None];
        tab = If[StringQ[Lookup[j, "PoseMessageId", None]], icPollReply[j["PoseMessageId"]], None];
        Which[
          (* タブレットの姿勢は 5 秒待って来なければ諦める (Root の原点の前に置く) *)
          AssociationQ[res] && (AssociationQ[tab] || !StringQ[Lookup[j, "PoseMessageId", None]] || iNow[] - j["Sent"] > 5),
            sd = SelectFirst[Lookup[Lookup[res, "data", <||>], "components", {}],
              AssociationQ[#] && StringEndsQ[ToString[Lookup[#, "componentType", ""]], "StaticDocument"] &, None];
            If[!AssociationQ[sd], Return[itNativeFail[j, "複製に StaticDocument がありません (雛形が標準ビューアではない?)"]]];
            If[Lookup[j, "Kind", "Doc"] === "Stash", Return[itNativeStashPlace[j]]];
            k = Length[itNativeDocs[]];
            pose = idJobPose[j, k, tab];
            itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateSlot[j["Root"],
              Join[<|"name" -> itTruncate[j["Title"], 80], "position" -> pose["Position"], "isActive" -> True|>,
                If[StringQ[pose["Parent"]], <|"parent" -> ResoniteRealtime`ResoniteRealtimeRef[pose["Parent"]]|>, <||>],
                If[ListQ[pose["Rotation"]], <|"rotation" -> pose["Rotation"]|>, <||>]]], Null];
            (* 置く時点の URL: 写しが用意できていればそれ (開いてから置くまでに送り終わることがある) *)
            With[{u = Quiet @ Check[ipcURLFor[Lookup[j, "CacheKey", None], j["URL"]], j["URL"]]},
              itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateComponent[sd["id"],
                <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", u]|>], Null];
              (* "Local" は 127.0.0.1 の URL、"Doc" は StaticDocument (写しの用意 / 消失で URL を差し替える) *)
              $itState["NativeDocs"] = Append[itNativeDocs[], j["Root"] ->
                <|"Title" -> j["Title"], "File" -> j["File"], "Pages" -> j["Pages"], "URL" -> u, "Local" -> j["URL"],
                  "Doc" -> sd["id"], "CacheKey" -> Lookup[j, "CacheKey", None], "Created" -> iNow[],
                  "Parent" -> pose["Parent"]|>]];
            itNativeLog[j["Id"], "Placed", j["Tries"], j["Root"] <> " under " <> ToString[pose["Parent"]]];
            itSetStatus["PDF: " <> itTruncate[j["Title"], 40] <> " (" <>
              If[IntegerQ[j["Pages"]] && j["Pages"] > 0, ToString[j["Pages"]] <> " ページ、", ""] <> "標準ビューア)"];
            (* ページを押したら次のページ: 複製を 1 回だけ全部読んで、ページ表示と [次へ] を探して結ぶ (itNativePageClick) *)
            If[TrueQ[ResoniteRealtime`$ResonitePDFPageClick],
              With[{m = itSendGet[j["Root"], -1, True]},
                If[StringQ[m], Join[j, <|"Phase" -> "PageClick", "MessageId" -> m, "Sent" -> iNow[]|>], None]],
              None],
          iNow[] - j["Sent"] > $itNativeReplySeconds,
            If[j["Tries"] < 2,
              Join[j, <|"MessageId" -> itSendGet[j["Root"], 0, True], "PoseMessageId" -> idJobPoseRequest[j],
                "Sent" -> iNow[], "Tries" -> j["Tries"] + 1|>],
              itNativeFail[j, "複製の読み取りに失敗しました"]],
          True, j],
      "PageClick",
        res = icPollReply[j["MessageId"]];
        Which[
          AssociationQ[res],
            Quiet @ Check[itNativePageClick[j, res], itNativeLog[j["Id"], "PageClick", j["Tries"], "失敗 (例外)"]];
            None,
          iNow[] - j["Sent"] > 20, itNativeLog[j["Id"], "PageClick", j["Tries"], "複製の全体が読めませんでした"]; None,
          True, j],
      _, None]];

(* ---- 標準ビューアのページを押したら次のページ (2026-09-25 ユーザー指示) ----
   デスクトップでは視線 (カーソル) を下の [>] まで動かさないとめくれず読みにくい。標準ビューアは雛形の複製で中身を
   知らない (155 slot / ProtoFlux 111) ので、複製の木から探す:
     ページ表示 = DocumentPageTexture を (SpriteProvider / 材質を 1 段経て) 参照する UIX Image / RawImage のスロット
     [次へ]    = UIX Button を持つスロットのうち、(1) ButtonValueShift<int> の Delta > 0 で PageIndex か番号を進める物、
                 (2) 名前か子の文字が Next / > / ▶ / → / › の物
   結び方 (FrooxEngine.dll で確認: ButtonPressEventRelay は Target のスロットの IButtonPressReceiver だけを呼び、
   ProtoFlux の ButtonEvents (Button.LocalPressed を聞く) には届かない):
     - [次へ] を聞く ProtoFlux ButtonEvents があれば、同じ型の ButtonEvents をもう 1 つ置き、Button = ページの Button、
       Pressed = 元と同じ行き先にする (impulse は複数から 1 つへつないでよい)
     - 無ければ ページに ButtonPressEventRelay (Target = [次へ] のスロット) を置く (ButtonValueShift 等の受け手が動く)
   ページのスロットに UIX Button が無ければ足す。結果は NativeLog と $itState["PageClickInfo"] に残し、
   複製の木を %TEMP%\ResoniteRealtime\native_pdf_tree.json に 1 回だけ書く (うまく結べないときの調査用) *)
If[!BooleanQ[ResoniteRealtime`$ResonitePDFPageClick], ResoniteRealtime`$ResonitePDFPageClick = True];

(* ページの上に重ねる押し面 (子スロット、親いっぱい)。戻り値は Button のスロット (受け手 = ValueShift / 中継はここに付ける)。
   Button.OnAttach は**同じスロットの** Image.Tint に色ドライバ (ホバー / 押下の色) を付ける:
     - ページの Image に付けた版: ホバーでページが暗くなった (2026-09-25 実機 1)
     - 透明 (α=0) の Image と同じスロットに付けた版: ホバーで不透明な灰色になりページが隠れた (実機 2。ハイライト色は α を保たない)
   なので Button のスロットには Image を置かず (色ドライバが付かない)、当たり判定の透明な Image は子スロットに置く
   (UIX は子の Graphic に当たった押下を親の Button に渡す。ボタンの文字の上を押しても効くのと同じ) *)
itClickOverlay[parent_String, id_ : Automatic] :=
  Module[{hit = icSlot["Mathematica PageClick", parent], face},
    icComp[hit, $icUIX <> "RectTransform", <|"AnchorMin" -> {0., 0.}, "AnchorMax" -> {1., 1.}|>];
    icComp[hit, $icUIX <> "Button", <|"PassThroughHorizontalMovement" -> True, "PassThroughVerticalMovement" -> True|>,
      Replace[id, Automatic :> ResoniteRealtime`ResoniteRealtimeNewId["PageBtn"]]];
    face = icSlot["HitArea", hit];
    icComp[face, $icUIX <> "RectTransform", <|"AnchorMin" -> {0., 0.}, "AnchorMax" -> {1., 1.}|>];
    icComp[face, $icUIX <> "Image", <|"Tint" -> RGBColor[1, 1, 1, 0]|>];
    hit];

itTreeSlots[s_Association, path_List : {}] :=
  With[{p = Append[path, ToString[itVal[Lookup[s, "name", ""]]]]},
    Prepend[Flatten[Map[itTreeSlots[#, p] &, Select[Lookup[s, "children", {}], AssociationQ]], 1],
      <|"Id" -> Lookup[s, "id", None], "Path" -> p, "Slot" -> s,
        "Comps" -> Select[Lookup[s, "components", {}], AssociationQ]|>]];

itCompType[c_Association] := ToString[Lookup[c, "componentType", ""]];
(* コンポーネントの参照先 (メンバの targetId) *)
itCompRefs[c_Association] :=
  Cases[Values[Replace[Lookup[c, "members", <||>], Except[_Association] -> <||>]],
    m_Association /; StringQ[Lookup[m, "targetId", None]] :> m["targetId"]];
itMemberTarget[c_Association, name_String] :=
  With[{m = Lookup[Replace[Lookup[c, "members", <||>], Except[_Association] -> <||>], name, None]},
    If[AssociationQ[m], Lookup[m, "targetId", None], None]];
itMemberIdOf[c_Association, name_String] :=
  With[{m = Lookup[Replace[Lookup[c, "members", <||>], Except[_Association] -> <||>], name, None]},
    If[AssociationQ[m], Lookup[m, "id", None], None]];

$itNextLabels = {">", "\:25b6", "\:2192", "\:203a", "\:25b8", "next", "next page", "forward", "\:6b21", "\:6b21\:3078"};

itNativePageClickPlan[tree_Association] :=
  Module[{slots, comps, slotOf, dpts, dptIds, lvl1, lvl2, pageSlot, btnSlots, pageFields, next, byShift, byLabel,
      label, flux, grefs, nextBtn, shiftQ, minDelta, anyShift},
    slots = itTreeSlots[tree];
    comps = Flatten[Map[Function[s, Map[<|"Slot" -> s["Id"], "Comp" -> #|> &, s["Comps"]]], slots], 1];
    slotOf = Association[Map[Lookup[#["Comp"], "id", None] -> #["Slot"] &, comps]];
    dpts = Select[comps, StringEndsQ[itCompType[#["Comp"]], "DocumentPageTexture"] &];
    If[dpts === {}, Return[<|"OK" -> False, "Why" -> "DocumentPageTexture がありません"|>]];
    dptIds = Lookup[Lookup[dpts, "Comp"], "id"];
    (* 1 段目: DocumentPageTexture を参照する物 (SpriteProvider / 材質)、2 段目: それを参照する UIX Image / RawImage *)
    lvl1 = Select[comps, IntersectingQ[itCompRefs[#["Comp"]], dptIds] &];
    lvl2 = Select[comps, StringMatchQ[itCompType[#["Comp"]], ___ ~~ ("UIX.Image" | "UIX.RawImage")] &&
      IntersectingQ[itCompRefs[#["Comp"]], Join[dptIds, Lookup[Lookup[lvl1, "Comp"], "id", {}]]] &];
    If[lvl2 === {}, Return[<|"OK" -> False, "Why" -> "ページを映す UIX Image が見つかりません (3D の板かもしれません)",
      "Level1" -> Map[itCompType[#["Comp"]] &, lvl1]|>]];
    pageSlot = First[lvl2]["Slot"];
    (* ページ番号を持つフィールド: DocumentPageTexture.PageIndex のメンバ ID *)
    pageFields = Select[Map[itMemberIdOf[#, "PageIndex"] &, Lookup[dpts, "Comp"]], StringQ];
    btnSlots = Select[slots, AnyTrue[#["Comps"], StringEndsQ[itCompType[#], "UIX.Button"] &] && #["Id"] =!= pageSlot &];
    shiftQ[c_, targets_] := StringContainsQ[itCompType[c], "ButtonValueShift"] && NumericQ[icMemberValue[c, "Delta"]] &&
      icMemberValue[c, "Delta"] > 0 && (targets === All || MemberQ[targets, itMemberTarget[c, "TargetValue"]]);
    minDelta[s_] := Min[Cases[s["Comps"], c_ /; StringContainsQ[itCompType[c], "ButtonValueShift"] :> icMemberValue[c, "Delta"]]];
    (* PageIndex を直接進める物 (最優先)、それ以外の ValueShift (拡大などもありうるので名前より後) *)
    byShift = Select[btnSlots, Function[s, AnyTrue[s["Comps"], shiftQ[#, pageFields] &]]];
    anyShift = Select[btnSlots, Function[s, AnyTrue[s["Comps"], shiftQ[#, All] &]]];
    (* 見出し = スロット名 + その下の UIX Text (兄弟のボタンは同じ名前のことが多いので、名前の道ではなく木で辿る) *)
    label[s_] := ToLowerCase[StringTrim[StringRiffle[Join[{Last[s["Path"]]},
      Cases[Flatten[Lookup[Rest[itTreeSlots[s["Slot"]]], "Comps", {}], 1],
        c_Association /; StringEndsQ[itCompType[c], "UIX.Text"] :> ToString[icMemberValue[c, "Content"]]]], " "]]];
    byLabel = Select[btnSlots, Function[s, With[{l = label[s]},
      AnyTrue[$itNextLabels, StringMatchQ[l, # | (# ~~ " " ~~ ___) | (___ ~~ " " ~~ #)] &] ||
        StringContainsQ[ToLowerCase[Last[s["Path"]]], "next"]]]];
    next = Which[
      (* [>] と [>>] の両方が ValueShift なら Delta の小さい方 = 1 ページ *)
      byShift =!= {}, First[SortBy[byShift, minDelta]],
      byLabel =!= {}, First[byLabel],
      anyShift =!= {}, First[SortBy[anyShift, minDelta]],
      True, None];
    If[!AssociationQ[next], Return[<|"OK" -> False, "Why" -> "[次へ] のボタンが見つかりません", "Page" -> pageSlot,
      "Buttons" -> Map[{StringRiffle[#["Path"], "/"], label[#]} &, btnSlots]|>]];
    nextBtn = Lookup[SelectFirst[next["Comps"], StringEndsQ[itCompType[#], "UIX.Button"] &, <||>], "id", None];
    (* [次へ] を聞く ProtoFlux ButtonEvents: Button (global) -> GlobalReference -> Reference = [次へ] の Button *)
    grefs = Select[comps, StringContainsQ[itCompType[#["Comp"]], "GlobalReference"] &&
      itMemberTarget[#["Comp"], "Reference"] === nextBtn &];
    flux = Select[comps, StringEndsQ[itCompType[#["Comp"]], "Interaction.ButtonEvents"] &&
      (itMemberTarget[#["Comp"], "Button"] === nextBtn || MemberQ[Lookup[Lookup[grefs, "Comp"], "id", {}], itMemberTarget[#["Comp"], "Button"]]) &];
    <|"OK" -> True, "Page" -> pageSlot, "PagePath" -> StringRiffle[Lookup[SelectFirst[slots, #["Id"] === pageSlot &], "Path"], "/"],
      "PageHasButton" -> AnyTrue[Lookup[SelectFirst[slots, #["Id"] === pageSlot &], "Comps"], StringEndsQ[itCompType[#], "UIX.Button"] &],
      "Next" -> next["Id"], "NextPath" -> StringRiffle[next["Path"], "/"], "NextLabel" -> label[next], "NextButton" -> nextBtn,
      "By" -> Which[byShift =!= {}, "PageIndexShift", byLabel =!= {}, "Label", True, "ValueShift"],
      "Flux" -> Map[<|"Type" -> itCompType[#["Comp"]], "Pressed" -> itMemberTarget[#["Comp"], "Pressed"]|> &, flux]|>];

itNativePageClick[j_Association, res_Association] :=
  Module[{tree = Lookup[res, "data", None], plan, btn, s, gref, n = 0, how, dump},
    If[!AssociationQ[tree], Return[itNativeLog[j["Id"], "PageClick", j["Tries"], "複製の全体が空でした"]]];
    dump = FileNameJoin[{$TemporaryDirectory, "ResoniteRealtime", "native_pdf_tree.json"}];
    (* カーネルごとに最初の 1 回だけ書く (上書き)。400 KB を開くたびに書かない *)
    If[!TrueQ[$itPageClickDumped],
      $itPageClickDumped = True;
      Quiet @ CreateDirectory[DirectoryName[dump], CreateIntermediateDirectories -> True];
      Quiet @ Check[With[{st = OpenWrite[dump, BinaryFormat -> True]}, BinaryWrite[st, ExportByteArray[tree, "RawJSON"]]; Close[st]], Null]];
    plan = itNativePageClickPlan[tree];
    $itState["PageClickInfo"] = Append[KeyDrop[plan, {}], "Time" -> DateString[]];
    If[!TrueQ[plan["OK"]], Return[itNativeLog[j["Id"], "PageClick", j["Tries"], "結べません: " <> plan["Why"]]]];
    itNoWait @ Block[{},
      (* ページの上に透明な押し面を重ねる (ページの Image に Button を付けるとホバーで暗くなる。itClickOverlay) *)
      btn = ResoniteRealtime`ResoniteRealtimeNewId["PageBtn"];
      s = Quiet @ Check[itClickOverlay[plan["Page"], btn], None];
      If[!StringQ[s], Return[itNativeLog[j["Id"], "PageClick", j["Tries"], "ページに押し面を足せませんでした"], Module]];
      Which[
        Select[plan["Flux"], StringQ[#["Pressed"]] &] =!= {},
          (* ProtoFlux の [次へ]: 同じ行き先へつなぐ ButtonEvents を押し面用に足す (ノードは 1 つずつ子スロットに) *)
          Do[
            With[{ns = Quiet @ Check[icSlot["flux", s], None]},
              gref = If[StringQ[ns], Quiet @ Check[icComp[ns, $icFE <> "ProtoFlux.GlobalReference<[FrooxEngine]FrooxEngine.IButton>",
                <|"Reference" -> ResoniteRealtime`ResoniteRealtimeRef[btn]|>, ResoniteRealtime`ResoniteRealtimeNewId["GRef"]], None], None];
              If[StringQ[gref] && StringQ[Quiet @ Check[icComp[ns, f["Type"],
                  <|"Button" -> ResoniteRealtime`ResoniteRealtimeRef[gref], "Pressed" -> ResoniteRealtime`ResoniteRealtimeRef[f["Pressed"]]|>,
                  ResoniteRealtime`ResoniteRealtimeNewId["Node"]], None]], n++]],
            {f, Select[plan["Flux"], StringQ[#["Pressed"]] &]}];
          how = "ProtoFlux ButtonEvents " <> ToString[n],
        True,
          If[StringQ[Quiet @ Check[icComp[s, $icFE <> "ButtonPressEventRelay",
              <|"Target" -> ResoniteRealtime`ResoniteRealtimeRef[plan["Next"]]|>, ResoniteRealtime`ResoniteRealtimeNewId["Relay"]], None]],
            n = 1];
          how = "ButtonPressEventRelay"]];
    $itState["PageClickInfo", "Applied"] = <|"How" -> how, "Count" -> n|>;
    itNativeLog[j["Id"], "PageClick", j["Tries"],
      how <> " (" <> ToString[n] <> ") ページ " <> plan["PagePath"] <> " -> 次へ " <> plan["NextPath"] <> " [" <> plan["NextLabel"] <> ", " <> plan["By"] <> "]"]];

(* 保管: 複製をタブレットの子に移し、非表示にして名前を付け、以後の雛形にする *)
itNativeStashPlace[j_Association] :=
  Module[{g = itGadget[], target = Lookup[j, "Target", None], board},
    If[!StringQ[target] && AssociationQ[g], target = Lookup[g, "Root", None]];
    board = StringQ[target] && KeyExistsQ[itThumbs[], target];
    If[!StringQ[target] || (!board && !(AssociationQ[g] && g["Root"] === target)),
      itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[j["Root"]], Null];
      Return[itNativeFail[j, "保管先 (タブレット / サムネイル一覧) がありません"]]];
    itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeUpdateSlot[j["Root"],
      <|"name" -> $itStashName, "isActive" -> False, "parent" -> ResoniteRealtime`ResoniteRealtimeRef[target],
        "position" -> {0., 0., 0.}|>], Null];
    If[board, $itState["Thumbs", target, "Stash"] = j["Root"], $itState["Gadget", "Stash"] = j["Root"]];
    $itState["TemplateCheckedAt"] = iNow[];
    itNativeLog[j["Id"], "Stashed", j["Tries"], j["Root"] <> " (非表示) を " <> target <> " の子に保管"];
    None];

(* やり直し (2 回まで)。複製が出なかったガジェットは壊れている可能性が高い (早すぎたトリガで永久に沈黙する) ので
   作り直す。3 回目は失敗にして雛形も忘れる (次の走査で探し直す) *)
itNativeRetry[j_Association, why_String] :=
  If[j["Tries"] < 2,
    itNativeLog[j["Id"], "Retry", j["Tries"] + 1, why];
    itNativeDupDiscard[];
    $itState["TemplateCheckedAt"] = 0;   (* 作り直す前に雛形を確かめ直す *)
    Join[j, <|"Phase" -> "Init", "Tries" -> j["Tries"] + 1, "TplOK" -> False|>],
    itNativeDupDiscard[];
    itForgetTemplate[itNativeTemplateId[]];
    $itState["TemplateWanted"] = True;   (* 次の PDF のために探し直しておく *)
    itNativeFail[j, why]];

(* 雛形を探す: 走査 (Root Depth 1 + 入れ物 Depth 1) を常駐監視でなくてもすぐ回し、itNoteScanSlots が見つけるのを待つ *)
$itNativeFindSeconds = 20;
itNativeFindTemplate[j_Association] :=
  ($itState["TemplateWanted"] = True;
   $itState["LastScan"] = 0;
   Join[j, <|"Phase" -> "FindTpl", "Since" -> iNow[]|>]);

(* 複製ガジェットを捨てる (置き場ごと。待たない) *)
itNativeDupDiscard[] :=
  With[{d = Lookup[$itState, "PDFDup", None]},
    If[AssociationQ[d] && StringQ[Lookup[d, "Holder", None]],
      itNoWait @ Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[d["Holder"]], Null]];
    $itState["PDFDup"] = None];

itHandlePDF[root_String, res_Association] :=
  Module[{v = itPDF[root], pressed},
    If[!AssociationQ[v], Return[Null]];
    pressed = itPressed[res, v["Ids"]["Buttons"]];
    If[pressed === {}, Return[Null]];
    Scan[itSetFlag[v["Ids"]["Buttons"][#], False] &, pressed];
    With[{p = pressed, rt = root},
      itPressGate["PDF " <> StringRiffle[p, ", "], None, itPDFAct[rt, p]]];
    pressed];

itPDFAct[root_String, pressed_List] :=
  Module[{},
    If[!AssociationQ[itPDF[root]], Return[Null]];
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
  Module[{pages, r},
    If[kind === "PDF" && itNativeTryQ[],
      (* 機密度は web サーバへの写し (ResoniteRealtime_pdfcache.wl) を置いてよいかの判定に使う *)
      r = Block[{$itOpenPL = itPL[pl]}, itNativeSpawn[file, title]];
      If[FailureQ[r], Throw[r, icTag]];
      Return[Join[<|"Kind" -> kind, "Title" -> title, "PrivacyLevel" -> itPL[pl], "File" -> file|>, r]]];
    pages = itPagesOfFile[file, o["MaxPages"]];
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
  "PanelScale" -> 0.0006, "FontSize" -> 30, "Name" -> "SourceVault List", "View" -> Automatic};

itRowsOf[rows_List] := Select[rows, AssociationQ];
itRowsOf[ds_Dataset] := itRowsOf[Normal[ds]];
itRowsOf[_] := {};

itRowLabel[row_Association, i_Integer, maxChars_Integer] :=
  Module[{t = itRowTitle[row], k},
    t = StringReplace[t, {"\n" -> " ", "\r" -> ""}];
    k = itKindLabel[row];
    itTruncate[ToString[i] <> ". " <> t, maxChars] <> If[k === "", "", "   (" <> k <> ")"]];

(* 非同期文脈 (runtime の提案コード実行 / tick) では組み立てを予約して即返す。それ以外はその場で組む *)
(* "View" -> Automatic: 直近のタブレットのプロンプトに「サムネ / 一覧」があればサムネイル一覧 (ResoniteThumbnailGadget)、
   「リスト」なら今の一覧。"Thumbnails" / "List" で明示 (2026-09-24) *)
ResoniteRealtime`ResoniteListGadget[rowsIn_, opts : OptionsPattern[]] :=
  If[itListView[OptionValue["View"]] === "Thumbnails",
    ResoniteRealtime`ResoniteThumbnailGadget[rowsIn, "Title" -> OptionValue["Title"]],
    If[itAsyncContextQ[],
      itDeferBuild[itListGadgetBuild[rowsIn, opts], "一覧ガジェット",
        <|"Kind" -> "ListGadget", "Rows" -> Length[itRowsOf[rowsIn]]|>],
      itListGadgetBuild[rowsIn, opts]]];

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
      itBacking[root, csz*pscale];
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
      (* サムネイル一覧へ切り替える小さなボタン (2026-09-24) *)
      ids["Buttons", "View"] = itButton[row, "View", "サムネ", fs*4., fs*1.7, RGBColor[0.25, 0.4, 0.35, 1], fs*0.75];
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
          If[rec["Hidden"] > 0, ", 機密度で非表示 " <> ToString[rec["Hidden"]], ""] <> ")"|>]), $Failed];
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
   サムネイル一覧 (ResoniteThumbnailGadget、2026-09-24)

   Eagle の項目は <lib>/images/<ID>.info/<name>_thumbnail.png を持つ。一覧の行をサムネイルの升目にして
   **1 枚の大きな面** (Canvas 1 つ) に並べる。升目の画像は WL で 1 枚の JPEG に貼り合わせて背景に敷き
   (テクスチャは 1 枚)、その上に升目ごとの透明なボタンと題名 (UIX Text) を重ねる。
   <Name>                Grabbable, AI_GeneratedContent
   ├─ State              ValueField<int> Selected (0 = なし、i = i 番目、-1 = リストへ、-2 = 閉じる、-3 = 接続、-4 = 形を変更、-5 = キャッシュ削除)
   └─ Panel              Canvas (px), 背景 Image (Sprite <- SpriteProvider <- StaticTexture2D = 貼り合わせ JPEG)
      ├─ Title           Text
      ├─ Connect / Shape / ToList / Close / ClearCache  Image + Button + ButtonValueSet<int> (-3 / -4 / -1 / -2 / -5)
      └─ Cell<i>         Image (ほぼ透明) + Button + ButtonValueSet<int> (i)、Label: Text
   クリックの検出: ボタンごとの bool を全部読むと升目が多いと重い (一覧 8 行で 212 KB)。ButtonValueSet<int> は
   押されると共有の Selected に自分の番号を書くので、監視は State スロット 1 つ (Depth 0) を読むだけでよい。
   ButtonValueSet.TargetValue には Selected.Value のメンバ ID が要るので、tick の組み立ては 1 巡目で結線する
   (結線用の getSlot は State スロットだけ: 戻り値の "WireSlot")。置き場所はタブレットの隣 (左)。
   タブレットの子にすると監視・引き継ぎ・インベントリ保存が升目の数だけ重くなる (標準 PDF ビューアの複製と同じ理由)。
   ============================================================ *)

Options[ResoniteRealtime`ResoniteThumbnailGadget] = {
  "Title" -> "SourceVault", "Columns" -> Automatic, "ThumbSize" -> {200, 260}, "LabelHeight" -> 70,
  "FontSize" -> 18, "ThumbMeters" -> 0.12, "MaxItems" -> Infinity, "MaxRows" -> 7, "Name" -> "SourceVault Thumbnails",
  "Position" -> {0, 1.3, 1.4}, "Parent" -> "Root",
  (* 2026-09-26: 貼る面 ("Plane" | "Cylinder" | "SphereInside" | "Mobius" | ResoniteThumbnailSurface[...]、
     ResoniteRealtime_surface.wl) と曲面の中心 (Automatic = アバターの目 / <|"Parent","Position","Rotation"|>) *)
  "Shape" -> "Plane", "Center" -> Automatic};

itThumbs[] := Replace[Lookup[$itState, "Thumbs", <||>], Except[_Association] -> <||>];
itThumbByState[state_String] :=
  SelectFirst[Keys[itThumbs[]], Lookup[Lookup[itThumbs[][#], "Ids", <||>], "State", None] === state &, None];

(* 「サムネイル / 一覧」の依頼か (直近 30 分のタブレットのプロンプトで決める)。「リスト」は今の一覧のまま *)
itThumbViewQ[] :=
  Module[{t = Lookup[$itState, "Turn", None], p},
    If[!AssociationQ[t], Return[False]];
    p = Lookup[t, "Prompt", ""];
    StringQ[p] && iNow[] - Lookup[t, "Start", 0] < 1800 &&
      (StringContainsQ[p, "サムネ" | "一覧" | "ギャラリー"] || StringContainsQ[p, "thumbnail" | "gallery", IgnoreCase -> True])];
itListView[v_] :=
  Switch[v,
    "Thumbnails" | "Thumbnail" | "Thumbs", "Thumbnails",
    "List", "List",
    _, If[TrueQ[itThumbViewQ[]], "Thumbnails", "List"]];

$itImageExts = {"png", "jpg", "jpeg", "gif", "bmp", "webp", "tif", "tiff"};
itRowFilePath[row_Association] :=
  With[{f = itRowGet[row, {"File", "FilePath", "Path", "path", "ファイル"}, None]},
    If[StringQ[f] && f =!= "" && FileExistsQ[f], f, None]];
itRowEagleId[row_Association] :=
  Module[{uri = ToString[Lookup[row, "URI", ""]], id},
    id = StringCases[uri, StartOfString ~~ "sv://object/eagle-" ~~ x__ :> x];
    Which[
      id =!= {}, First[id],
      ToLowerCase[itRowKind[row]] === "eagle" && StringQ[Lookup[row, "Id", None]], row["Id"],
      True, None]];

(* 行のサムネイル: 明示の "Thumbnail" > 同じフォルダの Eagle の *_thumbnail.png > 画像ファイルそのもの >
   Eagle ID から SourceVault に尋ねる > PDF の 1 ページ目 ({"PDF", file}) > None (空カード) *)
itRowThumbSource[row_Association] :=
  Module[{t, file, th, id, f},
    t = itRowGet[row, {"Thumbnail", "ThumbnailPath", "サムネイル"}, None];
    If[StringQ[t] && FileExistsQ[t], Return[t]];
    file = itRowFilePath[row];
    If[StringQ[file],
      (* Eagle の名前は <原本の名前>_thumbnail.png。まず決め打ちで見る (FileExistsQ 0.2 ms、FileNames は 20 ms) *)
      th = FileNameJoin[{DirectoryName[file], FileBaseName[file] <> "_thumbnail.png"}];
      If[FileExistsQ[th], Return[th]];
      If[MemberQ[$itImageExts, itExt[file]], Return[file]];
      th = Quiet @ Check[FileNames["*_thumbnail.png", DirectoryName[file]], {}];
      If[ListQ[th] && th =!= {}, Return[First[th]]]];
    id = itRowEagleId[row];
    f = icSym["SourceVault`SourceVaultEagleThumbnailPath"];
    If[StringQ[id] && f =!= None,
      th = Quiet @ Check[f[id], $Failed];
      If[StringQ[th] && FileExistsQ[th], Return[th]]];
    If[StringQ[file] && itExt[file] === "pdf", Return[{"PDF", file}]];
    None];

(* 形式を指定すると速い (実測 260 枚: Import 134 ms/枚 -> "PNG" 指定 67 ms/枚)。ただし形式は拡張子でなく先頭のバイトで決める:
   Eagle の <name>_thumbnail.png は中身が WebP (2026-09-25 実測: SF フォルダ 289 件すべて RIFF....WEBP)。拡張子で "PNG" と
   決め打った版は 289 件中 287 件が読めず、一覧が空カードだらけになった。形式指定で読めなければ Import に任せる *)
itImageFormat[src_String] :=
  Module[{b = Quiet @ Check[With[{st = OpenRead[src, BinaryFormat -> True]},
      WithCleanup[BinaryReadList[st, "Byte", 12], Close[st]]], {}]},
    Which[
      !ListQ[b] || Length[b] < 4, Automatic,
      b[[1 ;; 4]] === {137, 80, 78, 71}, "PNG",
      b[[1 ;; 3]] === {255, 216, 255}, "JPEG",
      b[[1 ;; 4]] === {82, 73, 70, 70} && Length[b] >= 12 && b[[9 ;; 12]] === {87, 69, 66, 80}, "WebP",
      b[[1 ;; 3]] === {71, 73, 70}, "GIF",
      b[[1 ;; 2]] === {66, 77}, "BMP",
      True, Automatic]];
itFirstImage[x_] := Which[ImageQ[x], x, ListQ[x] && x =!= {} && ImageQ[First[x]], First[x], True, $Failed];
itThumbImage[src_String] :=
  With[{fmt = itImageFormat[src]},
    Replace[itFirstImage[Quiet @ Check[If[fmt === Automatic, Import[src], Import[src, fmt]], $Failed]],
      $Failed :> If[fmt === Automatic, $Failed, itFirstImage[Quiet @ Check[Import[src], $Failed]]]]];
(* PDF の 1 ページ目 (40 dpi)。配信ディレクトリにキャッシュする *)
itThumbImage[{"PDF", file_String}] := idPdfFirstPage[file, ResoniteRealtime`ResoniteRealtimeAsset[]];
itThumbImage[_] := $Failed;

$itThumbColors = <|"Page" -> RGBColor[0.07, 0.08, 0.1], "Card" -> RGBColor[0.16, 0.18, 0.22],
  "Label" -> RGBColor[0.11, 0.12, 0.15], "Header" -> RGBColor[0.12, 0.16, 0.24]|>;
itExtColor[ext_String] :=
  Switch[ToLowerCase[ext],
    "pdf", RGBColor[0.55, 0.2, 0.2],
    "mp4" | "mov" | "webm" | "mkv", RGBColor[0.2, 0.35, 0.55],
    _, RGBColor[0.3, 0.33, 0.38]];
itByteRGB[img_Image] := Image[ColorConvert[RemoveAlphaChannel[img, White], "RGB"], "Byte"];
itFlat[color_, {w_Integer, h_Integer}] := Image[ConstantImage[color, {w, h}], "Byte"];

(* 縦横比を保って箱 {w, h} に収め、余白を bg で埋める (小さい画像は拡大する) *)
itFitBox[img_Image, {w_Integer, h_Integer}, bg_] :=
  Module[{iw, ih, s, r, pw, ph},
    {iw, ih} = ImageDimensions[img];
    s = Min[w/iw, h/ih];
    r = ImageResize[img, MapThread[Max[1, Min[#1, #2]] &, {Round[{iw, ih}*s], {w, h}}]];
    {pw, ph} = ImageDimensions[r];
    ImagePad[r, {{Floor[(w - pw)/2], Ceiling[(w - pw)/2]}, {Floor[(h - ph)/2], Ceiling[(h - ph)/2]}}, bg]];

itThumbLayout[n_Integer, o_Association] :=
  Module[{tw, th, lh, g = 16, m = 24, hh = 150, cw, ch, cols, rows},   (* hh: 見出し = 題名 + 状態欄 (2026-09-25 150 px) *)
    {tw, th} = Round[o["ThumbSize"]]; lh = Round[o["LabelHeight"]];
    cw = tw + g; ch = th + lh + g;
    (* 列数: 縦は MaxRows (7) 段まで積み、それ以上は横にいくらでも広げる (2026-09-25 ユーザー指示「縦 7、横は無制限、
       全部出す」)。段数の目安は升目の縦横比で正方形に近づける値 (25 件 = 7 列 x 4 段、49 件 = 9 x 6、289 件 = 42 x 7) *)
    cols = If[IntegerQ[o["Columns"]] && o["Columns"] > 0, o["Columns"],
      Max[1, Ceiling[Max[n, 1]/Clip[Ceiling[Sqrt[Max[n, 1]*cw/ch]], {1, Max[1, Lookup[o, "MaxRows", 7]]}]]]];
    cols = Max[1, Min[cols, Max[n, 1]]];
    rows = Max[1, Ceiling[n/cols]];
    (* SW = 升目の貼り合わせ (帯の画像) の幅。Canvas の幅 W は見出し (接続 / 形を変更 / リスト / 閉じる + 状態) が入るよう最低 $itThumbMinWidth *)
    <|"N" -> n, "TW" -> tw, "TH" -> th, "LH" -> lh, "G" -> g, "M" -> m, "HH" -> hh, "CW" -> cw, "CH" -> ch,
      "Cols" -> cols, "Rows" -> rows, "SW" -> 2 m + cols cw - g, "W" -> Max[2 m + cols cw - g, $itThumbMinWidth],
      "H" -> hh + 2 m + rows ch - g|>];
(* 2026-09-26: 見出しのボタンが 5 つ (形を変更・キャッシュ削除 を追加) になったので 2 つ分 (320 px) 広げ、状態欄の幅を前と同じに保つ *)
$itThumbMinWidth = 1720;

(* i 番目 (1 始まり) の升目 (サムネイル + 題名) の矩形 {x0, y0, w, h} (px、左上原点) *)
itThumbCell[L_Association, i_Integer] :=
  With[{c = Mod[i - 1, L["Cols"]], r = Quotient[i - 1, L["Cols"]]},
    {L["M"] + c L["CW"], L["HH"] + L["M"] + r L["CH"], L["TW"], L["TH"] + L["LH"]}];

(* 矩形 (px、左上原点) -> RectTransform の anchor (UIX は左下原点、0..1) *)
itAnchors[{x0_, y0_, w_, h_}, {W_, H_}] :=
  <|"AnchorMin" -> N[{x0/W, 1 - (y0 + h)/H}], "AnchorMax" -> N[{(x0 + w)/W, 1 - y0/H}]|>;

itThumbTile[img_, ext_String, L_Association] :=
  Module[{box},
    box = If[ImageQ[img],
      Image[itFitBox[itByteRGB[img], {L["TW"], L["TH"]}, $itThumbColors["Card"]], "Byte"],
      Image[ImageCompose[itFlat[$itThumbColors["Card"], {L["TW"], L["TH"]}],
        itFlat[itExtColor[ext], Round[{L["TW"]*0.45, L["TH"]*0.55}]]], "Byte"]];
    Image[ImagePad[ImageAssemble[{{box}, {itFlat[$itThumbColors["Label"], {L["TW"], L["LH"]}]}}],
      {{0, L["G"]}, {L["G"], 0}}, $itThumbColors["Page"]], "Byte"]];

(* 全升目を 1 枚に貼り合わせる (見出しの帯 + 余白込みで Canvas と同じ px) *)
(* 横に長い面は縦帯に分ける: テクスチャ 1 枚の幅には上限がある (16384 px) ので、$itThumbStripCols 列 (36 列 = 7,776 px) ごとに
   1 枚。戻り値 {{画像, 左端の x (px)}, ...}。帯をつなぐと Canvas と同じ px になる *)
$itThumbStripCols = 36;
itThumbStrips[imgs_List, exts_List, L_Association] :=
  Module[{tiles, blank, rowsOfTiles, groups, cs, ce, grid, body},
    tiles = MapThread[itThumbTile[#1, #2, L] &, {imgs, exts}];
    blank = itFlat[$itThumbColors["Page"], {L["CW"], L["CH"]}];
    tiles = PadRight[tiles, L["Cols"]*L["Rows"], blank];
    rowsOfTiles = Partition[tiles, L["Cols"]];
    groups = Partition[Range[L["Cols"]], UpTo[$itThumbStripCols]];
    Map[Function[grp,
        cs = First[grp]; ce = Last[grp];
        grid = ImageAssemble[rowsOfTiles[[All, cs ;; ce]]];
        body = Image[ImagePad[grid,
          {{If[cs === 1, L["M"], 0], If[ce === L["Cols"], L["M"] - L["G"], 0]}, {L["M"] - L["G"], L["M"]}},
          $itThumbColors["Page"]], "Byte"];
        {ImageAssemble[{{itFlat[$itThumbColors["Header"], {ImageDimensions[body][[1]], L["HH"]}]}, {body}}],
         If[cs === 1, 0, L["M"] + (cs - 1) L["CW"]]}],
      groups]];
(* 1 枚にまとめた版 (帯が 1 本のときと同じ) *)
itThumbSheet[imgs_List, exts_List, L_Association] :=
  With[{st = itThumbStrips[imgs, exts, L]},
    If[Length[st] === 1, st[[1, 1]], ImageAssemble[{st[[All, 1]]}]]];

(* 題名を幅 (px) で折り返す (全角 1.0、半角 0.56 文字幅の見積もり)。maxLines を超えたら末尾を … にする *)
itWrapLabel[s_String, widthPx_, fs_, maxLines_Integer] :=
  Module[{cwid, lines = {}, cur = "", w = 0.},
    cwid = If[First[ToCharacterCode[#]] > 11903, 1.0, 0.56]*fs &;
    Do[
      With[{d = cwid[c]},
        If[w + d > widthPx && cur =!= "", AppendTo[lines, cur]; cur = ""; w = 0.];
        cur = cur <> c; w += d],
      {c, Characters[StringReplace[s, {FromCharacterCode[10] -> " ", FromCharacterCode[13] -> ""}]]}];
    If[cur =!= "", AppendTo[lines, cur]];
    If[Length[lines] > maxLines,
      lines = Append[Take[lines, maxLines - 1],
        StringDrop[lines[[maxLines]], -Min[1, StringLength[lines[[maxLines]]]]] <> "…"]];
    StringRiffle[lines, FromCharacterCode[10]]];

itThumbTitle[row_Association] :=
  With[{t = StringTrim[itRowTitle[row]]},
    If[MemberQ[{"pdf", "png", "jpg", "jpeg", "webp", "mp4"}, ToLowerCase[FileExtension[t]]],
      StringDrop[t, -(StringLength[FileExtension[t]] + 1)], t]];

(* タブレットの左隣 (タブレットの親の子)。姿勢は監視の TabletPose (5 s ごとの Depth 0) から。まだ無ければタブレットの子 *)
itThumbPose[wM_, hM_, o_Association] :=
  Module[{g = itGadget[], tp = Lookup[$itState, "TabletPose", None], d, p, q, sc, parent, tw, th, off},
    If[!AssociationQ[g], Return[<|"Parent" -> o["Parent"], "Position" -> N[o["Position"]], "Rotation" -> None|>]];
    tw = Lookup[g, "CanvasSize", {1000, 1500}][[1]]*Lookup[g, "PanelScale", 0.0006];
    th = Lookup[g, "CanvasSize", {1000, 1500}][[2]]*Lookup[g, "PanelScale", 0.0006];
    off = N[{-(tw/2 + 0.12 + wM/2), hM/2 - th/2, 0.}];
    d = If[AssociationQ[tp], Lookup[tp, "Data", None], None];
    If[AssociationQ[d] && Lookup[d, "id", None] === g["Root"],
      p = itSlotVec[d, "position", {"x", "y", "z"}, None];
      q = itSlotVec[d, "rotation", {"x", "y", "z", "w"}, {0., 0., 0., 1.}];
      sc = itSlotVec[d, "scale", {"x", "y", "z"}, {1., 1., 1.}];
      parent = Lookup[Replace[Lookup[d, "parent", <||>], Except[_Association] -> <||>], "targetId", None];
      If[ListQ[p] && StringQ[parent],
        Return[<|"Parent" -> parent, "Position" -> p + itQRotate[q, sc*off], "Rotation" -> q|>]]];
    <|"Parent" -> g["Root"], "Position" -> off, "Rotation" -> None|>];

itThumbButton[panel_String, key_String, label_String, rect_List, L_Association, color_RGBColor, fs_] :=
  Module[{s, lbl},
    s = icSlot[key, panel];
    icComp[s, $icUIX <> "RectTransform", itAnchors[rect, {L["W"], L["H"]}]];
    icImage[s, color];
    icComp[s, $icUIX <> "Button", <||>];
    lbl = icSlot["Label", s];
    icComp[lbl, $icUIX <> "RectTransform", <|"AnchorMin" -> {0., 0.}, "AnchorMax" -> {1., 1.}|>];
    itText[lbl, label, fs, "Center", "Middle"];
    s];

(* 見出しの右端のボタン 5 つ (右から キャッシュ削除 -5 / 閉じる -2 / リスト -1 / 形を変更 -4 / 接続 -3)。L は見出しの Canvas の寸法 (W, HH, M)。
   戻り値 {接続ボタン, wires (結線する {スロット, 番号} を足したもの)}。平面と曲面の見出しで共有 *)
$itHeaderButtons = 5;
itThumbHeaderButtons[panel_String, L_Association, fs_, wires0_List] :=
  Module[{wires = wires0, connectBtn, y = 18, h = L["HH"] - 36, x},
    x[k_] := L["W"] - L["M"] - 160 k + 10;   (* 右から k 番目 (1 始まり) の左端 *)
    connectBtn = itThumbButton[panel, "Connect", "接続", {x[5], y, 150, h}, L, RGBColor[0.3, 0.35, 0.55, 1], fs*1.6];
    AppendTo[wires, {connectBtn, -3}];
    (* 2026-09-26: 形の切り替え (平面 -> 円筒 -> 球の内側 -> メビウスの帯 -> 平面、$ResoniteThumbnailShapes) *)
    AppendTo[wires, {itThumbButton[panel, "Shape", "形を変更", {x[4], y, 150, h}, L,
      RGBColor[0.42, 0.33, 0.55, 1], fs*1.45], -4}];
    AppendTo[wires, {itThumbButton[panel, "ToList", "リスト", {x[3], y, 150, h}, L,
      RGBColor[0.25, 0.4, 0.35, 1], fs*1.6], -1}];
    AppendTo[wires, {itThumbButton[panel, "Close", "閉じる", {x[2], y, 150, h}, L,
      RGBColor[0.5, 0.25, 0.25, 1], fs*1.6], -2}];
    (* 2026-09-26: 他のユーザーと共有するサーバの PDF の写しを全部消す (ResoniteRealtime_pdfcache.wl の ipcClearAllStart) *)
    AppendTo[wires, {itThumbButton[panel, "ClearCache", "キャッシュ
削除", {x[1], y, 150, h}, L,
      RGBColor[0.55, 0.38, 0.18, 1], fs*1.3], -5}];
    {connectBtn, wires}];

(* ButtonValueSet<int> -> Selected.Value (1 巡目、State を読む)。「接続」は押した瞬間に覆いの文字も書き換える
   (ButtonValueSet<string> -> 覆いの Text.Content。2 巡目、覆いの文字のスロットを読む)。Wolfram が気付くまでの間も反応が見える。
   tick の組み立てなら巡に回し ($itWireRounds)、トップレベルならメンバ ID を待って今足す *)
itThumbWire[state_String, sel_String, wires_List, connectBtn_String, vt_String, vid_String] :=
  Module[{fid},
    If[ListQ[$itWireLater],
      $itWireRounds = {
        Map[<|"Action" -> "Add", "Slot" -> #[[1]], "Type" -> $icFE <> "ButtonValueSet<int>",
          "Members" -> <|"SetValue" -> #[[2]]|>, "Refs" -> <|"TargetValue" -> {sel, "Value"}|>|> &, wires],
        {<|"Action" -> "Add", "Slot" -> connectBtn, "Type" -> $icFE <> "ButtonValueSet<string>",
          "Members" -> <|"SetValue" -> $idVeilPressedText|>, "Refs" -> <|"TargetValue" -> {vid, "Content"}|>|>}};
      Return[None]];
    fid = icMemberId[state, sel, "Value"];
    If[!StringQ[fid], Throw[iFailure["NoMemberId", "ValueField<int>.Value のメンバ ID が取れませんでした。"], icTag]];
    Scan[icComp[#[[1]], $icFE <> "ButtonValueSet<int>",
      <|"SetValue" -> #[[2]], "TargetValue" -> ResoniteRealtime`ResoniteRealtimeRef[fid]|>] &, wires];
    With[{cid = icMemberId[vt, vid, "Content"]},
      If[StringQ[cid], icComp[connectBtn, $icFE <> "ButtonValueSet<string>",
        <|"SetValue" -> $idVeilPressedText, "TargetValue" -> ResoniteRealtime`ResoniteRealtimeRef[cid]|>]]];
    fid];

(* 2026-09-25: 画像が帯のキャッシュに無ければ、読み込みと貼り合わせ (289 件で ~40 s) は作業用カーネルに任せ、出来てから組む
   (ResoniteRealtime_docboard.wl の idMaybeSheetJob)。監視の tick の中で 40 s 塞ぐと FE の Dynamic が待たされ
   「動的評価の放棄」ダイアログが出て、VR の中からは閉じられなかった *)
(* 曲面 ("Shape" が平面以外) で中心が決まっていなければ、先にアバターの位置を読む (tick の中なら待たずに、ResoniteRealtime_surface.wl) *)
ResoniteRealtime`ResoniteThumbnailGadget[rowsIn_, opts : OptionsPattern[]] /;
    itSurfaceShapeQ[OptionValue["Shape"]] && !AssociationQ[OptionValue["Center"]] :=
  If[itAsyncContextQ[],
    itSurfaceJobStart[itRowsOf[rowsIn], {opts}, None, None],
    ResoniteRealtime`ResoniteThumbnailGadget[rowsIn, Sequence @@ itWithCenter[{opts}, itSurfaceCenterSync[None]]]];
ResoniteRealtime`ResoniteThumbnailGadget[rowsIn_, opts : OptionsPattern[]] :=
  If[itAsyncContextQ[],
    With[{w = Quiet @ Check[idMaybeSheetJob[rowsIn, {opts}], None]},
      If[AssociationQ[w], w,
        itDeferBuild[itThumbGadgetBuild[rowsIn, opts], "サムネイル一覧",
          <|"Kind" -> "ThumbnailGadget", "Rows" -> Length[itRowsOf[rowsIn]]|>]]],
    itThumbGadgetBuild[rowsIn, opts]];

(* 組み立ての前半 (速い): 見せる行・配置・サムネイルの取得元・帯のキャッシュの鍵とファイル名 *)
(* 升目 (縮小画像・題名) は開示してよい (2026-09-26 方針)。秘匿は中身だけで、開くとき (itThumbOpen -> itGate) に判定する *)
If[!BooleanQ[ResoniteRealtime`$ResoniteThumbnailsDisclosable], ResoniteRealtime`$ResoniteThumbnailsDisclosable = True];
itThumbsDisclosableQ[] := TrueQ[ResoniteRealtime`$ResoniteThumbnailsDisclosable];

itThumbPlan[rowsIn_, o_Association] :=
  Module[{rows, hidden, shown, over, L, srcs, exts, key, nStrips, files},
    rows = itRowsOf[rowsIn];
    hidden = If[itThumbsDisclosableQ[], 0, Count[rows, r_ /; !itAllowedQ[itRowPL[r]]]];
    If[!itThumbsDisclosableQ[], rows = Select[rows, itAllowedQ[itRowPL[#]] &]];
    shown = If[IntegerQ[o["MaxItems"]] && o["MaxItems"] > 0, Take[rows, UpTo[o["MaxItems"]]], rows];
    over = Length[rows] - Length[shown];
    (* 曲面が段数を決める形 (メビウスの帯) なら、その列数で並べる (ResoniteRealtime_surface.wl の itSurfaceLayoutOpts) *)
    L = itThumbLayout[Length[shown], Quiet @ Check[itSurfaceLayoutOpts[o, Length[shown]], o]];
    srcs = itRowThumbSource /@ shown;
    exts = Map[With[{f = itRowFilePath[#]},
        If[StringQ[f], itExt[f], ToLowerCase[ToString[Lookup[#, "Ext", ""]]]]] &, shown];
    (* 帯ごとの JPEG のキャッシュ: 鍵は元画像のパス・大きさ・更新日時と配置 (画像を読まずに決まる)。揃っていれば
       読み込みごと省く (2026-09-25: 260 件の読み込みが 17 s。開き直しのたびに読んでいた) *)
    key = StringTake[Hash[{Map[If[StringQ[#] && FileExistsQ[#], {#, FileByteCount[#], Quiet[FileDate[#]]},
          If[MatchQ[#, {"PDF", _String}] && FileExistsQ[#[[2]]], {#, FileByteCount[#[[2]]], Quiet[FileDate[#[[2]]]]}, #]] &, srcs],
        exts, L, $itThumbStripCols, "v2"}, "SHA256", "HexString"], 16];   (* v2: WebP の読み違いで空カードの版を使わない *)
    nStrips = Ceiling[L["Cols"]/$itThumbStripCols];
    files = Table[FileNameJoin[{ResoniteRealtime`ResoniteRealtimeAsset[],
      "thumbs_" <> key <> If[nStrips === 1, "", "_" <> ToString[k]] <> ".jpg"}], {k, nStrips}];
    <|"Rows" -> rows, "Hidden" -> hidden, "Shown" -> shown, "Over" -> over, "Layout" -> L, "Srcs" -> srcs, "Exts" -> exts,
      "Key" -> key, "NStrips" -> nStrips, "Files" -> files,
      (* 打ち切った版・読めなかった画像がある版の名前 (次に開いたときキャッシュとして使わない) *)
      "FilesP" -> StringReplace[files, "thumbs_" <> key -> "thumbs_" <> key <> "p"],
      "StripX" -> Table[If[k === 1, 0, L["M"] + (k - 1)*$itThumbStripCols*L["CW"]], {k, nStrips}]|>];
If[!ValueQ[$idSheetOverride], $idSheetOverride = None];

itThumbGadgetBuild[rowsIn_, opts : OptionsPattern[ResoniteRealtime`ResoniteThumbnailGadget]] :=
  Catch[
    Module[{o, rows, hidden, shown, over, L, srcs, imgs, exts, t0, cut = False, key, files, urls, url, nStrips, stripX, texs,
            wM, hM, ps, pose, root, state, sel, panel, tex, s, wires = {}, fid, fs, title, rec, cell, lbl,
            content, veil, statusText, titleText, bw, connectBtn, vt, vid},
      If[!itLinkQ[], Return[iFailure["NotConnected", "サムネイル一覧の組み立てには ResoniteLink が要ります。"]]];
      If[!itEnsureImageServer[], Return[iFailure["NoServer", "画像配信 (ResoniteRealtimeStart[]) が要ります。"]]];
      o = Association @ Join[Options[ResoniteRealtime`ResoniteThumbnailGadget], {opts}];
      {rows, hidden, shown, over, L, srcs, exts, key, nStrips, files, stripX} =
        Lookup[itThumbPlan[rowsIn, o], {"Rows", "Hidden", "Shown", "Over", "Layout", "Srcs", "Exts", "Key", "NStrips", "Files", "StripX"}];
      fs = N[o["FontSize"]];
      (* 作業用カーネルが作った帯 (打ち切った版なら "p" の名前) *)
      If[AssociationQ[$idSheetOverride] && $idSheetOverride["Key"] === key && ListQ[$idSheetOverride["Files"]] &&
         AllTrue[$idSheetOverride["Files"], FileExistsQ],
        files = $idSheetOverride["Files"]];
      If[!AllTrue[files, FileExistsQ],
        (* Eagle / 画像のサムネイルはすぐ読める。PDF の 1 ページ目は時間がかかるので合計 20 s まで (以降は空カード) *)
        t0 = iNow[];
        imgs = Map[Which[
            # === None, $Failed,
            MatchQ[#, {"PDF", _String}] && iNow[] - t0 > 20, cut = True; $Failed,
            True, itThumbImage[#]] &, srcs];
        (* 打ち切った版・読めなかった画像がある版は別の名前で書く (次に開いたときキャッシュとして使わず、読み直す) *)
        If[MemberQ[MapThread[#1 =!= None && !ImageQ[#2] &, {srcs, imgs}], True], cut = True];
        If[cut, files = StringReplace[files, "thumbs_" <> key -> "thumbs_" <> key <> "p"]];
        MapThread[Quiet @ Check[Export[#1, #2[[1]], "JPEG", "CompressionLevel" -> 0.15], Null] &,
          {files, itThumbStrips[imgs, exts, L]}]];
      If[!AllTrue[files, FileExistsQ], Return[iFailure["Sheet", "サムネイルの画像を作れませんでした。"]]];
      (* 曲面 (円筒 / 球の内側 / メビウスの帯 / 任意の面): 升目ごとのタイルを面に置く (ResoniteRealtime_surface.wl) *)
      If[itSurfaceShapeQ[o["Shape"]],
        Return[itThumbSurfaceBuild[o, itThumbPlan[rowsIn, o], files, fs]]];
      If[itSurfaceName[o["Shape"]] =!= "Plane",
        Return[iFailure["UnknownShape", "形 " <> itSurfaceName[o["Shape"]] <> " は登録されていません。"]]];
      urls = ResoniteRealtime`ResoniteRealtimeAsset /@ files;
      url = First[urls];
      (* 高すぎる面だけ縮める (2.4 m)。横はいくら長くてもよい *)
      ps = N[Min[o["ThumbMeters"]/L["TW"], 2.4/L["H"]]];
      wM = L["W"]*ps; hM = L["H"]*ps;
      (* 曲面から平面に戻すときは、その中心 (アバター) の正面。ふだんはタブレットの左隣 *)
      pose = If[AssociationQ[o["Center"]], itFlatPoseFromCenter[o["Center"]], itThumbPose[wM, hM, o]];
      root = icSlot[o["Name"], pose["Parent"], "Position" -> pose["Position"],
        Sequence @@ If[ListQ[pose["Rotation"]], {"Rotation" -> pose["Rotation"]}, {}],
        "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["Thumbs"]];
      $itBuildRoot = root;
      icComp[root, $icFE <> "Grabbable", <|"Scalable" -> True|>];
      icComp[root, $icFE <> "AI_GeneratedContent",
        <|"Source" -> "Mathematica ResoniteRealtime thumbnail gadget (SourceVault rows)"|>];
      state = icSlot["State", root];
      sel = icComp[state, $icFE <> "ValueField<int>", <|"Value" -> 0|>, ResoniteRealtime`ResoniteRealtimeNewId["ThumbSel"]];
      panel = icSlot["Panel", root, "Scale" -> {ps, ps, ps}];
      itBacking[root, {wM, hM}];
      icComp[panel, $icUIX <> "Canvas",
        <|"Size" -> N[{L["W"], L["H"]}], "AcceptRemoteTouch" -> True, "AcceptPhysicalTouch" -> True|>];
      icMakeMaterials[panel];
      icImage[panel, $itThumbColors["Page"]];
      (* 升目 (帯の画像 + 升目のボタンと題名) は Content の下にまとめる。保存して出し直したときは Flux が Content を隠し、
         「接続」で Wolfram が確かめてから見せる (ResoniteRealtime_docboard.wl) *)
      content = icSlot["Content", panel, "Id" -> ResoniteRealtime`ResoniteRealtimeNewId["Content"]];
      icComp[content, $icUIX <> "RectTransform", <|"AnchorMin" -> {0., 0.}, "AnchorMax" -> {1., 1.}|>];
      (* 帯ごとに Image (Sprite <- SpriteProvider <- StaticTexture2D)。見出しや升目より先に作る (UIX は子の順に描く) *)
      texs = MapThread[Function[{u, x0, k},
          With[{sh = icSlot["Sheet" <> ToString[k], content],
                w = If[k === nStrips, L["SW"] - x0, stripX[[k + 1]] - x0]},
            icComp[sh, $icUIX <> "RectTransform", itAnchors[{x0, 0, w, L["H"]}, {L["W"], L["H"]}]];
            With[{t = icComp[sh, $icFE <> "StaticTexture2D", <|"URL" -> ResoniteRealtime`ResoniteRealtimeValue["Uri", u]|>,
                  ResoniteRealtime`ResoniteRealtimeNewId["ThumbTex"]]},
              With[{sp = icComp[sh, $icFE <> "SpriteProvider", <|"Texture" -> ResoniteRealtime`ResoniteRealtimeRef[t]|>]},
                icComp[sh, $icUIX <> "Image",
                  Join[<|"Sprite" -> ResoniteRealtime`ResoniteRealtimeRef[sp], "PreserveAspect" -> False,
                      "Tint" -> RGBColor[1, 1, 1, 1]|>,
                    If[StringQ[Lookup[$icMats, "Image", None]],
                      <|"Material" -> ResoniteRealtime`ResoniteRealtimeRef[$icMats["Image"]]|>, <||>]]]];
              t]]],
        {urls, stripX, Range[nStrips]}];
      tex = First[texs];
      (* 見出しとボタン *)
      title = ToString[o["Title"]] <> "  (" <> ToString[Length[shown]] <> " 件" <>
        If[hidden > 0, ", 機密度で非表示 " <> ToString[hidden], ""] <>
        If[over > 0, ", ほか " <> ToString[over] <> " 件はリストで", ""] <> ")";
      bw = L["W"] - 2 L["M"] - $itHeaderButtons*160;   (* 題名と状態欄の幅 (右にボタン 5 つ) *)
      s = icSlot["Title", panel];
      icComp[s, $icUIX <> "RectTransform", itAnchors[{L["M"], 8, Max[100, bw], 60}, {L["W"], L["H"]}]];
      titleText = itText[s, itTruncate[title, 90], fs*1.8, "Left", "Middle", ResoniteRealtime`ResoniteRealtimeNewId["ThumbTitle"]];
      (* 状態欄 (2026-09-25 ユーザー指示「接続を押したのに何も変化がないとわかりにくい。開いている PDF 名を出すステータスバーを」):
         背景の帯 (StatusBar) の上に文字 (Status)。UIX は 1 スロットに Graphic 1 つなので分ける。経過秒は tick が書く *)
      s = icSlot["StatusBar", panel];
      icComp[s, $icUIX <> "RectTransform", itAnchors[{L["M"], 76, Max[100, bw], L["HH"] - 88}, {L["W"], L["H"]}]];
      icImage[s, RGBColor[0.05, 0.07, 0.11, 1]];
      s = icSlot["Status", panel];
      icComp[s, $icUIX <> "RectTransform", itAnchors[{L["M"] + 12, 76, Max[100, bw] - 24, L["HH"] - 88}, {L["W"], L["H"]}]];
      statusText = itText[s, "接続済み [" <> itAccessLabel[] <> "]", fs*1.5, "Left", "Middle",
        ResoniteRealtime`ResoniteRealtimeNewId["ThumbStatus"], RGBColor[0.75, 0.85, 1., 1]];
      {connectBtn, wires} = itThumbHeaderButtons[panel, L, fs, wires];
      (* 升目: 透明なボタン + 題名 *)
      Do[
        cell = icSlot["Cell" <> ToString[i], content];
        icComp[cell, $icUIX <> "RectTransform", itAnchors[itThumbCell[L, i], {L["W"], L["H"]}]];
        icImage[cell, RGBColor[1, 1, 1, 0.01]];
        icComp[cell, $icUIX <> "Button", <||>];
        lbl = icSlot["Label", cell];
        icComp[lbl, $icUIX <> "RectTransform",
          <|"AnchorMin" -> {0., 0.}, "AnchorMax" -> {1., N[L["LH"]/(L["TH"] + L["LH"])]}|>];
        itText[lbl, itWrapLabel[itThumbTitle[shown[[i]]], L["TW"] - 8, fs, 3], fs, "Center", "Top"];
        AppendTo[wires, {cell, i}],
        {i, Length[shown]}];
      (* 覆い (保存して出し直したときだけ見える) / 行データ (署名つき) / 読み込み・複製で升目を隠す Flux *)
      {veil, vt, vid} = idBoardVeil[panel, L, fs];   (* 覆い / その文字のスロット / Text *)
      idBoardData[root, idBoardBody[shown, o["Title"], L, ps]];
      (* 升目を開示してよい方針なら、出し直したときに升目を隠す Flux は付けない (インベントリから出してすぐ見える) *)
      If[!itThumbsDisclosableQ[], idBoardFlux[root, content, veil]];
      fid = itThumbWire[state, sel, wires, connectBtn, vt, vid];
      rec = <|"Ids" -> <|"State" -> state, "Selected" -> sel, "Texture" -> tex, "Panel" -> panel, "Content" -> content,
          "Veil" -> veil, "VeilText" -> vid, "StatusText" -> statusText, "TitleText" -> titleText|>,
        "Root" -> root, "Rows" -> shown, "AllRows" -> rows, "Title" -> o["Title"], "Hidden" -> hidden, "Overflow" -> over,
        "URL" -> url, "URLs" -> urls, "Textures" -> texs, "Layout" -> L, "Meters" -> {wM, hM}, "Scale" -> ps,
        "Parent" -> pose["Parent"], "Phase" -> "Ready", "Level" -> itAccessLevel[], "Covers" -> <||>, "Stash" -> None, "Name" -> o["Name"],
        "Created" -> DateObject[], "Shape" -> "Plane", "Pose" -> pose,
        (* 曲面から戻した平面は、その中心を覚えておく (次にまた曲面にするときアバターが読めなければここ) *)
        "Center" -> If[AssociationQ[o["Center"]], o["Center"], None]|>;
      $itState["Thumbs"] = Append[itThumbs[], root -> rec];
      (* 帯の画像を Resonite の資産に取り込む (インベントリに保存できるように。http の配信 URL は Wolfram が居ないと出ない) *)
      MapThread[Quiet @ Check[idQueueTexImport[#1, #2, root], Null] &, {texs, files}];
      itSetStatus["サムネイル一覧: " <> itTruncate[ToString[o["Title"]], 40] <> " (" <> ToString[Length[shown]] <> " 件)"];
      <|"Root" -> root, "WireSlot" -> state, "WireSlots" -> {state, vt}, "View" -> "Thumbnails", "Count" -> Length[shown],
        "Hidden" -> hidden, "Overflow" -> over, "Title" -> o["Title"]|>],
    icTag];

ResoniteRealtime`ResoniteThumbnailGadgetRemove[root_String] :=
  Module[{r = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeRemoveSlot[root], $Failed]},
    $itState["Thumbs"] = KeyDrop[itThumbs[], root];
    r];
ResoniteRealtime`ResoniteThumbnailGadgetRemove[] :=
  Map[ResoniteRealtime`ResoniteThumbnailGadgetRemove, Keys[itThumbs[]]];

(* 升目のクリック。結果は $itState["LastShow"] に残す (一覧の ▶ と同じ) *)
If[!ValueQ[$itOpenAnchor], $itOpenAnchor = None];
itThumbOpen[root_String, i_Integer] :=
  Module[{rec = Lookup[itThumbs[], root, None], row, r, t0 = iNow[]},
    If[!AssociationQ[rec] || i < 1 || i > Length[rec["Rows"]], Return[None]];
    (* 接続した直後はワールドの公開範囲とオーナーを確かめ終わるまで開かない (2026-09-25 ユーザー指示)。
       2026-09-26: 断らずに覚えておき、確かめ終わったら開く (サムネイルを押すだけで接続 -> 確認 -> 開く、になる) *)
    If[Lookup[rec, "Phase", "Ready"] =!= "Ready",
      $itState["Thumbs", root, "PendingOpen"] = i;
      idBoardStatus[root, "ワールドを確認しています。済んだら「" <> itTruncate[itRowTitle[rec["Rows"][[i]]], 30] <> "」を開きます"];
      Return[<|"Pending" -> True, "Index" -> i|>]];
    row = rec["Rows"][[i]];
    (* 升目は見せても中身は表示上限で守る (2026-09-26 方針: 秘匿は中身だけ)。ここで止める (itShowObject の itGate でも止まる) *)
    If[!itAllowedQ[itRowPL[row]],
      idBoardStatus[root, "中身は開けません: 機密度 " <> itFmt[itRowPL[row]] <> " >= 表示上限 " <> itFmt[itAccessLevel[]] <>
        " [" <> itAccessLabel[] <> "]"];
      itSetStatus["開けません (機密度): " <> itTruncate[itRowTitle[row], 60]];
      Return[iFailure["PrivacyExceeded", "機密度 " <> itFmt[itRowPL[row]] <> " >= 表示上限 " <> itFmt[itAccessLevel[]]]]];
    itSetStatus["開いています: " <> itTruncate[itRowTitle[row], 60]];
    idBoardStatus[root, "「" <> itRowTitle[row] <> "」を開いています…"];
    (* 押した升目の真正面に出す ("Cell" = 升目の中心。距離とずらしは idJobPose) *)
    (* 曲面の升目なら、升目と中心 (アバター) の間に中心の方を向けて出す (itThumbAnchor、ResoniteRealtime_surface.wl) *)
    r = Block[{$itOpenAnchor = Quiet @ Check[itThumbAnchor[root, rec, i], <|"Root" -> root, "Cell" -> {0., 0., 0.}|>]},
      Quiet @ Check[ResoniteRealtime`ResoniteShowObject[row], $Failed]];
    $itState["LastShow"] = <|"Time" -> DateObject[], "Row" -> KeyTake[row, {"Kind", "Title", "URI", "File", "Id", "PrivacyLevel"}],
      "Result" -> r, "Seconds" -> Round[iNow[] - t0, 0.1], "LastError" -> Lookup[$itState, "LastError", None]|>;
    If[FailureQ[r], itSetStatus["開けません: " <> ToString[r["MessageTemplate"]]];
      idBoardStatus[root, "開けません: " <> ToString[r["MessageTemplate"]]]];
    (* 開くのに時間がかかる物 (PDF のジョブ / 予約した組み立て) は tick が状態欄に経過秒を書く (ResoniteRealtime_docboard.wl) *)
    If[KeyExistsQ[itThumbs[], root],
      $itState["Thumbs", root, "Opening"] =
        If[AssociationQ[r] && TrueQ[Lookup[r, "Deferred", False]] && StringQ[Lookup[r, "Id", None]],
          <|"Title" -> itRowTitle[row], "Since" -> t0, "Job" -> r["Id"]|>, None];
      If[AssociationQ[r] && !TrueQ[Lookup[r, "Deferred", False]],
        idBoardStatus[root, "「" <> itRowTitle[row] <> "」を表示しました"]]];
    r];

(* 表示の切り替え: 今のガジェットを消して、同じ行でもう一方を組む (tick の中なら予約) *)
itThumbToList[root_String] :=
  Module[{rec = Lookup[itThumbs[], root, None]},
    If[!AssociationQ[rec], Return[None]];
    (* 一覧からサムネイルに戻したときに同じスロット名 ("SourceVault Thumbnails <フォルダ名>") になるよう、題名で覚えておく *)
    If[StringQ[Lookup[rec, "Name", None]],
      $itState["ThumbNames"] = Append[Replace[Lookup[$itState, "ThumbNames", <||>], Except[_Association] -> <||>],
        ToString[rec["Title"]] -> rec["Name"]]];
    ResoniteRealtime`ResoniteThumbnailGadgetRemove[root];
    ResoniteRealtime`ResoniteListGadget[rec["AllRows"], "Title" -> rec["Title"], "View" -> "List"]];
itListToThumbs[root_String] :=
  Module[{rec = Lookup[$itState["Lists"], root, None], name},
    If[!AssociationQ[rec], Return[None]];
    name = Lookup[Replace[Lookup[$itState, "ThumbNames", <||>], Except[_Association] -> <||>], ToString[rec["Title"]],
      Lookup[Options[ResoniteRealtime`ResoniteThumbnailGadget], "Name"]];
    ResoniteRealtime`ResoniteListGadgetRemove[root];
    ResoniteRealtime`ResoniteThumbnailGadget[rec["Rows"], "Title" -> rec["Title"], "Name" -> name]];

(* 監視の応答 (State スロット、Depth 0): Selected が 0 以外なら処理して 0 に戻す *)
itHandleThumbs[state_String, res_Association] :=
  Module[{root = itThumbByState[state], rec, v},
    If[!StringQ[root], Return[Null]];
    rec = itThumbs[][root];
    v = icMemberValue[icFindComponent[res, rec["Ids"]["Selected"]], "Value"];
    If[!IntegerQ[v] || v === 0, Return[Null]];
    itNoWait @ Quiet @ Check[
      ResoniteRealtime`ResoniteRealtimeUpdateComponent[rec["Ids"]["Selected"], <|"Value" -> 0|>], Null];
    With[{rt = root, vv = v},
      itPressGate[
        "サムネイル " <> If[1 <= vv <= Length[rec["Rows"]], "「" <> itTruncate[itRowTitle[rec["Rows"][[vv]]], 40] <> "」", ToString[vv]],
        Function[s, idBoardStatus[rt, s]], itThumbAct[rt, vv]]];
    v];

itThumbAct[root_String, v_Integer] :=
  Module[{rec = Lookup[itThumbs[], root, None]},
    If[!AssociationQ[rec], Return[Null]];
    Which[
      v > 0, itThumbOpen[root, v],
      v === -1, itThumbToList[root],
      v === -2, ResoniteRealtime`ResoniteThumbnailGadgetRemove[root],
      (* 「形を変更」: 次の形で組み直す (曲面はアバターの位置を待たずに読んでから。ResoniteRealtime_surface.wl) *)
      v === -4, ResoniteRealtime`ResoniteThumbnailShape[root],
      (* 「キャッシュ削除」: サーバの写しを全部消す (待たない。経過と結果はこの一覧の状態欄に。ResoniteRealtime_pdfcache.wl) *)
      v === -5, With[{rt = root}, ipcClearAllStart[Function[s, idBoardStatus[rt, s]]]],
      (* 「接続」をもう一度: ワールドを確かめ直す *)
      v === -3,
        $itState["Thumbs", root] = Join[rec, <|"Phase" -> "Checking", "ConnectAt" -> iNow[], "ConnectStart" -> iNow[]|>];
        idBoardStatus[root, "ワールドの公開範囲とオーナーを確認しています..."];
        idForceWorldRead[],
      True, Null];
    v];

(* タブレット根の姿勢 (Depth 0)。サムネイル一覧をタブレットの隣に置くのに使う *)
$itPoseSeconds = 5;
itHandleTabletPose[res_Association] :=
  With[{d = Lookup[res, "data", None]},
    $itState["LastPose"] = iNow[];
    If[AssociationQ[d],
      $itState["TabletPose"] = <|"Data" -> KeyTake[d, {"id", "position", "rotation", "scale", "parent"}], "Time" -> iNow[]|>]];

(* Eagle のフォルダをそのまま一覧 / サムネイルに (行は SourceVaultEagleSummaryRow)。
   View は呼んだ時点で決める (Automatic = 直近のタブレットのプロンプトに「サムネ / 一覧」があればサムネイル) *)
Options[ResoniteRealtime`ResoniteEagleFolderGadget] = {"Recursive" -> False, "View" -> Automatic, "Title" -> Automatic,
  "Ext" -> All};
ResoniteRealtime`ResoniteEagleFolderGadget[folder_String, opts : OptionsPattern[]] :=
  With[{view = itListView[OptionValue["View"]]},
    If[itAsyncContextQ[],
      (* 2026-09-25: フォルダの一覧 (3.5-11 s) は作業用カーネルで。行と機密度はこのカーネル (SourceVault) で作る *)
      With[{w = Quiet @ Check[idMaybeEagleJob[folder, view, {opts}], None]},
        If[AssociationQ[w], w,
          itDeferBuild[itEagleFolderBuild[folder, view, opts], "Eagle フォルダ " <> folder,
            <|"Kind" -> "EagleFolder", "Folder" -> folder, "View" -> view|>]]],
      itEagleFolderBuild[folder, view, opts]]];

(* フォルダの item から行を作る (機密度は SourceVaultEagleSummaryRow。1 件 ~2 ms) *)
itEagleRows[items_List, o_Association] :=
  Module[{rowF = icSym["SourceVault`SourceVaultEagleSummaryRow"], rows},
    If[rowF === None, Return[$Failed]];
    rows = Select[Map[Quiet @ Check[rowF[#], $Failed] &, Select[items, AssociationQ]], AssociationQ];
    If[Lookup[o, "Ext", All] =!= All,
      rows = Select[rows, MemberQ[ToLowerCase /@ Flatten[{o["Ext"]}], ToLowerCase[ToString[Lookup[#, "Ext", ""]]]] &]];
    rows];

(* サムネイル一覧のスロット名: "SourceVault Thumbnails <フォルダ名>" (改行・制御文字は空白に、長すぎれば切る) *)
itBoardSlotName[folder_String] :=
  With[{f = StringTrim[StringReplace[folder, RegularExpression["[[:cntrl:]]+"] -> " "]]},
    If[f === "", "SourceVault Thumbnails", "SourceVault Thumbnails " <> itTruncate[f, 60]]];

itEagleFolderBuild[folder_String, view_String, opts : OptionsPattern[ResoniteRealtime`ResoniteEagleFolderGadget]] :=
  Catch[
    Module[{o = Association @ Join[Options[ResoniteRealtime`ResoniteEagleFolderGadget], {opts}], inF, rowF, items, rows, title},
      inF = icSym["SourceVault`SourceVaultEagleItemsInFolder"];
      rowF = icSym["SourceVault`SourceVaultEagleSummaryRow"];
      If[inF === None || rowF === None, Return[iFailure["NoSourceVault", "SourceVault (Eagle) がロードされていません。"]]];
      items = Quiet @ Check[inF[folder, "Recursive" -> TrueQ[o["Recursive"]]], $Failed];
      If[!ListQ[items],
        Return[iFailure["EagleFolder", "Eagle のフォルダ " <> folder <> " を読めませんでした: " <> ToString[Short[items, 2]]]]];
      rows = Select[Map[Quiet @ Check[rowF[#], $Failed] &, Select[items, AssociationQ]], AssociationQ];
      If[o["Ext"] =!= All,
        rows = Select[rows, MemberQ[ToLowerCase /@ Flatten[{o["Ext"]}], ToLowerCase[ToString[Lookup[#, "Ext", ""]]]] &]];
      title = Replace[o["Title"], Automatic -> "Eagle: " <> folder];
      If[view === "Thumbnails",
        (* スロット名にフォルダ名を付ける (2026-09-26 ユーザー指示。インベントリやインスペクタで見分けられるように)。
           監視の候補は名前の前方一致 ($idBoardName) なので "SourceVault Thumbnails <フォルダ名>" でも拾える *)
        itThumbGadgetBuild[rows, "Title" -> title, "Name" -> itBoardSlotName[folder]],
        itListGadgetBuild[rows, "Title" -> title]]],
    icTag];

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
  "- 「サムネイル」「一覧」を求められたら ResoniteListGadget[rows, \"Title\" -> \"...\", \"View\" -> \"Thumbnails\"]\n" <>
  "  (サムネイルを 1 枚の大きな面に並べ、クリックで開く)。「リスト」なら \"View\" -> \"List\" (今の一覧)。\n" <>
  "  Eagle のフォルダを求められたら ResoniteEagleFolderGadget[\"フォルダ名\"] (\"View\" の規則は同じ、\"Ext\" -> \"pdf\" で PDF だけ)。\n" <>
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

(* タブレットの監視は Panel (ボタンと入力欄) だけを読む。根から読むと子に付いた一覧ガジェット (1 つ 200 KB) や
   標準ビューアの複製 (1 枚 400 KB) まで毎回部品データごと読み、2026-09-24 実機で 1.2 MB / 往復 2.5 s になった *)
itTabletPollRoot[] :=
  With[{g = itGadget[]},
    If[StringQ[Lookup[g, "Panel", None]], g["Panel"], g["Root"]]];

itPollTargets[] :=
  Join[itScanTargets[],
    If[itGadgetQ[], {<|"Kind" -> "Tablet", "Root" -> itTabletPollRoot[]|>}, {}],
    Map[<|"Kind" -> "PDF", "Root" -> #|> &, Keys[itPDFViewers[]]],
    Map[<|"Kind" -> "List", "Root" -> #|> &, Keys[$itState["Lists"]]],
    itWorldInfoTargets[],
    (* サムネイル一覧は State スロットだけ (Selected に押された番号が入る) *)
    Map[<|"Kind" -> "Thumbs", "Root" -> #["Ids"]["State"], "Depth" -> 0, "Components" -> True|> &, Values[itThumbs[]]],
    (* タブレット根の姿勢 (サムネイル一覧をタブレットの隣に置くため。5 s ごと、Depth 0 で軽い) *)
    If[itGadgetQ[] && iNow[] - Lookup[$itState, "LastPose", 0] > $itPoseSeconds,
      {<|"Kind" -> "TabletPose", "Root" -> itGadget[]["Root"], "Depth" -> 0, "Components" -> False|>}, {}]];

SetAttributes[itTimed, HoldRest];
$itSlowStepSeconds = 1.0;
itTimed[name_String, expr_] :=
  Module[{t0 = iNow[], r, dt},
    r = expr;
    dt = iNow[] - t0;
    If[dt > $itSlowStepSeconds,
      $itState["SlowTicks"] = Take[Append[Replace[Lookup[$itState, "SlowTicks", {}], Except[_List] -> {}],
        <|"Time" -> DateString[{"Hour", ":", "Minute", ":", "Second"}], "Step" -> name, "Seconds" -> Round[dt, 0.01],
          "Builds" -> Lookup[Values[$itBuilds], "Label", {}]|>], -Min[30, Length[Lookup[$itState, "SlowTicks", {}]] + 1]]];
    r];

(* tick の送信はまとめ書き (ResoniteRealtime_ws.wl の RRWSBatch)。tick は応答を待たないので 1 回の書き込みで済む *)
(* tick の中で Throw (icCheck 等) や Abort が抜けると Busy が True のまま残り、以後の tick が何もせず戻って監視が黙って止まる。
   自分が立てた Busy は必ず戻し、抜けた Throw は LastError に残す (2026-09-25) *)
itPoll[] := ResoniteRealtime`RRWSBatch[
  Module[{mine = !TrueQ[$itState["Busy"]]},
    WithCleanup[
      Catch[Catch[itPoll0[], _, ($itState["LastError"] = iFailure["TickThrow", "tick から Throw が抜けました: " <> ToString[Short[#2, 2]]]) &]],
      If[mine, $itState["Busy"] = False]]]];
itPoll0[] :=
  Module[{pending, targets, idx, target, sent, res},
    If[TrueQ[$itState["Busy"]], Return[Null]];
    If[!itLinkQ[],
      If[TrueQ[$itState["Serve"]],
        $itState["Busy"] = True;
        Quiet @ Check[itServeConnect[], $itState["LastError"] = "connect"];
        $itState["Busy"] = False];
      Return[Null]];
    $itState["Busy"] = True;
    (* 各段の時間を計る (1 s を超えたら SlowTicks に残す。tick は割り込み型の評価なので、長いと FE の Dynamic が待たされる) *)
    itTimed["watch", Quiet @ Check[itWatchTurn[], $itState["LastError"] = "watch"]];
    itTimed["build", Quiet @ Check[itProcessBuilds[], $itState["LastError"] = "build"]];
    itTimed["worldinfo", Quiet @ Check[itMaybeWorldInfo[], $itState["LastError"] = "worldinfo"]];
    itTimed["presence", Quiet @ Check[itPresenceTick[], $itState["LastError"] = "presence"]];
    (* PDF の写し (ResoniteRealtime_pdfcache.wl): 裏の curl の終わりを拾い、置いたビューアの URL を差し替える *)
    itTimed["pdfcache", Quiet @ Check[ipcTick[], $itState["LastError"] = "pdfcache"]];
    itTimed["title", Quiet @ Check[itSyncTitle[], $itState["LastError"] = "title"]];
    itTimed["backing", Quiet @ Check[itMaybeBacking[], $itState["LastError"] = "backing"]];
    itTimed["stash", Quiet @ Check[itMaybeStash[], $itState["LastError"] = "stash"]];
    itTimed["docjob", Quiet @ Check[itProcessDocJobs[], $itState["LastError"] = "docjob"]];
    itTimed["chunk", Quiet @ Check[idProcessChunkJobs[], $itState["LastError"] = "chunk"]];
    (* サムネイル一覧の形の切り替え (ResoniteRealtime_surface.wl): アバターの位置を待たずに読んでから組み直す *)
    itTimed["surface", Quiet @ Check[itProcessSurfaceJobs[], $itState["LastError"] = "surface"]];
    (* サムネイル一覧 (ResoniteRealtime_docboard.wl): 画像の取り込み・引き継ぎ・表示上限の適用・作業用カーネル *)
    itTimed["worker", Quiet @ Check[idWorkerStep[], $itState["LastError"] = "worker"]];
    itTimed["teximport", Quiet @ Check[idProcessTexImports[], $itState["LastError"] = "teximport"]];
    itTimed["boardcand", Quiet @ Check[idPollBoardCands[], $itState["LastError"] = "boardcand"]];
    itTimed["boardjob", Quiet @ Check[idProcessBoardJobs[], $itState["LastError"] = "boardjob"]];
    itTimed["boards", Quiet @ Check[idMaybeBoards[], $itState["LastError"] = "boards"]];
    targets = itPollTargets[];
    If[targets === {}, $itState["Busy"] = False; Return[Null]];
    pending = Lookup[$itState, "Pending", None];
    If[!AssociationQ[pending],
      (* 急ぎ (押された操作を保留して在席の答えを待っている) は巡回を待たない *)
      target = SelectFirst[targets, TrueQ[Lookup[#, "Urgent", False]] &, None];
      If[!AssociationQ[target],
        idx = Mod[$itState["PollIndex"], Length[targets]] + 1;
        target = targets[[idx]];
        $itState["PollIndex"] = idx];
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
          itTimed["reply:" <> ToString[Lookup[pending["Target"], "Kind", "?"]],
            Quiet @ Check[itHandleReply[pending["Target"], res], $itState["LastError"] = "handle"]]],
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
  If[!TrueQ[$itState["Serve"]] && !TrueQ[Lookup[$itState, "TemplateWanted", False]], {},
    Join[
      If[iNow[] - Lookup[$itState, "LastScan", 0] > If[itGadgetQ[], $itScanSecondsAttached, $itScanSeconds] ||
         (TrueQ[Lookup[$itState, "TemplateWanted", False]] && iNow[] - Lookup[$itState, "LastScan", 0] > 3),
        {<|"Kind" -> "Scan", "Root" -> "Root", "Depth" -> 1, "Components" -> False|>}, {}],
      (* 入れ物 ("Spawn - User Holder" 等) の中も 1 段だけ見る。Root Depth 2 は大きなワールドで 1 MB を超え、
         純 WL の WebSocket 層がカーネルごと落ちた (2026-09-24 実機: 10,562 slot) *)
      Map[<|"Kind" -> "HolderScan", "Root" -> #, "Depth" -> 1, "Components" -> False|> &,
        Replace[Lookup[$itState, "ScanHolders", {}], Except[_List] -> {}]],
      (* 候補タブレット: 根を Depth 1 (部品込み) で 1 回読んで Panel / 板 / 保管した雛形の ID を控え、以後は Panel だけ読む。
         根ごと (Depth -1) 読むと子の雛形の保管 (400 KB) や一覧 (200 KB) まで毎回読む (2026-09-24) *)
      If[TrueQ[$itState["Serve"]],
        Map[With[{inf = itCandInfo[#]},
            If[AssociationQ[inf] && StringQ[inf["Panel"]] && iNow[] - inf["Time"] < 120,
              <|"Kind" -> "Candidate", "Root" -> inf["Panel"], "Depth" -> -1, "Components" -> True, "Tablet" -> #|>,
              <|"Kind" -> "CandidateTop", "Root" -> #, "Depth" -> 1, "Components" -> True|>]] &,
          Replace[Lookup[$itState, "Candidates", {}], Except[_List] -> {}]], {}],
      (* インベントリから出したサムネイル一覧の「接続」 *)
      Quiet @ Check[idBoardScanTargets[], {}]]];

itCandInfo[root_String] := Lookup[Replace[Lookup[$itState, "CandInfo", <||>], Except[_Association] -> <||>], root, None];
(* 根を Depth 1 で読んだ data から、Panel / 板 (部品込み) / 保管した雛形を拾う *)
itTabletTopInfo[top_Association] :=
  Module[{kids = Select[Lookup[top, "children", {}], AssociationQ], byName},
    byName[n_String] := SelectFirst[kids, ToString[itVal[Lookup[#, "name", ""]]] === n &, None];
    <|"Root" -> Lookup[top, "id", None], "Name" -> ToString[itVal[Lookup[top, "name", "Mathematica Tablet"]]],
      "Panel" -> itSlotId[byName["Panel"]], "Board" -> byName["Tablet Viewer"], "Stash" -> itSlotId[byName[$itStashName]],
      "Backing" -> itSlotId[byName["Backing"]],
      "Time" -> iNow[]|>];
(* 引き継ぎ用の木: 根 + Panel (全部) + 板。itParseTabletTree が読むのはこの 2 つだけ *)
itComposeTablet[inf_Association, panelData_Association] :=
  <|"data" -> <|"id" -> inf["Root"], "name" -> inf["Name"],
      "children" -> Select[{panelData, inf["Board"]}, AssociationQ]|>|>;
itHandleCandidateTop[root_String, res_Association] :=
  With[{d = Lookup[res, "data", None]},
    If[AssociationQ[d],
      $itState["CandInfo"] = Append[Replace[Lookup[$itState, "CandInfo", <||>], Except[_Association] -> <||>],
        root -> itTabletTopInfo[d]]]];

(* 入れ物らしい Root の子: 名前に holder / spawn を含む物 + $ResoniteTabletScanHolders *)
If[!ListQ[ResoniteRealtime`$ResoniteTabletScanHolders], ResoniteRealtime`$ResoniteTabletScanHolders = {}];
itHolderQ[s_Association] :=
  With[{n = ToLowerCase[ToString[itVal[Lookup[s, "name", ""]]]]},
    StringContainsQ[n, "holder" | "spawn"] || MemberQ[ToLowerCase /@ ResoniteRealtime`$ResoniteTabletScanHolders, n]];

itHandleScan[res_Association] :=
  Module[{kids},
    $itState["LastScan"] = iNow[];
    kids = itSlotsUpTo[Lookup[res, "data", <||>], 1];
    (* インベントリから出した物はワールドによっては "Spawn - User Holder" のような入れ物の下に入る (2026-09-24 実機)。
       その入れ物だけ次の tick で 1 段見る (Root Depth 2 は大きすぎる) *)
    (* Lookup[{}, "id"] は Missing を返すので Map で拾う *)
    $itState["ScanHolders"] = DeleteDuplicates[Map[Lookup[#, "id"] &, Select[kids, itHolderQ]]];
    Quiet @ Check[idSweepWorldInfo[kids], Null];
    itNoteScanSlots[kids, True]];

itHandleHolderScan[root_String, res_Association] :=
  Module[{kids = itSlotsUpTo[Lookup[res, "data", <||>], 1]},
    $itState["ScanHolders"] = DeleteCases[Replace[Lookup[$itState, "ScanHolders", {}], Except[_List] -> {}], root];
    (* 一覧が入っていたときだけ記録 (毎回は多すぎる) *)
    With[{nb = Count[kids, s_Association /; StringStartsQ[ToString[itVal[Lookup[s, "name", ""]]], "SourceVault Thumbnails"]]},
      If[nb > 0, Quiet @ Check[idBoardLog[root, "HolderScan", "入れ物の中にサムネイル一覧 " <> ToString[nb]], Null]]];
    itNoteScanSlots[kids, False]];

(* 走査で見えたスロットから、タブレット候補と標準 PDF ビューアの雛形を拾う。reset = Root の走査 (候補を作り直す) *)
itNoteScanSlots[kids_List, reset_] :=
  Module[{cands, prev},
    cands = Select[kids, AssociationQ[#] && StringQ[Lookup[#, "id", None]] &&
      StringStartsQ[ToString[itVal[Lookup[#, "name", ""]]], "Mathematica Tablet"] && Lookup[#, "id"] =!= itGadgetRoot[] &];
    prev = If[reset, {}, Replace[Lookup[$itState, "Candidates", {}], Except[_List] -> {}]];
    $itState["Candidates"] = DeleteDuplicates[Join[prev, Map[Lookup[#, "id"] &, cands]]];
    Quiet @ Check[idNoteBoardCands[kids, reset], Null];
    If[ResoniteRealtime`$ResonitePDFMode === "Native" && !StringQ[itNativeTemplateId[]],
      With[{tc = itNativeTemplateCandidates[kids]},
        If[tc =!= {}, $itState["PDFTemplate"] = First[tc]; $itState["TemplateWanted"] = False]]];
    Length[cands]];

(* root = 候補タブレットの根、res = その Panel を Depth -1 で読んだ応答 *)
itHandleCandidate[root_String, res_Association] :=
  Module[{inf = itCandInfo[root], ids, connect, pressed},
    $itState["Candidates"] = DeleteCases[Replace[Lookup[$itState, "Candidates", {}], Except[_List] -> {}], root];
    If[!AssociationQ[inf] || !AssociationQ[Lookup[res, "data", None]], Return[None]];
    ids = itParseTabletTree[itComposeTablet[inf, res["data"]]];
    If[!AssociationQ[ids], Return[None]];
    connect = Lookup[ids["Buttons"], "Connect", None];
    pressed = StringQ[connect] && icMemberValue[icFindComponent[res, connect], "Value"] === True;
    If[!pressed, Return[None]];
    (* 旗は先に戻す (断ったときに次の走査で押されたままに見えないように。引き継ぎでも戻す) *)
    itSetFlag[connect, False];
    With[{all = Join[ids, <|"Stash" -> inf["Stash"], "Backing" -> inf["Backing"]|>]},
      itPressGate["タブレットの接続", None, itAdoptIds[all]]];
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
    kids = itScanSlotsNow[];
    If[FailureQ[kids], Return[kids]];
    Map[<|"Id" -> #["id"], "Name" -> ToString[itVal[Lookup[#, "name", ""]]], "Attached" -> (#["id"] === itGadgetRoot[])|> &,
      Select[kids, AssociationQ[#] && StringQ[Lookup[#, "id", None]] &&
        StringStartsQ[ToString[itVal[Lookup[#, "name", ""]]], "Mathematica Tablet"] &]]];

(* 待つ版の走査: Root の子 + 入れ物の子 (1 段ずつ。Root Depth 2 はカーネルが落ちる) *)
itScanSlotsNow[] :=
  Module[{tree, kids, holders, more},
    tree = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot["Root", "Depth" -> 1, "Timeout" -> 60], $Failed];
    If[!AssociationQ[tree], Return[iFailure["GetSlot", "Root の階層が取れませんでした。"]]];
    kids = itSlotsUpTo[Lookup[tree, "data", <||>], 1];
    holders = Select[kids, itHolderQ];
    more = Flatten @ Map[Function[h,
      With[{t = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[h["id"], "Depth" -> 1, "Timeout" -> 30], $Failed]},
        If[AssociationQ[t], itSlotsUpTo[Lookup[t, "data", <||>], 1], {}]]], holders];
    Join[kids, more]];

Options[ResoniteRealtime`ResoniteTabletAdopt] = {"PollInterval" -> 1.0};
ResoniteRealtime`ResoniteTabletAdopt[opts : OptionsPattern[]] :=
  With[{found = ResoniteRealtime`ResoniteTabletFind[]},
    Which[FailureQ[found], found,
      found === {}, iFailure["NoTablet", "ワールドにタブレット (\"Mathematica Tablet\") がありません。"],
      True, ResoniteRealtime`ResoniteTabletAdopt[Last[found]["Id"], opts]]];
ResoniteRealtime`ResoniteTabletAdopt[root_String, opts : OptionsPattern[]] :=
  Module[{top, inf, tree, ids},
    If[!itLinkQ[], Return[iFailure["NotConnected", "ResoniteLink が未接続です (ResoniteRealtimeLinkConnect[])。"]]];
    (* 根は Depth 1 (Panel / 板 / 保管した雛形の ID)、Panel だけ全部。子の雛形の保管や一覧までは読まない *)
    top = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[root, "Depth" -> 1, "IncludeComponentData" -> True,
      "Timeout" -> 30], $Failed];
    If[!AssociationQ[top] || !AssociationQ[Lookup[top, "data", None]], Return[iFailure["GetSlot", root <> " が読めませんでした。"]]];
    inf = itTabletTopInfo[top["data"]];
    If[!StringQ[inf["Panel"]], Return[iFailure["NotATablet", root <> " はタブレットの構造ではありません (Panel がありません)。"]]];
    tree = Quiet @ Check[ResoniteRealtime`ResoniteRealtimeGetSlot[inf["Panel"], "Depth" -> -1, "IncludeComponentData" -> True,
      "Timeout" -> 30], $Failed];
    If[!AssociationQ[tree] || !AssociationQ[Lookup[tree, "data", None]], Return[iFailure["GetSlot", root <> " の Panel が読めませんでした。"]]];
    ids = itParseTabletTree[itComposeTablet[inf, tree["data"]]];
    If[!AssociationQ[ids], Return[iFailure["NotATablet", root <> " はタブレットの構造ではありません。"]]];
    ids = Join[ids, <|"Stash" -> inf["Stash"], "Backing" -> inf["Backing"]|>];
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
    If[n >= 2 && t["Kind"] === "Thumbs",
      With[{r = itThumbByState[root]},
        If[StringQ[r], $itState["Thumbs"] = KeyDrop[itThumbs[], r]];
        $itState["TargetFailures"] = KeyDrop[$itState["TargetFailures"], root];
        $itState["LastError"] = iFailure["GadgetGone", "サムネイル一覧 " <> ToString[r] <> " はワールドに無いので台帳から外しました。"]]];
    If[t["Kind"] === "TabletPose", $itState["LastPose"] = iNow[]];
    (* 入れ物の走査の失敗は黙っていた (2026-09-26: 入れ物の下のサムネイル一覧が候補に入らなかった調査)。記録し、2 回で諦める
       (次の Root の走査がまた入れ物を見つければやり直す) *)
    If[t["Kind"] === "HolderScan",
      Quiet @ Check[idBoardLog[root, "HolderScanFail", ToString[Short[Lookup[$itState, "LastError", ""], 3]]], Null];
      If[n >= 2,
        $itState["ScanHolders"] = DeleteCases[Replace[Lookup[$itState, "ScanHolders", {}], Except[_List] -> {}], root];
        $itState["TargetFailures"] = KeyDrop[$itState["TargetFailures"], root]]];
    If[t["Kind"] === "WorldInfo",
      $itState["WorldInfo", "LastRead"] = iNow[];
      If[n >= 2, $itState["WorldInfo"] = None; $itState["Presence"] = <||>; $itState["TargetFailures"] = KeyDrop[$itState["TargetFailures"], root];
        itWorldInfoApply[None]]];
    If[MemberQ[{"BoardCand", "BoardCandTop"}, t["Kind"]],
      $itState["BoardCands"] = DeleteCases[Replace[Lookup[$itState, "BoardCands", {}], Except[_List] -> {}], Lookup[t, "Board", root]];
      $itState["TargetFailures"] = KeyDrop[$itState["TargetFailures"], root]];
    (* Scan / Candidate の失敗は次の走査で拾い直す *)
    If[MemberQ[{"Scan", "Candidate", "CandidateTop"}, t["Kind"]],
      $itState["Candidates"] = DeleteCases[Replace[Lookup[$itState, "Candidates", {}], Except[_List] -> {}],
        Lookup[t, "Tablet", root]];
      $itState["CandInfo"] = KeyDrop[Replace[Lookup[$itState, "CandInfo", <||>], Except[_Association] -> <||>],
        Lookup[t, "Tablet", root]];
      $itState["TargetFailures"] = KeyDrop[$itState["TargetFailures"], root]]];

(* 押されたボタン (Value = True) を集めて False に戻し、種類ごとに処理する *)
itPressed[res_Association, buttons_Association] :=
  Select[Keys[buttons],
    icMemberValue[icFindComponent[res, buttons[#]], "Value"] === True &];

itHandleReply[target_Association, res_Association] :=
  Switch[target["Kind"],
    "Tablet", itHandleTablet[res],
    "List", itHandleList[target["Root"], res],
    "Thumbs", itHandleThumbs[target["Root"], res],
    "TabletPose", itHandleTabletPose[res],
    "WorldInfo", itHandleWorldInfo[res],
    "PDF", itHandlePDF[target["Root"], res],
    "Scan", itHandleScan[res],
    "HolderScan", itHandleHolderScan[target["Root"], res],
    "CandidateTop", itHandleCandidateTop[target["Root"], res],
    "Candidate", itHandleCandidate[Lookup[target, "Tablet", target["Root"]], res],
    "BoardCandTop", idHandleBoardCandTop[target["Root"], res],
    "BoardCand", idHandleBoardCand[Lookup[target, "Board", target["Root"]], res],
    _, Null];

itHandleTablet[res_Association] :=
  Module[{g = itGadget[], pressed},
    If[!AssociationQ[g], Return[Null]];
    pressed = itPressed[res, g["Buttons"]];
    If[pressed === {}, Return[Null]];
    Scan[itSetFlag[g["Buttons"][#], False] &, pressed];
    With[{p = pressed, r = res, gg = g},
      itPressGate["タブレット " <> StringRiffle[p, ", "], None, itTabletAct[p, r, gg]]];
    pressed];

itTabletAct[pressed_List, res_Association, g_Association] :=
  Module[{txt},
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
  Module[{rec = Lookup[$itState["Lists"], root, None], ids, pressed},
    If[!AssociationQ[rec], Return[Null]];
    ids = rec["Ids"];
    pressed = itPressed[res, ids["Buttons"]];
    If[pressed === {}, Return[Null]];
    Scan[itSetFlag[ids["Buttons"][#], False] &, pressed];
    With[{p = pressed, rt = root},
      itPressGate["一覧 " <> StringRiffle[p, ", "], None, itListAct[rt, p]]];
    pressed];

(* 保留されてから実行されることがあるので、一覧の記録はそのとき読み直す *)
itListAct[root_String, pressed_List] :=
  Module[{rec = Lookup[$itState["Lists"], root, None], opens},
    If[!AssociationQ[rec], Return[Null]];
    opens = Cases[pressed, s_String /; StringStartsQ[s, "Open"] :> ToExpression[StringDrop[s, 4]]];
    Which[
      MemberQ[pressed, "Close"], ResoniteRealtime`ResoniteListGadgetRemove[root],
      MemberQ[pressed, "View"], itListToThumbs[root],
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
      "AccessMode" -> ResoniteRealtime`$ResoniteWorldAccessMode,
      "WorldInfo" -> With[{w = itWorldInfo[]}, If[AssociationQ[w], Join[KeyTake[w, {"Root", "Fired"}],
        <|"Data" -> w["Data"], "Age" -> If[NumericQ[w["Time"]], Round[iNow[] - w["Time"], 0.1], None]|>], None]],
      "WorldAccess" -> icAccessName[],
      "OwnerPresence" -> ResoniteRealtime`ResoniteOwnerPresence[],
      "BoardLog" -> Replace[Lookup[$itState, "BoardLog", {}], Except[_List] -> {}],
      "Turn" -> If[AssociationQ[t], KeyTake[t, {"Prompt", "Phase", "RuntimeId", "LastStatus", "Start"}], None],
      "Viewer" -> If[AssociationQ[v], <|"Pages" -> Length[v["Pages"]], "Page" -> v["Page"], "Title" -> v["Title"]|>, None],
      "PDFViewer" -> With[{p = itPDF[]},
        If[AssociationQ[p], <|"Root" -> p["Ids"]["Root"], "Pages" -> Length[p["Pages"]], "Page" -> p["Page"], "Title" -> p["Title"]|>, None]],
      "PDFViewers" -> KeyValueMap[#1 -> <|"Pages" -> Length[#2["Pages"]], "Page" -> #2["Page"], "Title" -> #2["Title"]|> &, itPDFViewers[]],
      "Thumbs" -> KeyValueMap[#1 -> <|"Count" -> Length[#2["Rows"]], "Title" -> #2["Title"], "URL" -> #2["URL"],
        "Parent" -> #2["Parent"]|> &, itThumbs[]],
      "TabletPose" -> Lookup[$itState, "TabletPose", None],
      "PDFMode" -> ResoniteRealtime`$ResonitePDFMode,
      "PDFTemplate" -> itNativeTemplate[], "Stash" -> itStashId[],
      "NativeDocs" -> KeyValueMap[#1 -> KeyTake[#2, {"Title", "Pages"}] &, itNativeDocs[]],
      "DocJobs" -> Map[KeyTake[#, {"Id", "Phase", "Title", "Tries"}] &, Replace[Lookup[$itState, "DocJobs", {}], Except[_List] -> {}]],
      "NativeLog" -> Replace[Lookup[$itState, "NativeLog", {}], Except[_List] -> {}],
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
