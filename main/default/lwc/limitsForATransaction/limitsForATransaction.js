import { LightningElement, wire } from 'lwc';
import getOrgLimits from '@salesforce/apex/LimitsForATransactionController.getOrgLimits';
import chartjs from '@salesforce/resourceUrl/Chatjs';
import { loadScript } from 'lightning/platformResourceLoader';
import { refreshApex } from '@salesforce/apex';


export default class LimitsForATransaction extends LightningElement {
    limits = [];
    error;
    chartJsInitialized = false;
    wiredLimitsResult

    // Palette does NOT include red!
    get COLORS() {
        return [
            '#0070d2', '#36a2eb', '#ffce56', '#4bc0c0', '#9966ff', '#ff9f40', '#c9cbcf',
            '#3cb44b', '#ffe119', '#4363d8', '#f58231', '#911eb4', '#46f0f0', '#f032e6'
        ];
    }

    // Unique alert color (red)
    get ALERT_COLOR() {
        return '#ff0000';
    }
    handleRefresh() {
        refreshApex(this.wiredLimitsResult);
    }
    

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

    renderedCallback() {
        if (this.chartJsInitialized) {
            this.initializeCharts();
            return;
        }
        loadScript(this, chartjs)
            .then(() => {
                this.chartJsInitialized = true;
                if (this.limits && this.limits.length > 0) {
                    this.initializeCharts();
                }
            })
            .catch(error => {
                this.error = error;
            });
    }

    initializeCharts() {
        if (!window.Chart) return;
        this.limits.forEach((limit, idx) => {
            const canvas = this.template.querySelector(`canvas[data-id="${limit.name}"]`);
            if (canvas) {
                if (canvas.chartInstance) {
                    canvas.chartInstance.destroy();
                }
                const ctx = canvas.getContext('2d');
                const percent = limit.max && limit.max !== 0 ? Math.round((limit.used / limit.max) * 100) : 0;
                console.log('percent'+percent);
                
                // Use red only if percent >= 90, otherwise use palette color
                const usedColor = percent >= 90 ? this.ALERT_COLOR : this.COLORS[idx % this.COLORS.length];
                canvas.chartInstance = new window.Chart(ctx, {
                    type: 'doughnut',
                    data: {
                        labels: ['Used', 'Remaining'],
                        datasets: [{
                            data: [percent, 100 - percent],
                            backgroundColor: [usedColor, '#e0e0e0'],
                            borderWidth: 1
                        }]
                    },
                    options: {
                        rotation: -Math.PI,         // Start at the bottom
                        circumference: Math.PI, 
                       // rotation: -90,
                        //circumference: 180,
                        cutout: '70%',
                        plugins: {
                            tooltip: { enabled: true },
                            legend: { display: false }
                        }
                    }
                });
            }
        });
    }
}
