import { LightningElement, wire } from 'lwc';
import getOrgLimits from '@salesforce/apex/LimitsForATransactionController.getOrgLimits';
import chartjs from '@salesforce/resourceUrl/Chatjs';
import { loadScript } from 'lightning/platformResourceLoader';
import { refreshApex } from '@salesforce/apex';


export default class LimitsForATransaction extends LightningElement {
    limits = [];
    error;
    chartJsInitialized = false;
    wiredLimitsResult;

    labelMap = {
        API: 'API Usage',
        Storage: 'Storage',
        PlatformEvents: 'Platform Events',
        Email: 'Email',
        ReportsDashboards: 'Reports / Dashboards',
        Analytics: 'Analytics',
        AsyncApex: 'Async Apex ',
        MetadataDeploy: 'Deployments',
        Others: 'Other Limits'
    };
    get DEFAULT_COLOR() {
        return '#27ae60'; // Green
    }

    get ALERT_COLOR() {
        return '#ff0000'; // Red
    }

    @wire(getOrgLimits)
    wiredLimits(result) {
        this.wiredLimitsResult = result;
        const { data, error } = result;
        if (data) {
            this.limits = data;
            console.log('Limits data:', JSON.stringify(this.limits));
            
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
    data = {
        datasets: [{
            data: [80, 10, 10],
            backgroundColor: ['#FF3B30', '#FF9500', '#34C759'], // red, orange, green
            borderWidth: 0,
            cutout: '80%',
            circumference: 180,
            rotation: 270
        }]
    };


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
    getColorByPercent(percent) {
        if (percent < 80) {
            return '#2ECC71'; // Green
        } else if (percent >= 80 && percent <= 90) {
            return '#F39C12'; // Orange
        } else {
            return '#E74C3C'; // Red
        }
    }
    initializeCharts() {
        if (!window.Chart) return;
        this.limits.forEach((limit) => {
            const canvas = this.template.querySelector(`canvas[data-id="${limit.name}"]`);
            const percent = limit.max && limit.max !== 0 ? Math.round((limit.used / limit.max) * 100) : 0;
            const displayPercent =  percent >= 100 ? 100 : percent;
            if (canvas) {
                if (canvas.chartInstance) {
                    canvas.chartInstance.destroy();
                }
                const green = '#2ECC71';
            const orange = '#F39C12';
            const red = '#E74C3C';
            const grey = '#E0E0E0';

            let data = [];
            let backgroundColor = [];

            if (displayPercent <= 80) {
                data = [displayPercent, 100 - displayPercent];
                backgroundColor = [green, grey];
            } else if (displayPercent <= 90) {
                data = [80, displayPercent - 80, 100 - displayPercent];
                backgroundColor = [green, orange, grey];
            } else {
                //console.log('percent in else'+percent);
                
                data = [80, 10, displayPercent - 90, 100 - displayPercent];
                backgroundColor = [green, orange, red, grey];
            }
                const ctx = canvas.getContext('2d');
                canvas.chartInstance = new window.Chart(ctx, {
                    type: 'doughnut',
                    data: {
                        labels: ["Used", "Remaining"],
                        datasets: [{
                            data: data,
                            backgroundColor: backgroundColor,
                            borderWidth: 1
                        }]
                    },
                    options: {
                        rotation: -Math.PI,
                        circumference: Math.PI,
                        cutoutPercentage: 80,
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
                                ctx.textBaseline = 'middle';
                                ctx.fillStyle = '#000';
                                const text = `${displayPercent}%`;
                                console.log('text' +text );
                                
                                const textX = Math.round((width - ctx.measureText(text).width) / 2);
                                console.log('text in  textX ' +textX );
                                const textY = height / 1.25;
                                console.log('text in  textY ' +textY );
                                ctx.fillText(text, textX, textY);
                                ctx.save();
                            }
                        }
                    }
                });
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
        Others: []
        };
        this.limits.forEach(limit => {
            const name = limit.name ? limit.name.toLowerCase() : '';
            if (name.includes('api')) {
                categories.API.push(limit);
            } else if (name.includes('storage')  || name.includes('content')) {
                categories.Storage.push(limit);
            } else if (name.includes('event') || name.includes('stream') || name .includes('platformevent')) {
                categories.PlatformEvents.push(limit);
            } 
            else if (name.includes('email')) {
                categories.Email.push(limit);
            } else if (name.includes('dashboard') || name.includes('report')) {
                categories.ReportsDashboards.push(limit);
            } else if (name.includes('einstein') || name.includes('analytics')) {
                categories.Analytics.push(limit);
            } else if (name.includes('apex') || name.includes('workflow')) {
                categories.AsyncApex.push(limit);
            } else if (name.includes('metadata') || name.includes('package')) {
                categories.MetadataDeploy.push(limit);
            } else {
                categories.Others.push(limit);
            }
        });
        return Object.entries(categories).map(([type, limits]) => {
            const updatedLimits = limits.map(l => {
                const used = (l.name === 'FileStorageMB' || l.name === 'DataStorageMB') && l.used > l.max ? l.max : l.used;
                return {
                    ...l,
                used
                };
            });
            const overLimit = limits.some(l => l.max > 0 && (l.used / l.max) * 100 >= 90);
            const label = overLimit ? this.labelMap[type] + '⚠️ '  : this.labelMap[type];
            // const cappedUsed = actualUsed > maxValue ? maxValue : actualUsed;
            return { type, limits:updatedLimits, label };
        });
    }
    handleTabChange(event) {
        const tabLabel = event.target.label;
        setTimeout(() => {
            this.initializeCharts();
        }, 0);
    }
}