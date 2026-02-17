// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package runtime_test

import (
	"fmt"
	"testing"
)

var largeSizes = []int{
	1 << 10, // 1KB
	1 << 12, // 4KB
	1 << 14, // 16KB
	1 << 16, // 64KB
	1 << 18, // 256KB
	1 << 20, // 1MB
	1 << 22, // 4MB
	1 << 24, // 16MB
}

func benchmarkSizesLarge(b *testing.B, sizes []int, fn func(b *testing.B, n int)) {
	for _, n := range sizes {
		b.Run(fmt.Sprintf("%d", n), func(b *testing.B) {
			b.SetBytes(int64(n))
			fn(b, n)
		})
	}
}

func BenchmarkMemmoveLarge(b *testing.B) {
	benchmarkSizesLarge(b, largeSizes, func(b *testing.B, n int) {
		x := make([]byte, n)
		y := make([]byte, n)
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			copy(x, y)
		}
	})
}

func BenchmarkMemmoveLargeOverlap(b *testing.B) {
	benchmarkSizesLarge(b, largeSizes, func(b *testing.B, n int) {
		x := make([]byte, n+16)
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			copy(x[16:n+16], x[:n])
		}
	})
}

func BenchmarkMemmoveLargeUnaligned(b *testing.B) {
	benchmarkSizesLarge(b, largeSizes, func(b *testing.B, n int) {
		x := make([]byte, n+1)
		y := make([]byte, n)
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			copy(x[1:], y)
		}
	})
}

func TestMemmoveLarge16MB(t *testing.T) {
	if testing.Short() {
		t.Skip("-short")
	}
	t.Parallel()
	testSize(t, 1<<24)
}

func TestMemmoveLargeOverlap16MB(t *testing.T) {
	if testing.Short() {
		t.Skip("-short")
	}
	t.Parallel()
	testOverlap(t, 1<<24)
}

// Benchmark results on non-SVE hardware show no regression.

// Benchmark results on Neoverse V2 show SVE (~31GB/s) is slower than NEON (~69GB/s). Optimization required.
