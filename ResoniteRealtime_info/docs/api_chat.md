# ResoniteRealtime_chat API Reference

## 概要
Chat gadget for Resonite: runs an LLM chat from a notebook cell (ResoniteInput) and shows answers in a world-side UIX panel built via ResoniteLink (L2 only, no world-side node work). Part of the ResoniteRealtime` context; ResoniteRealtime.wl auto-loads it. Repo: https://github.com/transreal/ResoniteRealtime_chat
Flow:
1. Notebook: ResoniteChat[prompt] / ResoniteChatCell[]. Prompt → LLM → answer written to notebook and to the world panel.
2. World: ResoniteChatGadget[] builds the panel. Type in the input field, press the send button (ButtonToggle → ValueField<bool>); the ResoniteChatStart[] ScheduledTask polling picks it up, calls the LLM, writes the answer to the panel. Inputs starting with "flux:" / "pf:" are routed to ResoniteFluxChat (ResoniteRealtime_flux) when available.
3. L1 bridge: "ask<TAB>question" from world ProtoFlux runs the same path (Origin "Bridge").
Dependencies (weakly coupled, load-order independent): claudecode (ClaudeQuerySync / ClaudeQueryBg / ClaudeWriteResponse / $ClaudePrivateModel), SourceVault (release contexts, SourceVaultKBAnswer), NBAccess (prompt privacy). Core ResoniteRealtime provides AddSlot/AddComponent/UpdateComponent/GetSlot/Board/ShowImage.

## Access levels
- Access level = display-cap PL by world access: $ResoniteWorldAccessLevels (Private 1.0, Contacts 0.5, ContactsPlus 0.25, Public 0.25).
- Non-owner worlds (not $ResoniteWorldOwner) are always 0.25. Default is the strict side: Public, non-owner.
- Default mode Automatic: the tablet monitor reads world info (Root child "Mathematica World Info": SessionInfoSource + ProtoFlux WorldSessionID) for access, host, and record owner; host = owner → owner. Manual via ResoniteAccessLevel[access, "Owner" -> ...]. ResoniteAccessLevel[Automatic] reverts.
- SourceVault release context: "resonite-public" (non-owner) or "resonite-" <> ToLowerCase[access] (0.25 / 1.0 caps). Contexts are registered once automatically (MaxPrivacyLevel = level).
- LLM PrivacyLevel = Max[prompt PL, context PL]. Prompt PL: Notebook origin → NBAccess (notebook required level, cell level); World/Bridge origin → world level if >0.25 else 0.
- PL > 0.5 → local LLM ($ClaudePrivateModel) required; if unset → Failure "PrivateModelNotConfigured" (fail-closed).
- If prompt PL > access level → Failure "WorldAccessDenied" without calling the LLM.

## Design notes
- No resident Dynamic polling; world input is watched by exactly one ScheduledTask (pair ResoniteChatStart / ResoniteChatStop).
- Tick never waits for ResoniteLink replies (async handlers can't run inside ScheduledTask): Idle sends getSlot ("Wait" -> False); AwaitSlot looks for a reply by sourceMessageId in ResoniteRealtimeLinkMessages; 10 s timeout counts as a poll failure. Writes inside ticks are non-waiting. The LLM call (ClaudeQueryBg) blocks the kernel while running.
- Don't touch the FrontEnd inside ScheduledTask/SocketListen callbacks (only image rendering uses UsingFrontEnd).
- Panel: Canvas size is in meters at scale 1, so Canvas = CanvasSize units and the Panel slot is scaled by PanelScale (CanvasSize*PanelScale = 1.2 x 0.8 m). UIX graphics need UI_UnlitMaterial / UI_TextUnlitMaterial (created per panel).
- Panel Alpha blend is kept, so the panel is translucent; "Backdrop" -> True adds an opaque quad but was observed to cover the panel (off by default).
- Showing figures on the board needs ResoniteRealtimeStart[] (HTTP image serving) or $ResoniteRealtimePublicBaseURL, else Failure "NoServer".
- Sending uses a Button + ButtonToggle → ValueField<bool> (Checkbox alone does not respond to clicks).
- Errors are returned as Failure (via iFailure); tags include NotConnected, NoGadget, NoMemberId, EmptyPrompt, WorldAccessDenied, PrivateModelNotConfigured, NoClaudeCode, LLM, NoServer, Timeout.
- Panel structure: <Name> (Grabbable, AI_GeneratedContent) ├ Panel (Canvas) └ VLayout: Title, Input (Image+Button+TextField+TextEditor, child Text), SendRow (Send button + SendLabel), Status, Answer; plus optional Chat Board (ResoniteRealtimeBoard).
- Placement "User": finds the user's root slot ("User ..." with UserRoot), uses the Head slot pose, places at eye position + forward*Distance in the root's parent frame, yaw-rotated to face the user. Falls back to "Position"/"Parent" if no user is found.
- For claudecode docs injection, keywords ("Resonite", "ResoniteLink", "ProtoFlux", "ProtoGraph", "ResoniteChat", "ResoniteFlux", "ワールド") are registered in $ClaudePackageKeywordMap["ResoniteRealtime"].
- Test hook: Private`$icQueryOverride = Function[{prompt, privacy}, "answer"] replaces the LLM call.

## Variables
### $ResoniteWorldAccess
型: String ("Private"|"Contacts"|"ContactsPlus"|"Public"), 初期値: "Public"
Access of the currently open world (strict side by default). Invalid values reset to "Public".
### $ResoniteWorldAccessLevels
型: Association, 初期値: <|"Private" -> 1.0, "Contacts" -> 0.5, "ContactsPlus" -> 0.25, "Public" -> 0.25|>
World access → access level (display-cap PL).
### $ResoniteWorldOwner
型: True|False, 初期値: False
True: world is yours (access table applies). False: always 0.25. Automatic mode sets it from the world; ResoniteAccessLevel[access, "Owner" -> ...] sets it manually.
### $ResoniteWorldAccessMode
型: Automatic|"Manual", 初期値: Automatic
Automatic: tablet monitor reads world access and owner. "Manual": set via ResoniteAccessLevel[access, ...]. ResoniteAccessLevel[Automatic] reverts.
### $ResoniteOwnerUserId
型: String ("U-...")|Automatic, 初期値: Automatic
If set, auto-detection treats the host as owner only when the host ID equals it. Automatic: host = world record owner → owner.

## Functions
### ResoniteAccessLevel[] → Real
Current world's access level (1.0 / 0.5 / 0.25).
### ResoniteAccessLevel[access, opts]
Sets $ResoniteWorldAccess (and $ResoniteWorldOwner if "Owner" is True/False), switches to Manual mode, returns the level. access: "Private"|"Contacts"|"ContactsPlus"|"Public".
→ Real
Options: "Owner" -> Automatic (True|False sets $ResoniteWorldOwner; non-owner is always 0.25)
例: ResoniteAccessLevel["Private", "Owner" -> True]
### ResoniteAccessLevel[Automatic] → Real
Back to Automatic mode; resets owner False / access "Public" (strict) until the world info is read again.
### ResoniteChat[prompt, opts]
Sends the prompt to the LLM; writes the answer to the notebook and the in-world panel.
→ <|"Answer", "PrivacyLevel", "AccessLevel", "Context", "Shown", "Evaluated"|> or Failure
Options: "Notebook" -> Automatic (False suppresses writing the answer to the notebook; written only for Origin "Notebook"), "World" -> True (show on panel), "SourceVault" -> Automatic (False disables SourceVault KB context), "Evaluate" -> False (evaluate the answer's first ```mathematica block; graphics go to the board, other results are appended as text; 120 s limit), "Model" -> Automatic, "Timeout" -> 180, "Origin" -> "Notebook" ("Notebook"|"World"|"Bridge")
Notes: Notebook origin uses ClaudeQuerySync; others use ClaudeQueryBg (no PrivacyLevel option; uses $ClaudePrivateModel when PL > 0.5). Appends to the log (ResoniteChatLog).
### ResoniteChatCell[] → NotebookObject
Inserts a ResoniteInput cell into the input notebook (Shift+Enter runs ResoniteChat); embeds the style in the notebook's StyleDefinitions. Returns $Failed if there is no notebook.
### ResoniteChatGadget[opts]
Builds the Chat panel in-world via ResoniteLink (input field / send button / answer / board). Requires ResoniteRealtimeLinkConnect first (else Failure "NotConnected").
→ Association of IDs (also stored as the gadget state): "Root", "Panel", "Input", "InputText", "Editor", "SendBox", "StatusText", "AnswerText", "TitleText", "Image"/"Text" materials, "Board" (if enabled), "User" (if placed by user), "Backdrop" (if enabled), "Name", "Created"
Options: "Placement" -> "User" ("User"|"World"), "Distance" -> 1.5 (m in front of the avatar), "Height" -> Automatic (eye height - 0.25 m; a number = height from the feet), "User" -> Automatic (substring of the user name), "Position" -> {0, 1.4, 1.5} (used when Placement is "World" or the user is not found), "Parent" -> "Root" (same condition), "Name" -> "Mathematica Chat", "CanvasSize" -> {1200, 800} (units), "PanelScale" -> 0.001 (m/unit), "FontSize" -> 28, "Board" -> True (also create the figure board), "Backdrop" -> False (opaque quad behind the panel; experimental)
### ResoniteChatAttach[ids_Association] → Association
Adopts a panel made by another kernel (the return value of ResoniteChatGadget; must contain "Root"); registers its "Board" too.
### ResoniteChatRemoveGadget[] 
Stops monitoring and removes the in-world Chat panel (and its board record). Returns the removal response, or None if there is no gadget.
### ResoniteChatStart[opts] → TaskObject
Starts the single ScheduledTask that polls the panel input and registers the L1 "ask" handler (ResoniteRealtimeOn["ask", ...]). Replaces any existing task. Failure "NoGadget" if no panel.
Options: "PollInterval" -> 1.5 (seconds), "Evaluate" -> False (evaluate code in answers, as ResoniteChat's "Evaluate")
### ResoniteChatStop[] → None
Removes the monitoring task, clears Busy/Pending, and unregisters the "ask" handler.
### ResoniteChatShow[text_String]
Writes the string as-is into the panel's answer field.
### ResoniteChatShow[expr]
Non-string expr: shows it as an image on the board (needs an image server: ResoniteRealtimeStart[] or $ResoniteRealtimePublicBaseURL; else Failure "NoServer").
### ResoniteChatLog[n_Integer: 20] → List
Last n conversation records <|"Time", "Origin", "Prompt", "Answer", "PrivacyLevel", "AccessLevel"|>.
### ResoniteChatStatus[] → Association
State: "WorldAccess", "AccessLevel", "ReleaseContext", "Gadget" (root ID or None), "Listening", "PollInterval", "Busy", "PollFailures", "LinkConnected", "ClaudeCode", "SourceVault", "Conversations", "LastError".