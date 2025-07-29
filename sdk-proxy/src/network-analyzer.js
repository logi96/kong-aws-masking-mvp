const { spawn, exec } = require('child_process');
const fs = require('fs').promises;
const path = require('path');

/**
 * @typedef {Object} TrafficCapture
 * @property {string} timestamp - ISO timestamp
 * @property {string} source - Source IP:port
 * @property {string} destination - Destination IP:port
 * @property {string} protocol - Protocol (TCP/UDP)
 * @property {string} flags - TCP flags
 * @property {string} raw - Raw packet data
 */

/**
 * @typedef {Object} ProxyAnalysis
 * @property {boolean} proxyUsed - Whether proxy is being used
 * @property {string[]} directConnections - Direct connections to api.anthropic.com
 * @property {string[]} proxyConnections - Connections through proxy
 * @property {Object} diagnosis - Diagnostic information
 * @property {string[]} possibleCauses - List of possible causes
 */

class NetworkAnalyzer {
    constructor() {
        this.tcpdumpProcess = null;
        this.capturedPackets = [];
        this.proxyPort = process.env.PROXY_PORT || 8888;
        this.anthropicDomains = ['api.anthropic.com', 'claude.ai'];
        this.anthropicIPs = [];
        this.resultsDir = '/app/results';
    }

    /**
     * Initialize the network analyzer
     */
    async init() {
        // Ensure results directory exists
        await fs.mkdir(this.resultsDir, { recursive: true });
        
        // Resolve Anthropic IPs
        await this.resolveAnthropicIPs();
    }

    /**
     * Resolve Anthropic domain IPs
     */
    async resolveAnthropicIPs() {
        const dns = require('dns').promises;
        
        for (const domain of this.anthropicDomains) {
            try {
                const addresses = await dns.resolve4(domain);
                this.anthropicIPs.push(...addresses);
                console.log(`Resolved ${domain} to:`, addresses);
            } catch (error) {
                console.error(`Failed to resolve ${domain}:`, error.message);
            }
        }
    }

    /**
     * Start capturing network traffic
     * @param {number} duration - Capture duration in seconds
     * @returns {Promise<void>}
     */
    async startCapture(duration = 30) {
        return new Promise((resolve, reject) => {
            const filter = `(dst host ${this.anthropicDomains.join(' or dst host ')}) or (dst port ${this.proxyPort})`;
            
            // Use tcpdump to capture traffic
            this.tcpdumpProcess = spawn('tcpdump', [
                '-i', 'any',           // All interfaces
                '-n',                  // Don't resolve hostnames
                '-tt',                 // Timestamps
                '-vv',                 // Verbose
                '-X',                  // Hex dump
                '-s', '0',             // Full packet capture
                filter
            ]);

            let captureData = '';
            let errorData = '';

            this.tcpdumpProcess.stdout.on('data', (data) => {
                captureData += data.toString();
                this.parsePacketData(data.toString());
            });

            this.tcpdumpProcess.stderr.on('data', (data) => {
                errorData += data.toString();
            });

            this.tcpdumpProcess.on('error', (error) => {
                reject(new Error(`Failed to start tcpdump: ${error.message}`));
            });

            // Stop capture after duration
            setTimeout(() => {
                this.stopCapture();
                resolve();
            }, duration * 1000);
        });
    }

    /**
     * Stop capturing traffic
     */
    stopCapture() {
        if (this.tcpdumpProcess) {
            this.tcpdumpProcess.kill('SIGTERM');
            this.tcpdumpProcess = null;
        }
    }

    /**
     * Parse tcpdump output
     * @param {string} data - Raw tcpdump output
     */
    parsePacketData(data) {
        const lines = data.split('\n');
        
        for (const line of lines) {
            if (line.includes('>') && line.includes(':')) {
                const match = line.match(/(\d+\.\d+\.\d+\.\d+)\.(\d+) > (\d+\.\d+\.\d+\.\d+)\.(\d+):/);
                if (match) {
                    const packet = {
                        timestamp: new Date().toISOString(),
                        source: `${match[1]}:${match[2]}`,
                        destination: `${match[3]}:${match[4]}`,
                        protocol: 'TCP',
                        flags: this.extractTCPFlags(line),
                        raw: line
                    };
                    
                    this.capturedPackets.push(packet);
                }
            }
        }
    }

    /**
     * Extract TCP flags from tcpdump line
     * @param {string} line - tcpdump line
     * @returns {string} TCP flags
     */
    extractTCPFlags(line) {
        const flagMatch = line.match(/Flags \[([^\]]+)\]/);
        return flagMatch ? flagMatch[1] : '';
    }

    /**
     * Analyze captured traffic for proxy usage
     * @returns {ProxyAnalysis}
     */
    analyzeProxyUsage() {
        const analysis = {
            proxyUsed: false,
            directConnections: [],
            proxyConnections: [],
            diagnosis: {
                totalPackets: this.capturedPackets.length,
                uniqueConnections: new Set(),
                connectionTypes: {}
            },
            possibleCauses: []
        };

        // Analyze each packet
        for (const packet of this.capturedPackets) {
            const destIP = packet.destination.split(':')[0];
            const destPort = packet.destination.split(':')[1];
            
            // Check if connection is to Anthropic directly
            if (this.anthropicIPs.includes(destIP) || destPort === '443') {
                if (destPort === this.proxyPort.toString()) {
                    analysis.proxyConnections.push(packet);
                    analysis.proxyUsed = true;
                } else {
                    analysis.directConnections.push(packet);
                }
            }
            
            // Track unique connections
            analysis.diagnosis.uniqueConnections.add(packet.destination);
        }

        // Diagnose issues
        if (analysis.directConnections.length > 0 && !analysis.proxyUsed) {
            analysis.possibleCauses.push('Proxy settings not being respected by the application');
            analysis.possibleCauses.push('HTTPS_PROXY environment variable might be ignored');
            analysis.possibleCauses.push('Application may be using hardcoded connection settings');
        }

        if (analysis.directConnections.length > 0 && analysis.proxyUsed) {
            analysis.possibleCauses.push('Partial proxy bypass detected - some connections go direct');
            analysis.possibleCauses.push('Application may have multiple HTTP clients with different configurations');
        }

        return analysis;
    }

    /**
     * Check system proxy settings
     * @returns {Promise<Object>}
     */
    async checkSystemProxySettings() {
        const settings = {
            environment: {},
            systemProxy: {},
            npmProxy: null,
            gitProxy: null
        };

        // Check environment variables
        const proxyVars = ['HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy', 'NO_PROXY', 'no_proxy'];
        for (const varName of proxyVars) {
            if (process.env[varName]) {
                settings.environment[varName] = process.env[varName];
            }
        }

        // Check npm proxy settings
        try {
            const npmProxy = await this.execCommand('npm config get proxy');
            const npmHttpsProxy = await this.execCommand('npm config get https-proxy');
            settings.npmProxy = {
                proxy: npmProxy.trim(),
                httpsProxy: npmHttpsProxy.trim()
            };
        } catch (error) {
            console.error('Failed to get npm proxy settings:', error);
        }

        // Check git proxy settings
        try {
            const gitHttpProxy = await this.execCommand('git config --global http.proxy');
            const gitHttpsProxy = await this.execCommand('git config --global https.proxy');
            settings.gitProxy = {
                httpProxy: gitHttpProxy.trim(),
                httpsProxy: gitHttpsProxy.trim()
            };
        } catch (error) {
            console.error('Failed to get git proxy settings:', error);
        }

        return settings;
    }

    /**
     * Execute command and return output
     * @param {string} command - Command to execute
     * @returns {Promise<string>}
     */
    async execCommand(command) {
        return new Promise((resolve, reject) => {
            exec(command, (error, stdout, stderr) => {
                if (error) {
                    reject(error);
                } else {
                    resolve(stdout);
                }
            });
        });
    }

    /**
     * Check if process is bypassing proxy
     * @param {number} pid - Process ID to check
     * @returns {Promise<Object>}
     */
    async checkProcessProxyBypass(pid) {
        const result = {
            pid,
            connections: [],
            bypassingProxy: false
        };

        try {
            // Use lsof to check process connections
            const lsofOutput = await this.execCommand(`lsof -p ${pid} -i TCP`);
            const lines = lsofOutput.split('\n');
            
            for (const line of lines) {
                if (line.includes('api.anthropic.com') || this.anthropicIPs.some(ip => line.includes(ip))) {
                    result.connections.push(line);
                    
                    // Check if connection is direct (not through proxy)
                    if (!line.includes(`:${this.proxyPort}`)) {
                        result.bypassingProxy = true;
                    }
                }
            }
        } catch (error) {
            console.error(`Failed to check process ${pid}:`, error);
        }

        return result;
    }

    /**
     * Generate comprehensive analysis report
     * @param {ProxyAnalysis} proxyAnalysis - Proxy usage analysis
     * @param {Object} systemSettings - System proxy settings
     * @returns {string} Analysis report
     */
    generateReport(proxyAnalysis, systemSettings) {
        const report = [];
        
        report.push('=== Network Traffic Analysis Report ===');
        report.push(`Generated: ${new Date().toISOString()}`);
        report.push('');
        
        // Summary
        report.push('## Summary');
        report.push(`Total packets captured: ${proxyAnalysis.diagnosis.totalPackets}`);
        report.push(`Direct connections to Anthropic: ${proxyAnalysis.directConnections.length}`);
        report.push(`Proxy connections: ${proxyAnalysis.proxyConnections.length}`);
        report.push(`Proxy properly used: ${proxyAnalysis.proxyUsed ? 'Yes' : 'No'}`);
        report.push('');
        
        // System Proxy Settings
        report.push('## System Proxy Settings');
        report.push('### Environment Variables:');
        for (const [key, value] of Object.entries(systemSettings.environment)) {
            report.push(`  ${key}: ${value}`);
        }
        if (Object.keys(systemSettings.environment).length === 0) {
            report.push('  No proxy environment variables set');
        }
        report.push('');
        
        report.push('### NPM Proxy:');
        if (systemSettings.npmProxy) {
            report.push(`  proxy: ${systemSettings.npmProxy.proxy || 'not set'}`);
            report.push(`  https-proxy: ${systemSettings.npmProxy.httpsProxy || 'not set'}`);
        }
        report.push('');
        
        report.push('### Git Proxy:');
        if (systemSettings.gitProxy) {
            report.push(`  http.proxy: ${systemSettings.gitProxy.httpProxy || 'not set'}`);
            report.push(`  https.proxy: ${systemSettings.gitProxy.httpsProxy || 'not set'}`);
        }
        report.push('');
        
        // Direct Connections
        if (proxyAnalysis.directConnections.length > 0) {
            report.push('## Direct Connections Detected');
            report.push('WARNING: The following connections bypassed the proxy:');
            proxyAnalysis.directConnections.slice(0, 10).forEach((packet, index) => {
                report.push(`  ${index + 1}. ${packet.source} -> ${packet.destination} [${packet.flags}]`);
            });
            if (proxyAnalysis.directConnections.length > 10) {
                report.push(`  ... and ${proxyAnalysis.directConnections.length - 10} more`);
            }
            report.push('');
        }
        
        // Diagnosis
        report.push('## Diagnosis');
        if (proxyAnalysis.possibleCauses.length > 0) {
            report.push('Possible causes for proxy bypass:');
            proxyAnalysis.possibleCauses.forEach((cause, index) => {
                report.push(`  ${index + 1}. ${cause}`);
            });
        } else {
            report.push('No proxy bypass issues detected.');
        }
        report.push('');
        
        // Recommendations
        report.push('## Recommendations');
        if (!proxyAnalysis.proxyUsed) {
            report.push('1. Ensure HTTPS_PROXY environment variable is set correctly');
            report.push('2. Check if the application respects proxy environment variables');
            report.push('3. Verify that the proxy server is running and accessible');
            report.push('4. Consider using proxy-agent or similar libraries for better proxy support');
            report.push('5. Check for hardcoded API endpoints that might bypass proxy settings');
        } else if (proxyAnalysis.directConnections.length > 0) {
            report.push('1. Some connections are bypassing the proxy - check for multiple HTTP clients');
            report.push('2. Ensure all HTTP clients in the application use the same proxy configuration');
            report.push('3. Check for WebSocket or other protocols that might not respect HTTP proxy settings');
        } else {
            report.push('Proxy configuration appears to be working correctly.');
        }
        
        return report.join('\n');
    }

    /**
     * Run complete network analysis
     * @param {Object} options - Analysis options
     * @returns {Promise<void>}
     */
    async analyze(options = {}) {
        const { duration = 30, outputFile = 'traffic-analysis.txt' } = options;
        
        try {
            console.log('Initializing network analyzer...');
            await this.init();
            
            console.log(`Starting traffic capture for ${duration} seconds...`);
            await this.startCapture(duration);
            
            console.log('Analyzing captured traffic...');
            const proxyAnalysis = this.analyzeProxyUsage();
            
            console.log('Checking system proxy settings...');
            const systemSettings = await this.checkSystemProxySettings();
            
            console.log('Generating report...');
            const report = this.generateReport(proxyAnalysis, systemSettings);
            
            // Save report
            const outputPath = path.join(this.resultsDir, outputFile);
            await fs.writeFile(outputPath, report);
            console.log(`Analysis report saved to: ${outputPath}`);
            
            // Also output to console
            console.log('\n' + report);
            
        } catch (error) {
            console.error('Network analysis failed:', error);
            throw error;
        }
    }
}

// Export for use as module
module.exports = NetworkAnalyzer;

// Run if called directly
if (require.main === module) {
    const analyzer = new NetworkAnalyzer();
    analyzer.analyze({
        duration: process.argv[2] ? parseInt(process.argv[2]) : 30
    }).catch(console.error);
}