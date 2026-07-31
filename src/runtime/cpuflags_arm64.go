// Copyright 2020 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package runtime

import (
	"internal/cpu"
)

var (
	arm64UseAlignedLoads bool
	arm64UseNEON         bool
	arm64UseSVE          bool
	arm64UseSVE2         bool
)

func init() {
	if cpu.ARM64.IsNeoverse {
		arm64UseAlignedLoads = true
	}
	finishCPUInitARM64()
}

func finishCPUInitARM64() {
	if debug.arm64memmove != 0 && cpu.ARM64.HasASIMD {
		// As required, only check or enable SVE if ASIMD/NEON is present.
		if debug.arm64memmove == 1 || debug.arm64memmove == 2 {
			arm64UseNEON = true
		} else {
			arm64UseNEON = false
		}
		if cpu.ARM64.HasSVE && (debug.arm64memmove == 1 || debug.arm64memmove == 3) {
			arm64UseSVE = true
			if cpu.ARM64.HasSVE2 {
				arm64UseSVE2 = true
			} else {
				arm64UseSVE2 = false
			}
		} else {
			arm64UseSVE = false
			arm64UseSVE2 = false
		}
	} else {
		arm64UseNEON = false
		arm64UseSVE = false
		arm64UseSVE2 = false
	}
}

