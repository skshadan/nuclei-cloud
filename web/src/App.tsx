import React, { useState, useEffect } from 'react';
import './styles/App.css';

interface ScanResult {
  host: string;
  template: string;
  severity: string;
  match: string;
  timestamp: string;
  workerId: string;
}

interface WorkerStatus {
  id: string;
  ip: string;
  progress: number;
  currentDomain: string;
  domainsScanned: number;
  totalDomains: number;
  status: string;
}

interface ScanStatus {
  id: string;
  progress: number;
  activeDroplets: WorkerStatus[];
  results: ScanResult[];
  totalDomains: number;
  scannedDomains: number;
  status: string;
}

const App: React.FC = () => {
  const [domains, setDomains] = useState<string>('');
  const [droplets, setDroplets] = useState<number>(3);
  const [scanning, setScanning] = useState<boolean>(false);
  const [scanId, setScanId] = useState<string>('');
  const [scanStatus, setScanStatus] = useState<ScanStatus | null>(null);
  const [ws, setWs] = useState<WebSocket | null>(null);

  // WebSocket connection
  useEffect(() => {
    if (scanId && scanning) {
      const websocket = new WebSocket(`ws://${window.location.host}/ws/${scanId}`);
      
      websocket.onopen = () => {
        console.log('WebSocket connected');
      };

      websocket.onmessage = (event) => {
        const message = JSON.parse(event.data);
        
        switch (message.type) {
          case 'status_update':
            setScanStatus(message.data);
            break;
          case 'new_result':
            setScanStatus(prev => prev ? {
              ...prev,
              results: [...prev.results, message.data]
            } : null);
            break;
          case 'scan_complete':
            setScanStatus(message.data);
            setScanning(false);
            break;
        }
      };

      websocket.onclose = () => {
        console.log('WebSocket disconnected');
      };

      setWs(websocket);

      return () => {
        websocket.close();
      };
    }
  }, [scanId, scanning]);

  const startScan = async () => {
    const domainList = domains.split('\n').filter(d => d.trim());
    
    if (domainList.length === 0) {
      alert('Please enter at least one domain');
      return;
    }

    try {
      const response = await fetch('/api/scan', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          domains: domainList,
          droplets: droplets,
        }),
      });

      const data = await response.json();
      
      if (response.ok) {
        setScanId(data.scan_id);
        setScanning(true);
        setScanStatus(null);
      } else {
        alert(`Error: ${data.error}`);
      }
    } catch (error) {
      alert(`Network error: ${error}`);
    }
  };

  const stopScan = () => {
    if (ws) {
      ws.close();
    }
    setScanning(false);
    setScanId('');
    setScanStatus(null);
  };

  const exportResults = () => {
    if (!scanStatus || scanStatus.results.length === 0) {
      alert('No results to export');
      return;
    }

    const csv = [
      'Host,Template,Severity,Match,Timestamp,Worker ID',
      ...scanStatus.results.map(r => 
        `"${r.host}","${r.template}","${r.severity}","${r.match}","${r.timestamp}","${r.workerId}"`
      )
    ].join('\n');

    const blob = new Blob([csv], { type: 'text/csv' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `nuclei-scan-${scanId}.csv`;
    a.click();
    window.URL.revokeObjectURL(url);
  };

  const getSeverityClass = (severity: string) => {
    switch (severity.toLowerCase()) {
      case 'critical': return 'severity-critical';
      case 'high': return 'severity-high';
      case 'medium': return 'severity-medium';
      case 'low': return 'severity-low';
      default: return 'severity-info';
    }
  };

  return (
    <div className="app-container">
      <header className="header">
        <h1> Nuclei Distributed Scanner</h1>
        <p>Scan thousands of domains across multiple droplets</p>
      </header>

      <div className="main-content">
        <div className="config-panel">
          <div className="card">
            <h3>Scan Configuration</h3>
            
            <div className="input-group">
              <label>Target Domains</label>
              <textarea
                className="domains-input"
                value={domains}
                onChange={(e) => setDomains(e.target.value)}
                placeholder="Enter domains (one per line)&#10;example.com&#10;test.com&#10;target.org"
                rows={10}
                disabled={scanning}
              />
              <small>Enter one domain per line</small>
            </div>

            <div className="controls">
              <div className="droplet-control">
                <label>Number of Droplets</label>
                <input
                  type="number"
                  min={1}
                  max={10}
                  value={droplets}
                  onChange={(e) => setDroplets(parseInt(e.target.value))}
                  disabled={scanning}
                />
                <small>1-10 droplets (auto-optimized)</small>
              </div>

              <div className="button-group">
                {!scanning ? (
                  <button className="scan-button primary" onClick={startScan}>
                    🚀 Start Scan
                  </button>
                ) : (
                  <button className="scan-button danger" onClick={stopScan}>
                    ⏹️ Stop Scan
                  </button>
                )}
                
                {scanStatus && scanStatus.results.length > 0 && (
                  <button className="scan-button secondary" onClick={exportResults}>
                    📥 Export Results
                  </button>
                )}
              </div>
            </div>
          </div>
        </div>

        {scanning && scanStatus && (
          <div className="status-panel">
            <div className="card">
              <h3>Scan Progress</h3>
              
              <div className="overall-progress">
                <div className="progress-info">
                  <span>Overall Progress: {scanStatus.progress.toFixed(1)}%</span>
                  <span>{scanStatus.scannedDomains} / {scanStatus.totalDomains} domains</span>
                </div>
                <div className="progress-bar">
                  <div 
                    className="progress-fill"
                    style={{ width: `${scanStatus.progress}%` }}
                  />
                </div>
              </div>

              <div className="droplets-section">
                <h4>Active Droplets ({scanStatus.activeDroplets.length})</h4>
                <div className="droplets-grid">
                  {scanStatus.activeDroplets.map(droplet => (
                    <div key={droplet.id} className="droplet-card">
                      <div className="droplet-header">
                        <span className="droplet-name">🖥️ {droplet.id}</span>
                        <span className="droplet-ip">{droplet.ip}</span>
                      </div>
                      <div className="droplet-progress">
                        <div className="progress-bar small">
                          <div 
                            className="progress-fill"
                            style={{ width: `${droplet.progress}%` }}
                          />
                        </div>
                        <div className="droplet-stats">
                          <span>{droplet.domainsScanned} / {droplet.totalDomains} domains</span>
                          <span className="current-domain">{droplet.currentDomain || 'Preparing...'}</span>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              <div className="results-section">
                <h4>Live Results ({scanStatus.results.length})</h4>
                <div className="results-container">
                  {scanStatus.results.length === 0 ? (
                    <div className="no-results">No vulnerabilities found yet...</div>
                  ) : (
                    <div className="results-table-container">
                      <table className="results-table">
                        <thead>
                          <tr>
                            <th>Time</th>
                            <th>Host</th>
                            <th>Severity</th>
                            <th>Template</th>
                            <th>Match</th>
                            <th>Worker</th>
                          </tr>
                        </thead>
                        <tbody>
                          {scanStatus.results.slice(-20).reverse().map((result, i) => (
                            <tr key={i} className={getSeverityClass(result.severity)}>
                              <td>{new Date(result.timestamp).toLocaleTimeString()}</td>
                              <td className="host-cell">{result.host}</td>
                              <td className="severity-cell">
                                <span className={`severity-badge ${result.severity.toLowerCase()}`}>
                                  {result.severity.toUpperCase()}
                                </span>
                              </td>
                              <td className="template-cell">{result.template}</td>
                              <td className="match-cell">{result.match}</td>
                              <td className="worker-cell">{result.workerId}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                      {scanStatus.results.length > 20 && (
                        <div className="table-footer">
                          Showing latest 20 results. Export for full results.
                        </div>
                      )}
                    </div>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default App;
