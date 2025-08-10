package orchestrator

// ScanOptimizer optimizes the distribution of domains across droplets
type ScanOptimizer struct {
	MaxDomainsPerDroplet int
	MinDomainsPerDroplet int
	MaxDroplets          int
	MinDroplets          int
}

// NewScanOptimizer creates a new optimizer with default settings
func NewScanOptimizer() *ScanOptimizer {
	return &ScanOptimizer{
		MaxDomainsPerDroplet: 500,  // Max domains per droplet
		MinDomainsPerDroplet: 50,   // Min domains per droplet
		MaxDroplets:          5,   // Max droplets allowed
		MinDroplets:          1,    // Min droplets required
	}
}

// OptimizeDistribution calculates optimal distribution of domains across droplets
func (so *ScanOptimizer) OptimizeDistribution(domains []string, requestedDroplets int) (int, [][]string) {
	totalDomains := len(domains)
	
	if totalDomains == 0 {
		return 0, [][]string{}
	}

	// Calculate optimal number of droplets
	optimalDroplets := so.calculateOptimalDroplets(totalDomains, requestedDroplets)
	
	// Create chunks
	chunks := so.createChunks(domains, optimalDroplets)
	
	return optimalDroplets, chunks
}

func (so *ScanOptimizer) calculateOptimalDroplets(totalDomains, requestedDroplets int) int {
	// Start with requested droplets
	optimalDroplets := requestedDroplets
	
	// Ensure we don't exceed max droplets
	if optimalDroplets > so.MaxDroplets {
		optimalDroplets = so.MaxDroplets
	}
	
	// Ensure we have at least min droplets
	if optimalDroplets < so.MinDroplets {
		optimalDroplets = so.MinDroplets
	}
	
	// Check if domains per droplet would be too high
	domainsPerDroplet := totalDomains / optimalDroplets
	if domainsPerDroplet > so.MaxDomainsPerDroplet {
		// Need more droplets
		optimalDroplets = (totalDomains + so.MaxDomainsPerDroplet - 1) / so.MaxDomainsPerDroplet
		if optimalDroplets > so.MaxDroplets {
			optimalDroplets = so.MaxDroplets
		}
	}
	
	// Check if domains per droplet would be too low (unless total domains is small)
	if totalDomains > so.MinDomainsPerDroplet {
		domainsPerDroplet = totalDomains / optimalDroplets
		if domainsPerDroplet < so.MinDomainsPerDroplet {
			// Use fewer droplets
			optimalDroplets = totalDomains / so.MinDomainsPerDroplet
			if optimalDroplets < so.MinDroplets {
				optimalDroplets = so.MinDroplets
			}
		}
	}
	
	return optimalDroplets
}

func (so *ScanOptimizer) createChunks(domains []string, numDroplets int) [][]string {
	totalDomains := len(domains)
	baseChunkSize := totalDomains / numDroplets
	extraDomains := totalDomains % numDroplets
	
	chunks := make([][]string, numDroplets)
	start := 0
	
	for i := 0; i < numDroplets; i++ {
		chunkSize := baseChunkSize
		if i < extraDomains {
			chunkSize++ // Distribute extra domains among first few chunks
		}
		
		end := start + chunkSize
		if end > totalDomains {
			end = totalDomains
		}
		
		chunks[i] = domains[start:end]
		start = end
	}
	
	return chunks
}
