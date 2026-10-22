# IntelliFrame frontend inputs

`inputs.json` holds the request body that the IntelliFrame frontend
(IntelliFrame-Frontend, `src/components/submission/submission-utils.ts`) posts to
IntelliFrame-API (`POST /intelliframe/base`, struct `RunIntelliFrame`), plus the
project block used by the report header. Key names are the API's. Units are US
customary, as listed below. The example holds the frontend's default inputs.

## Project metadata (report header only, not sent to the API)

| Field | Description |
|---|---|
| `project_name` | Project title |
| `project_location` | City, state |
| `project_reference` | Job number |
| `client_name` | Client |
| `design_report_date` | `MM/DD/YYYY` |
| `time` | `HH:MM:SS` |
| `revision_no.` | Integer revision number |

## Request body

| Field | Description | Accepted values |
|---|---|---|
| `purlin_types` | Purlin sections, indexed by `purlin_size_span_assignment` | Array of `section_name`s in `database/Purlins.csv`; the frontend sends one, e.g. `["Z8x2.5 060"]` |
| `purlin_spans` | Span length of each bay, in order (ft) | Array of numbers |
| `purlin_size_span_assignment` | Which entry of `purlin_types` is used in each span | Array of 1-based indices, same length as `purlin_spans` |
| `purlin_laps` | Lap length on each side of each interior support (ft) | Array of length `2 * (number of spans - 1)`; `[]` for a single span. The frontend sends lap length / 2 on each side |
| `purlin_spacing` | Purlin spacing (ft) | Number |
| `frame_flange_width` | Rafter flange width at the support (in.) | Number |
| `roof_slope` | Rise over run | Number, e.g. `0.0833` for 1:12 |
| `deck_type` | Roof deck, used for both the existing deck and the new deck on the IntelliFrame | Any `deck_name` in `database/Existing_Deck.csv` / `New_Deck.csv` or in PurlinLine's `database/Existing_Deck.csv` (e.g. `"Rdeck 22 ga"`, `"SSR Ultra-Dek 18 in. 24 ga"`) |
| `loading_direction` | Direction of applied pressure (the report runs both) | `"gravity"`, `"uplift"` |
| `intelli_frame_type` | IntelliFrame sub-purlin section | Any `section_name` in `database/IntelliFrameRF.csv` |
| `purlin_frame_connection` | How the purlin attaches to the frame | `"Clip-mounted"` (the only value the frontend sends), `"Direct"` |
| `analysis_type` | API only: existing roof alone, or with the retrofit (the report runs both) | `"existing"`, `"retrofit"` |
| `generate_report` | API only | `true`, `false` |

Optional, not sent by the frontend: `intelli_frame_material` with `E_ksi`,
`nu`, `Fy_ksi`, `Fu_ksi`. When it is absent, the IntelliFrame steel is
E = 29500 ksi, ν = 0.30, Fy = 55 ksi, Fu = 70 ksi, the value the API hard-codes.
The purlin steel is fixed at Fy = 50 ksi in `UI.existing_roof_UI_mapper`.

## Lap convention

For `n` spans there are `n - 1` interior supports. `purlin_laps` lists, for
each interior support from left to right, the lap length on the left side then
on the right side. Three spans therefore need four entries.

## IntelliFrame orientation

There is no input for it. `combine_intelli_frame_purlin_geometry` always places
the IntelliFrame with its top flange pointing the same way as the purlin top
flange, as the frontend draws it.

## Mapping to the Julia API (as IntelliFrame-API calls it)

```julia
purlin_line = UI.existing_roof_UI_mapper(
    purlin_spans, purlin_laps, purlin_spacing, roof_slope,
    purlin_data, deck_type, existing_deck_data, frame_flange_width,
    purlin_frame_connection, purlin_types,
    purlin_size_span_assignment, loading_direction)

intelli_frame_purlin_line = UI.retrofit_UI_mapper(
    purlin_line, intelli_frame_data, intelli_frame_type, deck_type, new_deck_data,
    deck_type, existing_deck_data,
    [(29500.0, 0.30, 55.0, 70.0)], loading_direction)
```

Key outputs for the frontend: `applied_pressure` (ksi, multiply by
`1000 * 144` for psf), `failure_limit_state`, `failure_location` (in.), and the
deflected shape `model.inputs.z` / `model.outputs.v` (returned as `input_z`,
`output_v`).
