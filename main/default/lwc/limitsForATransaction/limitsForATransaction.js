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

    // Register plugin only once
    if (!Chart.plugins.getAll().some((p) => p.id === "centerTextPlugin")) {
      Chart.plugins.register({
        id: "centerTextPlugin",
        afterDraw: function (chart) {
          const ctx = chart.chart.ctx;
          const width = chart.chart.width;
          const height = chart.chart.height;
          const percent = chart.config.data.metaPercent || 0;
          const text = `${percent}%`;

          ctx.save();
          const fontSize = (height / 5).toFixed(2);
          ctx.font = `${fontSize}px Arial`;
          ctx.textBaseline = "middle";
          ctx.fillStyle = "#000";

          const textX = Math.round((width - ctx.measureText(text).width) / 2);
          const textY = height / 1.25;

          ctx.fillText(text, textX, textY);
          ctx.restore();
        },
      });
    }

    this.limits.forEach((limit) => {
      const canvas = this.template.querySelector(
        `canvas[data-id="${limit.name}"]`
      );
      const percent =
        limit.max && limit.max !== 0
          ? Math.round((limit.used / limit.max) * 100)
          : 0;
      const displayPercent = Math.min(percent, 100); // cap at 100%

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
          data = [80, 10, displayPercent - 90, 100 - displayPercent];
          backgroundColor = [green, orange, red, grey];
        }

        const ctx = canvas.getContext("2d");

        const chartConfig = {
          type: "doughnut",
          data: {
            labels: ["Used", "Remaining"],
            datasets: [
              {
                data: data,
                backgroundColor: backgroundColor,
                borderWidth: 0, // to avoid unwanted gaps
              },
            ],
            metaPercent: displayPercent, // used by plugin
          },
          options: {
            responsive: false,
            animation: false, // disables flickering
            rotation: -Math.PI,
            circumference: Math.PI,
            cutoutPercentage: 80,
            tooltips: { enabled: false },
            legend: { display: false },
            events: [], // disables hover re-renders
          },
        };

        canvas.chartInstance = new Chart(ctx, chartConfig);
      }
    });
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
      const percent = limit.max
        ? Math.round((limit.used / limit.max) * 100)
        : 0;

      const limitWithStyle = {
        ...limit,
        percentUsed: percent,
        showBulb: limit.threshold ? percent >= limit.threshold : percent >= 90,
      };

      if (name.includes("api")) categories.API.push(limitWithStyle);
      else if (name.includes("storage") || name.includes("content"))
        categories.Storage.push(limitWithStyle);
      else if (name.includes("event") || name.includes("stream"))
        categories.PlatformEvents.push(limitWithStyle);
      else if (name.includes("email")) categories.Email.push(limitWithStyle);
      else if (name.includes("dashboard") || name.includes("report"))
        categories.ReportsDashboards.push(limitWithStyle);
      else if (name.includes("einstein") || name.includes("analytics"))
        categories.Analytics.push(limitWithStyle);
      else if (name.includes("apex") || name.includes("workflow"))
        categories.AsyncApex.push(limitWithStyle);
      else if (name.includes("metadata") || name.includes("package"))
        categories.MetadataDeploy.push(limitWithStyle);
      else categories.Others.push(limitWithStyle);
    });

    return Object.entries(categories).map(([type, limits]) => {
      const updatedLimits = limits.map((l) => {
        const used =
          (l.name === "FileStorageMB" || l.name === "DataStorageMB") &&
          l.used > l.max
            ? l.max
            : l.used;
        return {
          ...l,
          used,
        };
      });

      const overLimit = limits.some(
        (l) => l.max > 0 && (l.used / l.max) * 100 >= 90
      );
      const label = overLimit
        ? this.labelMap[type] + "⚠️ "
        : this.labelMap[type];
      return { type, limits: updatedLimits, label };
    });
  }

  handleTabChange() {
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
