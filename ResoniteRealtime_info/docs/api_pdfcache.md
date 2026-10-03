# ResoniteRealtime_pdfcache API Reference

## 概要
Puts a temporary SHA-256-named copy of a PDF on a user-configured web server (via sftp) so friends can see it. This package extends the `ResoniteRealtime`` context. Repository: https://github.com/transreal/ResoniteRealtime_pdfcache. It is loaded by ResoniteRealtime.wl on every load, on top of the tablet and docboard parts (https://github.com/transreal/ResoniteRealtime_tablet, https://github.com/transreal/ResoniteRealtime_docboard).

Why: the standard viewer's StaticDocument.URL points to http://127.0.0.1:<port>/a/... . Each client fetches HTTP URL assets itself, so friends see nothing. The cache replaces that URL with a public one.

Behavior:
- Active only when the world is Private or Contacts, you are the owner, and the file is a PDF. This applies the first time the PDF is shown in the world.
- Public URL: `<$ResonitePDFCacheBaseURL>/<SHA-256 of content>.pdf`. This is the StaticDocument.URL that everyone reads.
- The name is the content hash, so the same PDF always gets the same URL and is uploaded once. URLs cannot be guessed from file names, and changed content never points at a stale copy.
- A HEAD request runs before uploading. If a file of the same size exists, it is used as is (uploaded earlier or by another PC). If the server has deleted it, it is re-uploaded. HEAD is re-run on each open, except for files verified within the last 60 s.
- While uploading, the viewer opens at 127.0.0.1 (the owner sees it at once). When the upload ends, the URL is swapped to the public one.
- The upload goes to `<hash>.pdf.part` and is then renamed, so partial files are never visible.
- A PDF whose PrivacyLevel exceeds `$ResonitePDFCacheMaxLevel` (default 0.5) is NOT uploaded (only the owner sees it). A PDF whose level cannot be read as a number is not uploaded either. The last 20 skipped PDFs are recorded (`ResonitePDFCacheStatus["Skipped"]`).
- All communication uses the sftp-capable curl bundled with Git for Windows. It is run via StartProcess and finished on tick (never waits).
- The password comes from NBAccess SystemCredential and is passed via curl stdin config, never on the command line. NBAccess: https://github.com/transreal/NBAccess.
- Only NBAccess touches SystemCredential (NBGetCredential / NBSetCredential / NBRemoveCredential / NBCredentialConfiguredQ).
- Copyright: forbid saving by non-owners in world settings. The URL is still visible in the inspector and fetchable by a browser, so run `ResonitePDFCacheClear[]` when finished.

Separation from other packages (e.g. https://github.com/transreal/SlideWorkflow):
- The server config lives only in this package's own settings file. It neither reads nor writes SlideWorkflow settings. No code dependency exists.
- Another package may use a different folder on the same server.
- Credential name defaults to `sftp://<user>@<host>`, i.e. per account.
- Same account → one saved password is shared by both packages.
- Different server or account → different name, saved separately.
- To separate packages with the same account, use `ResonitePDFCacheSetup[..., "Credential" -> "name"]` (only the name is stored in the settings file).
- `ResonitePDFCacheCredential[None]` with the default name also deletes the password of other packages using the same account. The return value (`"Note"`) says so.

Server settings:
- No server name, account, or password is in the source.
- Settings file: `$UserBaseDirectory/ApplicationData/ResoniteRealtime/pdfcache_server.json`, written by `ResonitePDFCacheSetup[upload, base]`.
- With no settings, no copy is made (only the owner sees it). The status line and `ResonitePDFCacheStatus[]` explain how to set up (guide shown once per session).

Typical setup:
1. `ResonitePDFCacheSetup["sftp://user@www.example.org/home/user/www/cache", "https://www.example.org/cache"]`
2. `ResonitePDFCacheCredential[]` (dialog; or `ResonitePDFCacheCredential["password"]`)
3. Open a PDF in the world. Copies are made automatically.

Internal per-key status flow (in ResonitePDFCacheStatus "Status"): Check → Checking → (Ready | Upload → Uploading → Check) ; Ready → Recheck → Rechecking after the verify interval ; Failed (retry via ResonitePDFCacheRetry, or automatic after the credential is saved) ; Removed.

## Variables

### $ResonitePDFCache
型: Boolean, 初期値: True
When the world is Private/Contacts and you are the owner, a temporary copy (`<SHA-256>.pdf`) is placed on the web server the first time a PDF is shown, and StaticDocument URL is set to it. False → no copy.

### $ResonitePDFCacheBaseURL
型: String | None, 初期値: value from the settings file, else None
URL prefix for reading copies (e.g. "https://www.example.org/cache"). None → no copies.

### $ResonitePDFCacheUploadURL
型: String | None, 初期値: value from the settings file, else None
sftp location where copies are written (e.g. "sftp://user@www.example.org/home/user/www/cache"). Password is saved via ResonitePDFCacheCredential[] through NBAccess.

### $ResonitePDFCacheMaxLevel
型: Number, 初期値: 0.5
PDFs with PrivacyLevel above this are not uploaded (only the owner sees them).

## Setup / Credential

### ResonitePDFCacheSetup[upload_String, base_String, opts]
Saves the server settings on this PC (settings file; not in source). upload = sftp write location, base = https URL that reads the same directory. Also sets `$ResonitePDFCacheUploadURL` / `$ResonitePDFCacheBaseURL` (trailing "/" of base trimmed) and re-enables the setup guide. Follow with ResonitePDFCacheCredential[].
→ Association (same as ResonitePDFCacheSetup[]) | Failure["PDFCacheSetup"]
Options: "Credential" -> Automatic (credential name = sftp://user@host, shared with other packages using the same account | "name" = package-specific name, passwords stored separately; the name is saved in the settings file)
Failures: upload not sftp://user@host/..., base not http(s)://..., password inside the URL (user:pass), invalid "Credential", settings file not writable.
例: ResonitePDFCacheSetup["sftp://user@www.example.org/home/user/www/cache", "https://www.example.org/cache", "Credential" -> "pdfcache-only"]

### ResonitePDFCacheSetup[] → Association
Current settings and guidance: <|"Configured", "UploadURL", "BaseURL", "ConfigFile", "Credential" (name or None), "CredentialShared" (True = account name shared with other packages, False = dedicated name, None = unconfigured), "PasswordSaved", "Next" (guide text)|>

### ResonitePDFCacheSetup[None] → Association
Deletes the settings file; sets both URL variables to None (no copies are made). Returns the ResonitePDFCacheSetup[] association.

### ResonitePDFCacheCredential[] → Association | $Canceled | Failure
Asks for the sftp password in a dialog (AuthenticationDialog, needs a front end) and saves it via NBAccess to SystemCredential (name = sftp://user@host unless overridden). Value is never in source or notebook. Returns <|"Credential", "Configured" -> True, "Shared"|>. Failure["PDFCacheCredential"] if unconfigured, NBAccess not loaded, or save fails; Failure["NoFrontEnd"] without a front end (use the password form).

### ResonitePDFCacheCredential[password_String] → Association | Failure
Saves the password directly (same return as the dialog form). "Shared" -> True when the name is the account name shared with other packages.

### ResonitePDFCacheCredential[None] → Association | Failure
Deletes the saved password. Returns <|"Credential", "Configured" -> False, "Shared"|>; if Shared, adds "Note" warning that other packages using the same account (e.g. SlideWorkflow) lost the password too.

## Status / Maintenance

### ResonitePDFCacheStatus[] → Association
<|hash -> <|"Status", "Title", "URL", "Bytes", "Error", "VerifiedSecondsAgo"|>|> for each copy this session. "Status" is one of Check, Checking, Recheck, Rechecking, Upload, Uploading, Ready, Failed, Removed. "Error" is None or a message. "VerifiedSecondsAgo" is None or an integer.

### ResonitePDFCacheStatus["Skipped"] → List
Last 20 PDFs not uploaded because PrivacyLevel > `$ResonitePDFCacheMaxLevel`. Each: <|"Title", "File", "PrivacyLevel", "Time"|>. (Empty if none.)

### ResonitePDFCacheRetry[] → List
Re-checks and re-uploads Failed copies (tick advances them). Returns their titles. Copies stopped for a missing password are re-sent automatically within 10 s of saving it with ResonitePDFCacheCredential[], so no call is needed. Authentication failures (wrong password) are not repeated automatically: re-save the password, then call ResonitePDFCacheRetry[] or reopen the PDF.

### ResonitePDFCacheList[] → List | Failure
Lists the names (`*.pdf`, `*.pdf.part`) on the server cache directory via sftp (waits). Failure when unconfigured, no curl, no password, or curl error.

### ResonitePDFCacheClear[opts]
Deletes the copies this PC uploaded (those in the ledger) from the server. Waits.
→ List (names deleted) | Failure
Options: "OlderThan" -> None (days; only ledger entries uploaded more than that many days ago)
例: ResonitePDFCacheClear["OlderThan" -> 7]

### ResonitePDFCacheClear[All] → List | Failure
Deletes all `*.pdf` (names from ResonitePDFCacheList[]) in the cache directory. Returns deleted names.

### ResonitePDFCacheClear[{hash, ...}] → List | Failure
Deletes the specified copies. Each element may be a hash or a name ending in ".pdf". Returns deleted names.

## UI
The "キャッシュ削除" button in the thumbnail-list header deletes all copies (`<SHA-256>.pdf` / `.part`) in the server cache regardless of which folder they came from. It does not wait: curl runs in the background (list → delete) and the tick picks up the result. Viewers that pointed at a copy return to the 127.0.0.1 URL. A second press only reports the running progress. The progress and result appear in the thumbnail-list status line. Timeout is 180 s.

## Notes
- curl is Git for Windows's sftp-capable curl, run with `-k`. Files whose paths contain non-ASCII or `[ ] { }` are first copied to `$TemporaryDirectory/ResoniteRealtime_pdfcache/<hash>.pdf`, so curl does not misread them (`--globoff` is also used).
- Exit code 67 from curl is treated as an authentication failure ("Auth" reason). A missing password gives reason "NoCredential" and is retried automatically every 10 s.
- After an upload, HEAD is run once more; if the file still cannot be seen at the public URL (size mismatch), the copy becomes Failed rather than re-uploading again.
- Skipped / failed copies set the status line message; errors also go to `$itState["LastError"]`.