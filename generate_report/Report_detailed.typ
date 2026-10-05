// IRF (IntelliFrame) purlin retrofit -- DETAILED report: full design and calculation record behind Report.typ
// (geometry, section properties, deck bracing, elastic buckling, AISI S100 strengths per segment, the bare-IntelliFrame
// cFSM local buckling study with signature curves and buckling modes, and the allowable-pressure analyses).
// Data: ../frontend_output/inputs.json, capacity_results.json, cfsm_local_buckling.json and figures/**, all written by
// IntelliFrame_cFSM.run_all_calculations (see test/working_code.jl).
// Compile from the repository root:  typst compile --root . generate_report/Report_detailed.typ
//
// Chapter order follows the web app modules: Project, Build, Methods, Existing Roof Analysis (Gravity, Uplift),
// Retrofitted Roof Analysis (Gravity, Uplift), Summary.

#let inputs = json("../frontend_output/inputs.json")
#let cap    = json("capacity_results.json")
#let cfsm   = json("cfsm_local_buckling.json")
#let s      = cfsm.specimen
#let ln     = cap.line
#let det    = cap.detail

// ─── FORMAT HELPERS ────────────────────────────────────────────────
#let _u(it) = text(size: 0.85em, it)

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

#let _sci(x) = if x == none { [---] } else if x == 0 { [0] } else {
  let e = calc.floor(calc.log(calc.abs(x), base: 10))
  [#_fix(x / calc.pow(10, e), d: 2)$times$10#super[#e]]
}

#let _ft(x) = [#_fix(x, d: 1) ft]
#let _psf(x) = [*#_fix(x, d: 1) psf*]
#let _Lratio(r) = [L/#calc.round(r)]
#let _improve(a, b) = [#_fix((b / a - 1) * 100, d: 0) %]
#let _na(n, a) = [#_fmt3(n) (#_fmt3(a))]   // nominal (allowable)
#let _Mcrl = $M_(c r ell)$
#let _Lcrl = $L_(c r ell)$

// deck details tuple as stored by PurlinLine: ("screw-fastened", deck t, fastener spacing, fastener diameter, Fss) or ("vertical leg standing seam", kϕ)
#let _deck(d) = if d.at(0) == "screw-fastened" [screw-fastened; deck $t$ = #d.at(1) in., fasteners #d.at(2) in. o.c., #d.at(3) in. diameter, $F_(s s)$ = #d.at(4) kip] else [#d.join(", ")]

#let _method_long = (
  "signature":   [the first L-dominated local minimum (trough) of the signature curve inside $[0.5 W, 2 W]$],
  "cFSM-Lcrl":   [no L-dominated trough of the signature curve inside $[0.5 W, 2 W]$ -- $L_(c r ell)$ is the minimum of the cFSM pure-local curve and $M_(c r ell)$ is the signature curve at that half-wavelength],
  "hole-length": [the punch-out length $L_"hole"$ is shorter than the true $L_(c r ell)$ of the net section -- $M_(c r ell)$ is the net-section signature curve at $L = L_"hole"$],
)
#let _ml(k) = _method_long.at(k, default: [#k])

// generic "stroke: none" table figure
#let _tbl(caption, cols, header, rows, size: 9pt, align: auto) = figure(
  kind: table,
  caption: caption,
  text(size: size, table(
    columns: cols,
    align: align,
    stroke: none,
    inset: (x: 4pt, y: 3.5pt),
    table.hline(),
    table.header(..header, table.hline()),
    ..rows,
    table.hline(),
  )),
)

// case results (same as the client report)
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
    caption: [#caption -- demand-to-capacity ratios of every limit state at the allowable pressure (star: governing location), strong-axis moment $M_x$ against the allowable strength $M_(n ell)$ along the line, and vertical deflection],
  )
]

// full cFSM model table
#let _model_table(m, caption, hole: false) = figure(
  kind: table,
  caption: caption,
  table(
    columns: (2.4fr, auto, 1fr),
    stroke: none,
    inset: (x: 5pt, y: 3.5pt),
    table.hline(),
    table.header([*Quantity*], [*Value*], [*Unit*], table.hline()),
    [*Reported elastic local buckling moment #_Mcrl*], [*#_fmt3(m.Mcrl)*], [#_u[kip-in.]],
    [Half-wavelength #_Lcrl],                          [#_fix(m.Lcrl)],      [#_u[in.]],
    [$L_(c r ell) \/ W$],                              [#_fix(m.Lcrl_over_W, d: 2)], [],
    [Widest flat element $W$],                        [#_fix(m.W)],         [#_u[in.]],
    table.cell(colspan: 3)[#text(9pt)[Method: #_ml(m.method)]],
    table.hline(stroke: (dash: "dotted")),
    [cFSM pure-local minimum],                        [#_fmt3(m.cfsm_Mcrl)], [#_u[kip-in.]],
    [at half-wavelength],                             [#_fix(m.cfsm_Lcrl)],  [#_u[in.]],
    [Signature curve at the cFSM $L_(c r ell)$],      [#_fmt3(m.signature_at_cfsm_Lcrl)], [#_u[kip-in.]],
    [Signature / cFSM at the cFSM $L_(c r ell)$],      [#_fix(m.ratio_signature_over_cfsm)], [],
    ..if hole {(
      table.hline(stroke: (dash: "dotted")),
      [Punch-out length $L_"hole"$],                  [#_fix(m.L_hole)],     [#_u[in.]],
      [Signature curve at $L = L_"hole"$],            [#_fmt3(m.signature_at_L_hole)], [#_u[kip-in.]],
      [cFSM pure-local curve at $L = L_"hole"$],      [#_fmt3(m.cfsm_at_L_hole)], [#_u[kip-in.]],
      [True $L_(c r ell)$ of the net section],         [#_fix(m.true_Lcrl)], [#_u[in.]],
      [#_Mcrl at the true $L_(c r ell)$],             [#_fmt3(m.true_Mcrl)], [#_u[kip-in.]],
    )} else { () },
    table.hline(stroke: (dash: "dotted")),
    [Mode participation at $L_(c r ell)$: G / D / L / O], [#_fix(m.participation.G, d: 1) / #_fix(m.participation.D, d: 1) / #_fix(m.participation.L, d: 1) / #_fix(m.participation.O, d: 1)], [%],
    ..for t in m.rejected_troughs {(
      [Rejected trough, #t.dominant-dominated (G/D/L/O = #_fix(t.participation.G, d: 0)/#_fix(t.participation.D, d: 0)/#_fix(t.participation.L, d: 0)/#_fix(t.participation.O, d: 0) %)],
      [#_fmt3(t.M) at #_fix(t.L, d: 2) in.], [#_u[kip-in.]],
    )},
    table.hline(stroke: (dash: "dotted")),
    [First-yield moment $M_y = F_y S_(min)$ (bare IntelliFrame)], [#_fmt3(m.My)], [#_u[kip-in.]],
    [#_Mcrl$\/ M_y$],                                  [#_fix(m.Mcrl_over_My, d: 2)], [],
    [Local slenderness $lambda_ell = sqrt(M_y \/ M_(c r ell))$], [#_fix(m.lambda_l)], [],
    table.hline(),
  ),
)

// per-segment tables shared by the two systems
#let _props_table(segs, caption, net: false) = _tbl(caption,
  (auto, auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  ([*Seg.*], [*Length*], [*$A$ (in.²)*], [*$y_c$ (in.)*], [*$I_(x x)$ (in.⁴)*], [*$I_(y y)$ (in.⁴)*], [*$I_(x y)$ (in.⁴)*], [*$J$ (in.⁴)*], [*$C_w$ (in.⁶)*]),
  for d in segs {
    let p = if net { d.net_properties } else { d.properties }
    ([#d.segment], [#_ft(d.length_ft)], [#_fmt3(p.A)], [#_fmt3(p.yc)], [#_fmt3(p.Ixx)], [#_fmt3(p.Iyy)], [#_fmt3(p.Ixy)], [#_fix(p.J, d: 5)], [#_fmt3(p.Cw)])
  },
  align: (left, left, center, center, center, center, center, center, center),
)

#let _buckling_table(segs, caption, retrofit: false) = _tbl(caption,
  if retrofit { (auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr) } else { (auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr) },
  if retrofit {
    ([*Seg.*], [*$M_(c r ell)^+$ ($L_(c r ell)$)*], [*$M_(c r ell,"hole")^+$*], [*$M_(c r ell)^-$*], [*$M_(c r d)^+$ ($L_(c r d)$)*], [*$M_(c r d,"hole")^+$*], [*$M_(c r d)^-$*], [*$M_y$*], [*$M_(y,"net")$*])
  } else {
    ([*Seg.*], [*$M_(c r ell)^+$ ($L_(c r ell)$)*], [*$M_(c r ell)^-$ ($L_(c r ell)$)*], [*$M_(c r d)^+$ ($L_(c r d)$)*], [*$M_(c r d)^-$*], [*$M_y^+$*], [*$M_y^-$*])
  },
  for d in segs {
    let b = d.buckling
    if retrofit {
      ([#d.segment], [#_fmt3(b.Mcrl_xx_pos) (#_fix(b.Lcrl_xx_pos, d: 1))], [#_fmt3(b.Mcrl_xx_net_pos)], [#_fmt3(b.Mcrl_xx_neg)],
       [#_fmt3(b.Mcrd_xx_pos) (#_fix(b.Lcrd_xx_pos, d: 1))], [#_fmt3(b.Mcrd_xx_net_pos)], [#_fmt3(b.Mcrd_xx_neg)], [#_fmt3(d.yield.My)], [#_fmt3(d.yield_net.My)])
    } else {
      ([#d.segment], [#_fmt3(b.Mcrl_xx_pos) (#_fix(b.Lcrl_xx_pos, d: 1))], [#_fmt3(b.Mcrl_xx_neg) (#_fix(b.Lcrl_xx_neg, d: 1))],
       [#_fmt3(b.Mcrd_xx_pos) (#_fix(b.Lcrd_xx_pos, d: 1))], [#_fmt3(b.Mcrd_xx_neg)], [#_fmt3(d.yield.My_pos)], [#_fmt3(d.yield.My_neg)])
    }
  },
  size: 8.5pt,
  align: (left, center, center, center, center, center, center, center, center),
)

#let _strength_table(segs, caption) = _tbl(caption,
  (auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  ([*Seg.*], [*$M_(n ell x)^+$*], [*$M_(n ell x)^-$*], [*$M_(n ell y)^+$*], [*$M_(n ell y)^-$*], [*$M_(n d)^+$*], [*$M_(n d)^-$*], [*$V_n$ (kip)*], [*$B_n$ (kip-in.²)*]),
  for d in segs {
    ([#d.segment], [#_na(d.flexure_xx.Mnl_pos, d.flexure_xx.eMnl_pos)], [#_na(d.flexure_xx.Mnl_neg, d.flexure_xx.eMnl_neg)],
     [#_na(d.flexure_yy.Mnl_pos, d.flexure_yy.eMnl_pos)], [#_na(d.flexure_yy.Mnl_neg, d.flexure_yy.eMnl_neg)],
     [#_na(d.distortional.Mnd_pos, d.distortional.eMnd_pos)], [#_na(d.distortional.Mnd_neg, d.distortional.eMnd_neg)],
     [#_na(d.shear.Vn, d.shear.eVn)], [#_na(d.torsion.Bn, d.torsion.eBn)])
  },
  size: 8.5pt,
  align: (left, center, center, center, center, center, center, center, center),
)

#let _wc_table(rows, caption) = _tbl(caption,
  (auto, auto, 1.4fr, 1fr, 1fr),
  ([*Support*], [*$z$*], [*Location*], [*Bearing $N$ (in.)*], [*Allowable $P_n$ (kip)*]),
  for w in rows { ([#w.support], [#_ft(w.z_ft)], [#w.load_location], [#_fix(w.N, d: 1)], [#_fmt3(w.ePn)]) },
)
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
  #text(14pt, weight: "bold")[Detailed design and calculation report]

]

#v(50pt)

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
    [IRF Purlin Retrofit Analysis -- detailed/#inputs.intelli_frame_type/Page #context counter(page).display() of #context counter(page).final().first()]
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

This detailed report records the geometry, section properties, bracing stiffness, elastic buckling values and AISI S100-16 strengths behind the allowable roof pressures of the existing purlin line and of the IRF (IntelliFrame) retrofit, for gravity and uplift, together with the bare-IntelliFrame local buckling study (finite strip signature curves, constrained finite strip method and buckling modes). The client report gives the results only.

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
    [Purlin],                       [#ln.purlin_types.at(0)#if ln.assignment.any(a => a == 2) [ and #ln.purlin_types.at(1)] (span assignment #ln.assignment.map(str).join(", "))],
    [Spans],                        [#ln.spans_ft.map(x => str(x)).join(" / ") ft (#ln.spans_ft.len() spans, #_fix(ln.spans_ft.sum(), d: 1) ft total)],
    [Purlin lap at each interior support], [#ln.laps_ft.at(0) ft each side of the support],
    [Purlin spacing],               [#ln.spacing_ft ft],
    [Roof slope],                   [#_fix(ln.roof_slope * 12, d: 1):12 (#_fix(ln.roof_slope, d: 4))],
    [Existing roof deck],           [#ln.existing_deck -- #_deck(det.existing_deck)],
    [Purlin-to-frame connection],   [#ln.purlin_frame_connection],
    [Frame flange width (bearing)], [#_fix(ln.frame_flange_width_in, d: 1) in.],
    [Purlin steel],                 [$F_y$ = #_fix(det.purlin_material.Fy, d: 0) ksi, $F_u$ = #_fix(det.purlin_material.Fu, d: 0) ksi, $E$ = #_fix(det.purlin_material.E, d: 0) ksi, $nu$ = #_fix(det.purlin_material.nu, d: 2)],
    table.hline(),
  ),
)

#_tbl([Purlin cross-section dimensions (in.) -- out-to-out, centerline model built from these],
  (auto, auto, auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  ([*Section*], [*Use*], [*Shape*], [*$t$*], [*$D_"bot"$*], [*$B_"bot"$*], [*$H$*], [*$B_"top"$*], [*$D_"top"$*]),
  for p in det.purlin_sections {
    ([#p.index], [#p.role], [#p.shape], [#_fix(p.t)], [#_fix(p.D_bot, d: 2)], [#_fix(p.B_bottom, d: 2)], [#_fix(p.H, d: 2)], [#_fix(p.B_top, d: 2)], [#_fix(p.D_top, d: 2)])
  },
)

#_tbl([Purlin cross-section angles (deg) and inside bend radii (in.)],
  (auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  ([*Section*], [*$theta_"bot lip"$*], [*$theta_"bot fl"$*], [*$theta_"web"$*], [*$theta_"top fl"$*], [*$theta_"top lip"$*], [*$r_1$*], [*$r_2$*], [*$r_3$*], [*$r_4$*]),
  for p in det.purlin_sections {
    ([#p.index], [#p.theta_bottom_lip], [#p.theta_bottom_flange], [#p.theta_web], [#p.theta_top_flange], [#p.theta_top_lip], [#_fix(p.r1)], [#_fix(p.r2)], [#_fix(p.r3)], [#_fix(p.r4)])
  },
)

#text(8pt)[Section indices above the number of purlin types are the lap sections: the first purlin's dimensions with the thickness of the two lapped purlins added.]

#figure(
  image(cap.profiles.span_configuration, width: 100%),
  caption: [Span configuration: purlins lapped over the interior frame supports, span lengths in ft, frame flange width #_fix(ln.frame_flange_width_in, d: 1) in. (horizontal to scale, vertical exaggerated 3×)],
)

#figure(
  image(cap.profiles.existing_purlin, width: 40%),
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
    [Punch-out (height $times$ length)], [#_fix(s.punchout.height) $times$ #_fix(s.punchout.length) in., measured from the IntelliFrame bottom face],
    [IntelliFrame steel],           [$F_y$ = #_fix(det.intelli_frame_material.Fy, d: 0) ksi, $F_u$ = #_fix(det.intelli_frame_material.Fu, d: 0) ksi, $E$ = #_fix(det.intelli_frame_material.E, d: 0) ksi, $nu$ = #_fix(det.intelli_frame_material.nu, d: 2)],
    [New roof deck],                [#ln.new_deck -- #_deck(det.new_deck)],
    [Attachment],                   [IntelliFrame screwed through the existing deck to the purlin top flange (closely spaced screws); new deck fastened to the IntelliFrame top flange],
    table.hline(),
  ),
)

#figure(
  kind: table,
  caption: [IntelliFrame nominal dimensions (`database/IntelliFrameRF.csv`)],
  table(
    columns: 13,
    stroke: none,
    inset: (x: 3pt, y: 4pt),
    table.hline(),
    table.header(
      [$t$], [$B_"bot"$], [$H$], [$B_"top"$], [$D$], [$alpha_1$], [$alpha_2$], [$alpha_3$], [$alpha_4$], [$r_1$], [$r_2$], [$r_3$], [$h_"hole" times L_"hole"$],
      [#_u[in.]], [#_u[in.]], [#_u[in.]], [#_u[in.]], [#_u[in.]], [#_u[deg]], [#_u[deg]], [#_u[deg]], [#_u[deg]], [#_u[in.]], [#_u[in.]], [#_u[in.]], [#_u[in.]],
      table.hline(),
    ),
    [#_fix(s.dimensions.t)], [#_fix(s.dimensions.B_bottom)], [#_fix(s.dimensions.H)], [#_fix(s.dimensions.B_top)], [#_fix(s.dimensions.D)],
    [#s.dimensions.bottom_flange_angle], [#s.dimensions.web_angle], [#s.dimensions.top_flange_angle], [#s.dimensions.lip_angle],
    [#_fix(s.dimensions.r1)], [#_fix(s.dimensions.r2)], [#_fix(s.dimensions.r3)],
    [#_fix(s.punchout.height) $times$ #_fix(s.punchout.length)],
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

#figure(
  image(cap.profiles.cufsm_sections, height: 3.2in),
  caption: [Combined purlin + IntelliFrame finite strip models exactly as analysed in CUFSM: gross section (left -- section properties, $M_(c r ell)$, $M_(c r d)$) and net section at the punch-out (right -- $M_(c r ell,"hole")$ at $L = L_"hole"$). The purlin and the IntelliFrame are separate strips tied at one node pair, with the deck springs at the two top flanges],
)

#figure(
  image(s.figures.cross_section, width: 100%),
  caption: [Bare IntelliFrame finite strip models: full cross-section (left) and net section at the punch-out (right), centerline nodes],
)

#figure(
  kind: table,
  caption: [Bare IntelliFrame centerline section properties],
  table(
    columns: (2fr, 1fr, 1fr, auto),
    stroke: none,
    inset: (x: 5pt, y: 3.5pt),
    table.hline(),
    table.header([*Property*], [*Full section*], [*Net section at punch-out*], [*Unit*], table.hline()),
    [Area $A$],                             [#_fmt3(s.gross_section.A)],   [#_fmt3(s.net_section.A)],   [#_u[in.²]],
    [Centroid $y_c$ (from bottom face)],    [#_fmt3(s.gross_section.yc)],  [#_fmt3(s.net_section.yc)],  [#_u[in.]],
    [Moment of inertia $I_(x x)$],          [#_fmt3(s.gross_section.Ixx)], [#_fmt3(s.net_section.Ixx)], [#_u[in.⁴]],
    [Moment of inertia $I_(y y)$],          [#_fmt3(s.gross_section.Iyy)], [#_fmt3(s.net_section.Iyy)], [#_u[in.⁴]],
    [Section modulus, top $S_c$],           [#_fmt3(s.gross_section.Sc)],  [#_fmt3(s.net_section.Sc)],  [#_u[in.³]],
    [Section modulus, bottom $S_t$],        [#_fmt3(s.gross_section.St)],  [#_fmt3(s.net_section.St)],  [#_u[in.³]],
    [First-yield moment $M_y$],             [#_fmt3(s.gross_section.My)],  [#_fmt3(s.net_section.My)],  [#_u[kip-in.]],
    table.hline(),
  ),
)

== Purlin line segments

The line is analysed as one continuous member divided into segments. Within the lap length on each side of an interior support the two overlapping purlins act together, so that segment is given a section with the combined thickness of the two purlins. Every strength is calculated separately for each segment; at the node shared by two segments the lower of their strengths is used. The retrofit keeps the same segments, with the IntelliFrame continuous over the supports.

#_tbl([Segments along the purlin line, left to right],
  (auto, auto, 2fr, auto, auto),
  ([*Segment*], [*Length*], [*Section*], [*$t$ (in.)*], [*Type*]),
  for sg in ln.segments { ([#sg.segment], [#_ft(sg.length_ft)], [#sg.section], [#_fix(sg.t)], [#if sg.lap [Lap (two purlins)] else [Span]]) },
)

#_props_table(det.existing, [Existing purlin -- centerline section properties per segment])
#_props_table(det.retrofit, [Retrofit (purlin + IntelliFrame) -- section properties per segment])
#_props_table(det.retrofit, [Retrofit, net section at the punch-out -- section properties per segment], net: true)

== Deck bracing

The roof deck restrains the top flange it is fastened to with a continuous lateral spring $k_x$ (kip/in. per in.) and rotational spring $k_phi$ (kip-in./rad per in.), from the deck fastener stiffness and the deck's rotational restraint (AISI S100-16 Appendix 2). $L_(c r d)$ is the distortional buckling half-wavelength used with the rotational spring. In the retrofit the existing deck braces the purlin top flange and the new deck braces the IntelliFrame top flange.

#_tbl([Deck bracing stiffness per segment],
  (auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  (table.cell(rowspan: 2, align: horizon)[*Seg.*], table.cell(colspan: 3)[*Existing deck on purlin*], table.cell(colspan: 3)[*New deck on IntelliFrame (retrofit)*],
   [$k_x$ (kip/in.²)], [$k_phi$ (kip-in./rad/in.)], [$L_(c r d)$ (in.)], [$k_x$ (kip/in.²)], [$k_phi$ (kip-in./rad/in.)], [$L_(c r d)$ (in.)]),
  for i in range(det.existing.len()) {
    let e = det.existing.at(i).bracing
    let n = det.retrofit.at(i).new_deck_bracing
    ([#(i + 1)], [#_fmt3(e.kx)], [#_fmt3(e.kphi)], [#_fix(e.Lcrd, d: 1)], [#_fmt3(n.kx)], [#_fmt3(n.kphi)], [#_fix(n.Lcrd, d: 1)])
  },
  align: (left, center, center, center, center, center, center),
)

// ════════════════════════════════════════════════════════════════════════════
= Methods
// ════════════════════════════════════════════════════════════════════════════

== Analysis model

The purlin line is solved as a continuous thin-walled beam (PurlinLine.jl / IntelliFrame.jl) under a uniform roof pressure $q$ on the purlin spacing, resolved along and normal to the slope. The deck bracing of the previous section acts as continuous springs at the braced flange; the interior supports restrain translation and twist ($u = v = phi = 0$) and the ends are simply supported. The analysis is second order, so the lateral and torsional response that governs lateral-torsional behaviour is contained in the demands $M_x$, $M_y$, $V_y$, $T$ and $B$. The free (unbraced) bottom flange is modelled separately as a beam-column carrying the axial force from $M_x$ and the shear flow from the roof pressure, giving its weak-axis moment for the H4.2 check. In the retrofit the purlin and the IntelliFrame are one section, and the IntelliFrame bottom flange is constrained to the purlin top flange in the finite strip models.

== Section strengths (AISI S100-16, #ln.design_code)

+ *Elastic buckling.* $M_(c r ell)$ and $M_(c r d)$ of every segment come from finite strip analyses (CUFSM) of the section with the deck springs, for positive and negative strong-axis bending and for weak-axis bending; at the IntelliFrame punch-out the net section is analysed as well.
+ *Flexure.* Direct Strength Method: $M_(n e) = M_y$ (global buckling is handled by the second-order analysis), local-global $M_(n ell)$ from Eq. F3.2.1-1 (F3.2.3 with inelastic reserve when $lambda_ell < 0.776$), net section at the punch-out from F3.2.2, and the lesser of the two governs. Distortional $M_(n d)$ from F4.1.
+ *Shear.* $V_n$ from G2.1 with $V_(c r)$ of the flat web (G2.3) and $V_y$ (G2.1.5), unreinforced web, $k_v$ = 5.34.
+ *Torsion.* Bimoment strength $B_n = F_y C_w \/ W_(n,max)$ (H4.1.1).
+ *Web crippling.* $P_n$ from G5 at every support, one-flange loading, fastened to the support, bearing length = frame flange width.
+ *Interaction checks along the line.* Flexural + torsional (H4.2, with the free-flange term), biaxial bending (H1.2), flexure + shear (H2.1), distortional buckling with the moment-gradient factor on $M_(c r d)$, and web crippling at the supports. Allowable values are nominal values divided by the ASD safety factors.

== Allowable pressure

The roof pressure is iterated until the largest demand-to-capacity ratio of all the checks along the line is 1.0 ($plus.minus$ 0.01). That pressure is the allowable roof pressure; the check and the node where the ratio is 1.0 are the governing limit state and failure location, and the deflection is read from the same solution.

== IntelliFrame local buckling (bare member, cFSM)

The local buckling moment of the bare IntelliFrame is determined independently of the combined model so that the retrofit cannot rely on a local buckling moment higher than the IntelliFrame itself can develop. The member is analysed under a unit strong-axis moment about its own centroid (top flange and lip in compression), simply supported, with the conventional finite strip method (CUFSM, signature curve) and the constrained finite strip method (cFSM, BucklingModeIdentification.jl: pure-local curve and G/D/L/O mode identification on the actual rounded-corner geometry).

*Rule.* $W$ is the widest flat element. The true $L_(c r ell)$ is the first local minimum of the signature curve inside $[0.5 W, 2 W]$ whose buckled shape is local-dominated (L is the largest of its G/D/L/O participations); if there is none, $L_(c r ell)$ is the minimum of the cFSM pure-local curve and $M_(c r ell)$ is the signature curve at that half-wavelength. At the punch-out the net section is the IntelliFrame with the bottom flange and the web below the punch-out height removed, and $L_(c r ell) = min(L_(c r ell,"true"), L_"hole")$ since a local buckle cannot be longer than the punch-out it forms in.

#_tbl([Finite strip analysis parameters],
  (2fr, 1fr),
  ([*Parameter*], [*Value*]),
  (
    [Reference load], [#cfsm.method.reference_moment],
    [Boundary conditions], [#cfsm.method.boundary_conditions],
    [Material], [$E$ = #_fix(cfsm.material.E, d: 0) ksi, $nu$ = #_fix(cfsm.material.nu, d: 2), $F_y$ = #_fix(cfsm.material.Fy, d: 0) ksi (for $M_y$ only)],
    [Local minimum search range], [$[#cfsm.method.range_lo_W W, #cfsm.method.range_hi_W W]$, #cfsm.method.n_range samples],
    [Half-wavelength sweep shown], [$[#cfsm.method.plot_lo_W W, #cfsm.method.plot_hi_W W]$],
    [Elements per flat (bottom flange, web, top flange, lip)], [#cfsm.method.fsm_n.map(str).join(", ")],
    [Elements per corner ($r_1$, $r_2$, $r_3$)], [#cfsm.method.fsm_n_radius.map(str).join(", ")],
    [Shortest strip kept], [#cfsm.method.min_segment_t $t$],
    [cFSM corner model], [#cfsm.method.corner_model],
  ),
)

*Reading the figures.* The black line is the signature curve and the blue dashed line is the cFSM pure-local curve. The shaded band is the $[0.5 W, 2 W]$ search range. The blue diamond is the cFSM pure-local minimum and the hollow circle is the signature curve at that half-wavelength; the red dot is the reported point, an orange cross a rejected (non-local-dominated) trough, and green squares the curves at $L = L_"hole"$. The insets show the conventional buckled shape at the reported point (red) and the cFSM pure-local shape (blue) over the undeformed section (dashed).

#figure(
  image(s.Mcrl_no_hole.figure, width: 90%),
  caption: [Bare IntelliFrame #s.section_name, away from the punch-out -- signature curve, cFSM pure-local curve and buckling modes],
)

#_model_table(s.Mcrl_no_hole, [#s.section_name -- $M_(c r ell,"no hole")$, bare IntelliFrame])

#pagebreak()

#figure(
  image(s.Mcrl_hole.figure, width: 90%),
  caption: [Bare IntelliFrame #s.section_name, net section at the punch-out -- signature curve, cFSM pure-local curve and buckling modes],
)

#_model_table(s.Mcrl_hole, [#s.section_name -- $M_(c r ell,"hole")$, bare IntelliFrame], hole: true)

== Governing local buckling moment of the retrofit

For positive bending the local buckling moment of every retrofit segment is the *minimum* of the combined-model value and the bare-IntelliFrame value converted to that segment's combined section through the critical stress at the IntelliFrame top fiber,
$ f_(c r ell) = M_(c r ell,"bare") c_("top,bare") \/ I_(x x,"bare"), quad M_(c r ell,"combined") = f_(c r ell) I_(x x,"comb") \/ c_("top,comb"), $
separately for the section away from the punch-out and for the net section at the punch-out. The local-global strengths $M_(n ell)$ are then recomputed with the governing values. Negative bending keeps the combined-model values.

#_tbl([Governing $M_(c r ell)^+$ per segment (kip-in.)],
  (auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  (table.cell(rowspan: 2, align: horizon)[*Seg.*], table.cell(colspan: 4)[*Away from punch-out*], table.cell(colspan: 4)[*At punch-out*],
   [combined], [bare, $f_(c r ell)$ (ksi)], [bare → combined], [*governing*], [combined], [bare, $f_(c r ell)$ (ksi)], [bare → combined], [*governing*]),
  for lb in cap.local_buckling {
    ([#lb.segment], [#_fmt3(lb.gross.intelliframe)], [#_fmt3(lb.gross.f_crl)], [#_fmt3(lb.gross.cfsm_combined)], [*#_fmt3(lb.gross.governing)*],
     [#_fmt3(lb.hole.intelliframe)], [#_fmt3(lb.hole.f_crl)], [#_fmt3(lb.hole.cfsm_combined)], [*#_fmt3(lb.hole.governing)*])
  },
  size: 8.5pt,
  align: (left, center, center, center, center, center, center, center, center),
)

#let _gsrc = cap.local_buckling.map(lb => lb.gross.source).dedup()
#let _hsrc = cap.local_buckling.map(lb => lb.hole.source).dedup()
#text(8pt)[Governing model -- away from the punch-out: #if _gsrc.len() == 1 [the #_gsrc.first() in every segment] else [#cap.local_buckling.map(lb => "segment " + str(lb.segment) + ": " + lb.gross.source).join("; ")]. At the punch-out: #if _hsrc.len() == 1 [the #_hsrc.first() in every segment] else [#cap.local_buckling.map(lb => "segment " + str(lb.segment) + ": " + lb.hole.source).join("; ")].]

#_tbl([Retrofit positive local-global flexural strength $M_(n ell x)^+$ (kip-in.), nominal (allowable)],
  (auto, 1fr, 1fr, 1fr),
  ([*Seg.*], [*Away from punch-out*], [*At punch-out (net section)*], [*Governing*]),
  for d in det.retrofit {
    ([#d.segment], [#_na(d.flexure_xx_no_hole.Mnl_pos, d.flexure_xx_no_hole.eMnl_pos)], [#_na(d.flexure_xx_hole.Mnl_pos, d.flexure_xx_hole.eMnl_pos)], [*#_na(d.flexure_xx.Mnl_pos, d.flexure_xx.eMnl_pos)*])
  },
  align: (left, center, center, center),
)

#pagebreak()

// ════════════════════════════════════════════════════════════════════════════
= Existing Roof Analysis
// ════════════════════════════════════════════════════════════════════════════

== Section strengths

#_buckling_table(det.existing, [Existing purlin -- elastic buckling moments (kip-in.) with half-wavelengths (in.), and first-yield moments])
#_strength_table(det.existing, [Existing purlin -- strengths per segment, nominal (allowable): moments in kip-in.])
#_wc_table(det.existing_web_crippling, [Existing purlin -- web crippling strength at the supports])
#if ln.purlin_frame_connection == "Clip-mounted" [
  #text(8pt)[With a clip-mounted purlin-to-frame connection the clip is assumed to brace the purlin web over the frame flange, and web crippling does not govern.]
]

#pagebreak()
#_case(cap.existing_gravity, cap.figures.existing_gravity, [Gravity], [Existing purlin line, gravity])
#pagebreak()
#_case(cap.existing_uplift, cap.figures.existing_uplift, [Uplift], [Existing purlin line, uplift])
#pagebreak()

// ════════════════════════════════════════════════════════════════════════════
= Retrofitted Roof Analysis
// ════════════════════════════════════════════════════════════════════════════

== Section strengths

#_buckling_table(det.retrofit, [Retrofit (purlin + IntelliFrame) -- elastic buckling moments (kip-in.) with half-wavelengths (in.), and first-yield moments; $M_(c r ell)^+$ values are the governing minima of the previous section], retrofit: true)
#_strength_table(det.retrofit, [Retrofit -- strengths per segment, nominal (allowable): moments in kip-in.])
#_wc_table(det.retrofit_web_crippling, [Retrofit -- purlin web crippling strength at the supports (the IntelliFrame bears on the purlin flange)])

#pagebreak()
#_case(cap.retrofit_gravity, cap.figures.retrofit_gravity, [Gravity], [IRF retrofit, gravity])
#pagebreak()
#_case(cap.retrofit_uplift, cap.figures.retrofit_uplift, [Uplift], [IRF retrofit, uplift])
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
  image(cap.figures.summary, width: 50%),
  caption: [Allowable roof pressure, existing vs. IRF retrofit],
)

The IRF retrofit raises the allowable gravity pressure of the purlin line from #_fix(eg.allowable_pressure_psf, d: 1) psf to #_fix(rg.allowable_pressure_psf, d: 1) psf and the allowable uplift pressure from #_fix(eu.allowable_pressure_psf, d: 1) psf to #_fix(ru.allowable_pressure_psf, d: 1) psf.

#v(0.5em)
#set text(size: 8.5pt)
#set enum(numbering: "[1]")
+ AISI S100-16, _North American Specification for the Design of Cold-Formed Steel Structural Members_, American Iron and Steel Institute, 2016.
+ Ádány, S. and Schafer, B.W. (2006). Buckling mode decomposition of single-branched open cross-section members via finite strip method: derivation. _Thin-Walled Structures_, 44(5), 563--584.
+ Ádány, S. and Schafer, B.W. (2008). A full modal decomposition of thin-walled, single-branched open cross-section members via the constrained finite strip method. _Journal of Constructional Steel Research_, 64(1), 12--29.
+ Moen, C.D. and Schafer, B.W. (2009). Elastic buckling of cold-formed steel columns and beams with holes. _Engineering Structures_, 31(12), 2812--2824.
+ PurlinLine.jl, IntelliFrame.jl, CUFSM.jl, cFSM.jl and BucklingModeIdentification.jl -- RunToSolve.
