// Copyright 2026 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package runtime_test

import (
	"fmt"
	"testing"
)

var sizes = []int{
	1, 7, 15, 17, 31, 33, 63, 65, 95, 127, 129, 255, 511, 1023, 4097, 16383, 65535, 1048577,
}

func BenchmarkMemmoveSizes(b *testing.B) {
	for _, size := range sizes {
		b.Run(fmt.Sprintf("%dB", size), func(b *testing.B) {
			src := make([]byte, size)
			dst := make([]byte, size)
			for i := range src {
				src[i] = byte(i)
			}
			b.SetBytes(int64(size))
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				copy(dst, src)
			}
		})
	}
}

func BenchmarkMemmoveOverlapSizes(b *testing.B) {
	for _, size := range sizes {
		b.Run(fmt.Sprintf("%dB", size), func(b *testing.B) {
			buf := make([]byte, size+32)
			for i := range buf {
				buf[i] = byte(i)
			}
			b.SetBytes(int64(size))
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				copy(buf[16:16+size], buf[:size])
			}
		})
	}
}
