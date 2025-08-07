import { LightningElement, wire } from "lwc";
import getOrgLimits from "@salesforce/apex/LimitsForATransactionController.getOrgLimits";
import getLimitSuggestions from "@salesforce/apex/LimitsForATransactionController.getLimitSuggestions";
import chartsResource from "@salesforce/resourceUrl/chartsResource";
import { loadScript } from "lightning/platformResourceLoader";
import { refreshApex } from "@salesforce/apex";

export default class LimitsForATransaction extends LightningElement {
  limits = [];
  error;
  chartJsInitialized = false;
  wiredLimitsResult;
  showSuggestions = false;
  selectedLimitName = "";
  currentSuggestions = [];

  labelMap = {
    API: "API Usage",
    Storage: "Storage",
    PlatformEvents: "Platform Events",
    Email: "Email",
    ReportsDashboards: "Reports / Dashboards",
    Analytics: "Analytics",
    AsyncApex: "Async Apex",
    MetadataDeploy: "Deployments",
    Others: "Other Limits",
  };

  @wire(getOrgLimits)
  wiredLimits(result) {
    this.wiredLimitsResult = result;
    const { data, error } = result;
    if (data) {
      this.limits = data;
      if (this.chartJsInitialized) {
        this.initializeCharts();
      }
    } else if (error) {
      this.error = error;
    }
  }

  handleRefresh() {
    refreshApex(this.wiredLimitsResult);
  }

  renderedCallback() {
    if (this.chartJsInitialized) {
      this.initializeCharts();
      return;
    }

    loadScript(this, chartsResource)
      .then(() => {
        this.chartJsInitialized = true;

        // Register the centerText plugin once
        if (!window.Chart.registry.plugins.get("centerText")) {
          window.Chart.register({
            id: "centerText",
            beforeDraw(chart) {
              const pluginConfig = chart.config.options.plugins.centerText;
              if (!pluginConfig || !pluginConfig.display) return;

              const ctx = chart.ctx;
              const width = chart.width;
              const height = chart.height;
              const fontSize = (height / 5).toFixed(2);
              const text = pluginConfig.text;

              ctx.save();
              ctx.font = `${fontSize}px Arial`;
              ctx.fillStyle = "#000";
              ctx.textBaseline = "middle";
              const textX = Math.round(
                (width - ctx.measureText(text).width) / 2
              );
              const textY = height / 1.25;
              ctx.fillText(text, textX, textY);
              ctx.restore();
            },
          });
        }

        if (this.limits && this.limits.length > 0) {
          this.initializeCharts();
        }
      })
      .catch((error) => {
        this.error = error;
      });
  }
  getTwoLineName(name) {
    if (!name) return "";
    const words = name.split(" ");
    if (words.length < 2) return name;
    // Split roughly in half
    const mid = Math.ceil(words.length / 2);
    return words.slice(0, mid).join(" ") + "<br>" + words.slice(mid).join(" ");
  }
  getColorByPercent(percent) {
    if (percent < 80) {
      return "#2ECC71"; // Green
    } else if (percent >= 80 && percent <= 90) {
      return "#F39C12"; // Orange
    } else {
      return "#E74C3C"; // Red
    }
  }
  initializeCharts() {
    if (!window.Chart) return;
    this.limits.forEach((limit) => {
      const canvas = this.template.querySelector(
        `canvas[data-id="${limit.name}"]`
      );
      const percent =
        limit.max && limit.max !== 0
          ? Math.round((limit.used / limit.max) * 100)
          : 0;
      const usedColor = percent >= 90 ? this.ALERT_COLOR : this.DEFAULT_COLOR;
      // const usedColor =   this.getColorByPercent(percent);

      if (canvas) {
        if (canvas.chartInstance) {
          canvas.chartInstance.destroy();
        }
        const green = "#2ECC71";
        const orange = "#F39C12";
        const red = "#E74C3C";
        const grey = "#E0E0E0";

        let data = [];
        let backgroundColor = [];

        if (displayPercent <= 80) {
          data = [displayPercent, 100 - displayPercent];
          backgroundColor = [green, grey];
        } else if (displayPercent <= 90) {
          data = [80, displayPercent - 80, 100 - displayPercent];
          backgroundColor = [green, orange, grey];
        } else {
          console.log("percent in else" + percent);

          data = [80, 10, percent - 90, 100 - percent];
          backgroundColor = [green, orange, red, grey];
        }
        const ctx = canvas.getContext("2d");
        canvas.chartInstance = new window.Chart(ctx, {
          type: "doughnut",
          data: {
            labels: ["Used", "Remaining"],
            datasets: [
              {
                data: data,
                backgroundColor: backgroundColor,
                borderWidth: 1,
              },
            ],
          },
          // data: {
          //     labels: ["Used", "Remaining"],
          //     datasets: [
          //       {
          //         data: [percent, 100 - percent],
          //         backgroundColor: [usedColor, "#E0E0E0"],
          //         borderWidth: 1,
          //       },
          //     ],
          //   },

          // data: {
          //     labels: ['Used', 'Remaining'],
          //     datasets: [{
          //         data: [percent, 100 - percent],
          //         backgroundColor: [usedColor, '#e0e0e0'],
          //         borderWidth: 1
          //     }],

          // },
          options: {
            rotation: -Math.PI,
            circumference: Math.PI,
            cutoutPercentage: 70,
            tooltips: { enabled: false },
            legend: { display: false },
            animation: {
              animateRotate: true,
              onComplete: function () {
                const chartInstance = this.chart;
                const ctx = chartInstance.ctx;
                const width = chartInstance.width;
                const height = chartInstance.height;
                ctx.restore();
                const fontSize = (height / 5).toFixed(2);
                ctx.font = `${fontSize}px Arial`;
                ctx.textBaseline = "middle";
                ctx.fillStyle = "#000";
                const text = `${percent}%`;
                console.log("text" + text);

                const textX = Math.round(
                  (width - ctx.measureText(text).width) / 2
                );
                console.log("text in  textX " + textX);
                const textY = height / 1.25;
                console.log("text in  textY " + textY);
                ctx.fillText(text, textX, textY);
                ctx.save();
              },
            },
          },
        });
      }
    });
  }
  get groupedLimits() {
    const groups = {};
    this.limits.forEach((limit) => {
      const category = limit.category || "Other";
      if (!groups[category]) {
        groups[category] = [];
      }
      // Add two-line name for each limit
      const [line1, line2] = this.splitNameTwoLines(limit.name);
      groups[category].push({ ...limit, line1, line2 });
    });
    // return Object.entries(groups).map(([category, limits]) => ({ category, limits }));
    return Object.entries(categories).map(([type, limits]) => {
      const shouldHighlight = limits.some((limit) => {
        const percent =
          limit.max && limit.max !== 0
            ? Math.round((limit.used / limit.max) * 100)
            : 0;
        return percent >= 90;
      });
      return { type, limits, highlight: shouldHighlight };
    });
  }
  getTabClass(group) {
    return group.highlight ? "tab-alert" : "";
  }
  splitNameTwoLines(name) {
    if (!name) return ["", ""];
    const words = name.split(" ");
    if (words.length < 2) {
      const mid = Math.ceil(name.length / 2);
      return [name.slice(0, mid), name.slice(mid)];
    }
    const mid = Math.ceil(words.length / 2);
    return [words.slice(0, mid).join(" "), words.slice(mid).join(" ")];
  }
  get categorizedLimits() {
    const categories = {
      API: [],
      Storage: [],
      PlatformEvents: [],
      Email: [],
      ReportsDashboards: [],
      Analytics: [],
      AsyncApex: [],
      MetadataDeploy: [],
      Others: [],
    };

    this.limits.forEach((limit) => {
      const name = limit.name ? limit.name.toLowerCase() : "";
      if (name.includes("api")) {
        categories.API.push(limit);
      } else if (name.includes("storage") || name.includes("content")) {
        categories.Storage.push(limit);
      } else if (
        name.includes("event") ||
        name.includes("stream") ||
        name.includes("platformevent")
      ) {
        categories.PlatformEvents.push(limit);
      } else if (name.includes("email")) {
        categories.Email.push(limit);
      } else if (name.includes("dashboard") || name.includes("report")) {
        categories.ReportsDashboards.push(limit);
      } else if (name.includes("einstein") || name.includes("analytics")) {
        categories.Analytics.push(limit);
      } else if (name.includes("apex") || name.includes("workflow")) {
        categories.AsyncApex.push(limit);
      } else if (name.includes("metadata") || name.includes("package")) {
        categories.MetadataDeploy.push(limit);
      } else {
        categories.Others.push(limit);
      }
    });
    // Convert to array for template iteration
    // return Object.entries(categories).map(([type, limits]) => ({ type, limits }));
    return Object.entries(categories).map(([type, limits]) => {
      const overLimit = limits.some(
        (l) => l.max > 0 && (l.used / l.max) * 100 >= 80
      );
      const label = overLimit
        ? "⚠️ " + this.labelMap[type]
        : this.labelMap[type];
      return { type, limits, label };
    });
  }
  handleTabChange(event) {
    const tabLabel = event.target.label;
    console.log("tabLabel" + tabLabel);

    // Delay to allow DOM to render
    setTimeout(() => {
      this.initializeCharts();
    }, 0);
  }

  handleSuggestionClick(event) {
    const limitName = event.currentTarget.dataset.limitName;
    this.selectedLimitName = limitName;

    getLimitSuggestions({ limitName: this.selectedLimitName })
      .then((result) => {
        this.currentSuggestions = result.map((item) => item.message);
        this.showSuggestions = true;
      })
      .catch((error) => {
        this.currentSuggestions = ["Error retrieving suggestions."];
        this.error = error;
        this.showSuggestions = true;
      });
  }

  closeSuggestions() {
    this.showSuggestions = false;
  }
}
