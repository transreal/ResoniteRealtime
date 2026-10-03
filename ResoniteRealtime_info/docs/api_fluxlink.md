# ResoniteRealtime_fluxlink API Reference

## 概要
Places a JSON graph description as ProtoFlux nodes in a Resonite world via ResoniteLink, wires them, and reads back results. It is part of the `ResoniteRealtime` context and is auto-loaded by ResoniteRealtime.wl.
Repository: https://github.com/transreal/ResoniteRealtime_fluxlink
Depends on ResoniteRealtime https://github.com/transreal/ResoniteRealtime, which provides `ResoniteRealtimeValue`, `ResoniteRealtimeRef`, `ResoniteFluxCatalog[]`, and the connection state.
Placed nodes execute immediately. Example: 1+2 writes 3 to a dynamic variable, and the result follows input changes.

## Verified behavior (Resonite 2026.9 / ResoniteLink 0.13)
- Nodes are ProtoFluxBindings components. A wrong type name gets no response (timeout).
  - Logic nodes: `[ProtoFluxBindings]FrooxEngine.ProtoFlux.Runtimes.Execution.Nodes.<Cat>.<Node><float>`
  - Core nodes: `[ProtoFluxBindings]FrooxEngine.FrooxEngine.ProtoFlux.CoreNodes.<Node><[FrooxEngine]FrooxEngine.Slot>`
- Inputs (SyncRef<INodeValueOutput<T>>) are references to the source node's component ID. For multi-output nodes (e.g. Unpack_Float3 X/Y/Z) they reference the member ID.
- Impulse outputs (OnUpdate, OnTrue, ...) are references to the destination node's component ID.
- Constants are the Value of ValueInput<T> / ValueObjectInput<string>.
- World slots/components use GlobalReference<T> (Reference → target ID) plus ElementSource<T> (Source → GlobalReference).
- Writing a dynamic variable needs a DynamicVariableSpace. Without one, OnNotFound fires and nothing happens.
- `DynamicValueVariableDriver<T>.Target` can be written as a reference to a member ID. The ValueFieldDrive node's drive target (Proxy) cannot be written via ResoniteLink.

## Graph description (Association / JSON)
Keys:
- name: short name
- nodes: list of node Associations
- probes: dynamic variable names read back after placement (they live in the root slot's space, default "wl")

Node keys:
- id: unique string
- type: a catalog Type with concrete type args, e.g. `ValueAdd<float>`
- value: constant (ValueInput / ValueObjectInput only; otherwise a warning and ignored)
- inputs: name → node id, or "id.Output" for a multi-output node
- impulses: name → destination node id
- ref: `"$root"` | `"$panel"` (Chat panel root) | `"$user"` (own avatar root) | a world ID. Only for ElementSource / ValueSource / ObjectValueSource / ReferenceSource.
- globals: name → constant, for inputs declared `global<T>` in the catalog (e.g. the Tag of DynamicImpulseReceiver). Placed as GlobalValue<T>.

Example:
```
{"name": "SumDemo",
 "nodes": [
  {"id": "a",    "type": "ValueInput<float>", "value": 1.0},
  {"id": "b",    "type": "ValueInput<float>", "value": 2.0},
  {"id": "sum",  "type": "ValueAdd<float>", "inputs": {"A": "a", "B": "b"}},
  {"id": "path", "type": "ValueObjectInput<string>", "value": "wl/sum"},
  {"id": "here", "type": "ElementSource<Slot>", "ref": "$root"},
  {"id": "w",    "type": "WriteOrCreateDynamicValueVariable<float>",
                 "inputs": {"Value": "sum", "Path": "path", "Target": "here"}},
  {"id": "tick", "type": "LocalUpdate", "impulses": {"OnUpdate": "w"}}],
 "probes": ["wl/sum"]}
```

## Type rules
- Primitive type args (used as is): float, int, bool, string, double, long, uint, ulong, byte, sbyte, short, ushort, char, decimal, float2/3/4, int2/3/4, uint2/3/4, double2/3/4, floatQ, doubleQ, color, colorX, bool2/3/4, float2x2, float3x3, float4x4, DateTime, TimeSpan, Uri.
- Type args starting with `[` pass through. Other names (Slot, User, ...) are qualified as `[FrooxEngine]FrooxEngine.<name>`. Nested `A<B,C>` is handled recursively.
- Object types: string, Uri, `[..]` types, and anything not in the primitive list (Slot, User, ...). Value-type nodes with object args are rejected by validation, so use Object variants. Example: "Failed to resolve type" for WriteOrCreateDynamicValueVariable<string>.
  - ValueInput → ValueObjectInput
  - ValueSource → ObjectValueSource
  - DynamicValueVariable → DynamicObjectVariable
  - ValueFieldDrive → ObjectFieldDrive
  - ValueWrite → ObjectWrite
- Constants via ValueInput<T> are typed as follows:
  - float/double → N
  - int/long/uint/byte/short → Round
  - bool → TrueQ
  - string → ToString
  - float3/float2 → N
  - float4/floatQ → {x,y,z,w}
  - colorX/color → ColorQ as is, else `RGBColor @@ v`

## Functions

### ResoniteFluxBindingType[type_String] → String | None
Builds the ProtoFluxBindings component type name from a catalog type, e.g. "ValueAdd<float>". Returns None if the base type is not in the catalog.

### ResoniteFluxValidateGraph[graph_Association] → <|"OK","Errors","Warnings","Nodes"|>
Validates the graph description. "Nodes" maps id → catalog entry.
Errors: empty nodes, duplicate ids, type not in catalog, missing type args for a generic type, object type args on a Value-type node, unknown input/impulse names, undefined source/destination node.
Warnings: value on a non-Input node, ref on a non-Source node, empty probes.

### ResoniteFluxPlace[graph, opts]
Places and wires the graph in the world. It validates first, then creates the root slot, DynamicVariableSpace and AI_GeneratedContent. Pass 1 creates node slots and bodies, pass 2 wires them. If probes exist, it waits 1.5 s and then reads them back. Slot layout is x = Spacing[[1]]*depth, y = -Spacing[[2]]*row. On failure it removes the half-built root slot.
→ <|"Root","Parent","Name","Nodes","Slots","Errors","ProbeNames","Graph","Probes"|> or Failure
"Nodes" maps id → component ID, "Slots" maps id → slot ID, and "Errors" lists wiring failures. "Probes" is present only if probes is non-empty. Failure tags: "NotConnected", "InvalidGraph", "NoOutput".
Options: "Parent" -> Automatic (slot ID string; Automatic = Chat panel root, else in front of the user, else Root), "Position" -> Automatic ({0,0,0} when Parent is given; {-1.6,0.3,0} for the Chat panel; else in front of the user or {0,1.2,1.5}), "Name" -> Automatic ("Flux <name>"), "Spacing" -> {0.35, 0.25} (x per depth, y per row), "SpaceName" -> "wl" (DynamicVariableSpace name)

### ResoniteFluxProbe[placed_Association] → Association
Reads back the dynamic variables in placed["ProbeNames"] by scanning the DynamicValueVariable / DynamicReferenceVariable components under the root. Returns <|name -> value|>. The value is Missing["NotFound"] if not found. Returns <||> if the slot cannot be read.

### ResoniteFluxRemove[placed_Association]
Deletes the root slot of the placed graph.
→ result of ResoniteRealtimeRemoveSlot

### ResoniteFluxDisplay[placed, var_String, opts]
Shows the dynamic variable var (one of the probes) as 3D text in the world. A string variable is driven directly. A numeric variable gets a converter graph (ReadDynamicValueVariable → ToString_* → WriteOrCreateDynamicObjectVariable<string> into `<var>_text`, placed at {0.9,0,0}). A DynamicValueVariableDriver<string> then drives TextRenderer.Text.
→ <|"Slot","Text","Variable","Type","Converter"|> or Failure
"Converter" is the Place result, or None for string. Failure tags: "NotConnected", "NoMemberId", "NoToString".
Options: "Position" -> {0, 0.4, 0}, "Scale" -> 0.3 (uniform), "Color" -> RGBColor[1, 0.9, 0.2, 1], "Type" -> Automatic (variable type; inferred from the graph's writer node, "float" if unknown)
ToString nodes by type: int → ToString_Int, float → ToString_Float, bool → ToString_Bool, double → ToString_Double, long → ToString_Long, float3 → ToString_Float3, float2 → ToString_Float2, colorX → ToString_ColorX. Other types fail with "NoToString".

### ResoniteFluxDrive[placed, var_String, targetMemberId_String, type_String : "float"] → String | Failure
Adds a DynamicValueVariableDriver<type> to the root slot. It drives the world field (member ID) with dynamic variable var. Returns the component ID, or the Failure of the add. Failure "NotConnected" if there is no connection.
例: ResoniteFluxDrive[placed, "wl/x", memberId, "float3"]

## Variables

### $ResoniteFluxGraphSpec
型: String, 初期値: spec text (Japanese)
Graph description spec to pass to an LLM. It covers the JSON format, conventions and limits:
- Output one JSON in a ```json fence.
- Constants must be ValueInput<T> / ValueObjectInput<string> nodes referenced from inputs, never numbers written directly in inputs.
- Use Object variants for string / Uri / Slot / User.
- Convert numbers to text with ToString_Int / ToString_Float (input V).
- Start impulse chains with LocalUpdate (every frame), SecondsTimer (Interval input), FireOnTrue (condition) or DynamicImpulseReceiver (external).
- Always write results with WriteOrCreateDynamicValueVariable<T> to the dynamic variable "wl/<name>" (Target = ElementSource<Slot> with ref "$root", Path = ValueObjectInput<string>), and list the name in probes.
- At most 40 nodes. Do not invent node types, input names or impulse names that are not in the catalog.

## Typical flow
1. Connect with ResoniteRealtime.
2. `placed = ResoniteFluxPlace[graph]` (validate first with ResoniteFluxValidateGraph if needed).
3. `ResoniteFluxProbe[placed]` to read results.
4. `ResoniteFluxDisplay[placed, "wl/sum"]` to show them in the world.
5. `ResoniteFluxRemove[placed]` to clean up.