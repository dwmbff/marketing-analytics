"""Проверка гипотез и графики на основе витрин mart.customer и mart.rfm."""
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
from scipy import stats
from scipy.optimize import brentq

BLUE, ORANGE, GREY = "#2f6db5", "#e07b39", "#8c8c8c"
sns.set_theme(style="whitegrid", font="DejaVu Sans")
plt.rcParams.update({"axes.spines.top": False, "axes.spines.right": False, "figure.dpi": 130})


def cramers_v(table):
    chi2 = stats.chi2_contingency(table, correction=False)[0]
    n = table.to_numpy().sum()
    return float(np.sqrt(chi2 / (n * (min(table.shape) - 1))))


def diff_ci(p1, n1, p2, n2):
    se = np.sqrt(p1 * (1 - p1) / n1 + p2 * (1 - p2) / n2)
    d = p1 - p2
    return d - 1.96 * se, d + 1.96 * se


def cohen_h(p1, p0):
    return 2 * np.arcsin(np.sqrt(p1)) - 2 * np.arcsin(np.sqrt(p0))


def sample_size_per_group(p0, p1, alpha=0.05, power=0.8):
    h = abs(cohen_h(p1, p0))
    z = stats.norm.ppf(1 - alpha / 2) + stats.norm.ppf(power)
    return int(np.ceil(2 * (z / h) ** 2))


def power_two_proportions(p0, p1, n, alpha=0.05):
    h = abs(cohen_h(p1, p0))
    return float(stats.norm.cdf(h * np.sqrt(n / 2) - stats.norm.ppf(1 - alpha / 2)))


def min_detectable_rate(p0, n, alpha=0.05, power=0.8):
    return float(brentq(lambda p1: power_two_proportions(p0, p1, n, alpha) - power, p0 + 1e-6, 0.999))


def loyal_power_analysis(df, alpha=0.05, power=0.8):
    loyal = df[df["rfm_segment"] == "2. Loyal"]
    p0 = float(loyal["response"].mean())
    n_group = len(loyal) // 2
    lifts = [0.03, 0.05, 0.075, 0.10, 0.15]
    return {
        "segment_size": len(loyal),
        "baseline_response_pct": round(100 * p0, 1),
        "alpha": alpha,
        "target_power": power,
        "n_per_group_available": n_group,
        "min_detectable_response_pct": round(100 * min_detectable_rate(p0, n_group, alpha, power), 1),
        "scenarios": [
            {
                "lift_pp": round(100 * d, 1),
                "n_per_group_required": sample_size_per_group(p0, p0 + d, alpha, power),
                "power_with_available_n_pct": round(100 * power_two_proportions(p0, p0 + d, n_group, alpha), 1),
            }
            for d in lifts
        ],
    }


def test_children_response(df):
    table = pd.crosstab(df["has_children"], df["response"])
    chi2, p, _, _ = stats.chi2_contingency(table)
    g = df.groupby("has_children")["response"].agg(["mean", "count"])
    lo, hi = diff_ci(g.loc[True, "mean"], g.loc[True, "count"], g.loc[False, "mean"], g.loc[False, "count"])
    return {
        "response_rate_with_children_pct": round(100 * g.loc[True, "mean"], 1),
        "response_rate_without_children_pct": round(100 * g.loc[False, "mean"], 1),
        "diff_pp_ci95": [round(100 * lo, 1), round(100 * hi, 1)],
        "chi2": round(chi2, 1), "p_value": float(p), "cramers_v": round(cramers_v(table), 3),
    }


def test_partner_income(df):
    d = df.dropna(subset=["income"])
    a = d.loc[d.partner_status == "В паре", "income"]
    b = d.loc[d.partner_status == "Без пары", "income"]
    u, p = stats.mannwhitneyu(a, b, alternative="two-sided")
    return {
        "median_income_partner": float(a.median()), "median_income_no_partner": float(b.median()),
        "mean_income_partner": round(float(a.mean())), "mean_income_no_partner": round(float(b.mean())),
        "rank_biserial": round(float(2 * u / (len(a) * len(b)) - 1), 3),
        "mannwhitney_p_value": float(p),
    }


def run(mart, rfm, out: Path):
    df = mart.copy()
    df["has_children"] = df["has_children"].astype(bool)
    df["response"] = df["response"].astype(int)
    for c in ["income", "total_spend", "total_purchases"]:
        df[c] = df[c].astype(float)
    df = df.merge(rfm[["customer_id", "rfm_segment"]], on="customer_id")

    results = {"n_customers": len(df)}

    results["H1_children_vs_response"] = test_children_response(df)
    results["H2_partner_vs_income"] = test_partner_income(df)
    d = df.dropna(subset=["income"])
    rho, p = stats.spearmanr(d["income"], d["total_spend"])
    results["H3_income_vs_spend"] = {"spearman_rho": round(float(rho), 3), "p_value": float(p), "n": len(d)}
    t = pd.crosstab(df["rfm_segment"], df["response"])
    chi2, p, _, _ = stats.chi2_contingency(t)
    results["H4_rfm_vs_response"] = {"chi2": round(chi2, 1), "p_value": float(p), "cramers_v": round(cramers_v(t), 3)}

    nd = df[~df["is_suspected_duplicate"].astype(bool)]
    results["sensitivity_without_suspected_duplicates"] = {
        "n_customers": len(nd),
        "H1": test_children_response(nd),
        "H2": test_partner_income(nd),
    }
    results["loyal_ab_power"] = loyal_power_analysis(df)
    (out / "stats_results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")

    charts = out / "charts"
    h1, h2, h3 = results["H1_children_vs_response"], results["H2_partner_vs_income"], results["H3_income_vs_spend"]

    g = df.groupby("children")["response"].agg(["mean", "count"]).reset_index()
    fig, ax = plt.subplots(figsize=(8, 4.8))
    bars = ax.bar(g["children"].astype(str), 100 * g["mean"], color=[BLUE if c == 0 else ORANGE for c in g["children"]])
    for b, n, m in zip(bars, g["count"], g["mean"]):
        ax.text(b.get_x() + b.get_width() / 2, 100 * m + 0.6, f"{100 * m:.1f}%\n(n={n})", ha="center", fontsize=9)
    ax.set_ylim(0, 100 * g["mean"].max() + 8)
    ax.set_xlabel("Число детей в семье")
    ax.set_ylabel("Отклик на последнюю кампанию, %")
    ax.set_title(f"Клиенты с детьми откликаются реже: {h1['response_rate_with_children_pct']}% против "
                 f"{h1['response_rate_without_children_pct']}% без детей", fontsize=11, loc="left")
    fig.tight_layout(); fig.savefig(charts / "01_response_by_children.png"); plt.close(fig)

    fig, ax = plt.subplots(figsize=(8, 4.8))
    sns.boxplot(data=df.dropna(subset=["income"]), x="partner_status", y="income",
                order=["В паре", "Без пары"], palette=[BLUE, ORANGE], hue="partner_status", legend=False,
                showfliers=False, ax=ax)
    ax.set_xlabel(""); ax.set_ylabel("Годовой доход")
    ax.set_title(f"Разница в доходе по семейному положению невелика: медианы "
                 f"{h2['median_income_partner']:,.0f} и {h2['median_income_no_partner']:,.0f}".replace(",", " "),
                 fontsize=11, loc="left")
    fig.tight_layout(); fig.savefig(charts / "02_income_by_partner_status.png"); plt.close(fig)

    order = ["Q1 (низкий)", "Q2", "Q3", "Q4 (высокий)"]
    cat = (df[df.income_segment.isin(order)]
           .groupby("income_segment")[["spend_wine", "spend_meat", "spend_gold", "spend_other"]].mean().loc[order])
    cat.columns = ["Вино", "Мясо", "Золото", "Прочее (фрукты, рыба, сладости)"]
    fig, ax = plt.subplots(figsize=(8, 4.8))
    cat.plot(kind="bar", stacked=True, ax=ax, color=[BLUE, ORANGE, "#d9b44a", GREY], width=0.7)
    ax.set_xlabel("Квартиль дохода"); ax.set_ylabel("Средние траты на клиента")
    plt.setp(ax.get_xticklabels(), rotation=0)
    ax.set_title(f"Чем выше доход, тем выше траты: ρ Спирмена = {h3['spearman_rho']}", fontsize=11, loc="left")
    ax.legend(frameon=False, fontsize=9)
    fig.tight_layout(); fig.savefig(charts / "03_spend_by_income_quartile.png"); plt.close(fig)

    seg = df.groupby("rfm_segment").agg(customers=("customer_id", "count"), revenue=("total_spend", "sum")).reset_index()
    seg["customers_pct"] = 100 * seg.customers / seg.customers.sum()
    seg["revenue_pct"] = 100 * seg.revenue / seg.revenue.sum()
    seg["label"] = seg.rfm_segment.str.replace(r"^\d\. ", "", regex=True)
    top = seg.sort_values("revenue_pct", ascending=False).iloc[0]
    x = np.arange(len(seg)); w = 0.38
    fig, ax = plt.subplots(figsize=(9, 4.8))
    ax.bar(x - w / 2, seg.customers_pct, w, color=GREY, label="Доля клиентов, %")
    ax.bar(x + w / 2, seg.revenue_pct, w, color=BLUE, label="Доля выручки, %")
    ax.set_xticks(x); ax.set_xticklabels(seg.label, rotation=15)
    ax.set_title(f"Сегмент {top.label}: {top.customers_pct:.0f}% клиентов дают {top.revenue_pct:.0f}% выручки",
                 fontsize=11, loc="left")
    ax.legend(frameon=False)
    fig.tight_layout(); fig.savefig(charts / "04_rfm_segments.png"); plt.close(fig)

    camp = pd.read_csv(out / "queries" / "q6_campaign_acceptance.csv")
    camp = camp.sort_values("campaign")
    fig, ax = plt.subplots(figsize=(8, 4.8))
    ax.bar(camp.campaign, camp.acceptance_rate_pct, color=[ORANGE if c == "last" else BLUE for c in camp.campaign])
    for i, v in enumerate(camp.acceptance_rate_pct):
        ax.text(i, v + 0.3, f"{v:.1f}%", ha="center", fontsize=9)
    ax.set_ylabel("Приняли предложение, %"); ax.set_xlabel("Кампания (last: последняя)")
    ax.set_title(f"Последняя кампания принята лучше предыдущих: {camp.set_index('campaign').loc['last', 'acceptance_rate_pct']:.1f}%",
                 fontsize=11, loc="left")
    fig.tight_layout(); fig.savefig(charts / "05_campaign_acceptance.png"); plt.close(fig)

    pw = results["loyal_ab_power"]
    p0 = pw["baseline_response_pct"] / 100
    lifts = np.linspace(0.03, 0.15, 60)
    need = [sample_size_per_group(p0, p0 + d) for d in lifts]
    fig, ax = plt.subplots(figsize=(8, 4.8))
    ax.plot(100 * lifts, need, color=BLUE, lw=2)
    ax.axhline(pw["n_per_group_available"], color=ORANGE, ls="--")
    ax.text(15, pw["n_per_group_available"] + 25, f"доступно в сегменте: {pw['n_per_group_available']} на группу",
            ha="right", color=ORANGE, fontsize=9)
    ax.set_xlabel("Ожидаемый прирост отклика, п.п.")
    ax.set_ylabel("Нужно клиентов на группу")
    ax.set_title(f"A/B-тест в сегменте Loyal заметит рост отклика с {pw['baseline_response_pct']}% "
                 f"до {pw['min_detectable_response_pct']}% и выше", fontsize=11, loc="left")
    fig.tight_layout(); fig.savefig(charts / "06_loyal_power.png"); plt.close(fig)

