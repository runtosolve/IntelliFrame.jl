# IntelliFrame frontend inputs

`inputs.json` is the contract between the web frontend and the Julia backend.
The frontend writes it; the backend reads it and maps each field onto the
arguments of `UI.existing_roof_UI_mapper` and `UI.retrofit_UI_mapper`.
All values are US customary units. Unit suffixes are part of the key names.

## Project metadata (report header only)

| Field | Description |
|---|---|
| `project_name` | Project title |
| `project_location` | City, state |
| `project_reference` | Job number |
| `client_name` | Client |
| `design_report_date` | `MM/DD/YYYY` |
| `time` | `HH:MM:SS` |
| `revision_no.` | Integer revision number |

## Design settings

| Field | Description | Accepted values |
|---|---|---|
| `design_method` | Design standard method | `"ASD"`, `"LRFD"` |
| `loading_direction` | Direction of applied pressure | `"gravity"`, `"uplift"` |

## Existing roof

| Field | Description | Accepted values |
|---|---|---|
| `purlin_spans_ft` | Span length of each bay, in order | Array of numbers, one per span |
| `purlin_type_1` | First purlin section | Any `section_name` in `database/Purlins.csv`, e.g. `"Z8x2.5 060"`, `"C8x2.5 060"` |
| `purlin_type_2` | Second purlin section | Any `section_name` in `database/Purlins.csv`, or `"none"` |
| `purlin_size_span_assignment` | Which purlin type is used in each span | Array of `1` or `2`, same length as `purlin_spans_ft` |
| `purlin_laps_ft` | Lap length on each side of each interior support | Array of length `2 * (number of spans - 1)`; empty `[]` for a single span |
| `purlin_spacing_ft` | Purlin spacing | Number |
| `roof_slope` | Rise over run | Number, e.g. `0.0833` for 1:12 |
| `frame_flange_width_in` | Rafter flange width at the support | Number |
| `purlin_frame_connection` | How the purlin attaches to the frame | `"Clip-mounted"`, `"Direct"` |
| `existing_deck_type` | Existing roof deck | Any `deck_name` in `database/Existing_Deck.csv` |

## Retrofit

| Field | Description | Accepted values |
|---|---|---|
| `intelli_frame_type` | IntelliFrame sub-purlin section | Any `section_name` in `database/IntelliFrameRF.csv` |
| `intelli_frame_material.E_ksi` | Elastic modulus | Number, typically `29500.0` |
| `intelli_frame_material.nu` | Poisson's ratio | Number, typically `0.30` |
| `intelli_frame_material.Fy_ksi` | Yield stress | Number |
| `intelli_frame_material.Fu_ksi` | Tensile stress | Number |
| `new_deck_type` | New roof deck installed on the IntelliFrame | Any `deck_name` in `database/New_Deck.csv` |

## Lap convention

For `n` spans there are `n - 1` interior supports. `purlin_laps_ft` lists, for
each interior support from left to right, the lap length on the left side then
on the right side. Three spans therefore need four entries.

## Mapping to the Julia API

```julia
purlin_line = UI.existing_roof_UI_mapper(
    Tuple(purlin_spans_ft), Tuple(purlin_laps_ft), purlin_spacing_ft, roof_slope,
    purlin_data, existing_deck_type, existing_deck_data, frame_flange_width_in,
    purlin_frame_connection, (purlin_type_1, purlin_type_2),
    Tuple(purlin_size_span_assignment), loading_direction)

intelli_frame_purlin_line = UI.retrofit_UI_mapper(
    purlin_line, intelli_frame_data, intelli_frame_type, new_deck_type, new_deck_data,
    existing_deck_type, existing_deck_data,
    [(E_ksi, nu, Fy_ksi, Fu_ksi)], loading_direction)
```

Key outputs for the frontend: `applied_pressure` (ksi, multiply by
`1000 * 144` for psf), `failure_limit_state`, and `failure_location`.
