// IntelliFrame orientation on the existing purlin -- comparison of the two arrangements.
// Data and figures: run_orientation_comparison.jl in this folder.
// Compile from the repository root:
//   typst compile --root . generate_report/orientation_comparison/Orientation_Comparison.typ

#let inputs = json("../../frontend_output/inputs.json")
#let d      = json("orientation_comparison.json")
#let A      = d.A
#let B      = d.B

// ─── FORMAT HELPERS ────────────────────────────────────────────────
#let _fix(x, d: 2) = {
  if x == none { [---] }
  else {
    let rounded = calc.round(x, digits: d)
    let sign = if rounded < 0 { "−" } else { "" }
    let parts = str(calc.abs(rounded)).split(".")
    let fp = if parts.len() > 1 { parts.at(1) } else { "" }
    while fp.len() < d { fp = fp + "0" }
    [#(sign + parts.at(0) + if d > 0 { "." + fp } else { "" })]
  }
}
#let _pct(a, b) = {
  let p = (b - a) / calc.abs(a) * 100
  if calc.abs(p) < 0.05 { [0 %] } else { [#(if p > 0 { "+" } else { "" })#_fix(p, d: 1) %] }
}
// difference instead of a percentage, for quantities whose value can be near zero (positions, angles)
#let _diff(a, b, unit, d: 2) = [#(if b - a > 0 { "+" } else { "" })#_fix(b - a, d: d) #unit]
#let _u(it) = text(size: 0.85em, it)
#let _row(name, unit, a, b, d: 2, diff: none) = ([#name], [#_u[#unit]], [#_fix(a, d: d)], [#_fix(b, d: d)],
  if diff == none { [#_pct(a, b)] } else { _diff(a, b, diff, d: d) })
#let _cmp(caption, rows) = figure(
  kind: table,
  caption: caption,
  table(
    columns: (2.4fr, auto, 1fr, 1fr, auto),
    align: (left, left, center, center, center),
    stroke: none,
    inset: (x: 5pt, y: 3.5pt),
    table.hline(),
    table.header([*Quantity*], [*Unit*], [*A*], [*B*], [*B vs A*], table.hline()),
    ..rows,
    table.hline(),
  ),
)
// ───────────────────────────────────────────────────────────────────

#set page(paper: "us-letter", margin: (top: 1in, bottom: 1in), numbering: "1",
  header: context {
    set text(size: 8pt)
    [IntelliFrame orientation comparison/#d.intelli_frame on #d.purlin/Page #counter(page).display() of #counter(page).final().first()]
    line(length: 100%, stroke: 0.5pt)
  },
  footer: context {
    set text(size: 8pt)
    line(length: 100%, stroke: 0.5pt)
    [#inputs.project_name (#inputs.project_reference)]
  },
)
#set par(justify: true, leading: 8pt)
#set text(size: 10pt)
#set heading(numbering: "1.")
#show heading: set block(above: 18pt, below: 10pt)
#show figure.where(kind: table): set figure.caption(position: top)
#show figure.where(kind: table): it => align(left, it)
#show table: set par(justify: false)


#v(2pt)
#text(16pt, weight: "bold")[IntelliFrame Orientation on the Existing Purlin] \
#text(11pt)[Comparison of the two arrangements -- section properties, strengths and allowable roof pressure]
#v(6pt)

#table(
  columns: (1fr, 2.2fr),
  stroke: none,
  inset: (x: 5pt, y: 3pt),
  table.hline(),
  [*Existing purlin*],  [#d.purlin, spans #inputs.purlin_spans_ft.map(str).join(" / ") ft, laps #inputs.purlin_laps_ft.at(0) ft each side],
  [*IntelliFrame*],     [#d.intelli_frame],
  [*Decks*],            [existing #inputs.existing_deck_type, new #inputs.new_deck_type],
  [*Design method*],    [ASD, AISI S100-16],
  table.hline(),
)

= Summary

The IntelliFrame can sit on the purlin in two mirror-image ways:

- *A* -- the IntelliFrame top flange points the same way as the purlin *bottom* flange (the arrangement IntelliFrame now models);
- *B* -- the IntelliFrame top flange points the same way as the purlin *top* flange (the arrangement modelled before).

Everything else is identical in the two analyses. The result:

#figure(
  kind: table,
  caption: [Allowable roof pressure of the retrofitted purlin line],
  table(
    columns: (1.6fr, 1fr, 1fr, auto, 1fr),
    align: (left, center, center, center, center),
    stroke: none,
    inset: (x: 5pt, y: 4pt),
    table.hline(),
    table.header([], [*A*], [*B*], [*B vs A*], [*Existing line*], table.hline()),
    [Gravity], [*#_fix(A.gravity.pressure_psf) psf*], [*#_fix(B.gravity.pressure_psf) psf*], [#_pct(A.gravity.pressure_psf, B.gravity.pressure_psf)], [#_fix(d.existing.gravity.pressure_psf) psf],
    [Uplift],  [*#_fix(A.uplift.pressure_psf) psf*],  [*#_fix(B.uplift.pressure_psf) psf*],  [#_pct(A.uplift.pressure_psf, B.uplift.pressure_psf)],  [#_fix(d.existing.uplift.pressure_psf) psf],
    table.hline(),
  ),
)

*The orientation changes the allowable roof pressure by less than 1 %.* It changes the strong-axis strengths not at all and the weak-axis strengths by about a third (Section 4); the weak-axis difference has no practical effect because the governing check is dominated by strong-axis bending and the weak-axis moment at the governing location is negligible (Section 5).

= Axis directions and sign conventions

#figure(
  image("orientation_sections.png", width: 100%),
  caption: [The two arrangements, drawn as analysed (centerline of each part), with the centroidal axes $x$, $y$ and the principal axes 1, 2 of the combined section],
)

- *$z$* runs along the purlin. The section lies in the $x$--$y$ plane: *$x$ horizontal*, across the roof slope, and *$y$ vertical*, up through the purlin web and the IntelliFrame.
- *Strong-axis bending $M_x$* is bending about the horizontal centroidal $x$-axis -- the purlin bending in its depth under the roof pressure. Positive $M_x$ puts the *top* (IntelliFrame) in compression: midspan under gravity, over the supports under uplift.
- *Weak-axis bending $M_y$* is bending about the vertical centroidal $y$-axis -- lateral bending of the purlin. Positive $M_y$ puts the outer fibre on the *$-x$ side* in compression, negative $M_y$ the outer fibre on the *$+x$ side*. It comes from the slope component of gravity and from the lateral and torsional response of the Z-section, restrained by the deck springs.
- *Principal axes 1, 2.* A Z-section is point-symmetric, so its centroidal $x$, $y$ axes are not principal ($I_(x y) != 0$); the principal axes are rotated by the angle shown. The analysis is in the $x$, $y$ axes with $I_(x y)$ included, the deck restraining the section to bend about $x$ (restrained bending).

In *A* the IntelliFrame turns back over the purlin, so the combined section stays narrow about the purlin web. In *B* the IntelliFrame top flange and lip continue past the purlin top flange, so the combined section is wider on the $+x$ side, the centroid moves towards $+x$, and the principal axes rotate further from $x$, $y$.

= Section properties

#_cmp([Combined purlin + IntelliFrame section, span segment], (
  .._row([Area $A$], [in.²], A.section.A, B.section.A, d: 3),
  .._row([Centroid $x_c$], [in.], A.section.xc, B.section.xc, d: 3, diff: "in."),
  .._row([Centroid $y_c$ (from the purlin bottom)], [in.], A.section.yc, B.section.yc, d: 3),
  .._row([$I_(x x)$ -- strong axis], [in.⁴], A.section.Ixx, B.section.Ixx),
  .._row([$I_(y y)$ -- weak axis], [in.⁴], A.section.Iyy, B.section.Iyy),
  .._row([$I_(x y)$ -- product of inertia], [in.⁴], A.section.Ixy, B.section.Ixy),
  .._row([Principal-axis angle (axis 1 from $x$)], [deg], A.section.theta_p, B.section.theta_p, d: 1, diff: "°"),
  .._row([$I_1$ / $I_2$ principal moments], [in.⁴], A.section.I1, B.section.I1),
  ..([], [], [#_fix(A.section.I2)], [#_fix(B.section.I2)], [#_pct(A.section.I2, B.section.I2)]),
  .._row([Overall width of the section], [in.], A.section.width, B.section.width),
  .._row([$S_y$, $-x$ fibre / $+x$ fibre], [in.³], A.section.Sy_pos, B.section.Sy_pos),
  ..([], [], [#_fix(A.section.Sy_neg)], [#_fix(B.section.Sy_neg)], [#_pct(A.section.Sy_neg, B.section.Sy_neg)]),
))

#text(9pt)[Area, $y_c$ and $I_(x x)$ are identical: mirroring the IntelliFrame moves material only in $x$. The outer fibre on the $+x$ side belongs to the #A.section.fibre_plus_x in A and to the #B.section.fibre_plus_x in B (its own $F_y$ is used for first yield).]

= Strengths

#_cmp([Elastic buckling and allowable strengths, span segment (kip-in.; $V_n$ in kip, $B_n$ in kip-in.²)], (
  table.cell(colspan: 5)[_Strong axis ($x$)_],
  .._row([Local buckling $M_(c r ell)^+$], [kip-in.], A.strengths.Mcrl_pos, B.strengths.Mcrl_pos, d: 1),
  .._row([Local buckling at the punch-out $M_(c r ell,"hole")^+$], [kip-in.], A.strengths.Mcrl_pos_hole, B.strengths.Mcrl_pos_hole, d: 1),
  .._row([Local buckling $M_(c r ell)^-$], [kip-in.], A.strengths.Mcrl_neg, B.strengths.Mcrl_neg, d: 1),
  .._row([Distortional $M_(c r d)^+$ / $M_(c r d)^-$], [kip-in.], A.strengths.Mcrd_pos, B.strengths.Mcrd_pos, d: 1),
  ..([], [], [#_fix(A.strengths.Mcrd_neg, d: 1)], [#_fix(B.strengths.Mcrd_neg, d: 1)], [#_pct(A.strengths.Mcrd_neg, B.strengths.Mcrd_neg)]),
  .._row([First yield $M_y$], [kip-in.], A.strengths.My_x, B.strengths.My_x, d: 1),
  .._row([*Flexure $M_(n ell x)^+$*], [kip-in.], A.strengths.Mnx_pos, B.strengths.Mnx_pos, d: 1),
  .._row([*Flexure $M_(n ell x)^-$*], [kip-in.], A.strengths.Mnx_neg, B.strengths.Mnx_neg, d: 1),
  .._row([Distortional $M_(n d)^+$], [kip-in.], A.strengths.Mnd_pos, B.strengths.Mnd_pos, d: 1),
  .._row([Distortional $M_(n d)^-$], [kip-in.], A.strengths.Mnd_neg, B.strengths.Mnd_neg, d: 1),
  table.hline(stroke: (dash: "dotted")),
  table.cell(colspan: 5)[_Weak axis ($y$)_],
  .._row([First yield $M_(y,y)$], [kip-in.], A.section.My_y, B.section.My_y, d: 1),
  .._row([*Flexure $M_(n ell y)^+$* ($-x$ fibre in compression)], [kip-in.], A.strengths.Mny_pos, B.strengths.Mny_pos, d: 1),
  .._row([*Flexure $M_(n ell y)^-$* ($+x$ fibre in compression)], [kip-in.], A.strengths.Mny_neg, B.strengths.Mny_neg, d: 1),
  table.hline(stroke: (dash: "dotted")),
  .._row([Shear $V_n$], [kip], A.strengths.Vn, B.strengths.Vn),
  .._row([Torsion (bimoment) $B_n$], [kip-in.²], A.strengths.Bn, B.strengths.Bn, d: 1),
))

#figure(
  image("orientation_strengths.png", width: 100%),
  caption: [Allowable strengths of the span segment and allowable roof pressure of the line, A vs B],
)

The strong-axis strengths do not depend on the orientation: $I_(x x)$ and the distance from the neutral axis to the top and bottom fibres are unchanged, and the plate elements that buckle locally are the same plates under the same stress. The weak-axis strengths do: B is wider in $x$, so $I_(y y)$ and the weak-axis section moduli are larger, and $M_(n ell y)$ follows.

= Torsion

#let TA = d.torsion.A
#let TB = d.torsion.B

Torsion is resisted by St. Venant torsion ($G J$) and by warping ($E C_w$). The warping constant and shear centre are computed for the *connected section* -- the IntelliFrame web joined to the purlin top flange at the screw line, the two flanges acting as one flange of thickness $t_p + t_i$ where they overlap -- and these are the values the line analysis of both arrangements uses in this comparison. The St. Venant constant $J$ is the sum of the purlin and IntelliFrame sheets, which act separately in St. Venant torsion where they overlap.

#figure(
  image("orientation_torsion.png", width: 82%),
  caption: [Connected purlin + IntelliFrame sections with their shear centre SC, its distances from the left and right edges and from the bottom of the section (in., centerline), and the roof load on the IntelliFrame top flange with its eccentricity $e$ from SC],
)

#_cmp([Torsional properties], (
  .._row([St. Venant constant $J$ (sum of the two sheets)], [in.⁴], TA.section.J_model, TB.section.J_model, d: 5),
  .._row([Warping constant $C_w$ -- connected section], [in.⁶], TA.section.Cw, TB.section.Cw, d: 1),
  .._row([Shear centre $x_s$ -- connected section], [in.], TA.section.xs, TB.section.xs, d: 2, diff: "in."),
  .._row([Shear centre $y_s$ -- connected section], [in.], TA.section.ys, TB.section.ys, d: 2, diff: "in."),
  .._row([#h(1em) SC from the left edge of the section], [in.], TA.section.sc_from_left, TB.section.sc_from_left, d: 2, diff: "in."),
  .._row([#h(1em) SC from the right edge of the section], [in.], TA.section.sc_from_right, TB.section.sc_from_right, d: 2, diff: "in."),
  .._row([#h(1em) SC above the bottom of the purlin], [in.], TA.section.sc_from_bottom, TB.section.sc_from_bottom, d: 2, diff: "in."),
  .._row([#h(1em) SC below the top of the IntelliFrame], [in.], TA.section.sc_from_top, TB.section.sc_from_top, d: 2, diff: "in."),
  .._row([#h(1em) SC from the purlin web (+ towards the purlin top flange)], [in.], TA.section.sc_from_web, TB.section.sc_from_web, d: 2, diff: "in."),
  .._row([Load line (IntelliFrame top flange centre) from the purlin web], [in.], TA.section.load_from_web, TB.section.load_from_web, d: 2, diff: "in."),
  .._row([*Load eccentricity $|e|$ from the shear centre*], [in.], calc.abs(TA.section.e), calc.abs(TB.section.e), d: 2),
))

#_cmp([Torsion capacity, allowable (ASD), span segment], (
  .._row([*Bimoment strength $B_n$* -- as checked (purlin + IntelliFrame)], [kip-in.²], TA.section.Bn, TB.section.Bn, d: 1),
  .._row([#h(1em) purlin part], [kip-in.²], TA.section.Bn_purlin, TB.section.Bn_purlin, d: 1),
  .._row([#h(1em) IntelliFrame part], [kip-in.²], TA.section.Bn_if, TB.section.Bn_if, d: 1),
  .._row([Bimoment strength of the connected section, $F_y C_w \/ W_(n,max) \/ Omega$], [kip-in.²], TA.section.Bn_connected, TB.section.Bn_connected, d: 1),
  .._row([St. Venant torque at shear yield, $0.6 F_y J \/ t \/ Omega_v$ (indicative)], [kip-in.],
         0.6 * TA.section.Fy * TA.section.J_model / 0.06 / 1.6, 0.6 * TB.section.Fy * TB.section.J_model / 0.06 / 1.6, d: 3),
))

#text(9pt)[The code checks torsion only through the bimoment, $B \/ B_n$ in the H4.2 interaction (AISI S100 H4.1.1: $B_n = F_y C_w \/ W_n$, $Omega = 1.67$), with $B_n$ the sum of the purlin and IntelliFrame strengths, which does not depend on the orientation. Torsional shear (St. Venant or warping) is not checked; the shear-yield torque above uses $F_y$ = #_fix(TA.section.Fy, d: 0) ksi, the single-sheet thickness $t$ = 0.060 in. and $Omega_v = 1.60$ for comparison only. $J$ is the sum of the purlin and IntelliFrame sheets, which act separately in St. Venant torsion where they overlap; the connected section (overlap shown thicker in the figure) is used for $C_w$ and the shear centre only.]

#figure(
  kind: table,
  caption: [Torsion demand along the line at the allowable pressure],
  table(
    columns: (2.2fr, 1fr, 1fr, 1fr, 1fr),
    align: (left, center, center, center, center),
    stroke: none,
    inset: (x: 5pt, y: 3.5pt),
    table.hline(),
    table.header([], table.cell(colspan: 2)[*Gravity*], table.cell(colspan: 2)[*Uplift*], [], [A], [B], [A], [B], table.hline()),
    [Max twist $phi$ (rad)], [#_fix(TA.gravity.phi_max, d: 5)], [#_fix(TB.gravity.phi_max, d: 5)], [#_fix(TA.uplift.phi_max, d: 5)], [#_fix(TB.uplift.phi_max, d: 5)],
    [Max total torque $T$ (kip-in.)], [#_fix(TA.gravity.T_max, d: 3)], [#_fix(TB.gravity.T_max, d: 3)], [#_fix(TA.uplift.T_max, d: 3)], [#_fix(TB.uplift.T_max, d: 3)],
    [Max St. Venant torque $G J phi'$ (kip-in.)], [#_fix(TA.gravity.T_sv_max, d: 4)], [#_fix(TB.gravity.T_sv_max, d: 4)], [#_fix(TA.uplift.T_sv_max, d: 4)], [#_fix(TB.uplift.T_sv_max, d: 4)],
    [Max St. Venant shear stress $G t phi'$ (ksi)], [#_fix(TA.gravity.tau_sv_max, d: 3)], [#_fix(TB.gravity.tau_sv_max, d: 3)], [#_fix(TA.uplift.tau_sv_max, d: 3)], [#_fix(TB.uplift.tau_sv_max, d: 3)],
    [Max bimoment $B$ (kip-in.²)], [#_fix(TA.gravity.B_max, d: 2)], [#_fix(TB.gravity.B_max, d: 2)], [#_fix(TA.uplift.B_max, d: 2)], [#_fix(TB.uplift.B_max, d: 2)],
    [Max $B \/ B_n$ along the line], [#_fix(TA.gravity.B_over_Bn_max, d: 3)], [#_fix(TB.gravity.B_over_Bn_max, d: 3)], [#_fix(TA.uplift.B_over_Bn_max, d: 3)], [#_fix(TB.uplift.B_over_Bn_max, d: 3)],
    [$B \/ B_n$ at the governing location], [#_fix(TA.gravity.B_over_Bn_gov, d: 3)], [#_fix(TB.gravity.B_over_Bn_gov, d: 3)], [#_fix(TA.uplift.B_over_Bn_gov, d: 3)], [#_fix(TB.uplift.B_over_Bn_gov, d: 3)],
    table.hline(),
  ),
)

*Resistance.* $J$ is the same in A and B (mirroring does not change the plates) and the connected-section $C_w$ differs by only about 5 %, so the two orientations have practically the same torsional resistance; the allowable bimoment strength as checked is identical.

*Why the shear centre matters.* A load whose line of action passes through the shear centre bends the member without twisting it. A load at a horizontal distance $e$ from the shear centre also applies a distributed torque $m_t = q dot e$ per unit length, which the member resists by St. Venant and warping torsion (and the deck by its rotational restraint). The torque, and with it the twist, bimoment and torsional stresses, grows in proportion to $e$: the further the shear centre lies from the line of action of the load, the more torsion is developed for the same pressure.

*Torque from the roof load.* The new deck bears on the IntelliFrame top flange. In A that flange sits back over the purlin, #_fix(calc.abs(TA.section.e)) in. from the shear centre; in B it reaches past the purlin, #_fix(calc.abs(TB.section.e)) in. away. For the same pressure B therefore applies about #_pct(calc.abs(TA.section.e), calc.abs(TB.section.e)) more torque per unit length. *If torsion occurs, A is the better arrangement:* equal resistance, less torque.

*Magnitude.* In both arrangements the decks hold the twist to a few hundredths of a degree; the St. Venant shear stress is a small fraction of a ksi and $B \/ B_n$ is at most #_fix(calc.max(TA.gravity.B_over_Bn_max, TA.uplift.B_over_Bn_max, TB.gravity.B_over_Bn_max, TB.uplift.B_over_Bn_max), d: 2), at the interior supports, where it does not govern. With practically the same torsional stiffness, B -- whose load is further from the shear centre -- twists more and develops the larger torsion demands.

= Why the allowable pressure barely changes

The allowable pressure is reached when the governing interaction check equals 1.0. In both arrangements that is the flexural + torsional interaction (AISI S100 H4.2), which adds the strong-axis ratio $M_x \/ M_(n ell x)$, the weak-axis ratio $M_y \/ M_(n ell y)$, the bimoment ratio $B \/ B_n$ and the free-flange term. At the governing location:

#figure(
  kind: table,
  caption: [Strong- and weak-axis ratios at the governing location, at the allowable pressure],
  table(
    columns: (1.3fr, 1fr, 1fr, 1fr, 1fr),
    align: (left, center, center, center, center),
    stroke: none,
    inset: (x: 5pt, y: 3.5pt),
    table.hline(),
    table.header([], table.cell(colspan: 2)[*Gravity*], table.cell(colspan: 2)[*Uplift*], [], [A], [B], [A], [B], table.hline()),
    [Location $z$ (ft)], [#_fix(A.split_gravity.z_ft, d: 1)], [#_fix(B.split_gravity.z_ft, d: 1)], [#_fix(A.split_uplift.z_ft, d: 1)], [#_fix(B.split_uplift.z_ft, d: 1)],
    [$|M_x| \/ M_(n ell x)$], [#_fix(A.split_gravity.Mx_over_Mnx, d: 3)], [#_fix(B.split_gravity.Mx_over_Mnx, d: 3)], [#_fix(A.split_uplift.Mx_over_Mnx, d: 3)], [#_fix(B.split_uplift.Mx_over_Mnx, d: 3)],
    [$|M_y| \/ M_(n ell y)$], [#_fix(A.split_gravity.My_over_Mny, d: 3)], [#_fix(B.split_gravity.My_over_Mny, d: 3)], [#_fix(A.split_uplift.My_over_Mny, d: 3)], [#_fix(B.split_uplift.My_over_Mny, d: 3)],
    table.hline(),
  ),
)

The strong-axis term is the large one and is practically the same in A and B, because $M_(n ell x)$ is unchanged and so is the moment the line carries. The weak-axis term is essentially zero in both: the deck restrains the purlin laterally, so the weak-axis moment at the governing location is negligible, and the about one-third larger $M_(n ell y)$ of B divides a moment that is not there. The rest of the H4.2 sum comes almost entirely from the lateral bending of the unbraced free (bottom) flange -- about 0.28 under gravity and 0.20 under uplift -- with the bimoment adding no more than about 0.02 (Section 5). These depend slightly on how the two parts are arranged ($I_(x y)$, the torsional response), and they account for the small differences in the allowable pressure, under 1 %:

#figure(
  kind: table,
  caption: [Results of the retrofitted line],
  table(
    columns: (1.1fr, 2fr, 2fr),
    align: (left, left, left),
    stroke: none,
    inset: (x: 5pt, y: 3.5pt),
    table.hline(),
    table.header([], [*A*], [*B*], table.hline()),
    [Gravity], [#_fix(A.gravity.pressure_psf) psf -- #A.gravity.limit_state, #A.gravity.location; deflection #_fix(A.gravity.deflection_in, d: 3) in.],
               [#_fix(B.gravity.pressure_psf) psf -- #B.gravity.limit_state, #B.gravity.location; deflection #_fix(B.gravity.deflection_in, d: 3) in.],
    [Uplift],  [#_fix(A.uplift.pressure_psf) psf -- #A.uplift.limit_state, #A.uplift.location; deflection #_fix(A.uplift.deflection_in, d: 3) in.],
               [#_fix(B.uplift.pressure_psf) psf -- #B.uplift.limit_state, #B.uplift.location; deflection #_fix(B.uplift.deflection_in, d: 3) in.],
    table.hline(),
  ),
)

= Conclusion

- The two orientations give the *same allowable roof pressure within 1 %*, the same governing limit state and the same failure locations.
- Strong-axis section properties and strengths are identical; *weak-axis strength is about one third higher in B*, because the IntelliFrame extends past the purlin in that arrangement -- but the weak-axis moment at the governing location is negligible, so this does not raise the capacity of the line.
- Torsional resistance is practically the same in both ($J$ identical, $C_w$ within about 5 %, same $B_n$); A attracts less torque from the roof load because the load sits closer to the shear centre, so *A is preferable where torsion matters*.
- The choice of orientation should therefore follow the installation detail; the design result is not sensitive to it. IntelliFrame models arrangement A.


