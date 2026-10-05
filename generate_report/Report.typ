// IRF (IntelliFrame) purlin retrofit report -- allowable roof pressure, governing limit state, failure location and
// maximum deflection of the existing purlin line and of the IntelliFrame retrofit, for gravity and uplift.
// Data: ../frontend_output/inputs.json, capacity_results.json, cfsm_local_buckling.json and figures/**, all written by
// IntelliFrame_cFSM.run_all_calculations (see test/working_code.jl).
// Compile from the repository root:  typst compile --root . generate_report/Report.typ
//
// Chapter order follows the web app modules: Project, Build, Methods, Existing Roof Analysis (Gravity, Uplift),
// Retrofitted Roof Analysis (Gravity, Uplift), Summary.

#let inputs = json("../frontend_output/inputs.json")
#let cap    = json("capacity_results.json")     // allowable pressures, existing vs. retrofit
#let cfsm   = json("cfsm_local_buckling.json")  // bare-IntelliFrame local buckling (Methods)
#let s      = cfsm.specimen
#let ln     = cap.line

// ─── FORMAT HELPERS ────────────────────────────────────────────────
#let _u(it) = text(size: 0.85em, it)

// 3 significant figures with trailing zeros kept (30 → "30.0", 1.5 → "1.50")
#let _fmt3(x) = {
  if x == none { [---] }
  else if x == 0 { [0] }
  else {
    let mag = calc.floor(calc.log(calc.abs(x), base: 10))
    let d = calc.min(3, calc.max(0, 2 - mag))
    let rounded = calc.round(x, digits: d)
    let sign = if rounded < 0 { "-" } else { "" }
    let parts = str(calc.abs(rounded)).split(".")
    let fp = if parts.len() > 1 { parts.at(1) } else { "" }
    while fp.len() < d { fp = fp + "0" }
    [#(sign + parts.at(0) + if d > 0 { "." + fp } else { "" })]
  }
}

// fixed number of decimals
#let _fix(x, d: 3) = {
  if x == none { [---] }
  else {
    let rounded = calc.round(x, digits: d)
    let sign = if rounded < 0 { "-" } else { "" }
    let parts = str(calc.abs(rounded)).split(".")
    let fp = if parts.len() > 1 { parts.at(1) } else { "" }
    while fp.len() < d { fp = fp + "0" }
    [#(sign + parts.at(0) + if d > 0 { "." + fp } else { "" })]
  }
}

#let _ft(x) = [#_fix(x, d: 1) ft]
#let _psf(x) = [*#_fix(x, d: 1) psf*]
#let _Lratio(r) = [L/#calc.round(r)]
#let _improve(a, b) = [#_fix((b / a - 1) * 100, d: 0) %]
#let _Mcrl = $M_(c r ell)$

// one results table for a load case
#let _case_table(r, caption) = figure(
  kind: table,
  caption: caption,
  table(
    columns: (2fr, 3fr),
    stroke: none,
    inset: (x: 5pt, y: 4pt),
    table.hline(),
    [*Allowable roof pressure*],      [#_psf(r.allowable_pressure_psf) (#_fix(r.allowable_line_load_plf, d: 0) plf on the purlin)],
    [*Governing limit state*],        [#r.limit_state],
    [*Failure location*],             [#_ft(r.failure_location_ft) from the left end, #r.failure_location],
    [*Maximum vertical deflection*],  [#_fix(r.max_deflection_in, d: 2) in. (#_Lratio(r.max_deflection_ratio)) in span #r.max_deflection_span, #_ft(r.max_deflection_location_ft) from the left end],
    table.hline(),
  ),
)

#let _case(r, fig, title, caption) = [
  == #title
  #_case_table(r, caption)
  #figure(
    image(fig, width: 100%),
    caption: [#caption -- demand-to-capacity ratios at the allowable pressure (star: governing location), strong-axis moment against the allowable strength, and vertical deflection],
  )
]
// ───────────────────────────────────────────────────────────────────

#set page(
  paper: "us-letter",
  number-align: center,
  margin: (
  top: 1in,
  bottom: 1in,
))

#set par(
  justify: true,
  leading: 8pt
        )

#set heading(numbering: "1.")

#show outline.entry.where(
  level: 1
): it => {
  v(12pt, weak: true)
  strong(it)
}

#show heading: set block(above: 24pt, below: 12pt)

#set page(numbering: none)
#show math.frac: it => [#it.num #sym.slash #it.denom]

// Caption on top and left-aligned for all table figures
#show figure.where(kind: table): set figure.caption(position: top)
#show figure.where(kind: table): it => align(left, it)
#show table: set par(justify: false)

// ── FRONT PAGE ────────────────────────────────────────────────────────────────

#align(center)[
  #image("figures/IMETCO_Logo.png", width: 60%)
  \
  \
  \
  \

  #text(20pt, weight: "bold")[IRF Purlin Retrofit Analysis]\
  #v(4pt)



]

#v(50pt)

// Project details
#grid(
  columns: (150pt, 1fr),
  row-gutter: 15pt,
  [*Project Name:*],      [#inputs.project_name],
  [*Project Reference:*], [#inputs.project_reference],
  [*Project Location:*],  [#inputs.project_location],
  [*Client:*],            [#inputs.client_name],
  [*Design Report Date:*],[#inputs.design_report_date],
  [*Revision No.:*],      [#inputs.at("revision_no.")],
)

#v(1fr)

#pagebreak()
#set page(
  numbering: "1",
  header: context {
    set text(size: 8pt)
    [IRF Purlin Retrofit Analysis/#inputs.intelli_frame_type/Page #context counter(page).display() of #context counter(page).final().first()]
    line(length: 100%, stroke: 0.5pt)
  },
  footer: context {
    set text(size: 8pt)
    line(length: 100%, stroke: 0.5pt)
    grid(
      columns: (1fr, auto),
      align: (left + top, right + top),
      [#inputs.project_name (#inputs.project_reference)],
      [Rev. No.: #inputs.at("revision_no.")],
    )
  },
)
#outline(
  title: [Table of Contents],
  target: heading.where(outlined: true),
  indent: auto
)

#pagebreak()
#set text(size: 10pt)

// ════════════════════════════════════════════════════════════════════════════
= Project
// ════════════════════════════════════════════════════════════════════════════

#table(
  columns: (1fr, 2fr),
  stroke: none,
  inset: (x: 5pt, y: 4pt),
  table.hline(),
  [*Client Name*],         [#inputs.client_name],
  [*Project Name*],        [#inputs.project_name],
  [*Project Location*],    [#inputs.project_location],
  [*Project Reference*],   [#inputs.project_reference],
  [*Design Method*],       [#ln.design_code, AISI S100-16],
  [*Design Report Date*],  [#inputs.design_report_date],
  [*Time*],                [#inputs.time],
  [*Revision No.*],        [#inputs.at("revision_no.")],
  table.hline(),
)

This report gives the allowable roof pressure of the existing purlin line and of the same line after the IRF retrofit, for gravity and uplift loading. For each case it reports the limit state that governs, where along the line it governs, and the maximum vertical deflection at the allowable pressure.

// ════════════════════════════════════════════════════════════════════════════
= Build
// ════════════════════════════════════════════════════════════════════════════

== Existing roof

#figure(
  kind: table,
  caption: [Existing purlin line],
  table(
    columns: (1.4fr, 2fr),
    stroke: none,
    inset: (x: 5pt, y: 3.5pt),
    table.hline(),
    [Purlin],                       [#ln.purlin_types.at(0)#if ln.assignment.any(a => a == 2) [ and #ln.purlin_types.at(1)]],
    [Spans],                        [#ln.spans_ft.map(x => str(x)).join(" / ") ft (#ln.spans_ft.len() spans, #_fix(ln.spans_ft.sum(), d: 1) ft total)],
    [Purlin lap at each interior support], [#ln.laps_ft.at(0) ft each side of the support],
    [Purlin spacing],               [#ln.spacing_ft ft],
    [Roof slope],                   [#_fix(ln.roof_slope * 12, d: 1):12],
    [Existing roof deck],           [#ln.existing_deck],
    [Purlin-to-frame connection],   [#ln.purlin_frame_connection],
    [Frame flange width],           [#_fix(ln.frame_flange_width_in, d: 1) in.],
    table.hline(),
  ),
)

#figure(
  image(cap.profiles.span_configuration, width: 100%),
  caption: [Span configuration: purlins lapped over the interior frame supports, span lengths in ft, frame flange width #_fix(ln.frame_flange_width_in, d: 1) in. (horizontal to scale, vertical exaggerated 3×)],
)

#figure(
  image(cap.profiles.existing_purlin, width: 42%),
  caption: [Existing purlin, #ln.purlin_types.at(0)],
)

== IRF retrofit

#figure(
  kind: table,
  caption: [IntelliFrame and new roof],
  table(
    columns: (1.4fr, 2fr),
    stroke: none,
    inset: (x: 5pt, y: 3.5pt),
    table.hline(),
    [IntelliFrame section],         [#ln.intelli_frame],
    [Thickness $t$],                [#_fix(s.dimensions.t) in.],
    [Bottom flange / web / top flange / lip], [#_fix(s.dimensions.B_bottom, d: 2) / #_fix(s.dimensions.H, d: 2) / #_fix(s.dimensions.B_top, d: 2) / #_fix(s.dimensions.D, d: 2) in.],
    [Punch-out (height $times$ length)], [#_fix(s.punchout.height) $times$ #_fix(s.punchout.length) in.],
    [Steel],                        [$F_y$ = #_fix(cfsm.material.Fy, d: 0) ksi, $E$ = #_fix(cfsm.material.E, d: 0) ksi],
    [New roof deck],                [#ln.new_deck],
    [Attachment],                   [IntelliFrame screwed through the existing deck to the purlin top flange; new deck fastened to the IntelliFrame top flange],
    table.hline(),
  ),
)

#grid(
  columns: (1fr, 1.3fr),
  gutter: 10pt,
  align: horizon,
  figure(image(cap.profiles.intelliframe, width: 100%), caption: [IntelliFrame #ln.intelli_frame]),
  figure(image(cap.profiles.retrofit_assembly, width: 100%), caption: [Retrofit assembly: IntelliFrame on the existing purlin, between the existing and the new deck]),
)

== Purlin line segments

The line is analysed as one continuous member. Within the lap length on each side of an interior support the two overlapping purlins act together, so that segment is given a section with the combined thickness of the two purlins; every strength is calculated separately for each segment, and the lower of two adjacent segments' strengths is used where they meet.

#figure(
  kind: table,
  caption: [Segments along the purlin line, left to right],
  table(
    columns: (auto, auto, 2fr, auto, auto),
    stroke: none,
    inset: (x: 5pt, y: 3.5pt),
    table.hline(),
    table.header([*Segment*], [*Length*], [*Section*], [*t (in.)*], [*Type*], table.hline()),
    ..for sg in ln.segments { ([#sg.segment], [#_ft(sg.length_ft)], [#sg.section], [#_fix(sg.t)], [#if sg.lap [Lap (two purlins)] else [Span]]) },
    table.hline(),
  ),
)

// ════════════════════════════════════════════════════════════════════════════
= Methods
// ════════════════════════════════════════════════════════════════════════════

+ *Analysis.* The purlin line is solved as a continuous thin-walled beam under a uniform roof pressure, with the roof deck acting as continuous lateral and rotational bracing on the top flange (both decks in the retrofit). The free bottom flange is modelled separately as a beam-column. The analysis is second order, so lateral-torsional buckling is included in the demands.
+ *Strengths.* Section strengths follow AISI S100-16 (#ln.design_code): flexure by the Direct Strength Method with local, distortional and net-section (punch-out) effects, shear, torsion, and web crippling at the supports. In the retrofit the purlin and the IntelliFrame act as one section.
+ *Allowable pressure.* The pressure is increased until the governing demand-to-capacity ratio along the line reaches 1.0. The limit states checked are flexural + torsional interaction (H4.2), biaxial bending (H1.2), flexure + shear (H2.1), distortional buckling (F4) and web crippling (G5). The deflection is reported at that pressure.
+ *IntelliFrame local buckling.* For positive bending, the local buckling moment of the retrofit section is the *minimum* of two values: the value from the combined purlin + IntelliFrame model, and the value of the bare IntelliFrame found from its finite strip signature curve with the local half-wavelength identified by the constrained finite strip method (cFSM), converted to the combined section through the critical stress at the IntelliFrame top fiber. This is done for the section away from the punch-out and for the net section at the punch-out.

#figure(
  kind: table,
  caption: [IntelliFrame local buckling moment, positive bending (kip-in.) -- governing value per segment],
  table(
    columns: (auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
    align: (left, center, center, center, center, center, center),
    stroke: none,
    inset: (x: 4pt, y: 3.5pt),
    table.hline(),
    table.header(
      table.cell(rowspan: 2, align: horizon)[*Segment*], table.cell(colspan: 3)[*Away from punch-out*], table.cell(colspan: 3)[*At punch-out*],
      [combined], [bare (cFSM)], [*governing*], [combined], [bare (cFSM)], [*governing*],
      table.hline(),
    ),
    ..for lb in cap.local_buckling {
      ([#lb.segment], [#_fmt3(lb.gross.intelliframe)], [#_fmt3(lb.gross.cfsm_combined)], [*#_fmt3(lb.gross.governing)*],
       [#_fmt3(lb.hole.intelliframe)], [#_fmt3(lb.hole.cfsm_combined)], [*#_fmt3(lb.hole.governing)*])
    },
    table.hline(),
  ),
)

#text(8pt)[Bare IntelliFrame: #_Mcrl = #_fmt3(s.Mcrl_no_hole.Mcrl) kip-in. away from the punch-out and #_fmt3(s.Mcrl_hole.Mcrl) kip-in. at the punch-out, about its own centroid, before conversion to the combined section.]

#text(8pt)[The signature curves, buckling modes and full calculation details are given in the detailed report.]

#pagebreak()

// ════════════════════════════════════════════════════════════════════════════
= Existing Roof Analysis
// ════════════════════════════════════════════════════════════════════════════

#_case(cap.existing_gravity, cap.figures.existing_gravity, [Gravity], [Existing purlin line, gravity])
#pagebreak()
#_case(cap.existing_uplift, cap.figures.existing_uplift, [Uplift], [Existing purlin line, uplift])
#pagebreak()

// ════════════════════════════════════════════════════════════════════════════
= Retrofitted Roof Analysis
// ════════════════════════════════════════════════════════════════════════════

#_case(cap.retrofit_gravity, cap.figures.retrofit_gravity, [Gravity], [IRF retrofit, gravity])
#pagebreak()
#_case(cap.retrofit_uplift, cap.figures.retrofit_uplift, [Uplift], [IRF retrofit, uplift])

== Allowable flexural strengths

#figure(
  kind: table,
  caption: [Allowable strong-axis flexural strength $M_(n ell)$ (kip-in.) per segment, existing vs. retrofit],
  table(
    columns: (auto, 1fr, 1fr, 1fr, 1fr),
    align: (left, center, center, center, center),
    stroke: none,
    inset: (x: 5pt, y: 3.5pt),
    table.hline(),
    table.header(
      table.cell(rowspan: 2, align: horizon)[*Segment*], table.cell(colspan: 2)[*Existing purlin*], table.cell(colspan: 2)[*IRF retrofit*],
      [positive (+)], [negative (−)], [positive (+)], [negative (−)],
      table.hline(),
    ),
    ..for r in cap.segment_strengths {
      ([#r.segment], [#_fmt3(r.existing.Mnx_pos)], [#_fmt3(r.existing.Mnx_neg)], [#_fmt3(r.retrofit.Mnx_pos)], [#_fmt3(r.retrofit.Mnx_neg)])
    },
    table.hline(),
  ),
)

#pagebreak()

// ════════════════════════════════════════════════════════════════════════════
= Summary
// ════════════════════════════════════════════════════════════════════════════

#let eg = cap.existing_gravity
#let eu = cap.existing_uplift
#let rg = cap.retrofit_gravity
#let ru = cap.retrofit_uplift

#figure(
  kind: table,
  caption: [Allowable roof pressure and governing limit state],
  table(
    columns: (1.1fr, 1fr, 1fr, 1fr, 1fr),
    align: (left, center, center, center, center),
    stroke: none,
    inset: (x: 5pt, y: 4pt),
    table.hline(),
    table.header(
      [], table.cell(colspan: 2)[*Gravity*], table.cell(colspan: 2)[*Uplift*],
      [], [Existing], [IRF retrofit], [Existing], [IRF retrofit],
      table.hline(),
    ),
    [*Allowable pressure*],  [#_psf(eg.allowable_pressure_psf)], [#_psf(rg.allowable_pressure_psf)], [#_psf(eu.allowable_pressure_psf)], [#_psf(ru.allowable_pressure_psf)],
    [Improvement],           table.cell(colspan: 2, align: center)[+#_improve(eg.allowable_pressure_psf, rg.allowable_pressure_psf)], table.cell(colspan: 2, align: center)[+#_improve(eu.allowable_pressure_psf, ru.allowable_pressure_psf)],
    [Governing limit state], [#text(8.5pt)[#eg.limit_state]], [#text(8.5pt)[#rg.limit_state]], [#text(8.5pt)[#eu.limit_state]], [#text(8.5pt)[#ru.limit_state]],
    [Failure location],      [#text(8.5pt)[#eg.failure_location]], [#text(8.5pt)[#rg.failure_location]], [#text(8.5pt)[#eu.failure_location]], [#text(8.5pt)[#ru.failure_location]],
    [Max. deflection],       [#_fix(eg.max_deflection_in, d: 2) in. (#_Lratio(eg.max_deflection_ratio))], [#_fix(rg.max_deflection_in, d: 2) in. (#_Lratio(rg.max_deflection_ratio))], [#_fix(eu.max_deflection_in, d: 2) in. (#_Lratio(eu.max_deflection_ratio))], [#_fix(ru.max_deflection_in, d: 2) in. (#_Lratio(ru.max_deflection_ratio))],
    table.hline(),
  ),
)

#figure(
  image(cap.figures.summary, width: 52%),
  caption: [Allowable roof pressure, existing vs. IRF retrofit],
)

The IRF retrofit raises the allowable gravity pressure of the purlin line from #_fix(eg.allowable_pressure_psf, d: 1) psf to #_fix(rg.allowable_pressure_psf, d: 1) psf and the allowable uplift pressure from #_fix(eu.allowable_pressure_psf, d: 1) psf to #_fix(ru.allowable_pressure_psf, d: 1) psf. Deflections are reported at the allowable pressure; the IRF stiffens the line, so the retrofitted deflection at the higher pressure is #if rg.max_deflection_in < eg.max_deflection_in [still smaller than] else [comparable with] that of the existing line.

#v(1em)
#text(8pt)[_Reference:_ AISI S100-16, _North American Specification for the Design of Cold-Formed Steel Structural Members_. Analysis with PurlinLine.jl and IntelliFrame.jl (RunToSolve).]
