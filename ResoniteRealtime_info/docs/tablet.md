# タブレット — ClaudeEval を Resonite ワールド内で走らせる

`ResoniteRealtime_tablet.wl` (ResoniteRealtime.wl が自動ロード。chat ガジェットのヘルパの上に載る)。
2026-09-22 起草。ワールド内のタブレットに打ったプロンプトを、ノートブックの ClaudeInput セルを評価したのと
**同じ処理** (ClaudeEval の runtime 経路: 提案コードの実行、承認、結果セル) で走らせ、結果をワールドへ出す。

## できること

- タブレット (UIX パネル): 入力欄 / **Eval** / Clear / Cancel / 状態行 / **承認・拒否** (承認待ちのときだけ有効) /
  **スクロールする出力欄** (Mask + ScrollRect + ContentSizeFitter) / 画像ビューア (板) と ◀ n/N ▶ 閉じる。
- Eval → 専用ノートブック「Resonite Tablet」に `ResoniteTabletTurn["..."]` の Input セルを書いて評価
  (中身は `ClaudeEval`。`$UseClaudeRuntime` を Block で True にして runtime 経路。あわせて `$ClaudeEvalMode = "Single"`、
  PromptRouter / natural dispatch を False にして ClaudeOrchestrator へ回らないようにする。2026-09-22: Eagle の PDF 一覧が
  オーケストレーションに回り、runtime が無いままタブレットが Pending の連想だけ描いた)。それでも `OrchJobId` が返ったときは
  `ResoniteTabletNoteTurnResult` が控えて `ClaudeOrchestrationStatus` の完了まで見張り、ノートブックに書かれた結果を描く。
- 承認待ち → タブレットに理由と式を出し、承認/拒否ボタン。押すと claudecode の `ClaudeRuntimeDecide` が
  ノートブックの承認ボタンと同じ処理 (runtime 再開 → 結果セル表示)。タイムアウト延長 (`TimeoutExtension`) は
  LLM が見積もった秒数で延長承認。
- 完了 → ターン開始後に増えたセルを機密度でふるい、平文を出力欄へ、ラスタライズしたページ画像をビューアへ。
  Dynamic/Button 入りのセル (承認 UI 等) は落とす。ページは幅 1000 px (`ImageResolution -> 144` + `PageWidth` で
  折り返し。Notebook の Rasterize は画面 DPI で膨らみ `ImageSize` は上限にならない。2026-09-22 実機)、
  高さ 1000 px で割り、分割した最後のページは白で埋めて高さを揃える (板の大きさがページ送りで変わらない)。
- `ResoniteShowObject[x]`: SourceVault オブジェクト (sv:// URI / 共通スキーマ行 / ファイル / 画像 / 式 / 行リスト) を
  ワールドへ。PDF はページ送り、動画は `ResoniteVideoBoard`、本文は出力欄、行リストは `ResoniteListGadget`。
- `ResoniteListGadget[rows]`: core 関数 (`SourceVaultArXiv` 等) の行リストをボタン付き一覧に。▶ でビューアへ。
  フッタの「サムネ」でサムネイル一覧に切り替わる。
- **裏板** (2026-09-24 ユーザー指示): UIX のパネルは奥行きを書かない半透明の扱いで、後ろのドームのガラスや空が手前に描かれて
  透けて見え、厚みも無いので横から見ると消えた。タブレット・サムネイル一覧・一覧ガジェット・自前 PDF パネルの裏 (+z。利用者は -z 側)
  に "Backing" (BoxMesh 厚さ 1.5 cm、パネルより 1.2 cm ずつ大きい + 不透明の PBS_Metallic 暗灰) を置く。裏板の無い既存のタブレット
  (この版より前に作った / インベントリから出した) には tick で 1 回だけ後付けする (引き継ぎで既存の Backing は数えるので二重にしない)。
- `ResoniteThumbnailGadget[rows]` (2026-09-24): 行のサムネイルを 1 枚の大きな面に升目で並べ、クリックでその PDF / 画像を開く。
  「リスト」で一覧に戻る。プロンプトに「サムネ」「一覧」があれば `ResoniteListGadget` は既定でこちらを出す (「リスト」なら一覧)。
  Eagle のフォルダは `ResoniteEagleFolderGadget["フォルダ名"]`。構成と取得元は api.md。
  実機 (2026-09-24、Eagle 1 + arXiv 3 + 図 1): 組み立て 7 s、ButtonValueSet 7 本 (升目 5 + 見出し 2) が同じ Selected を指し、
  Selected に 1 を書くと Eagle の PDF が標準ビューアで開いて Selected は 0 に戻った (12 s)。
  **縦 7 段・横は無制限・全件** (2026-09-25 ユーザー指示「このサムネイルサイズで縦方向を 7 に、横は無制限に伸ばして、表示されていない
  139 件もすべて」): 1 枚 0.12 m のまま、縦は 7 段まで、列は件数なりに増やす (上限 14 列と MaxItems 150 を撤廃)。横に長い面は
  36 列ずつの帯 (テクスチャ 1 枚ずつ) に分けて貼る。組み立ての送信 (~2,300 通) は tick ごとにまとめ書き (`RRWSBatch`) にし、
  サムネイルは Eagle の `<名前>_thumbnail.png` を決め打ちで見て、先頭のバイトで決めた形式で読む。帯の JPEG は元画像と配置が同じなら
  画像を読まずに使い回す。実機 (合成画像 260 件): 38 x 7・4.94 x 1.53 m・帯 2 枚、組み立て 65 s → 35.5 s、開き直し 13.3 s。
  **空カードだらけ (2026-09-25 実機、Eagle の SF フォルダ 289 件)**: Eagle の `_thumbnail.png` は中身が WebP (先頭 `RIFF....WEBP`、
  287 件。PNG は 2 件だけ)。拡張子で "PNG" と決め打って読んだため 287 件が読めず、ext 色の空カードが描かれた。先頭のバイトで形式を
  決めるように直し (読めなければ Import に任せる)、読めない画像がある版はキャッシュにしない。289 件すべて表紙が出ることを実データで確認。

## 手順

### Resonite 側から使う (インベントリのタブレット + 「接続」ボタン) — 2026-09-22

一度 `ResoniteTablet[]` で作ったタブレットは Resonite のインベントリに保存しておける。以後は

1. Mathematica で `Get["ResoniteRealtime.wl"]` (claudecode / SourceVault / NBAccess はロード済みの前提)。ノートブックのセッションでは
   ロード時に **常駐監視 `ResoniteTabletServe[]` が自動で始まる** (`$ResoniteTabletAutoServe`)。
2. Resonite で ResoniteLink を有効化 (ホストであること)。ポートは **自動検出** (`ResoniteRealtimeDiscover[]` = Windows の http.sys
   登録一覧 `netsh http show servicestate` から Resonite / Renderite.Host が登録した `HTTP://LOCALHOST:<port>/` を拾う。即時。
   無ければ resoloop discover、環境変数 RESONITE_LINK_URL)。常駐監視が 15 秒ごとに探して繋ぐ。
3. インベントリからタブレットを出して **「接続」** を押す。常駐監視が Root 直下と、入れ物 (名前に holder / spawn を含む Root の子。
   ワールドによってはインベントリから出した物が "Spawn - User Holder" の下に入る) の 1 段下の "Mathematica Tablet" を 5 秒ごとに見ていて、
   「接続」の ValueField が True のものをスロット名とコンポーネント型で読み取り (`itParseTabletTree`。ID はインベントリ経由で
   付け直されているので名前だけが頼り)、このカーネルのタブレットとして引き継ぐ (`ResoniteTabletAdopt`)。状態欄が
   「接続しました (PL<=…)」になれば使える。

ノートブックから明示的にやるなら `ResoniteRealtimeLinkConnect[]` → `ResoniteTabletFind[]` → `ResoniteTabletAdopt[root]`。
常駐監視は ResoniteLink の応答が 5 回続けて途絶えたら切断して再探索に戻り、ワールドから消えたタブレット (getSlot が 3 回失敗) は
台帳から外す。`ResoniteTabletServe[False]` で止める。

### ノートブックから作る

```mathematica
Get["ResoniteRealtime.wl"];                     (* claudecode / SourceVault / NBAccess はロード済みの前提 *)
ResoniteRealtimeLinkConnect[];                  (* ResoniteLink (常時オン)。ポートは自動検出。明示なら [port] *)
(* 表示上限は既定でワールドから自動で読む (自分がホストで所有するプライベートワールドなら 1.0)。手で決めるなら
   ResoniteAccessLevel["Private", "Owner" -> True] *)
ResoniteTablet[]                                (* 正面 1.2 m にタブレット + 板。監視も始まる *)
```

ワールド側: 入力欄に打って **Eval**。承認が要るときはタブレットの **承認 / 拒否**。図はビューアに映る。
ノートブック側でも同じことができる: `ResoniteTabletEval["..."]`, `ResoniteTabletApprove[]`, `ResoniteTabletDeny[]`,
`ResoniteTabletCancel[]`, `ResoniteTabletShow[text | expr]`, `ResoniteTabletStatus[]`, `ResoniteTabletLog[]`。
片付け: `ResoniteTabletRemove[]` (`ResoniteListGadgetRemove[]`, `ResoniteViewerRemove[]`)。

## 表示上限 (アクセスレベル)

| ワールド | オーナー | 表示上限 PL |
|---|---|---|
| Private | ○ | 1.0 |
| Contacts | ○ | 0.5 |
| ContactsPlus / Public | ○ | 0.25 |
| どれでも | × (既定) | 0.25 |

- 所有者と公開度は**ワールドから自動で読む** (2026-09-25)。ResoniteLink のメッセージには無いが、部品 SessionInfoSource に
  今のセッション ID (ProtoFlux の WorldSessionID で書かせる) を入れると公開度 / ホスト / ワールド記録の所有者が埋まる。
  ホスト = 所有者ならオーナー。表示上限が変わるとタブレットの見出し [PL<...] と状態欄を書き直す。読めないうちは 0.25。
  手で決めるなら `ResoniteAccessLevel[kind, "Owner" -> True]` (手動になる)、`ResoniteAccessLevel[Automatic]` で自動に戻る。
- 表示: セルは `NBCellExprPrivacyLevel`、行は `PrivacyLevel` キー、sv:// は `SourceVaultObjectPrivacyLevel`。
  **数値が取れないものは出さない (fail-closed)**。上限を超えたセルは「[非表示: 機密度 …]」の注記に置き換わる。
- LLM に渡す `PrivacySpec -> <|"AccessLevel" -> …|>` は `Min[表示上限, $ResoniteTabletCloudMaxLevel (0.5)]`。
  `ResoniteTablet["Model" -> ローカルモデル]` のときだけ表示上限と同じ。
- ワールドで打った文字の機密度 (chat と共通 `icPromptPrivacy`) は Private 1.0 / Contacts 0.5 / それ以外 0。

## フレンドの操作はオーナーが在席しているときだけ実行する (2026-09-25)

ワールドのボタンは同期されたフィールド (`ValueField<bool>` / サムネイル一覧の `Selected`) なので、**フレンドが押しても
オーナーの PC のこのカーネルが読んで実行する** (もともとそう動く)。そこに「オーナーがそのワールドにいて見ているときだけ」の
関門 `itPressGate` を足した (`$ResoniteOwnerPresenceGate`、既定 True)。対象: タブレット (Eval / 承認 / 拒否 / 中止 / 3D / 板の
ページ送り…)、一覧、サムネイル一覧 (開く / 表示切替 / 閉じる / 再接続)、自前 PDF パネル、インベントリから出したタブレットと
サムネイル一覧の「接続」。手で呼ぶ関数 (`ResoniteShowObject` 等) とノートブックからの操作は通さない。

**Resonite の挙動 (FrooxEngine.dll の IL で確認、2026-09-25)**

| 状況 | 結果 |
|---|---|
| ホスト (= ResoniteLink をつないでいるオーナー) がワールドを去る | セッションが終わる。クライアントは `OnHostConnectionClosed` → `World.Destroy`。ホストの移譲は無い (VRChat のように残らない) |
| ホストが別のワールドにフォーカスを移す | 元のワールドは裏で動き続け、ResoniteLink も残る。`User.IsPresentInWorld` が False (`WorldManager.BeginUpdate` がフォーカス切替で書く) |
| VR でヘッドセットを外す | `User.IsPresent` が False (`IsPresent = IsPresentInWorld && (!VR_Active \|\| IsPresentInHeadset)`) |
| デスクトップで Mathematica のウインドウに切り替える | `IsPresentInWorld` は変わらない (Resonite 内のフォーカスの話) → 在席扱い |

ボタンを押せるのはそのワールドにフォーカスしている人だけなので、「オーナーが在席していない」なら押したのはオーナー以外。
押した人を個別に調べなくても、在席を確かめれば「オーナーが見ているときだけ実行」になる。

**仕組み**: ワールド情報の仕掛け (`Mathematica World Info`) に在席の問い合わせを足した。WL が `nonce` (ValueInput<int>) を
1 増やすと、`FireOnValueChange<int>` (`OnlyForUser` = `HostUser`、ホストのクライアントだけが評価) が
`IsUserPresent(HostUser)` を info の `ValueField<bool>` に、nonce を `ValueField<int>` (Ack) に書く。WL は info を
SessionInfoSource と一緒に読み、**Ack が送った nonce と一致したときだけ**答えとして使う (ホストのクライアントがいまこのワールドで
評価した証拠。裏に回ったワールドで評価されなければ答えは来ない → 不在扱い)。

- 直近 `$ResoniteOwnerPresenceFreshSeconds` (5 s) 以内の答えが「在席」→ すぐ実行。
- それより古い → 操作を保留し、問い合わせを出して巡回を待たずに info を読む。「在席」なら実行、押した後の問い合わせに
  「不在」→ 断る、8 s 答えが無い → 断る。状態欄 (タブレット / サムネイル一覧) に「オーナーの在席を確かめています…」
  「オーナーがこのワールドを見ていないので実行しません (…)」と出す。ボタンの旗は押された時点で戻すので、断った操作は消える。
- 定期の問い合わせは 3 s ごと (巡回の読み取りに載る)。在席中はたいていすぐ実行できる。
- 公開度を手動 (`ResoniteAccessLevel[kind, ...]`) にしてもワールド情報の仕掛けは組む (在席の確認に要る)。
- 診断: `ResoniteOwnerPresence[]` (`Present` / `AckSecondsAgo` / 保留中 `Held` / 直近の実行と拒否 `Log`)、
  `ResoniteTabletStatus[]["OwnerPresence"]`。単独でのデバッグ時だけ `$ResoniteOwnerPresenceGate = False`。
- テスト: `references/tests/test_presence.wl` (27、ResoniteLink はスタブ)。**実機 (フレンドとの 2 人) は未検証**。

**残っている課題**
- 承認ボタン: オーナーが在席していれば、フレンドがタブレットで Eval → 承認まで押せる (提案コードがオーナーの PC で走る)。
  押した人を知るには、ボタンごとに `ButtonEvents.Pressed` (押した人のクライアントで発火) → `LocalUser` → `UserUserID` を
  同期フィールドへ書く ProtoFlux が要る。承認だけオーナー限定にするならこれを足す。
- PDF は下の「PDF の写しを web サーバに置く」で見えるようになった。自前パネル (`$ResonitePDFMode = "Panel"`) のページ画像・
  板・動画は今も `http://127.0.0.1:<port>/a/...` なのでフレンドには見えない (`importTexture2DFile` の `local://` だけ配られる)。
- Chat ガジェット (`ResoniteRealtime_chat.wl`) は別の監視なので、この関門を通っていない。

## PDF の写しを web サーバに置く (`ResoniteRealtime_pdfcache.wl`、2026-09-25)

HTTP の URL 資産は各クライアントが自分で取りに行くので、`http://127.0.0.1:…` の PDF はフレンドには見えない。
ワールドが **Private か Contacts** で自分がオーナーのとき、PDF を**初めてワールドに出すとき**に、利用者が設定した web サーバへ
写しを置き、全員が `<$ResonitePDFCacheBaseURL>/<SHA-256>.pdf` を読むようにする (`$ResonitePDFCache`、既定 True)。

**サーバの設定 (PC ごとに一度。2026-09-26 から、ソースにはサーバ名・アカウント・パスワードを書かない)**:

```wolfram
ResonitePDFCacheSetup["sftp://user@www.example.org/home/user/www/cache", "https://www.example.org/cache"]
ResonitePDFCacheCredential[]   (* パスワードをダイアログで。NBAccess 経由で SystemCredential に保存 *)
ResonitePDFCacheSetup[]        (* 今の設定と、次にすること *)
```

1 つ目は sftp で書き込むディレクトリ、2 つ目はそのディレクトリを https で読む URL。設定は
`$UserBaseDirectory/ApplicationData/ResoniteRealtime/pdfcache_server.json` に保存され、ロードのたびにここから読む
(URL にパスワードを入れると断る)。

**他のパッケージとの分離**: このサーバ設定はこのパッケージの設定ファイルだけにあり、SlideWorkflow 等の設定は読みも書きもしない
(コードの依存も無い)。片方だけ使う人も、両方で別々のサーバを使う人も、同じサーバの別フォルダを使う人もそのまま設定できる。
重なりうるのはパスワードの名前だけ: 既定はアカウント名 `sftp://user@host` なので、同じアカウントなら 1 回保存したパスワードを
両方が使い (同じアカウントのパスワードは同じ)、サーバかアカウントが違えば別々に保存される。同じアカウントでもパッケージごとに
分けたいときは `ResonitePDFCacheSetup[upload, base, "Credential" -> "ResoniteRealtime pdfcache"]` のように専用の名前にする
(設定ファイルには名前だけ残る)。既定の名前のまま `ResonitePDFCacheCredential[None]` で消すと、同じアカウントを使う他のパッケージの
パスワードも消えるので、戻り値の `"Shared" -> True` と `"Note"` で知らせる。SystemCredential の読み書きは NBAccess (`NBGetCredential` / `NBSetCredential` / `NBRemoveCredential` /
`NBCredentialConfiguredQ`) だけが行い、値はこの層の外へ出さず curl の標準入力の設定で渡す。**未設定のときは写しを置かず**
(PDF はオーナーにだけ見える)、状態欄に設定の仕方を出す。

- 名前は**中身の SHA-256** (ファイル名のハッシュだと名前を知る人に URL を当てられ、中身を直しても古い写しを指す)。
  同じ PDF は何度開いても同じ URL で、送るのは 1 回。`/cache/` の一覧表示は 403 (2026-09-25 確認)。
- 開くたびに HEAD で確かめる (60 s 以内に確かめた物は省く)。同じ大きさで置いてあれば使う (別の PC が送った物も)。
  サーバから消されていたら、ビューアを 127.0.0.1 に戻して送り直し、送り終わったら URL を戻す。
- 送っている間は 127.0.0.1 で開き (オーナーはすぐ見える)、送り終わって HEAD で確かめてから StaticDocument.URL を差し替える
  (標準ビューアの複製 `NativeDocs` / 文書表示 `DocViewers` の記録に `Doc` (StaticDocument の ID) と `CacheKey` を持たせた)。
- 送り先は `$ResonitePDFCacheUploadURL` (設定ファイルの値)。
  `<hash>.pdf.part` に送ってから rename (途中のファイルを見せない)。curl は `--globoff` (ファイル名の `[ ]` を範囲指定と読ませない)、
  パスに ASCII 以外か `[ ] { }` があれば一時フォルダに `<hash>.pdf` で写してから送る (日本語の引数が化ける。2026-09-25 実機 exit 3)。`--ftp-create-dirs` で cache が無ければ作る。
- 通信は Git for Windows 同梱の sftp 対応 curl を **StartProcess で裏で走らせ、tick で終わりを拾う** (FE を止めない)。
  パスワードは SystemCredential (`sftp://user@host`) を NBAccess で取り、curl の標準入力の設定 (`-K -`) で渡す
  (コマンドラインに出さない)。**PC ごとに一度** `ResonitePDFCacheCredential[]` で保存しておく。
- 機密度が `$ResonitePDFCacheMaxLevel` (既定 0.5) を超える PDF、機密度が数値で取れない PDF は送らない (オーナーだけに見える)。
  ワールドの表示上限 (Private 1.0) とは別の「外のサーバに置いてよいか」の上限。置かなかったときは状態欄に
  「機密度 … なのでサーバに写しを置きません」と出し、`ResonitePDFCacheStatus["Skipped"]` に残す。**Eagle の行の機密度は
  要約記録の値 > ライブラリ既定 (`$SourceVaultEaglePrivacyLevel`、未設定なら 1.0) で、Cloud-Publishable タグの物だけ上限が
  下がる**ので、既定のままだと Eagle の PDF はたいてい置かれない。
- 片付け: 台帳 `$UserBaseDirectory/ApplicationData/ResoniteRealtime/pdfcache.json` (この PC が置いた物と時刻)。
  `ResonitePDFCacheClear[]` (台帳の物) / `ResonitePDFCacheClear["OlderThan" -> 7]` / `ResonitePDFCacheClear[All]` (cache の *.pdf 全部) /
  `ResonitePDFCacheList[]`。状態は `ResonitePDFCacheStatus[]`。
  **サムネイル一覧の見出しの「キャッシュ削除」ボタン** (閉じるの右、Selected = -5、2026-09-26): どの Eagle フォルダの物かに関係なく、
  サーバの cache にある写し (`<SHA-256>.pdf` と送りかけの `.pdf.part`。同じディレクトリの他のファイルは触らない) をすべて消す。
  監視の tick の中なので待たない (curl を裏で走らせて一覧 → 削除、経過と件数はその一覧の状態欄)。消す名前は curl の標準入力の
  設定 (`quote = "*rm …"`) で渡す (数百件だとコマンドラインの長さの上限を超えるため)。置いたビューアのうち写しを指していた物は
  127.0.0.1 に戻し (フレンドには見えなくなる)、台帳からも外す。次に開けば送り直す。在席ゲートを通るのでオーナーの操作だけが実行される。パスワード未保存で止まった写しは、保存すれば 10 s 以内に自動で送り直す
  (開き直し不要)。パスワード違い・通信失敗は `ResonitePDFCacheRetry[]` で送り直す。
- 著作権: ワールドの設定でオーナー以外の保存を禁じる運用。ただし URL はインスペクタ等で見え、ブラウザで直接取れるので、
  会が終わったら `ResonitePDFCacheClear[]` で消す。
- テスト: `references/tests/test_pdfcache.wl` (37。サーバは cache.example.org の仮置き、curl はスタブ + 手元の file:// への実送信 +
  この PC に設定したサーバへの実際の HEAD 1 回 (未設定なら省く)。サーバへの送信はしない)。設定・パスワード・キャッシュ削除ボタンは
  `test codes/ResoniteRealtime_tablet_test.wls` の "PDF cache server" (10。NBAccess と curl はスタブ、設定ファイルは一時フォルダ)。**実機の送信は未検証**。

## 升目 (サムネイル) は開示してよい / 升目を押せば接続 (`$ResoniteThumbnailsDisclosable`、既定 True、2026-09-26 方針)

ユーザー方針: **縮小画像 (と題名) は機密度にかかわらず開示してよい。秘匿すべきは PDF の中身**。これで一覧を升目込みで
インベントリに保存してそのまま出せる (帯は `local://` 資産なので Mathematica が居なくてもすぐ見える)。

- 組み立て (`itThumbPlan`): 表示上限で行を落とさない (Hidden = 0)。一覧 (文字だけの `ResoniteListGadget`) は従来どおり落とす。
- 「出し直したら升目を隠して覆いを出す」Flux (`idBoardFlux`: OnLoaded / OnDuplicate) を付けない。前の版の一覧は、一度接続すると
  その Flux を外す (`FluxRemoved`)。そのまま保存し直せば次からは出してすぐ見える。
- 表示上限以上の升目に覆い (非表示 PL …) を付けない (前に付けた覆いは外す)。状態欄に「中身は開けない n」。
- **中身は開くときに判定** (`itThumbOpen`): 機密度 >= 表示上限なら「中身は開けません」で止める (`itShowObject` の `itGate` でも止まる)。
- **升目を押せば接続**: 未接続の一覧の升目を押すと State の Selected が升目の番号になる。監視の候補の読み取りが -3 (「接続」) と
  同じく正の数も拾い、引き継ぎ → ワールドの公開範囲とオーナーの確認 → その升目を開く (`idGatedAdopt[root, i]` / `PendingOpen` /
  `idFirePendingOpen`)。接続済みで確認中に押した升目も断らずに覚えて、確認が済んだら開く。「接続」ボタンは再確認用に残る。
- 注意: 一覧の行データ (Data の ValueField<string>、署名つき) は保存するとインベントリ (クラウド) に入る。表示上限以上の行の題名・
  ファイルのパスも入るようになった (升目に題名が見えるのと同じ扱い)。
- テスト: `references/tests/test_boardcand.wl` (16)。
- スロット名 (2026-09-26): Eagle フォルダから作った一覧は `"SourceVault Thumbnails <フォルダ名>"` (`itBoardSlotName`。制御文字は空白、
  60 字で切る)。監視の候補・引き継ぎ・入れ物の走査は前方一致なので同じく拾う。リスト⇄サムネの切り替えでも名前を引き継ぎ、
  `ResoniteTabletCleanup` は前方一致 (`"Prefixes"`) で消す。

## サムネイル一覧を曲面に貼る: 円筒 / 球の内側 / メビウスの帯 / 任意の面 (`ResoniteRealtime_surface.wl`、2026-09-26)

ユーザー指示「平面のパネルを、アバターの位置を中心とした湾曲パネルや球面の内側に切り替えるボタンを。汎用的に: 各サムネイル領域を
変換後の表面領域に対応させる関数を設計し、表面をフォーカスして左クリックした点が表面と交わる領域のサムネイルの PDF を開く。
メビウスの帯やトーラスの外側など、自由に面を設計できるように」。

- **面 = 平面座標 → 3D 点の写像** `S(x, y)`。平面座標は今の一覧の升目の座標 (m、升目の範囲の中心が原点、x 右 / y 上)、戻り値は
  中心 (アバターの目、y 上、+z = 視線の水平方向) から見た点。定義は `ResoniteThumbnailSurface[Function[{x, y, g}, {X, Y, Z}], opts]`
  (`g` = 寸法 `<|"W", "H", "Y0", "R", ...|>`、`"Fit" -> Function[g, <|"R" -> ...|>]` で件数に合わせて半径などを決める)。
  組み込み: `"Plane"`, `"Cylinder"` (半径 1.3 m から、幅が 0.9 周を超えれば広げる), `"SphereInside"` (正弦図法 φ = y/R、θ = x/(R cos φ)
  で横の間隔を保つ。**段数は球が自分で選ぶ** (2026-09-26 ユーザー「湾曲が足りない、半径を小さく」: 平面と同じ 7 段の横長の帯だと 462 件で
  半径 1.72 m・緯度 ±28° の円筒のような見た目だった)。段数 1..24 のうち半径が一番小さくなるもの (1% 以内なら経度:緯度 ≈ 2:1 に近いもの) で、
  462 件 = 12 段・1.48 m・±53°、289 件 = 10 段・1.18 m、100 件 = 6 段・1.0 m。半径は「緯度 ≤ 1 rad、一番上の段でも経度 ≤ ±0.9π、最小 1.0 m」を
  満たす最小値を二分法で解く (前の反復は段が多いと振動し、極の近くで升目が重なる半径を返しえた), `"Mobius"` (半径 R の円に沿って **2 周** (s = 4πx/W)、縦は w(s) = cos(s/2) 上 + sin(s/2) 外 で
  半回転ねじれる。w(s+2π) = -w(s) なので 2 周目は S(x+W/2, y) = S(x, -y) に法線が逆向きで来る = 1 周目の裏面。表裏の無い帯の両面に
  一続きの升目が載る (2026-09-26 ユーザー指示)。段数は 2 周を 9 割以上埋める一番多い段数 (`"Rows"` フック、289 件 = 2 段 x 145 列、
  462 件 = 3 段、2000 件 = 7 段で半径が広がる)。表裏のある面 (`"TwoSided" -> True`) は升目を面から表側へ裏板の半分浮かせ、裏板は面の中央、
  光線の逆写像は光線に表を向けた升目を選び、開いた PDF は升目の表の前に升目を向けて出す), `"TorusOutside"` (例。正面のトーラスの手前の外側。巡回には入れていない)。
  名前で使うには `$ResoniteThumbnailSurfaces["名前"] = ResoniteThumbnailSurface[...]`、ボタンの巡回は `$ResoniteThumbnailShapes`。
- **升目 = 面の上のタイル**: 升目ごとに小さな UIX Canvas を位置 `S(c_i)`、向き = 接平面 (ex = ∂S/∂x、ey = ∂S/∂y を直交化、ez = ex × ey) に置く。
  UIX の表は -z なので、ez が中心から外を向くように面を書けば表が中心 (アバター) を向く (`"Flip" -> True` で反転)。絵は平面と同じ帯の
  JPEG の升目の矩形だけを、タイルごとの `SpriteProvider` の `Rect` (UV、左下原点) で切り出す (テクスチャは帯の枚数のまま)。裏板は共有の BoxMesh。
  **実機の罠 (2026-09-26)**: 最初は帯全体を升目の外まで広げた Image を UIX `Mask` で切る作りだったが、Mask は切らず、升目ごとに帯全体
  (36 列 x 7 段、幅 4.7 m) が接平面に出た (接平面は円筒・球の外側なので「外に元の平面が残っている」ように見えた)。ResoniteLink の Rect は
  `<|"$type" -> "Rect", "value" -> <|"position" -> <|x, y|>, "size" -> <|x, y|>|>|>` (実機で書いて読み戻し確認)。段が上下逆に出たら
  `ResoniteRealtime`Private`$itTileUVTopLeft = True`。
- **クリック = 光線と面の交点の升目**: レーザーは升目のコライダー (= 面を升目ごとの接平面で近似した面) に当たり、その升目の
  Button + `ButtonValueSet<int>` が番号を Selected に書く。監視・開く処理は平面と同じ (State スロット 1 つ)。Wolfram 側でも同じ対応を
  解ける: `ResoniteThumbnailSurfaceHit[root, {origin, dir}]` (Newton 法で S(x,y) = o + t d、(x, y) を含む升目。升目の間は None)。
- **「形を変更」ボタン** (見出し、Selected = -4): 平面 → 円筒 → 球の内側 → メビウスの帯 → 平面。曲面へは監視の tick で**待たずに**
  Root (Depth 1) → 入れ物 (`Spawn - User Holder` 等、Depth 1) → `User ...` (Depth 1、子の Head) を読み、目の位置と頭の向き (水平) を中心にして
  同じ行で組み直す。ボタンは押した人を記録しないので、押した人 = 一覧に一番近いアバター (入れ物の姿勢で Root の座標に直して比べる)。
  **実機の罠 (2026-09-26)**: アバターは Root の直下とは限らない (このワールドは入れ物の中)。Root の直下だけ見ていた版は見つけられず、
  前の中心に組み直していた (「以前の座標に生成される」)。テストのモックは Root を平らに全部返すので気付かなかった → `$mockRootDirect`。
  アバターが見つからない / 8 s 読めないときは、平面のパネルの手前 1.3 m (利用者側 -z)、または直前の中心。平面へ戻すと中心の正面 1.4 m。
  見出しは 4 ボタンになったので最小幅を 1400 → 1560 px にした (状態欄の幅は前と同じ)。
- 曲面の構成: 根 (中心) の下に State / Data / Panel (見出しの Canvas、面の上端の上に接平面で) / Backing / Content (Assets + Cell<i> + Back<i>)。
  行データ (署名つき) に `shape` / `geometry` を入れ、インベントリから出した曲面の一覧も引き継げる (Content は Panel でなく根の子を使う)。
  升目から開いた PDF は升目と中心の間 (中心から 升目の距離 - 0.45 m、最低 0.6 m) に中心を向けて出す (`itThumbAnchor`)。
  表示上限を超える行があるとき (升目を開示しない設定のみ)、曲面では升目ごと隠して覆いを出す (平面の覆いを面に置けないので fail-closed)。
- テスト: `test codes/ResoniteRealtime_tablet_test.wls` の "thumbnail surfaces" (43)。フレームの正規直交性・四元数、円筒 / 球の距離と向き、
  メビウスの閉じ方、光線 → 升目の往復 (4 形 + 自作の面)、ボタンで円筒 → 球 → メビウス → 平面、アバター無しの中心。
  実機: メビウスの帯 (462 件) の組み立てと表示はユーザー確認済み (帯の見え方は Mask の問題のみ → Rect に変更、変更後は未確認)。

## サムネイルから開いた PDF の置き場所 (2026-09-25)

押した升目の**真正面**に出す: 升目の中心 (根の座標系。パネルの根は中心) に根の拡大率を掛け、そこから根の向きで手前 (-z) に
`$idFrontMeters` = 0.3 m (拡大率を掛けない)。重ね置きのずらしは同じ一覧から直近 120 s に開いた数 (4 で折り返し、1 段 4 cm 右・3 cm 下)。
以前は高さがパネル中心固定・距離 0.45 m × 拡大率・ずらしがセッション中に開いた全 PDF 数 (ワールドで閉じても減らない) で、
開くほど右下の床の方へ流れた (ユーザー実機)。テスト: `references/tests/test_placement.wl` (6)。

## ページを押すと次のページ (`$ResonitePDFPageClick`、既定 True、2026-09-25)

デスクトップでは視線 (カーソル) を下の `[>]` まで動かさないとめくれず読みにくい、とのユーザー指示。

- **押し面** = 子スロット `Mathematica PageClick` (RectTransform 親いっぱい + **Button だけ**) + その子 `HitArea`
  (RectTransform 親いっぱい + Image Tint α=0・材質なし = 当たり判定)。`Button.OnAttach` は**同じスロットの** `Image.Tint` に
  色ドライバ (ホバー / 押下の色) を付けるので、Image と同じスロットに Button を置かない:
  ページの Image に付けた版はホバーでページが暗くなり、α=0 の Image と同じスロットに付けた版はホバーで不透明な灰色になって
  ページが隠れた (2026-09-25 実機 2 回。ハイライト色は α を保たない)。UIX の Canvas は当たった Graphic のスロットから
  親へ `GetComponentInParents<IUIInteractable>` で辿る (FrooxEngine.dll で確認) ので、子の HitArea への押下は親の Button に届く。
- **文書表示** (`ResoniteDocViewer`、`Mathematica PDF Viewer`): 押し面に `[>]` と同じ `ButtonValueShift<int>` 2 つ
  (PageIndex と表示の番号、+1、最後で止まる) を付けて組む。ワールドの中だけで動く。
- **標準ビューアの複製**: 中身を知らない雛形なので、置いた直後 (DocJob の段 `PageClick`) に複製を Depth -1 で 1 回読み、
  - ページ表示 = `DocumentPageTexture` を (SpriteProvider / 材質を 1 段経て) 参照する UIX Image / RawImage のスロット
  - `[次へ]` = UIX Button のスロットのうち、PageIndex を進める `ButtonValueShift` (Delta 最小) > 名前・文字が Next / > / ▶ / → / ›
    > その他の +方向の ValueShift
  を探して結ぶ。`ButtonPressEventRelay` は Target のスロットの IButtonPressReceiver しか呼ばず ProtoFlux の `ButtonEvents` には
  届かない (FrooxEngine.dll で確認) ので、`[次へ]` を聞く `ButtonEvents` があれば同じ型の `ButtonEvents` をページの Button 用に
  足して Pressed を元と同じ行き先につなぎ、無ければ `ButtonPressEventRelay` (Target = `[次へ]`) を置く。
  結果は `ResoniteTabletStatus[]["NativeLog"]` の `PageClick` 行と `$itState["PageClickInfo"]`。カーネルごとに最初の 1 回、
  複製の木を `%TEMP%\ResoniteRealtime\native_pdf_tree.json` に書く (結べなかったときの調査用)。
- テスト: `references/tests/test_pageclick.wl` (13、合成した木)。**標準ビューアの実物では未検証** (雛形の中身を見ていない)。

## パネルの構成 (すべて ResoniteLink で組み立て)

```
<Name>                 Grabbable, AI_GeneratedContent
├─ Panel               Canvas 1000x1500 (単位) を PanelScale 0.0006 で縮小 = 0.6 m x 0.9 m
│  └─ VLayout          VerticalLayout
│     ├─ Title         Text (名前 + [PL<=x.xx kind])
│     ├─ Input         Image + Button + TextEditor + TextField / Text
│     ├─ ButtonRow     [Eval] [Clear] [Cancel] [3D生成] [接続]   ← Button + ValueField<bool> + ButtonToggle
│     ├─ Status        Text
│     ├─ ApprovalRow   [承認] [拒否] + ラベル         ← isActive=False。承認待ちのときだけ有効
│     ├─ Output        Image + Mask
│     │  └─ Content    RectTransform (上端固定) + VerticalLayout + ContentSizeFitter(VerticalFit=MinSize) + ScrollRect
│     │     └─ Text    LayoutElement (MinHeight = 文字数から見積り) + Text
│     └─ ViewerBar     [<] [n/N] [>] [閉じる]
└─ Tablet Viewer       ResoniteRealtimeBoard (パネルの右隣。ページ画像を映す)
```

- enum は `<|"$type" -> "enum", "value" -> "MinSize"|>` で書ける (2026-09-22 実測。数値や型名指定は弾かれる)。
- スロットの有効/無効は `updateSlot` の `isActive`。
- ボタンは chat と同じ「Button + ValueField<bool> + ButtonToggle (メンバ ID 結線)」。WL が Value を読んで False に戻す。

## 図が板に出ないとき (2026-09-22)

runtime の表示セル (実行結果の図) は LLM の応答セルより後に書かれることがあり、タブレットが「セル数が 2 tick 安定」で描いた時点では
無いことがあった (実機: ガンマ関数の Plot が板に出ず、テキストだけ)。対策は 2 段:

1. **表示 stash**: 実行時に `$ClaudeRuntimeDisplayHook` で拾った生の結果のうち図 (Graphics / Graphics3D / Legended / Image) を runtime ごとに
   `StashDisplay` に取っておき、結果セルに図が無いターンではそこからページを描く (`itStashDisplayCells`。機密度は同じ上限で判定)。
2. **遅れて来たセル**: Done の後 `$itLateCellSeconds` (180 s) の間に結果セルが増えたら Finishing に戻して描き直す (ログは同じ記録を置き換える)。

## 監視 (ScheduledTask 1 本、既定 1 秒)

- tick では待たない: `getSlot` を `"Wait" -> False` で送り、次の tick で `sourceMessageId` を照合 (chat と同じ 2 相)。
  対象はタブレットの Panel (ボタンと入力欄) と一覧ガジェットの根を交互に。タブレットは根から読まない: 子に付いた一覧ガジェット
  (1 つ 200 KB) や PDF まで部品データごと毎秒読み、2026-09-24 実機で 1.2 MB / 往復 2.5 s になった (Panel だけなら 177 KB)。
- 同じ tick で runtime を見張る (`ClaudeRuntimeState`): Starting (`$ClaudeLastRuntimeId` が変わるのを待つ) →
  Running → AwaitingApproval (承認 UI) → Done/Failed → Finishing (セル数が 2 tick 安定するまで待つ) → 描画。
  終端の後に承認待ちへ戻ることがある (実行タイムアウト → 失敗 → 修復ターンが延長申告で再提案。2026-09-22 実機) ので、
  Finishing の間と Done の後 600 秒 (`$itDoneWatchSeconds`) は状態を見張り、AwaitingApproval / Running に戻ったらターンを再開する。
  タブレットの出力には診断用 Code セルとノートブック側の承認 UI ブロック (CellTags `claudecode-approval-*`) を出さない。
- FrontEnd を触るのはターン開始のセル書き込み/評価と完了時のラスタライズだけ。
- 承認/拒否/中止は別の ScheduledTask に投げる (`ClaudeRuntimeDecide` は実行を伴う)。
  runtime が `AwaitingApproval` でなければ送らない (押し直し / 古い読み取りで、後から来た別の提案を勝手に承認しない。2026-09-23)。
  承認したら出力欄の「承認が必要です」は「承認しました。実行しています ...」に置き換える。
- 「実行中」には内訳を付ける (`itRunPhaseLabel`): runtime の DAG にまだノードがあれば「LLM 応答待ち」、CurrentPhase が
  Execute なら「式を実行」。2026-09-23 実機: 承認後、続きの LLM 応答 (claude CLI) に 10 分かかり、何をしているか分からなかった。

## 承認 UI がノートブックに残る問題 (2026-09-23、修正済み)

タブレットで承認しても、ノートブック側の承認 UI (❓ 通知 / NeedsApproval セル / 承認・中止ボタン、CellTags
`claudecode-approval-<rid>`) はそのまま残っていた。しかも承認後の結果セル (提案コード / 出力 / ContinueEval 行) はジョブの
アンカー直後 = 承認 UI より**上**に挿入されるので、ノートブックの末尾に押せる承認ボタンが残り「2 度目の承認要求」に見えた。
押すと `ClaudeApproveProposal` は `NotAwaitingApproval` を返して無言 (runtime は Running で続きの LLM 応答待ち)。
対策 (claudecode.wl): `ClaudeRuntimeDecide` が承認 / 拒否 / 中止のときにそのタグのセルを消し、アンカー直後に
「✅ ワールド内タブレットで承認しました」を書く。ノートブックの承認ボタンも、処理済みなら案内 (`iRuntimeNotAwaitingNotice`) だけ書いて
`iRuntimeDisplayResult` を呼ばない (結果セルの二重書き防止)。

## LLM への指示

プロンプト先頭に `[Resonite tablet]` と表示上限、`ResoniteShowObject` / `ResoniteListGadget` の使い方を付ける
(`itPromptWithContext`)。規則 `Claude Directives/rules/110-resonite-tablet.md` も同じ内容。
表示 API は NBAccess の許可ヘッドに 2 層登録 (`ResoniteTabletRegisterHeads[]`、ロード時自動) するので、
LLM の提案コードが `ResoniteListGadget[SourceVaultArXiv["LLM"]]` を呼んでも承認は要らない。
削除系 (`ResoniteTabletRemove` 等) は承認ヘッド。
2026-09-23: 「クリックしたら赤と青の色が変わる Box」は `ResoniteColorToggleBox[{Red, Blue}]` 1 つで作るよう指示する
(状態確認 `ResoniteRealtimeStatus` / `ResoniteFluxCatalogSearch` は許可ヘッドにしたが「不要」と伝える。
実機では LLM がまず状態確認を提案 → 承認 → 続きの応答に 10 分 → 本題に進めなかった)。

## 未検証 (2026-09-22)

- 実機: ScrollRect のドラッグスクロール、`NormalizedPosition -> {0,1}` が「上端」か、Text の折り返しと
  MinHeight の見積り (ASCII 0.55 em / それ以外 1.0 em)、Mask のクリップ、ボタンのラベル配置。
- `ResoniteVideoBoard` の再生開始 (VideoTextureProvider の Playback は未操作)。
- `SelectionEvaluate` を ScheduledTask の中から呼んで FE がセルを評価するか (ノートブックの kernel で確認する)。
- 承認後の結果セル表示 (`ClaudeRuntimeDecide` → `iRuntimeDisplayResult`) は 2026-09-23 に実機で通った
  (結果セルは書かれる。残った承認 UI は上記のとおり修正)。
- `ResoniteColorToggleBox` (2026-09-23): 初版は箱は出たが押しても変わらなかった (BooleanValueDriver.State に参照を書いていた。
  State は bool 値。FrooxEngine.dll の反射 `resources/tools/frooxengine-reflect.fsx` で確認)。2 版 = TouchButton →
  ButtonToggle (→ driver.State) → BooleanValueDriver (TargetField → TintColor)。**ノートブックのトップレベル
  `ResoniteColorToggleBox[]` は実機で押すと赤⇔青が切り替わった (2026-09-23)**。タブレット経由 (tick の 2 巡結線) は
  ヘッドレステストのみで、実機は未確認。

## テスト

`test codes/ResoniteRealtime_tablet_test.wls` (ヘッドレス、ResoniteLink をモック、claudecode / ClaudeRuntime /
NBAccess は公開名のスタブ)。組み立て・出力欄の高さ・Eval → ターン開始・承認 UI と決定・完了時の PL ふるい分け・
ResoniteShowObject の分岐 (PDF / 画像 / 文字列 / 行の PL 拒否) ・一覧ガジェットのページ送りと ▶・中止・削除。

## 非同期文脈からの組み立ては予約する (2026-09-22)

ResoniteLink の応答待ちは ScheduledTask / SessionSubmit / runtime の実行ジョブの中では必ずタイムアウトする (受信ハンドラが走れない)。
LLM の提案コードが呼ぶ `ResoniteListGadget` (ButtonToggle の結線にメンバ ID の応答が要る) は runtime のジョブの中で実行されるので、
そのままでは「ResoniteLink 無応答」になった。`$CurrentTask` が TaskObject のとき (`$ResoniteTabletDeferMode` Automatic) は
組み立てを専用ノートブックの Input セル `ResoniteTabletRunDeferred["id"]` として評価を予約し、即座に
`<|"Deferred" -> True, "Id" -> id|>` を返す (セルはトップレベル評価なので応答を受けられる)。対象: `ResoniteListGadget` /
`ResoniteVideoBoard` / `ResoniteViewer`。台帳は `ResoniteTabletDeferred[]`。ビューアへの表示や板のテクスチャ更新は待たない送信なので予約不要。
タブレットの出力欄には提案コード (Input セル) を出さない (`$ResoniteTabletShowCode = True` で出す)。

2026-09-22 追記 (現行): **予約した組み立ては監視 tick の中で「待たずに」組む** (`$ResoniteTabletBuildMode` Automatic = tick が動いていれば "Tick")。
ノートブックのセルに予約する方式は、セルの応答待ちループの最中に runtime の非同期タスク (LLM 問い合わせ・セル書き込み) が割り込むと
FrontEnd とカーネルが待ち合って固まった (実機 2 回: 3 行組んだところで `In[•]` のまま停止、ボタンが空)。tick 方式は
1. Send: ビルダーを `$iLinkWaitDefault = False` で走らせ、スロット/コンポーネントを送りっぱなし。ボタンの `ButtonToggle` だけ後回し (`$itWireLater` に積む)。
   置き場所 "User" はアバター位置の問い合わせ (待ち) が要るので、タブレットがあればその子 (`{0,0,0}` + 各ガジェットの Offset) にする。
2. Wire: 根の `getSlot` (Depth -1, 待たない) を送り、次の tick で応答から `ValueField<bool>.Value` のメンバ ID を拾って `ButtonToggle` を結線。
   10 秒来なければ再送 (3 回まで)。それでも来なければ失敗にして**組みかけの根を消す** (結線されていない一覧は使えない)。
台帳は `ResoniteTabletDeferred[]` (`"Via" -> "Tick"`)、進行中は `ResoniteTabletStatus[]["Builds"]`。tick が無いときだけ従来のセル予約に落ちる (`"Notebook"`)。
`ResoniteTabletRunDeferred` は tick 予約の id には何もしない。

旧 (2026-09-22 前半): 予約の判定は `$CurrentTask` だけでは足りない。runtime は提案コードを `TimeConstrained[..., 30]` で主カーネルで直接実行する経路もあり (`$CurrentTask` は None)、22 行の一覧を直接組み始めて 30 秒で中断され、待ちループ内の Abort でカーネルが固着した (ボタン 4 個だけの一覧が残った)。そこで **タブレットのターンが進行中なら常に予約** する (`itTurnActiveQ`)。予約セルの中 (`$itInDeferredRun`) では直接組む。固着したら「評価 > 評価の中止」かカーネル再起動 → 再ロード → `ResoniteTabletCleanup[]` (Root 直下の名前で残骸を消し状態を空にする) → `ResoniteTablet[]`。

## 一覧の ▶ が開かないときの診断

▶ は監視 tick の中で `ResoniteShowObject[row]` を呼ぶ。結果は `ResoniteTabletStatus[]["LastShow"]`
(行の Kind/URI/File、Result、所要秒、LastError) に残る。PDF は `Import[file, {"PDF", "PageImages", {n}}]` (FrontEnd 不要) で
描き、駄目なら `"Pages"` + Rasterize。行に `File` が無ければ sv:// URI から `SourceVaultObjectProperties` → `SourceVaultResolveReference`
→ `SourceVaultObjectData` の順に解決する。HTML スナップショット (arXiv の abs ページ) は平文にして出力欄へ。
実測 (2026-09-22 ヘッドレス): arXiv の raw PDF (5 ページ) は tick の中でも約 6 秒で開いた。

## 3D生成 (2026-09-22)

タブレットの **3D生成** ボタン (`ResoniteTabletMake3D[]`) は直前のターンの結果にある Graphics3D (Plot3D / ArrayPlot3D 等) を
`ResoniteGraphics3D` でワールド内の実体メッシュにする (アバター正面 1.2 m、最長辺 0.6 m、頂点色、Grabbable)。
生の結果は claudecode の `$ClaudeRuntimeDisplayHook` (表示ストアに記録されるたびに呼ばれる seam) で拾う。
無ければ runtime の `LastExecutionResult["RawResult"]`、それも無ければ結果セルの Graphics3DBox から取る。機密度が表示上限を超える結果は作らない。
プロンプトで「ワールドに 3D で出して」と言えば LLM が `ResoniteGraphics3D[Plot3D[...]]` を直接呼ぶ (規則 110)。
仕組み: `ResoniteRealtime_mesh.wl` → ImportMeshJSON (vertices/submeshes) → resoloop apply の `kind: mesh` 資産 → `StaticMesh` + `PBS_VertexColorMetallic` (Culling Off) + `MeshRenderer` + `MeshCollider`。
罠: プロジェクト配下の `.resoloop/state` は Dropbox が新規 checkpoint を掴んで `APPLY_STATE_WRITE_FAILED` になる
(フォルダの `com.dropbox.ignored` は新規ファイルに効かなかった。タブレットの 3D生成で実機再現)。そのため mesh/apply/checkpoint は
`%LOCALAPPDATA%\ResoLoop\g3d` (Dropbox の外) に書き、それでも checkpoint 失敗なら同じ apply を最大 3 回再実行して収束させる。

## PDF は Resonite 標準のドキュメントビューアで開く (`$ResonitePDFMode = "Native"`、2026-09-24)

ResoniteLink 0.13.1 には「ファイルのインポート」も「スロットの複製」も無い (mesh / texture 資産だけ) ので、標準ビューアを
一から作ることはできない (雛形は 155 slot / 348 component、ProtoFlux 111 個)。代わりに:

1. **雛形**: ワールドにある Resonite 標準の PDF ビューア (PDF をインポートしたときの物) を 1 つ覚える。名前が `PDF Template` で
   始まる物 (空白 / `_` / `-` と大小は無視) を優先、無ければ名前が `.pdf` で終わる物 (Root 直下と入れ物の 1 段下。
   **Root Depth 2 は大きなワールドで 1 MB を超え、純 WL の WebSocket 層がカーネルごと落ちる** (2026-09-24 実機、10,562 slot) ので使わない)。常駐監視の走査で自動、手動は `ResonitePDFTemplate[]` /
   `ResonitePDFTemplate[slotId]`。**ワールドに標準ビューアが 1 つも無いときは自前パネル (Panel) に落ちる。**
2. **複製ガジェット** (一度だけ): Root 直下 `Mathematica PDFs` (置き場) の下に ProtoFlux 5 ノード
   `ValueInput<bool>` → `FireOnTrue` → `DuplicateSlot(Template = 雛形, OverrideParent = 置き場)`。出力が一つの `ValueInput` を
   トリガにするのはプロキシ解決 (待つ getSlot) が要らないため。fluxlink と同じく結線は 2 段目。
3. **開くたび**: 配信 URL (L3) を用意 → 置き場の子を控える → トリガを True → 置き場に現れた複製と
   タブレット根 (Depth 0: 親から見た position / rotation / scale と親) を読む → 複製を**タブレットの隣** (タブレットの親の子) の
   右前へ (タブレットから見て {0.65,0,-0.35}、2 つ目以降は少しずつずらす。位置 = タブレット位置 + 回転 (scale × offset)、
   回転 = タブレットの回転) → `StaticDocument.URL` を配信 URL に差し替え → トリガを False。
   **タブレットの子にはしない** (2026-09-24 実機: 子にすると 1 枚 155 slot / 400 KB ずつ監視・引き継ぎ・インベントリ保存が重くなる)。
   タブレットが無いときは Root の原点の前。置き場には残さない (やり直しで置き場ごと捨てると消えるため)。
   実機 (2026-09-24): http の PDF を標準ビューアが描画した (TextureSizeDriver の縦横比で確認)。
   すべて tick の 2 相 (`DocJobs`: Init → Before → Fired → Await → Configure)。**組み立て直後にトリガを書くとノード群が二度と
   発火しない** (2026-09-24 実機: 0 s 後は永久に沈黙、0.5 s 後なら動く。NB の tick は前の tick の終わりから 0.1 s 後に来ることがある)
   ので、組み立てから `$itNativeWarmupSeconds` (3 s) は触らない。Resonite 側に重い読み出しが溜まっていても、この規則で複製は出る
   (2026-09-24 実機: 400 KB の読み出し 12 本と同時でも成功)。複製はトリガの約 2 s 後に現れる。
   カーネルの最初のガジェットがときどき沈黙する (結線は揃っていて、作り直すと動く。NB でも headless でも観測) ので、
   6 秒で現れなければガジェットを捨てて作り直し (2 回まで)、駄目なら雛形も忘れ、**同じ PDF を自前パネルで開く** (見えないよりよい)。
   **雛形の出し直し** (2026-09-24 実機): ユーザーが雛形をインベントリから出し直すと ID が変わり、古い ID のガジェットは黙って何も
   複製しない (3 回とも失敗して自前パネルに落ちた)。対策 = ガジェットを使う前に雛形を Depth 0 で読んで確かめ (`CheckTpl`、直近 60 s に
   確かめていれば省く。作り直しの前は必ず)、無ければ記録を消して走査 (Root Depth 1 + 入れ物 Depth 1) をすぐ回し (`FindTpl`、
   常駐監視でなくても回す)、見つかった雛形で続ける。20 s 見つからなければ自前パネル、その後 5 分は探しに行かず自前パネル。
   雛形を知らないときも標準ビューアをまず試す。実機: 古い ID のまま開いて、探し直し込み 17.5 s で標準ビューアに出た。
   **雛形の保管** (2026-09-24 ユーザー指示、`$ResoniteTabletStashTemplate` 既定 True): タブレットがあり、ワールドの雛形を知っていて、
   PDF を開いていないとき、雛形を 1 つ複製してタブレットの子に「PDF Template (Mathematica)」として**非表示** (isActive False) で置き、
   以後はそれを雛形に使う (ワールドの雛形より優先)。保管から作った複製も非表示なので、置くときに isActive True にする。
   タブレットをインベントリに保存すると保管も入り、引き継ぎ (根を Depth 1 で読む) で見つかる。保管が消されたら確かめで気づき、
   ワールドの雛形の記録 → 走査の順で探し直し、見つかった雛形から保管を作り直す。保管は走査の雛形候補から除く。
   実機: 保管 9.4 s、保管からの PDF 10.1 s (表示状態、1/2 ページで読み込み)、引き継ぎ直しで同じ保管を見つけた。
   **タブレットの読み取りを軽く** (保管を入れると根ごとは 583 KB): 候補の見張りは根を Depth 1 (部品込み、35 KB) で 1 回読んで
   Panel / 板 / 保管の ID を控え、以後は Panel だけ (178 KB) を読んで「接続」を見る。`ResoniteTabletAdopt[root]` も同じ 2 回の読み取り。
   **複製は出たのに中身が空 (ページ表示 1/-1)** = 文書を受け取れていない。2026-09-24: 配信 (L3) が約 1 MB を超えるファイルを途中で
   切っていた (待たない書き込みが溢れて黙って捨てられる。Resonite のログに `Failed gather ... Progress: 86.94`)。書き込みを
   `SocketWriteMessage[..., "Blocking" -> True]` に替えて解決 (3.7 MB の arXiv PDF で 1/13 表示を実機確認)。
   もう 1 つの原因は**ファイル名**: 日本語・空白・かぎ括弧を含む名前 (Eagle の PDF) を URL にそのまま入れると Resonite は
   パーセント符号化で要求し、配信側が戻さずに探して 404 だった (ログに Failed gather も出ない)。URL を作る側で符号化し、
   配信側で戻す (11.3 MB・174 ページの Eagle PDF で 1/174 を実機確認)。
4. **記録**: `ResoniteTabletStatus[]` の `PDFTemplate` / `NativeDocs` / `DocJobs` / `NativeLog` (段階の遷移、空振りした照会ごとの
   置き場の子の数と経過秒、失敗理由、Fallback)。同じ記録を `$ResoniteNativeLogFile`
   (既定 `%TEMP%\ResoniteRealtime\native_pdf.log`、タブ区切り: 時刻 / NB か headless / PID / ジョブ / 段階 / 試行 / 注記) にも追記する。
   ノートブックのカーネルでだけ失敗するとき (2026-09-24: headless では 11 s / 5 s で開き、NB では「複製が現れません」) に外から読むため。
   実機 (ScheduledTask 駆動、ユーザーのタブレットを引き継いで): 初回 11 s (組み立て + 暖機)、2 枚目から 5 s。
   `ResonitePDFViewerRemove[All]` と `ResoniteTabletCleanup[]` は標準ビューアの複製も消す (台帳から。名前では拾えない)。
   `ResoniteTabletCleanup[]` は置き場も消す。

## 雛形なしの文書ビューアと、インベントリに保存できるサムネイル一覧 (`ResoniteRealtime_docboard.wl`、2026-09-25)

**きっかけ (ユーザー報告)**: 「また PDF Viewer が元に戻っている」。ワールドを開き直すと標準ビューアの雛形もタブレットの保管も無くなり
(ノートブックから組み直したタブレットには保管が無い)、`native_pdf.log` は毎回「ワールドに雛形が見つかりません → 自前パネル」だった。
加えて「構成したサムネイルアレイをこのままインベントリに保存して再利用できるように。「接続」ボタンでタブレットが無くても PDF を
開けるように (雛形も内蔵)。接続時にワールドがプライベートか、オーナーが誰かをまず調べ、適切な PL に達していなければ開けないように」。

### 文書ビューア (`Mathematica PDF Viewer`)
ResoniteLink で `StaticDocument` (URL = 配信 URL) → `DocumentPageTexture` (PageIndex、0 始まり) → `SpriteProvider` → UIX `Image`
(PreserveAspect) を組む。**描くのは Resonite** (標準ビューアと同じ部品) なので Wolfram がページを画像にしない (324 ページでも待たない)。
操作列 `[<<] [<] n / N [>] [>>] [閉じる]` は**ワールドの中だけで動く**: `ButtonValueShift<int>` / `ButtonValueSet<int>` が PageIndex と
表示用の `ValueField<int>` Page (1 始まり) を同時に動かし (端で止まる)、`ValueTextFormatDriver<int>` が「n / N」を書き、
閉じるは `ButtonDestroy`。標準ビューアの雛形 (保管 → ワールド) があればこれまでどおり複製を使い、**無いとき / 複製に失敗したとき**に
これを組む (`$ResonitePDFLite`、既定 True。False なら従来の自前パネル)。`$ResonitePDFMode = "Lite"` なら常にこれ。
実機 (2026-09-25): 組み立て 5 s、Resonite が 2 s 後に `/a/<name>.pdf` を取りに来た。ボタンの参照は `IField<int>` に結ばれ、
Page を 2 にすると表示が「2 / 2」に変わった。**罠**: `DocumentAssetMetadata.PageCount` は RawOutput で ResoniteLink からは
`empty` としか読めない (読み込み確認には使えない)。同じ URL は Resonite がキャッシュするので、要求が来ないのは失敗とは限らない。

### サムネイル一覧をインベントリに保存して使い回す
- 構成: 根の子に `State` (Selected)、`Data` (`ValueField<string>` = 署名 + 行 JSON)、`Flux`、`Backing`、`Panel`
  (`Content` = 帯の画像 + 升目、見出し = 題名 / 状態 / [接続] [リスト] [閉じる]、`Veil` = 「接続を押すと表示」の覆い、既定は非表示)。
  Canvas の幅は見出しが入るよう最低 1100 px (`SW` = 帯の画像の幅)。
- **画像は Resonite の資産に**: 帯の JPEG を `importTexture2DFile` で取り込み (`local://…`)、StaticTexture2D の URL を差し替える
  (tick で応答を待たずに照合)。保存するとクラウドに上がるので Wolfram が居なくても画像は出る。取り込み後の状態欄
  「インベントリに保存できます (画像を取り込み済み)」。
- **行データは署名つき**: 題名 / ファイル / URI / Id / 機密度 (必ず数。不明は 1.0) と配置を JSON にし、HMAC-SHA256 (鍵 =
  `$ResoniteBoardKeyFile`、この PC の `$UserBaseDirectory/ApplicationData/ResoniteRealtime/board.key`、32 バイト) を 1 行目に付ける。
  Wolfram は一覧のファイルパスを開いてワールドに配るので、ワールドの誰かがパスや機密度を書き換えた一覧は**接続を断る**
  (升目は隠したまま、状態欄に理由)。別の PC で作った一覧も断る (鍵が違う)。
- **読み込み / 複製で隠す**: `Flux` = `OnLoaded` / `OnDuplicate` → `SetSlotActiveSelf(Content, false)` → `SetSlotActiveSelf(Veil, true)`。
  インベントリから出した一覧は Wolfram が確かめるまで画像も題名も見えない。実機 (2026-09-25): ワールド内で DuplicateSlot した複製は
  Content 非表示 / Veil 表示になった (OnLoaded はインベントリから出したときに同じ経路で動く想定。実機未確認)。
- **「接続」(Selected = -3)**: 常駐監視の走査 (Root + 入れ物 1 段) が台帳に無い `SourceVault Thumbnails` を候補にし、根を Depth 1
  (部品なし) で読んで State の ID を控え、以後 State を Depth 0 で見る (Root の走査で控えを捨てない。2026-09-25 実機の不具合)。
  -3 なら 0 に戻して引き継ぎ: 根を Depth 1 (部品込み) → Panel を Depth 1 → 署名を確かめて行を復元 (機密度は署名つきの値と、
  SourceVault が読めれば今の値の大きい方) → **ワールド情報を読み直す** (公開度 / ホスト / 所有者。自動モードでは接続より後の
  読み取りが来るまで「確認中」で見せない。30 s 来なければ厳しい側) → 表示上限以上の升目に覆い (「非表示 PL x」) を付けて
  Content を見せ、Veil を隠す。公開度が後で変わったら覆いを付け直す。確認中と覆いの升目は押しても開かない (状態欄に理由)。
  実機 (2026-09-25): 複製の候補化 11 s、「接続」から表示まで 21 s、8 行を復元。
- **雛形も内蔵**: 標準ビューアの雛形が分かっていれば、保管 (`PDF Template (Mathematica)`、非表示) をタブレットに無ければ一覧にも作る
  (元はワールドの雛形 / タブレットの保管 / 別の一覧の保管のどれでもよい)。雛形の出どころの順はタブレットの保管 → 一覧の保管 →
  ワールドの雛形。実機: ワールドの `PDF_Template.pdf` から一覧と、その複製の両方に保管ができた。
- **一覧から開いた PDF は、押した升目の前** (一覧の座標系で {升目の x, 0, -0.45}、一覧の親の子) に出る。
  標準ビューアの複製でも文書ビューアでも同じ (開くジョブの "Anchor")。
- **状態欄と経過表示** (2026-09-25 ユーザー指示「接続を押したのに何も変化がないとわかりにくい。タブレットと同様に時間経過を。
  サムネイルをクリックしたときも <ファイル名> を開いています、と出すステータスバーを」):
  見出しを 150 px にし、題名の下に帯 (`StatusBar`、UIX は 1 スロット 1 Graphic なので文字 `Status` と分ける) を置く。
  「接続」を押した瞬間に覆いの文字が「接続を要求しました / Mathematica の応答を待っています…」に変わる (ワールドの中だけ:
  `ButtonValueSet<string>` → 覆いの Text.Content。組み立ての 2 巡目 = 巡ごとの結線スロット `"WireSlots"`)。
  候補の一覧は監視の巡回 (1 対象 = 2 tick。対象が多いと 10-20 s 気付かなかった) に載せず、2 秒おきに State を直接読む。
  確認中は状態欄と覆いに「ワールドの公開範囲とオーナーを確認しています… n 秒」、終わると「接続済み [PL<…] (n 秒)」で、
  覆いの文字は元に戻す (押した跡のまま保存されない)。升目を押すと「「題名」を開いています… n 秒 (標準ビューアを複製しています /
  雛形を探しています / Resonite の文書表示を用意しています / ビューアを組み立てています)」→「「題名」を開きました (n 秒)」
  または「開けませんでした: 理由」。文は状態欄の幅で切るので大事な方を先に書く。
  実機: 見出しの並び Content / Title / StatusBar / Status / Connect / ToList / Close / Veil、「接続」の ButtonValueSet<string> が
  覆いの Text.Content (IField<string>) を指す。
- **タブレットの題名** [PL<…] は tick ごとに今の表示上限と比べて違うときだけ書き直す (`itSyncTitle`。2026-09-25: 題名 [PL<0.25 guest]
  と状態 ready (PL<1.00 Private) が食い違った。題名は表示上限が「変わったとき」しか書いておらず、再ロードや引き継ぎで古いまま残った)。
- 片付け: ワールド情報の仕掛け (`Mathematica World Info`) と複製ガジェットの置き場 (`Mathematica PDFs`) は、自分の物が組み上がって
  いれば Root の走査で他の同名を消す (2026-09-25 実機: カーネルを替えるたびに溜まり、それぞれ 4 つと 7 つあった)。

## FE を止めない: 重い仕事は作業用カーネル、送信は tick に分ける (2026-09-25)

**きっかけ (ユーザー報告、スクリーンショット)**: タブレットで「Eagle の計算と自然フォルダのサムネイルリスト」の後、ノートブックに
「動的評価の放棄 (動的更新を無効にする / 引き続き待機する)」と「処理中… ノートブックコンテンツをフォーマットしています」が出て、
VR の中からは閉じられなかった。**原因**: 監視の tick は割り込み型の評価 (ScheduledTask) で、tick の中で長く塞ぐと FE の Dynamic も
割り込めない。一覧の組み立てが 1 tick で Eagle の一覧 (3.5-11 s) → 行 → 画像の読み込みと貼り合わせ (289 件 ~40 s) → 2,100 通の送信を
していた。PDF を開くときのページ数 (130 MB で 5-8 s) も tick の中だった。

- **作業用カーネル** (`idWorker*`、`ResoniteTabletWorkerStatus[]` / `ResoniteTabletWorkerStop[]`、`$ResoniteTabletWorker` 既定 True):
  `LinkLaunch["WolframKernel -subkernel -noinit -wstp"]` を 1 つ常駐させる (サブカーネルの席)。**すぐ `LinkActivate`** (0.2 s):
  しないと `LinkReadyQ` は接続前から True を返し、最初の `LinkRead` がカーネルの立ち上がり (2-9 s。Resonite が動いていると遅い)
  まで tick を止めた。関数の定義は `Language`ExtendedFullDefinition` で 1 回送る (ロードごとに 1 回作る。読み直したら送り直す)。
  仕事は `EvaluatePacket` を書いて戻り、tick ごとに `LinkReadyQ` を見て **`LinkRead[link, Hold]`** で受ける。
  - 仕事: サムネイルの帯 (`idSheetWork`、キャッシュに無いときだけ。出来たら同じ ID で組み立て)、Eagle フォルダの一覧
    (`idEagleListWork`: 作業用カーネルで `SourceVault_eagle.wl` を読む。関数名は文字列で持ち込み、定義は送らない)、
    大きな PDF のページ数 (`idPageCount`: 5 MB 以下はその場、超えたら作業用カーネル。分かるまで 0、文書ビューアは 40 s まで待つ。
    数えられなかった 0 は覚えず 1 分後に数え直す)。
  - **罠 1**: 送る式に `Module` の変数が残ると、作業用カーネルでは未定義の記号 → 関数が合わず評価されずに戻る → こちらで評価すると
    重い仕事をこのカーネルでやってしまう (実測: 一覧取得がこちらで 10 s)。値は `With` で埋め込み、`idWorkSubmit` は Temporary な
    記号を含む式を断る。戻りが作業用の関数のままなら失敗扱い (ここで評価しない)。
  - **罠 2**: 2 MB の結果をリンクで受けると、Resonite が CPU を使っている間は作業用カーネルの書き出しが遅く、`LinkRead` が 8.8 s
    止まった。200 KB を超える結果は作業用カーネルが WXF ファイルに書き、ファイル名だけ返す (`idWorkerPack` / `idWorkerUnpack`)。
  - **罠 3**: 新しいカーネルで最初に PDF を読むと無害なメッセージが出る。`Check` で包むと数えられているのに 0 になった。
- **組み立ての送信を tick に分ける**: `itBuildSend` は Sender の間 `ResoniteRealtimeLink` を記録に差し替え (返事は待たない送信と
  同じ `<|"Sent", "MessageId"|>`)、`Drain` 相で tick ごとに `$itDrainSeconds` (0.3 s) ぶん送る。小さい組み立てはその tick で
  送り終わる。全部送ってから結線の getSlot。状態欄に「送っています (n / N)」。
- **小分けの仕事** (`idChunkSubmit`): Eagle の行 (`SourceVaultEagleSummaryRow`、289 件で 0.6-1.8 s) を tick ごとに 0.3 s ぶん。
- **計る**: tick の各段を `itTimed` で計り、1 s を超えた段を `$itState["SlowTicks"]` (最新 30、`ResoniteTabletWorkerStatus[]` でも
  見える) に残す。FE が止まったら、まずここを見る。
- **tick から Throw / Abort が抜けても監視は止まらない**: 自分が立てた Busy は `WithCleanup` で必ず戻し、抜けた Throw は
  `LastError` (TickThrow) に残す (それまでは Busy が True のまま残り、以後の tick が何もせず戻って黙って止まる作りだった)。
- 実機 (2026-09-25、Eagle SF フォルダ 289 件、headless + Resonite): 呼び出しはすぐ戻り (作業用カーネル)、一覧 22-33 s、
  組み立ての送信は ~7 tick に分かれた。tick の最長: 修正前 10-12 s → 2.1-3.1 s (最初の 1 件の行作りが SourceVault の冷えた
  キャッシュを読む 1 回の呼び出し。分けられない)。ノートブックの FE でダイアログが出ないかは未確認。

## PDF ビューア (自前パネル、`$ResonitePDFMode = "Panel"`、2026-09-22)

`ResonitePDFViewer[file | pages]`: Resonite のドキュメントビューア風の掴めるパネル (Canvas 1000x1400、0.6 m x 0.84 m)。
ヘッダ `[<<] [<] n/N [>] [>>] [閉じる]`、タイトル、ページ画像 (`StaticTexture2D` → `SpriteProvider` → `UIX.Image` PreserveAspect)。
ページ送りは StaticTexture2D の URL 差し替え (待たない送信) なので tick の中でも動く。一覧の ▶ と `ResoniteShowObject` の
PDF / 画像 / .nb はここに出る (タブレットの板はターンの図用)。▶ を押すたびに**新しいビューアが増え、前のは残る** (2026-09-22 ユーザー指示。
2 つ目以降は右下手前へ `$itPDFCascade` = {0.12, -0.05, -0.06} m ずつずらして並べる。掴んで並べ替えられる)。同じパネルへ読み込みたいときは
`"Reuse" -> True` (最新) か `"Reuse" -> root`。各ビューアの 閉じる はそのビューアだけ消す。`ResonitePDFViewerRemove[All]` で全部。
無いときの組み立ては応答待ちが要るので、非同期文脈では予約 (`Deferred`)。既定はアバターの正面 1.0 m、右へ 0.65 m (`"Offset"`)。
ボタンは監視 tick が `itHandlePDF` で読む。`ResonitePDFViewerPage["Next" | "+10" | n]` / `ResonitePDFViewerRemove[]`。

置き場所の注意 (2026-09-22 実機): 予約を tick が組むときはアバターの位置を問い合わせられない (待ちが要る) ので、タブレットの子として
置く。このとき同じ平面 (z = 0) に置くと、右隣の板 (Tablet Viewer、幅 1.2 m、x = 0.98) と重なって**板の裏に隠れ、押しても
何も出ないように見えた**。tick で組むガジェットは利用者側 (-z) に `$itFrontOffset` (0.35 m) だけ前に出す (PDF ビューアは
`{0.65, 0, -0.35}`)。また、ワールドから消えたビューア/一覧 (getSlot が 2 回続けて失敗) は台帳から外す (`GadgetGone`)。
残したままだと次の ▶ が `Reuse` で存在しないビューアに書き込み、何も出ない。組み立ての失敗は `ResoniteTabletStatus[]["LastError"]`
(`<|"Build", "Label", "Result"|>`) と `ResoniteTabletDeferred[]` の `Result` に残る。
