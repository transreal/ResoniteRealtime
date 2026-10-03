# ResoniteRealtime_flux API Reference

## 概要
ProtoFlux-generation gadget for ResoniteRealtime (same `ResoniteRealtime`` context; auto-loaded by ResoniteRealtime.wl). Reuses LLM calling, access levels and panel display from ResoniteRealtime_chat.
Pipeline: LLM writes → static check against node catalog → (flux-sdk build, if installed) → fix loop.
Two formats via `"Format"`:
- "Graph" (default): LLM writes a JSON graph description; validated, placed in the world via ResoniteLink (ResoniteRealtime_fluxlink), probes read back, fixed in loop. Runs directly in-world.
- other value (e.g. "ProtoGraph"): LLM writes a ProtoGraph module (Flux SDK text language, 1:1 with ProtoFlux); static check → flux-sdk build → .brson.
Catalog: references/protoflux-nodes.json (reflected from Resonite DLLs; regenerate with ResoniteRealtime_info/resources/tools/protoflux-nodes-dump.fsx + protoflux-catalog-build.wl). references/ is not published on GitHub; user builds catalog and protograph excerpt per setup.md. Language spec: references/protograph/protograph-skill.md.
flux-sdk (dotnet tool Papaltine.FluxSDK, `dotnet tool install --global --version 1.9.0 Papaltine.FluxSDK`) is optional: generation and static check work without it; build/.brson need it.
Related: https://github.com/transreal/ResoniteRealtime , https://github.com/transreal/ResoniteRealtime_chat , https://github.com/transreal/ResoniteRealtime_fluxlink

## Conventions (ProtoGraph mode prompt)
- Output exactly one ProtoGraph module in a ```protograph fence; first line `module <PascalCaseName>`; `in`/`out` for I/O, body in `where { ... }`.
- Use only catalog nodes or ProtoGraph keywords (if/while/for/switch/impulse/bind/sync/local/display/~read/~write/~trigger).
- Bind world objects via `in` (Source)/`out` (Drive), not by searching in body.
- WL integration: WebsocketTextMessageReceiver/Sender (one TAB-separated line, no JSON) or dynamic variables (~read/~write).
- Prefer pure dataflow in froox context; minimal impulses.
- Keywords exempt from unknown-node check: If, Display, ImpulseDisplay, Write, Read, Delay, Sequence, Impulse, AsyncImpulse, Operation, AsyncOperation.

## Graph JSON format (Format -> "Graph")
Top-level: {"name", "nodes":[...], "probes":[dynamic-variable paths]}. Node: {"id","type", "value"?, "ref"?, "inputs":{InName:id}, "impulses":{ImpulseName:id}}. Extracted from ```json fence (or first `{` to last `}`); must contain "nodes". Spec text: `$ResoniteFluxGraphSpec` (defined in ResoniteRealtime_fluxlink). Example:
```json
{"name":"SumDemo","nodes":[
 {"id":"a","type":"ValueInput<float>","value":1.0},
 {"id":"b","type":"ValueInput<float>","value":2.0},
 {"id":"sum","type":"ValueAdd<float>","inputs":{"A":"a","B":"b"}},
 {"id":"path","type":"ValueObjectInput<string>","value":"wl/sum"},
 {"id":"here","type":"ElementSource<Slot>","ref":"$root"},
 {"id":"w","type":"WriteOrCreateDynamicValueVariable<float>","inputs":{"Value":"sum","Path":"path","Target":"here"}},
 {"id":"tick","type":"LocalUpdate","impulses":{"OnUpdate":"w"}}],
 "probes":["wl/sum"]}
```
Generation loop (Graph): per round → LLM → extract JSON → ResoniteFluxValidateGraph → (if no errors and Place) ResoniteFluxPlace (removes previous placement via ResoniteFluxRemove) → check probes exist (Missing probes → diagnostic: check impulse chain from LocalUpdate to WriteOrCreateDynamicValueVariable, Target is ElementSource<Slot> ref "$root", Path is ValueObjectInput<string>) → break when no diagnostics. On success with Display, first probe shown as in-world 3D text via ResoniteFluxDisplay. Graph saved to `$ResoniteFluxProjects/<slug>/<name>.flux.json`.

## Variables
### $ResoniteFluxSDK
型: String | Automatic, 初期値: Automatic (unset)
Path to flux-sdk executable. If not an existing file: searches ~/.dotnet/tools then PATH (flux-sdk.exe on Windows); result cached.
### $ResoniteFluxProjects
型: String, 初期値: $packageDirectory/ResoniteFlux_projects
Root dir for generated projects (one subdir per slugified module name).

## Catalog
### ResoniteFluxCatalog[] → List[Association]
Node catalog (cached after first read of references/protoflux-nodes.json; {} if missing). Each: <|"Type","Name","Category","Inputs","Outputs","Impulses","Result"|>.
### ResoniteFluxCatalogSearch[query, n:30] → List[Association]
Word search (words ≥2 chars, case-insensitive, matched against Type+Name+Category); top n sorted by hit count desc then Type length asc. {} if no words/catalog.
### ResoniteFluxUnknownNodes[source] → List[String]
Names in ProtoGraph source (capitalized identifier followed by `(` or `<`) not in catalog (base type before `<`), keyword list, locally defined values (`X = ...`) or `use` lines.

## flux-sdk
### ResoniteFluxBuild[pgFile] → Association | Failure
Runs `flux-sdk build [-L <ResoniteDir>] pgFile` (-L omitted if env RESONITE_MANAGED_DATA_PATH set or default Steam Resonite dir absent).
→ <|"Success" (ExitCode 0 and .brson found), "ExitCode", "Output", "Diagnostics" (lines containing error/warning/expected), "Brson" (newest matching .brson path or None)|>
Failures: "NoFluxSDK", "NoFile", "Build".

## Generation
### ResoniteFluxGenerate[spec, opts]
LLM generates from natural-language spec, loops up to MaxRounds. Access level/privacy same rules as Chat: spec privacy > ResoniteAccessLevel[] → Failure["WorldAccessDenied"]; empty spec → Failure["EmptyPrompt"]; LLM Failure is returned as is.
→ Association
Options: "Format" -> "Graph" ("Graph" = JSON graph placed in world; otherwise ProtoGraph module), "Place" -> Automatic (Graph: place via ResoniteLink; Automatic = whether a link is connected), "Display" -> True (Graph: show first probe as in-world 3D text), "MaxRounds" -> 3, "Module" -> Automatic (ProtoGraph module name hint), "Model" -> Automatic, "Timeout" -> 300, "Build" -> Automatic (ProtoGraph: run flux-sdk build; Automatic = if flux-sdk found), "SourceVault" -> False (add SourceVault context to prompt), "Origin" -> "Notebook", "Hints" -> 40 (max catalog nodes by spec search; core-query nodes added: 60 in Graph, 40 in ProtoGraph)
Graph result: <|"Format"->"Graph","Graph","Source" (JSON string),"Module","File" (.flux.json),"Project","Placed","Probes","Display","Unknown"->{},"Build"->None,"Rounds","Diagnostics","Answer","PrivacyLevel","AccessLevel","Elapsed"|>
ProtoGraph result: <|"Source","Module","File" (.pg),"Project","Unknown","Build","Rounds","Diagnostics" ({} = success),"Answer","PrivacyLevel","AccessLevel","Elapsed"|> (no "Format" key)
ProtoGraph loop: unknown nodes → diagnostic; build only if no unknown nodes; build diagnostics (first 20) fed back.
例: ResoniteFluxGenerate["Add two floats and publish to wl/sum", "Format" -> "Graph", "MaxRounds" -> 2]

## Gadget
### ResoniteFluxChat[prompt, opts]
ResoniteChat for ProtoFlux: runs ResoniteFluxGenerate, shows result in notebook (via ClaudeCode`ClaudeWriteResponse when origin "Notebook") and in-world panel (AnswerText), saves project file; appends to chat log with Mode "ProtoFlux".
→ Association (same as ResoniteFluxGenerate) | Failure
Options: all ResoniteFluxGenerate options, plus "Notebook" -> Automatic (False = skip notebook write), "World" -> True (write to in-world panel)
In-world input prefixes "flux:", "pf:", "protoflux:" (case-insensitive) route to ProtoFlux mode (called from Chat poller).
### ResoniteFluxCell[] → NotebookObject | $Failed
Inserts a ResoniteFluxInput cell (Shift+Enter runs ResoniteFluxChat on its text) into InputNotebook[].

## Deploy
### ResoniteFluxDeploy[result, opts]
Deploy a generation result (ProtoGraph) into the world.
→ Association | Failure
Options: "Method" -> "Import" ("Import": needs result["Build"]["Brson"], returns <|"Method","Brson","Instruction"|> (drag & drop .brson into Resonite; wire in/out via Flux SDK UI I/O Assigner); Failure "NoBrson" if none. "ResoniteLink": experimental hot deploy via resources/tools/flux-deploy.fsx with `dotnet fsi`, needs ResoniteLink port ($iState "LinkPort") → <|"Method","ExitCode","Output"|>; Failures "NoScript","NotConnected","Deploy"), "Parent" -> "Flux" (parent slot name for ResoniteLink method). Other Method → Failure "BadMethod".