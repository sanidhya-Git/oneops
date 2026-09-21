#!/usr/bin/env python3
"""
OneOps - Form-3 Weekly Progress Report Generator
Usage: python generate_report.py weekly
"""

import sys
import subprocess
import datetime
import os

from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import cm
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Table, TableStyle, Paragraph,
    Spacer, HRFlowable, Image
)
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import io

# ── Config ────────────────────────────────────────────────────────────────────
PROJECT_NAME   = "OneOps"
PROJECT_DESC   = "AI-Powered Salesforce ERP Platform"
INSTITUTION    = "Fulminous Software"
TEAM_MEMBERS   = [
    {"name": "Sanidhya Mehra",  "email": "sanidhyamehra36@gmail.com",  "role": "AI Engine & Backend"},
    {"name": "Sudhanshu",       "email": "sudhanshuag78@gmail.com",    "role": "Business Services & Data"},
    {"name": "Shivam Goyal",    "email": "shivamgoyal3013@gmail.com",  "role": "Dashboard & LWC"},
]
MEMBER_COLORS  = ["#4A90D9", "#E67E22", "#2ECC71"]

# ── Git helpers ───────────────────────────────────────────────────────────────
def git(*args):
    result = subprocess.run(["git"] + list(args), capture_output=True, text=True)
    return result.stdout.strip()


def get_week_bounds():
    today = datetime.date.today()
    # Last Saturday → this Saturday
    days_since_sat = (today.weekday() + 2) % 7
    end   = today
    start = today - datetime.timedelta(days=6)
    return start, end


def get_commits_for_week(start, end):
    since  = start.strftime("%Y-%m-%d 00:00:00")
    until  = end.strftime("%Y-%m-%d 23:59:59")
    raw = git(
        "log", "--all",
        f"--since={since}", f"--until={until}",
        "--pretty=format:%ae|%an|%s|%ad",
        "--date=short"
    )
    commits = []
    for line in raw.splitlines():
        if "|" not in line:
            continue
        parts = line.split("|", 3)
        if len(parts) == 4:
            commits.append({
                "email":   parts[0].strip(),
                "author":  parts[1].strip(),
                "message": parts[2].strip(),
                "date":    parts[3].strip(),
            })
    return commits


def group_by_member(commits):
    groups = {m["name"]: [] for m in TEAM_MEMBERS}
    email_map = {m["email"]: m["name"] for m in TEAM_MEMBERS}
    for c in commits:
        name = email_map.get(c["email"])
        if name:
            groups[name].append(c)
    return groups


def get_all_time_commits():
    """All commits since project start across all members."""
    project_start = datetime.date(2026, 8, 10)
    since = project_start.strftime("%Y-%m-%d 00:00:00")
    raw = git(
        "log", "--all",
        f"--since={since}",
        "--pretty=format:%ae|%an|%s|%ad",
        "--date=short"
    )
    commits = []
    for line in raw.splitlines():
        if "|" not in line:
            continue
        parts = line.split("|", 3)
        if len(parts) == 4:
            commits.append({
                "email":   parts[0].strip(),
                "author":  parts[1].strip(),
                "message": parts[2].strip(),
                "date":    parts[3].strip(),
            })
    return commits


def week_number_of_project(start):
    project_start = datetime.date(2026, 8, 10)
    delta = (start - project_start).days
    return max(1, delta // 7 + 1)

# ── Chart ─────────────────────────────────────────────────────────────────────
def build_bar_chart(groups):
    names  = [m["name"].split()[0] for m in TEAM_MEMBERS]
    counts = [len(groups.get(m["name"], [])) for m in TEAM_MEMBERS]
    clrs   = MEMBER_COLORS

    fig, ax = plt.subplots(figsize=(5.5, 2.6))
    bars = ax.bar(names, counts, color=clrs, width=0.5, zorder=3)
    ax.set_ylabel("Commits", fontsize=9)
    ax.set_title("Commits This Week", fontsize=10, fontweight="bold")
    ax.yaxis.grid(True, linestyle="--", alpha=0.6, zorder=0)
    ax.set_axisbelow(True)
    ax.spines[["top", "right"]].set_visible(False)
    for bar, val in zip(bars, counts):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.1,
                str(val), ha="center", va="bottom", fontsize=9, fontweight="bold")
    fig.tight_layout()

    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=130, bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    return buf

# ── PDF builder ───────────────────────────────────────────────────────────────
def build_pdf(mode="weekly"):
    start, end = get_week_bounds()
    week_no    = week_number_of_project(start)
    commits    = get_commits_for_week(start, end)
    groups     = group_by_member(commits)

    date_str   = end.strftime("%Y-%m-%d")
    filename   = f"Week{week_no}_Weekly_Progress_Report_Form-3_{date_str}.pdf"

    doc = SimpleDocTemplate(
        filename,
        pagesize=A4,
        leftMargin=2*cm, rightMargin=2*cm,
        topMargin=1.8*cm, bottomMargin=1.8*cm
    )

    styles  = getSampleStyleSheet()
    BRAND   = "#1A3C6E"
    ACCENT  = "#2980B9"

    title_style = ParagraphStyle("title", parent=styles["Normal"],
        fontSize=16, textColor=colors.HexColor(BRAND),
        alignment=TA_CENTER, fontName="Helvetica-Bold", spaceAfter=2)

    sub_style = ParagraphStyle("sub", parent=styles["Normal"],
        fontSize=9, textColor=colors.HexColor("#555555"),
        alignment=TA_CENTER, spaceAfter=6)

    h2_style = ParagraphStyle("h2", parent=styles["Normal"],
        fontSize=11, textColor=colors.HexColor(BRAND),
        fontName="Helvetica-Bold", spaceBefore=10, spaceAfter=4)

    cell_style = ParagraphStyle("cell", parent=styles["Normal"],
        fontSize=8, leading=11)

    label_style = ParagraphStyle("label", parent=styles["Normal"],
        fontSize=8, fontName="Helvetica-Bold")

    story = []

    # ── Header ──
    story.append(Paragraph(f"{PROJECT_NAME} – Form-3 Weekly Progress Report", title_style))
    story.append(Paragraph(f"{PROJECT_DESC} &nbsp;|&nbsp; {INSTITUTION}", sub_style))
    story.append(Paragraph(
        f"Week #{week_no} &nbsp;|&nbsp; "
        f"{start.strftime('%d %b %Y')} – {end.strftime('%d %b %Y')} &nbsp;|&nbsp; "
        f"Generated: {datetime.datetime.now().strftime('%d %b %Y %H:%M')}",
        sub_style))
    story.append(HRFlowable(width="100%", thickness=1.5,
                             color=colors.HexColor(BRAND), spaceAfter=8))

    # ── Summary table ──
    # ── All-time stats ──
    all_commits   = get_all_time_commits()
    all_groups    = group_by_member(all_commits)
    total_ever    = len(all_commits)

    story.append(Paragraph("1. Project Overview (All-Time)", h2_style))
    overview_data = [
        [Paragraph("<b>Member</b>", label_style),
         Paragraph("<b>Role</b>", label_style),
         Paragraph("<b>Total Commits</b>", label_style)],
    ]
    for m in TEAM_MEMBERS:
        overview_data.append([
            m["name"],
            m["role"],
            str(len(all_groups.get(m["name"], []))),
        ])
    overview_data.append([
        Paragraph("<b>TOTAL</b>", label_style), "", Paragraph(f"<b>{total_ever}</b>", label_style)
    ])
    ov_tbl = Table(overview_data, colWidths=[5*cm, 7.5*cm, 3.5*cm])
    ov_tbl.setStyle(TableStyle([
        ("BACKGROUND",  (0, 0), (-1, 0), colors.HexColor(BRAND)),
        ("TEXTCOLOR",   (0, 0), (-1, 0), colors.white),
        ("FONTNAME",    (0, 0), (-1, 0), "Helvetica-Bold"),
        ("BACKGROUND",  (0, -1), (-1, -1), colors.HexColor("#E8F0F8")),
        ("FONTSIZE",    (0, 0), (-1, -1), 8.5),
        ("ROWBACKGROUNDS", (0, 1), (-1, -2), [colors.HexColor("#F4F8FC"), colors.white]),
        ("GRID",        (0, 0), (-1, -1), 0.4, colors.HexColor("#CCDDEE")),
        ("TOPPADDING",  (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING",(0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("ALIGN",       (2, 0), (2, -1), "CENTER"),
    ]))
    story.append(ov_tbl)
    story.append(Spacer(1, 10))

    story.append(Paragraph("2. Week at a Glance", h2_style))
    total = sum(len(v) for v in groups.values())
    summary_data = [
        [Paragraph("<b>Metric</b>", label_style), Paragraph("<b>Value</b>", label_style)],
        ["Total Commits This Week", str(total)],
        ["Project Week Number",     f"Week {week_no}"],
        ["Report Period",           f"{start.strftime('%d %b')} – {end.strftime('%d %b %Y')}"],
        ["Active Contributors",     str(sum(1 for v in groups.values() if v))],
    ]
    summary_tbl = Table(summary_data, colWidths=[9*cm, 7*cm])
    summary_tbl.setStyle(TableStyle([
        ("BACKGROUND",  (0, 0), (-1, 0), colors.HexColor(BRAND)),
        ("TEXTCOLOR",   (0, 0), (-1, 0), colors.white),
        ("FONTNAME",    (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE",    (0, 0), (-1, -1), 8.5),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.HexColor("#F4F8FC"), colors.white]),
        ("GRID",        (0, 0), (-1, -1), 0.4, colors.HexColor("#CCDDEE")),
        ("TOPPADDING",  (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING",(0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(summary_tbl)
    story.append(Spacer(1, 8))

    # ── Bar chart ──
    chart_buf = build_bar_chart(groups)
    img = Image(chart_buf, width=13*cm, height=6.5*cm)
    story.append(img)
    story.append(Spacer(1, 8))

    # ── Per-member commit tables ──
    story.append(Paragraph("3. This Week's Contributions by Member", h2_style))

    for idx, member in enumerate(TEAM_MEMBERS):
        mname  = member["name"]
        mrole  = member["role"]
        mcolor = colors.HexColor(MEMBER_COLORS[idx])
        mcommits = groups.get(mname, [])

        story.append(Paragraph(
            f"<b>{mname}</b> &nbsp;·&nbsp; {mrole} &nbsp;·&nbsp; {len(mcommits)} commit(s)",
            ParagraphStyle("mh", parent=styles["Normal"],
                           fontSize=9, textColor=mcolor,
                           fontName="Helvetica-Bold", spaceBefore=6, spaceAfter=3)
        ))

        if mcommits:
            rows = [[
                Paragraph("<b>#</b>", label_style),
                Paragraph("<b>Date</b>", label_style),
                Paragraph("<b>Commit Message</b>", label_style),
            ]]
            for i, c in enumerate(mcommits, 1):
                rows.append([
                    str(i),
                    c["date"],
                    Paragraph(c["message"], cell_style),
                ])
            tbl = Table(rows, colWidths=[0.8*cm, 2.4*cm, 13*cm])
            tbl.setStyle(TableStyle([
                ("BACKGROUND",  (0, 0), (-1, 0), mcolor),
                ("TEXTCOLOR",   (0, 0), (-1, 0), colors.white),
                ("FONTSIZE",    (0, 0), (-1, -1), 8),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1),
                 [colors.HexColor("#F9F9F9"), colors.white]),
                ("GRID",        (0, 0), (-1, -1), 0.3, colors.HexColor("#DDDDDD")),
                ("TOPPADDING",  (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING",(0, 0), (-1, -1), 4),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("VALIGN",      (0, 0), (-1, -1), "TOP"),
            ]))
            story.append(tbl)
        else:
            story.append(Paragraph(
                "No commits recorded for this member this week.",
                ParagraphStyle("none", parent=styles["Normal"],
                               fontSize=8, textColor=colors.grey, spaceAfter=4)
            ))

    # ── Footer ──
    story.append(Spacer(1, 12))
    story.append(HRFlowable(width="100%", thickness=0.8,
                             color=colors.HexColor("#AAAAAA"), spaceAfter=4))
    story.append(Paragraph(
        f"Auto-generated by OneOps CI/CD Pipeline &nbsp;·&nbsp; "
        f"GitHub Actions &nbsp;·&nbsp; {datetime.datetime.now().strftime('%d %b %Y %H:%M UTC')}",
        ParagraphStyle("footer", parent=styles["Normal"],
                       fontSize=7, textColor=colors.grey, alignment=TA_CENTER)
    ))

    doc.build(story)
    print(f"[OK] Report generated: {filename}")
    return filename


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "weekly"
    build_pdf(mode)
