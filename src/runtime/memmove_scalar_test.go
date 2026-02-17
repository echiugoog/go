// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package runtime_test

import (
	"testing"
)

// BenchmarkMemmoveScalar benchmarks a simple byte-by-byte copy loop
// to establish a true scalar baseline without assembly optimizations.
func BenchmarkMemmoveScalar(b *testing.B) {
	benchmarkSizesLarge(b, largeSizes, func(b *testing.B, n int) {
		x := make([]byte, n)
		y := make([]byte, n)
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			// Naive byte copy loop
			for j := 0; j < n; j++ {
				x[j] = y[j]
			}
		}
	})
}
