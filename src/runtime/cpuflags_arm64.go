// Copyright 2020 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package runtime

import (
	"internal/cpu"
)

var arm64UseAlignedLoads bool
var arm64UseMOPS bool
var arm64UseSVE bool
var arm64UseNEON = true
var arm64UseSVEAlways bool

func init() {
	if cpu.ARM64.IsNeoverse {
		arm64UseAlignedLoads = true
	}
	if cpu.ARM64.HasMOPS {
		arm64UseMOPS = true
	}
	if cpu.ARM64.HasSVE {
		arm64UseSVE = true
	}
}

func processMemmoveOptions(env string) {
	if env == "" {
		return
	}
	for i := 0; i < len(env); {
		j := i
		for j < len(env) && env[j] != ',' {
			j++
		}
		pair := env[i:j]
		if len(pair) > 14 && pair[:14] == "memmove_arm64=" {
			val := pair[14:]
			switch val {
			case "NEON_ONLY":
				arm64UseMOPS = false
				arm64UseSVE = false
				arm64UseNEON = true
			case "SVE_ALL":
				if cpu.ARM64.HasSVE {
					arm64UseSVE = true
					arm64UseSVEAlways = true
				}
			case "NO_SIMD":
				arm64UseMOPS = false
				arm64UseSVE = false
				arm64UseNEON = false
			case "OPTIMAL":
				// Default behavior
			}
		}
		i = j + 1
	}
}
